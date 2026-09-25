import Foundation

// Pure Decodable DTOs with no actor affinity — exempted from the project's default
// MainActor isolation so JSONDecoder (itself nonisolated) can decode them from
// ChatService's own actor context without a cross-actor hop.
private nonisolated struct IDResponse: Decodable { let id: String }

private nonisolated struct ResponsesAPIResult: Decodable {
    let output: [OutputItem]?
    let error: APIErrorDetail?

    struct OutputItem: Decodable {
        let role: String?
        let content: [ContentItem]?
    }
    struct ContentItem: Decodable {
        let type: String
        let text: String?
    }
    struct APIErrorDetail: Decodable {
        let message: String?
    }
}

private nonisolated struct ConversationItemsResult: Decodable {
    let data: [Item]

    struct Item: Decodable {
        let id: String
        let type: String
        let role: String?
        let content: [ContentItem]?

        struct ContentItem: Decodable {
            let type: String
            let text: String?
        }
    }
}

enum ChatServiceError: Error {
    case apiError(String)
    case noAssistantMessage
}

/// Rewritten against OpenAI's Responses API — the Assistants API (threads/runs) this
/// originally ported from chatService.ts was permanently shut down by OpenAI on
/// 2026-08-26, no transition period. Per developers.openai.com/api/docs/assistants/migration:
/// Threads -> Conversations, Runs go away entirely (Responses returns the completion
/// synchronously, no polling), and `instructions` stays a direct per-request parameter
/// (no dashboard Prompt object needed) — matching how this app already injects a fresh
/// dynamic prompt on every call rather than relying on stored Assistant config.
actor ChatService {
    static let shared = ChatService()

    private let client = APIClient(serviceName: "ChatService")
    private var currentConversationId: String?
    private var createConversationTask: Task<String, Error>?

    private init() {}

    private func baseRequest(path: String, method: String, body: [String: Any]? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(Secrets.firebaseOpenAIProxyURL)\(path)")!)
        request.httpMethod = method
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func getCurrentConversation() async -> ChatConversation? {
        do {
            if let currentConversationId {
                return try await ChatConversationService.get(currentConversationId)
            }
            if let recent = try await findMostRecentConversationWithRetry() {
                currentConversationId = recent.id
                return recent
            }
            return nil
        } catch {
            handleError(error, context: ErrorContext(location: "ChatService", action: "getCurrentConversation"))
            return nil
        }
    }

    /// `ChatConversationService.mostRecent()` returns nil both when the user genuinely
    /// has no conversation yet and when `Auth.auth().currentUser` isn't readable yet —
    /// the two are indistinguishable from here, and `getOrCreateConversation()` treats
    /// either as "create a fresh one". Confirmed live on a physical device (not the
    /// simulator): the very first authenticated Firestore query right after a cold
    /// launch + fresh sign-in can resolve before the connection is fully warmed up,
    /// which silently created a brand-new empty conversation and stranded the user's
    /// real history behind it — fixed by signing out and back in, which re-ran this
    /// same lookup against an already-warm connection. One retry after a short delay
    /// absorbs that race; a genuinely new user just pays one harmless extra ~700ms on
    /// their very first chat load.
    private func findMostRecentConversationWithRetry() async throws -> ChatConversation? {
        if let recent = try await ChatConversationService.mostRecent() {
            return recent
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        return try await ChatConversationService.mostRecent()
    }

    private func createNewConversation() async throws -> String {
        if let createConversationTask {
            return try await createConversationTask.value
        }
        let task = Task<String, Error> {
            let (data, _) = try await RetryHelpers.retryRequest {
                try await self.client.send(self.baseRequest(path: "/conversations", method: "POST", body: [:]))
            }
            let conversationId = try JSONDecoder().decode(IDResponse.self, from: data).id
            let conversation = try await ChatConversationService.create(openaiConversationId: conversationId)
            currentConversationId = conversation.id
            return conversationId
        }
        createConversationTask = task
        defer { createConversationTask = nil }
        return try await task.value
    }

    func getOrCreateConversation() async throws -> String {
        if let conversation = await getCurrentConversation(), let conversationId = conversation.openaiConversationId {
            return conversationId
        }
        return try await createNewConversation()
    }

    /// Sends the user message with the dynamic prompt as `instructions` and returns the
    /// assistant's reply text. No polling: /v1/responses returns the completion directly.
    func sendMessage(_ message: String) async throws -> String {
        let isOnline = await ConnectivityMonitor.hasInternetConnectivity()
        guard isOnline else {
            throw URLError(.notConnectedToInternet)
        }

        let conversationId = try await getOrCreateConversation()
        let instructions = try await PromptManager.shared.dynamicPrompt()
        let model = try await PromptManager.shared.requiredAIModel()

        let (data, _) = try await RetryHelpers.retryRequest {
            try await self.client.send(self.baseRequest(
                path: "/responses",
                method: "POST",
                body: [
                    "model": model,
                    "instructions": instructions,
                    "input": [["role": "user", "content": message]],
                    "conversation": conversationId,
                    "text": ["format": ChatResponseSchema.responseFormat],
                ]
            ), timeout: NetworkConfig.chatSendTimeout)
        }

        #if DEBUG
        // Temporary visibility into Structured Outputs while validating the new
        // envelope live — the full /responses body first (confirms text.format
        // actually reached OpenAI and what it sent back around the text), then just
        // the extracted assistant text below (the JSON string that actually gets
        // parsed downstream, easiest to eyeball for shape/content correctness).
        print("🔵 [ChatService] Raw /responses body:\n\(String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>")")
        #endif

        let result = try JSONDecoder().decode(ResponsesAPIResult.self, from: data)

        if let apiErrorMessage = result.error?.message {
            handleError(ChatServiceError.apiError(apiErrorMessage), context: ErrorContext(location: "ChatService", action: "sendMessage"))
            throw ChatServiceError.apiError(apiErrorMessage)
        }

        let responseText = (result.output ?? [])
            .filter { $0.role == "assistant" }
            .flatMap { $0.content ?? [] }
            .filter { $0.type == "output_text" }
            .compactMap { $0.text }
            .joined()

        guard !responseText.isEmpty else {
            handleError(ChatServiceError.noAssistantMessage, context: ErrorContext(location: "ChatService", action: "sendMessage"))
            return "Sorry, I could not generate a text response. Please try again."
        }

        #if DEBUG
        print("🟢 [ChatService] Extracted assistant text:\n\(responseText)")
        #endif

        await updateConversationMetadata(conversationId: conversationId)
        return responseText
    }

    /// Mirrors loadChatHistory's getThreadMessages call: the old Assistants API's
    /// GET /threads/{id}/messages, replaced by the Responses API's GET
    /// /conversations/{id}/items. Items carry no created_at (unlike Assistants
    /// messages), so timestamps are synthesized purely to satisfy ChatMessageItem —
    /// display order comes from array order, not the timestamp value. Default order
    /// is newest-first (matching the old threads default), so results are reversed
    /// to oldest-first here, exactly like chatService.ts did.
    func loadHistoryMessages(conversationId: String) async throws -> [ChatMessageItem] {
        let (data, _) = try await RetryHelpers.retryRequest {
            try await self.client.send(self.baseRequest(path: "/conversations/\(conversationId)/items", method: "GET"))
        }
        let result = try JSONDecoder().decode(ConversationItemsResult.self, from: data)

        let now = Date()
        var messages: [ChatMessageItem] = []
        // Tracked across iterations (oldest-first) so a reload applies the same
        // missing-days reconciliation as a live send — see MealPlanParser.reconcile.
        // Without this, history would show the raw (possibly partial) plan a live
        // session had already patched up, and re-accepting it after a reload could
        // still truncate the saved week.
        var previousPlan: MealPlan?

        for (index, item) in result.data.reversed().enumerated() {
            guard item.type == "message",
                  let roleString = item.role,
                  let role = ChatMessageItem.Role(rawValue: roleString) else {
                continue
            }

            let text = (item.content ?? [])
                .filter { $0.type == "input_text" || $0.type == "output_text" }
                .compactMap { $0.text }
                .joined()
            let timestamp = now.addingTimeInterval(TimeInterval(index))

            if role == .assistant, let json = AssistantJSONExtractor.tryExtractJSON(from: text) {
                if AssistantJSONExtractor.isStructuredMealPlan(json), var mealPlan = MealPlanParser.parse(json) {
                    mealPlan = MealPlanParser.reconcile(updated: mealPlan, previous: previousPlan)
                    previousPlan = mealPlan
                    messages.append(ChatMessageItem(id: item.id, role: role, content: nil, timestamp: timestamp, mealPlan: mealPlan))
                    continue
                }
                // Structured Outputs (see ChatResponseSchema) wraps even a plain
                // clarifying question in a JSON envelope — unwrap it so reloaded
                // history shows the question text, not the raw envelope.
                if let questionText = AssistantJSONExtractor.extractQuestionText(from: json) {
                    messages.append(ChatMessageItem(id: item.id, role: role, content: questionText, timestamp: timestamp))
                    continue
                }
            }
            messages.append(ChatMessageItem(id: item.id, role: role, content: text, timestamp: timestamp))
        }
        return messages
    }

    /// Mirrors resetChatThread: starts a brand-new conversation, leaving the old
    /// Firestore doc intact as history (its openaiConversationId is a dead reference
    /// only if it predates this migration).
    func resetChatConversation() async throws -> String {
        let (data, _) = try await RetryHelpers.retryRequest {
            try await self.client.send(self.baseRequest(path: "/conversations", method: "POST", body: [:]))
        }
        let newConversationId = try JSONDecoder().decode(IDResponse.self, from: data).id
        let newConversation = try await ChatConversationService.create(openaiConversationId: newConversationId)
        currentConversationId = newConversation.id
        return newConversationId
    }

    private func updateConversationMetadata(conversationId: String) async {
        do {
            if let conversation = await getCurrentConversation() {
                try await ChatConversationService.update(
                    conversation.id,
                    openaiConversationId: conversationId,
                    lastMessageAt: ISO8601DateFormatter().string(from: Date()),
                    messageCount: conversation.messageCount + 2
                )
            } else {
                let conversation = try await ChatConversationService.create(openaiConversationId: conversationId)
                currentConversationId = conversation.id
            }
        } catch {
            handleError(error, context: ErrorContext(location: "ChatService", action: "updateConversationMetadata"))
        }
    }
}
