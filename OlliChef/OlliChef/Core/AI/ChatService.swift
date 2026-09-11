import Foundation

private struct IDResponse: Decodable { let id: String }
private struct RunStatusResponse: Decodable {
    let id: String
    let status: String
    let lastError: LastError?

    struct LastError: Decodable { let message: String? }

    enum CodingKeys: String, CodingKey {
        case id, status
        case lastError = "last_error"
    }
}
private struct MessageContentText: Decodable { let value: String }
private struct MessageContentItem: Decodable { let type: String; let text: MessageContentText? }
private struct ThreadMessage: Decodable { let role: String; let content: [MessageContentItem] }
private struct MessagesListResponse: Decodable { let data: [ThreadMessage] }

enum ChatServiceError: Error {
    case missingAssistantID
    case runFailed(String)
    case runCancelled
    case runExpired
    case noAssistantMessage
}

/// Ported from chatService.ts. Thread/run lifecycle against the OpenAI Assistants API
/// via the Firebase Cloud Function proxy — same exponential polling backoff
/// (200ms doubling, capped at 4000ms) and per-request retry as the original.
actor ChatService {
    static let shared = ChatService()

    private let client = APIClient(serviceName: "ChatService")
    private var currentConversationId: String?
    private var createThreadTask: Task<String, Error>?

    private init() {}

    private func baseRequest(path: String, method: String, body: [String: Any]? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(Secrets.firebaseOpenAIProxyURL)\(path)")!)
        request.httpMethod = method
        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
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
            if let recent = try await ChatConversationService.mostRecent() {
                currentConversationId = recent.id
                return recent
            }
            return nil
        } catch {
            handleError(error, context: ErrorContext(location: "ChatService", action: "getCurrentConversation"))
            return nil
        }
    }

    private func createNewThread() async throws -> String {
        if let createThreadTask {
            return try await createThreadTask.value
        }
        let task = Task<String, Error> {
            let (data, _) = try await RetryHelpers.retryRequest {
                try await self.client.send(self.baseRequest(path: "/threads", method: "POST", body: [:]))
            }
            let threadId = try JSONDecoder().decode(IDResponse.self, from: data).id
            let conversation = try await ChatConversationService.create(openaiThreadId: threadId)
            currentConversationId = conversation.id
            return threadId
        }
        createThreadTask = task
        defer { createThreadTask = nil }
        return try await task.value
    }

    func getOrCreateThread() async throws -> String {
        if let conversation = await getCurrentConversation(), let threadId = conversation.openaiThreadId {
            return threadId
        }
        return try await createNewThread()
    }

    /// Mirrors sendMessage: adds the user message, runs the assistant with the dynamic
    /// prompt as instructions, polls for completion, and returns the assistant's reply text.
    func sendMessage(_ message: String) async throws -> String {
        let isOnline = await ConnectivityMonitor.hasInternetConnectivity()
        guard isOnline else {
            throw URLError(.notConnectedToInternet)
        }

        let threadId = try await getOrCreateThread()

        _ = try await RetryHelpers.retryRequest {
            try await self.client.send(self.baseRequest(
                path: "/threads/\(threadId)/messages",
                method: "POST",
                body: ["role": "user", "content": message]
            ))
        }

        guard !Secrets.openAIAssistantID.isEmpty else {
            throw ChatServiceError.missingAssistantID
        }

        let instructions = await PromptManager.shared.dynamicPrompt()
        let (runData, _) = try await RetryHelpers.retryRequest {
            try await self.client.send(self.baseRequest(
                path: "/threads/\(threadId)/runs",
                method: "POST",
                body: ["assistant_id": Secrets.openAIAssistantID, "instructions": instructions]
            ))
        }
        let runId = try JSONDecoder().decode(IDResponse.self, from: runData).id

        try await pollRunUntilComplete(threadId: threadId, runId: runId)

        let (messagesData, _) = try await RetryHelpers.retryRequest {
            try await self.client.send(self.baseRequest(path: "/threads/\(threadId)/messages", method: "GET"))
        }
        let messages = try JSONDecoder().decode(MessagesListResponse.self, from: messagesData)

        guard let latest = messages.data.first(where: { $0.role == "assistant" }) else {
            handleError(ChatServiceError.noAssistantMessage, context: ErrorContext(location: "ChatService", action: "sendMessage"))
            return "Sorry, I could not generate a response. Please try again."
        }

        let responseText = latest.content
            .filter { $0.type == "text" }
            .compactMap { $0.text?.value }
            .joined()

        guard !responseText.isEmpty else {
            return "Sorry, I could not generate a text response. Please try again."
        }

        await updateConversationMetadata(threadId: threadId)
        return responseText
    }

    private func pollRunUntilComplete(threadId: String, runId: String) async throws {
        var status = "queued"
        var pollDelayMs: UInt64 = 200

        while status == "queued" || status == "in_progress" {
            try await Task.sleep(nanoseconds: pollDelayMs * 1_000_000)

            let (data, _) = try await RetryHelpers.retryRequest {
                try await self.client.send(self.baseRequest(path: "/threads/\(threadId)/runs/\(runId)", method: "GET"))
            }
            let run = try JSONDecoder().decode(RunStatusResponse.self, from: data)
            status = run.status
            pollDelayMs = min(pollDelayMs * 2, 4000)

            switch status {
            case "failed":
                let message = run.lastError?.message ?? "Unknown error"
                handleError(ChatServiceError.runFailed(message), context: ErrorContext(location: "ChatService", action: "sendMessage"))
                throw ChatServiceError.runFailed(message)
            case "cancelled":
                handleError(ChatServiceError.runCancelled, context: ErrorContext(location: "ChatService", action: "sendMessage"))
                throw ChatServiceError.runCancelled
            case "expired":
                handleError(ChatServiceError.runExpired, context: ErrorContext(location: "ChatService", action: "sendMessage"))
                throw ChatServiceError.runExpired
            default:
                break
            }
        }
    }

    private func updateConversationMetadata(threadId: String) async {
        do {
            if let conversation = await getCurrentConversation() {
                try await ChatConversationService.update(
                    conversation.id,
                    openaiThreadId: threadId,
                    lastMessageAt: ISO8601DateFormatter().string(from: Date()),
                    messageCount: conversation.messageCount + 2
                )
            } else {
                let conversation = try await ChatConversationService.create(openaiThreadId: threadId)
                currentConversationId = conversation.id
            }
        } catch {
            handleError(error, context: ErrorContext(location: "ChatService", action: "updateConversationMetadata"))
        }
    }
}
