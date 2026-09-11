import Combine
import Foundation

/// Ported from ChatScreen.tsx's handleSend/handleAcceptMealPlan. Grocery-list
/// generation is intentionally deferred to the Recipe + Grocery phase — accepting a
/// plan here saves it and switches tabs, matching the RN flow's save step exactly,
/// but doesn't yet call the AI grocery-aggregation step.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessageItem] = []
    @Published var inputText = ""
    @Published var isThinking = false
    @Published var isAccepting = false
    @Published var acceptError: String?

    func loadWelcomeMessage() async {
        guard messages.isEmpty else { return }
        let welcome = await PromptManager.shared.welcomeMessage()
        messages.append(ChatMessageItem(id: UUID().uuidString, role: .assistant, content: welcome, timestamp: Date()))
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
        acceptError = nil
        defer { isAccepting = false }

        do {
            try await MealPlanStorageService.save(plan)
            router.selection = .mealPlan
        } catch {
            handleError(error, context: ErrorContext(location: "ChatScreen", action: "accepting_meal_plan"))
            acceptError = NetworkErrorClassifier.isNetworkError(error)
                ? NetworkConfig.offlineMessage
                : "Failed to save meal plan"
        }
    }
}
