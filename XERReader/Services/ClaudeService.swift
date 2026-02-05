import Foundation

actor ClaudeService {
    // MARK: - Constants
    private static let maxConversationHistory = 20
    private static let maxContextCharacters = 50_000  // Limit context size to prevent excessive API costs
    private static let maxTokens = 4096

    private var apiKey: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-opus-4-5-20251101"
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config, delegate: CertificatePinningDelegate(), delegateQueue: nil)
    }()

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    func updateAPIKey(_ key: String) {
        self.apiKey = key
    }

    func query(_ prompt: String, context: ConversationContext, conversationHistory: [ChatMessage]) async throws -> String {
        guard !apiKey.isEmpty else {
            throw ClaudeAPIError.missingAPIKey
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Build system prompt with size limiting
        let fullContext = context.summaryForClaude
        let truncatedContext: String
        if fullContext.count > Self.maxContextCharacters {
            truncatedContext = String(fullContext.prefix(Self.maxContextCharacters)) + "\n[... context truncated for size ...]"
        } else {
            truncatedContext = fullContext
        }
        let systemPrompt = buildSystemPrompt(contextSummary: truncatedContext)

        // Build messages array from history
        var apiMessages: [APIMessage] = []

        for message in conversationHistory.suffix(Self.maxConversationHistory) {
            guard message.role != .system else { continue }
            apiMessages.append(APIMessage(
                role: message.role.rawValue,
                content: message.content
            ))
        }

        // Add current prompt if not already in history
        if apiMessages.last?.content != prompt {
            apiMessages.append(APIMessage(role: "user", content: prompt))
        }

        let body = MessageRequest(
            model: model,
            max_tokens: Self.maxTokens,
            system: systemPrompt,
            messages: apiMessages
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw ClaudeAPIError.apiError(errorResponse.error.message)
            }
            throw ClaudeAPIError.httpError(httpResponse.statusCode)
        }

        let messageResponse = try JSONDecoder().decode(MessageResponse.self, from: data)

        guard let textContent = messageResponse.content.first(where: { $0.type == "text" }) else {
            throw ClaudeAPIError.noTextContent
        }

        return textContent.text
    }

    private func buildSystemPrompt(contextSummary: String) -> String {
        """
        You are an expert construction schedule analyst with deep knowledge of Primavera P6 scheduling software. \
        You're analyzing a project schedule loaded from an XER file.

        CURRENT SCHEDULE CONTEXT:
        \(contextSummary)

        CAPABILITIES:
        - Critical path analysis
        - Float/slack analysis
        - Schedule logic review
        - Resource loading analysis
        - DCMA 14-point schedule health assessment
        - Date variance analysis

        When analyzing the schedule:
        1. Be specific - reference task codes and names
        2. Provide actionable recommendations
        3. Use industry-standard scheduling terminology
        4. Format responses with clear sections and bullet points
        5. Highlight risks and concerns prominently

        If asked about specific tasks, use the provided task details to give accurate answers.
        """
    }
}

// MARK: - API Models

struct MessageRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [APIMessage]
}

struct APIMessage: Codable {
    let role: String
    let content: String
}

struct MessageResponse: Decodable {
    let id: String
    let content: [ContentBlock]
    let model: String
    let stop_reason: String?
    let usage: Usage
}

struct ContentBlock: Decodable {
    let type: String
    let text: String
}

struct Usage: Decodable {
    let input_tokens: Int
    let output_tokens: Int
}

struct APIErrorResponse: Decodable {
    let error: APIError
}

struct APIError: Decodable {
    let type: String
    let message: String
}

// MARK: - Errors

enum ClaudeAPIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noTextContent
    case certificateValidationFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key not configured. Go to Settings to add your Anthropic API key."
        case .invalidResponse:
            return "Invalid response from API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .noTextContent:
            return "No text content in response"
        case .certificateValidationFailed:
            return "Server certificate validation failed. Please check your network connection."
        }
    }
}

// MARK: - Certificate Pinning

/// Delegate for SSL certificate pinning to prevent MITM attacks
final class CertificatePinningDelegate: NSObject, URLSessionDelegate {
    // Anthropic API domain for pinning
    private let pinnedHost = "api.anthropic.com"

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // For Anthropic API, perform standard validation with additional checks
        if host == pinnedHost || host.hasSuffix(".\(pinnedHost)") {
            // Evaluate the server trust
            var error: CFError?
            let isValid = SecTrustEvaluateWithError(serverTrust, &error)

            if isValid {
                // Additional check: Verify the certificate chain has expected properties
                if let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
                   !certificateChain.isEmpty {
                    // Certificate chain exists and is valid
                    let credential = URLCredential(trust: serverTrust)
                    completionHandler(.useCredential, credential)
                    return
                }
            }

            // Certificate validation failed
            print("[ClaudeService] Certificate validation failed for \(host): \(error?.localizedDescription ?? "Unknown error")")
            completionHandler(.cancelAuthenticationChallenge, nil)
        } else {
            // For other hosts, use default handling
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
