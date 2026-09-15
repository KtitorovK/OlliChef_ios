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

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        messages.append(ChatMessageItem(id: UUID().uuidString, role: .user, content: text, timestamp: Date()))
        isThinking = true
        defer { isThinking = false }

        do {
            let responseText = try await ChatService.shared.sendMessage(text)

            if let json = AssistantJSONExtractor.tryExtractJSON(from: responseText),
               AssistantJSONExtractor.isStructuredMealPlan(json),
               let mealPlan = MealPlanParser.parse(json) {
                messages.append(ChatMessageItem(id: UUID().uuidString, role: .assistant, content: nil, timestamp: Date(), mealPlan: mealPlan))
            } else {
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
