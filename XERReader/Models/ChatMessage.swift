import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    var isStreaming: Bool

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }

    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    static func assistant(_ content: String, isStreaming: Bool = false) -> ChatMessage {
        ChatMessage(role: .assistant, content: content, isStreaming: isStreaming)
    }

    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct ConversationContext {
    let schedule: Schedule
    let selectedTasks: [ScheduleTask]
    let analysisHistory: [AnalysisResult]

    var summaryForClaude: String {
        var parts: [String] = []

        if let project = schedule.primaryProject {
            parts.append("Project: \(project.name)")
            if let start = project.planStartDate, let end = project.planEndDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                parts.append("Duration: \(formatter.string(from: start)) to \(formatter.string(from: end))")
            }
        }

        parts.append("Total Activities: \(schedule.taskCount)")
        parts.append("Critical Activities: \(schedule.criticalTasks.count)")
        parts.append("Milestones: \(schedule.milestones.count)")

        if !selectedTasks.isEmpty {
            parts.append("\nCurrently selected \(selectedTasks.count) task(s):")
            for task in selectedTasks.prefix(10) {
                parts.append("- \(task.taskCode): \(task.name)")
            }
            if selectedTasks.count > 10 {
                parts.append("- ... and \(selectedTasks.count - 10) more")
            }
        }

        return parts.joined(separator: "\n")
    }
}

struct AnalysisResult: Identifiable {
    let id = UUID()
    let type: AnalysisType
    let title: String
    let summary: String
    let details: String
    let timestamp: Date
    let affectedTasks: [String] // task IDs

    init(type: AnalysisType, title: String, summary: String, details: String = "", affectedTasks: [String] = []) {
        self.type = type
        self.title = title
        self.summary = summary
        self.details = details
        self.timestamp = Date()
        self.affectedTasks = affectedTasks
    }
}

enum AnalysisType: String {
    case criticalPath
    case floatAnalysis
    case logicCheck
    case resourceLoading
    case scheduleHealth
    case dateComparison
    case custom
}
