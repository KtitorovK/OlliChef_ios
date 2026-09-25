import Combine
import Foundation

/// Ported from ChatScreen.tsx's handleSend/handleAcceptMealPlan. Grocery-list
/// generation is intentionally deferred to the Recipe + Grocery phase — accepting a
/// plan here saves it and switches tabs, matching the RN flow's save step exactly,
/// but doesn't yet call the AI grocery-aggregation step.
/// Mirrors ChatScreen.tsx's `AcceptStep`: drives the 3-step "Saving meal plan / Building
/// grocery list / All done!" progress popup shown while `isAccepting`.
enum AcceptStep {
    case saving, grocery, done

    enum StepState { case inactive, active, done }

    /// Mirrors getStepStatus exactly, including its 1-indexed step numbering.
    func status(forStep stepNumber: Int) -> StepState {
        switch self {
        case .saving:
            return stepNumber == 1 ? .active : .inactive
        case .grocery:
            if stepNumber == 1 { return .done }
            if stepNumber == 2 { return .active }
            return .inactive
        case .done:
            if stepNumber == 1 || stepNumber == 2 { return .done }
            return .active
        }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessageItem] = []
    @Published var inputText = ""
    // A multiline `TextField(axis: .vertical)` bound to `inputText` doesn't reliably
    // repaint when the binding is cleared from code while the field still has focus —
    // a known SwiftUI quirk, confirmed live after send(). Bumping this and keying the
    // TextField's view identity to it (see ChatScreen) forces SwiftUI to recreate the
    // field on every clear instead of trusting the stale one to redraw itself.
    @Published var composerResetToken = 0
    @Published var isThinking = false
    @Published var isAccepting = false
    @Published var acceptStep: AcceptStep = .saving
    @Published var acceptError: String?

    /// Ported from ChatScreen.tsx's loadChatHistory: fetches prior turns for the
    /// current conversation and prepends the welcome message unless it's already
    /// the first message, matching the RN behavior exactly. Firestore only ever
    /// stored conversation metadata there (never message content) — real history
    /// came from OpenAI's own thread storage, so this loads it the same way here,
    /// via the Responses API's conversation instead of the old Assistants thread.
    func loadHistory() async {
        guard messages.isEmpty else { return }
        let welcome = await PromptManager.shared.welcomeMessage()

        do {
            let conversationId = try await ChatService.shared.getOrCreateConversation()
            var history = try await ChatService.shared.loadHistoryMessages(conversationId: conversationId)
            let alreadyHasWelcome = history.first?.role == .assistant
                && history.first?.content?.trimmingCharacters(in: .whitespacesAndNewlines) == welcome
            if !alreadyHasWelcome {
                history.insert(ChatMessageItem(id: UUID().uuidString, role: .assistant, content: welcome, timestamp: Date()), at: 0)
            }
            messages = history
        } catch {
            handleError(error, context: ErrorContext(location: "ChatScreen", action: "loadHistory"))
            let content = NetworkErrorClassifier.isNetworkError(error) ? NetworkConfig.offlineMessage : welcome
            messages = [ChatMessageItem(id: UUID().uuidString, role: .assistant, content: content, timestamp: Date())]
        }
    }

    /// Called when Profile's "Clear Chat History" resets the conversation server-side
    /// while this view model is still alive (see TabRouter.chatHistoryClearedAt) —
    /// loadHistory() alone would no-op since its `messages.isEmpty` guard is already
    /// false, so this clears local state first to force a real reload of the fresh,
    /// empty conversation.
    func resetAfterExternalClear() async {
        messages = []
        await loadHistory()
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        composerResetToken += 1
        messages.append(ChatMessageItem(id: UUID().uuidString, role: .user, content: text, timestamp: Date()))
        isThinking = true
        defer { isThinking = false }

        do {
            let responseText = try await ChatService.shared.sendMessage(text)

            if let json = AssistantJSONExtractor.tryExtractJSON(from: responseText) {
                if AssistantJSONExtractor.isStructuredMealPlan(json), let mealPlan = MealPlanParser.parse(json) {
                    // No client-side merging with the previous plan: whether this is an
                    // edit (keep the rest of the week) or an intentionally fresh plan
                    // (don't) is a judgment call about the user's actual request, which
                    // only the model can make — a date-overlap heuristic here can't
                    // reliably tell the two apart and was confirmed live to sometimes
                    // glue stale days onto a plan the user asked to replace entirely.
                    // The dynamic prompt now states this distinction directly instead.
                    #if DEBUG
                    let mealCounts = mealPlan.days.map { "\($0.day ?? $0.date): \($0.meals.count)" }.joined(separator: ", ")
                    print("🟢 [ChatViewModel] Parsed meal plan — \(mealPlan.days.count) days [\(mealCounts)]")
                    #endif
                    messages.append(ChatMessageItem(id: UUID().uuidString, role: .assistant, content: nil, timestamp: Date(), mealPlan: mealPlan))
                } else if let questionText = AssistantJSONExtractor.extractQuestionText(from: json) {
                    // The Structured Outputs envelope (see ChatResponseSchema) wraps even
                    // a plain clarifying question in JSON — unwrap it rather than showing
                    // the raw envelope text.
                    #if DEBUG
                    print("🟢 [ChatViewModel] Parsed question envelope: \(questionText)")
                    #endif
                    messages.append(ChatMessageItem(id: UUID().uuidString, role: .assistant, content: questionText, timestamp: Date()))
                } else {
                    #if DEBUG
                    print("🟡 [ChatViewModel] Parsed as JSON but unrecognized envelope shape — showing raw text: \(json)")
                    #endif
                    messages.append(ChatMessageItem(id: UUID().uuidString, role: .assistant, content: responseText, timestamp: Date()))
                }
            } else {
                #if DEBUG
                print("🟡 [ChatViewModel] Response wasn't JSON at all (pre-migration plain-text shape)")
                #endif
                messages.append(ChatMessageItem(id: UUID().uuidString, role: .assistant, content: responseText, timestamp: Date()))
            }
        } catch {
            handleError(error, context: ErrorContext(location: "ChatScreen", action: "handleSend"))
            let content = NetworkErrorClassifier.isNetworkError(error)
                ? NetworkConfig.offlineMessage
                : await PromptManager.shared.errorRecoveryPrompt()
            messages.append(ChatMessageItem(id: UUID().uuidString, role: .assistant, content: nil, timestamp: Date(), error: content))
        }
    }

    func acceptMealPlan(_ plan: MealPlan, router: TabRouter) async {
        isAccepting = true
        acceptStep = .saving
        acceptError = nil
        defer {
            acceptStep = .saving
            isAccepting = false
        }

        do {
            try await MealPlanStorageService.save(plan)
            // Mirrors handleAcceptMealPlan: replace any prior list for this plan, then
            // generate a fresh one. generateGroceryListForPlan only throws when the plan
            // has no ingredients at all — AI failures fall back internally, so this
            // rarely fails, but a failure here should still surface as an accept error
            // rather than navigating to a plan with no grocery list.
            try await GroceryListStorageService.deleteByMealPlanId(plan.id)
            acceptStep = .grocery
            _ = try await GroceryService.shared.generateGroceryListForPlan(plan)
            acceptStep = .done
            // Mirrors the RN flow's own 600ms pause before the "Success" alert appears —
            // long enough for the "All done!" step to actually be seen, not skipped past.
            try? await Task.sleep(nanoseconds: 600_000_000)
            router.selection = .mealPlan
        } catch {
            handleError(error, context: ErrorContext(location: "ChatScreen", action: "accepting_meal_plan"))
            acceptError = NetworkErrorClassifier.isNetworkError(error)
                ? NetworkConfig.offlineMessage
                : "Failed to save meal plan"
        }
    }
}
