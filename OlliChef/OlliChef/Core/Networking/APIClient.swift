import Foundation

enum APIClientError: Error {
    case httpError(statusCode: Int, data: Data?)
    case decodingFailed(Error)
}

/// Mirrors networkUtils.ts's createApiClient: attaches a Firebase ID token to every
/// request, and on a 401 (proxy rejected the token) refreshes it once and retries —
/// exactly as the axios response interceptor does.
actor APIClient {
    private let serviceName: String
    private let session: URLSession

    init(serviceName: String, session: URLSession = .shared) {
        self.serviceName = serviceName
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var req = request
        req.timeoutInterval = NetworkConfig.timeout
        if req.value(forHTTPHeaderField: "Content-Type") == nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let token = try await FirebaseTokenProvider.idToken()
        req.setValue(token, forHTTPHeaderField: "x-firebase-token")

        return try await performWithTokenRetry(req, retried: false)
    }

    func send<T: Decodable>(_ request: URLRequest, decoding type: T.Type) async throws -> T {
        let (data, _) = try await send(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIClientError.decodingFailed(error)
        }
    }

    private func performWithTokenRetry(_ request: URLRequest, retried: Bool) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            // Proxy returns 401 when the token is missing/invalid — refresh once and retry
            if httpResponse.statusCode == 401, !retried {
                var retryRequest = request
                let refreshedToken = try await FirebaseTokenProvider.idToken(forceRefresh: true)
                retryRequest.setValue(refreshedToken, forHTTPHeaderField: "x-firebase-token")
                return try await performWithTokenRetry(retryRequest, retried: true)
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw APIClientError.httpError(statusCode: httpResponse.statusCode, data: data)
            }

            return (data, httpResponse)
        } catch let error as APIClientError {
            throw error
        } catch {
            if NetworkErrorClassifier.isNetworkError(error) {
                handleError(error, context: ErrorContext(
                    location: serviceName,
                    action: "network_request",
                    errorCode: (error as NSError).domain,
                    errorMessage: error.localizedDescription
                ))
            }
            throw error
        }
    }
}
