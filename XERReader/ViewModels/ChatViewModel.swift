import SwiftUI
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var analysisResults: [AnalysisResult] = []
    @Published private(set) var apiKeyConfigured: Bool = false

    private var claudeService: ClaudeService
    private var currentStreamingMessage: ChatMessage?

    init(apiKey: String = "") {
        self.claudeService = ClaudeService(apiKey: apiKey)
        self.apiKeyConfigured = !apiKey.isEmpty
    }

    func updateAPIKey(_ key: String) {
        Task {
            await claudeService.updateAPIKey(key)
            self.apiKeyConfigured = !key.isEmpty
        }
    }

    var hasAPIKey: Bool {
        apiKeyConfigured
    }

    func sendMessage(context: ConversationContext) async {
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }

        // Add user message
        messages.append(.user(userMessage))
        inputText = ""
        isLoading = true
        error = nil

        do {
            let response = try await claudeService.query(
                userMessage,
                context: context,
                conversationHistory: messages.filter { $0.role != .system }
            )

            messages.append(.assistant(response))
        } catch let err as ClaudeAPIError {
            handleClaudeAPIError(err)
        } catch let urlError as URLError {
            handleNetworkError(urlError)
        } catch {
            self.error = "Unexpected error: \(error.localizedDescription)"
            messages.append(.system("Error: \(error.localizedDescription)"))
        }

        isLoading = false
    }

    // MARK: - Error Handling

    private func handleClaudeAPIError(_ error: ClaudeAPIError) {
        switch error {
        case .missingAPIKey:
            self.error = "API key not configured"
            messages.append(.system("Please configure your Anthropic API key in Settings (⌘,) to use the chat feature."))
        case .httpError(let code):
            let guidance = httpErrorGuidance(for: code)
            self.error = "HTTP \(code): \(guidance.title)"
            messages.append(.system("Error \(code): \(guidance.message)"))
        case .apiError(let message):
            self.error = "API Error"
            if message.contains("rate_limit") {
                messages.append(.system("Rate limit exceeded. Please wait a moment and try again."))
            } else if message.contains("invalid_api_key") {
                messages.append(.system("Invalid API key. Please check your key in Settings."))
            } else {
                messages.append(.system("API Error: \(message)"))
            }
        case .invalidResponse:
            self.error = "Invalid response"
            messages.append(.system("Received an invalid response from the API. Please try again."))
        case .noTextContent:
            self.error = "Empty response"
            messages.append(.system("The API returned an empty response. Please try rephrasing your question."))
        case .certificateValidationFailed:
            self.error = "Security error"
            messages.append(.system("Server certificate validation failed. Please check your network connection and try again."))
        }
    }

    private func handleNetworkError(_ error: URLError) {
        switch error.code {
        case .notConnectedToInternet:
            self.error = "No internet connection"
            messages.append(.system("You appear to be offline. Please check your internet connection and try again."))
        case .timedOut:
            self.error = "Request timed out"
            messages.append(.system("The request timed out. The server may be busy - please try again in a moment."))
        case .cannotFindHost, .cannotConnectToHost:
            self.error = "Cannot reach server"
            messages.append(.system("Cannot connect to the Anthropic API. Please check your network settings."))
        default:
            self.error = "Network error"
            messages.append(.system("Network error: \(error.localizedDescription). Please try again."))
        }
    }

    private func httpErrorGuidance(for code: Int) -> (title: String, message: String) {
        switch code {
        case 401:
            return ("Unauthorized", "Your API key is invalid or expired. Please update it in Settings.")
        case 403:
            return ("Forbidden", "Access denied. Please check your API key permissions.")
        case 429:
            return ("Rate Limited", "Too many requests. Please wait a moment and try again.")
        case 500...599:
            return ("Server Error", "The Anthropic API is experiencing issues. Please try again later.")
        default:
            return ("Error", "Request failed with status \(code). Please try again.")
        }
    }

    func runAnalysis(_ type: AnalysisType, schedule: Schedule) async {
        isLoading = true
        error = nil

        let analysisPrompt: String
        switch type {
        case .criticalPath:
            analysisPrompt = "Analyze the critical path. List all critical activities, explain why they're critical, and identify any risks."
        case .floatAnalysis:
            analysisPrompt = "Analyze float/slack in the schedule. Identify activities with significant float and those with negative float."
        case .logicCheck:
            analysisPrompt = "Check the schedule logic. Identify: open ends (no predecessors/successors), redundant logic, and constraint issues."
        case .resourceLoading:
            analysisPrompt = "Analyze resource loading. Identify over-allocated resources and periods of high demand."
        case .scheduleHealth:
            analysisPrompt = "Perform a schedule health check using DCMA 14-point assessment criteria."
        case .dateComparison:
            analysisPrompt = "Compare baseline vs current dates. Highlight activities that have slipped."
        case .custom:
            return
        }

        let context = ConversationContext(
            schedule: schedule,
            selectedTasks: [],
            analysisHistory: analysisResults
        )

        messages.append(.user(analysisPrompt))

        do {
            let response = try await claudeService.query(
                analysisPrompt,
                context: context,
                conversationHistory: []
            )

            messages.append(.assistant(response))

            // Create analysis result
            let result = AnalysisResult(
                type: type,
                title: type.rawValue.capitalized,
                summary: String(response.prefix(200)),
                details: response
            )
            analysisResults.append(result)
        } catch let err as ClaudeAPIError {
            handleClaudeAPIError(err)
        } catch let urlError as URLError {
            handleNetworkError(urlError)
        } catch {
            self.error = "Analysis failed"
            messages.append(.system("Analysis failed: \(error.localizedDescription). Please try again."))
        }

        isLoading = false
    }

    func clearHistory() {
        messages.removeAll()
        error = nil
    }

    func addSystemMessage(_ content: String) {
        messages.append(.system(content))
    }
}
