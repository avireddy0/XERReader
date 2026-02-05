import Foundation

struct Relationship: Codable, Equatable, Identifiable {
    var id: String { "\(taskId)-\(predecessorTaskId)" }

    let taskId: String
    let predecessorTaskId: String
    let relationshipType: RelationshipType
    let lagDays: Double

    init(taskId: String, predecessorTaskId: String, relationshipType: RelationshipType, lagDays: Double = 0) {
        self.taskId = taskId
        self.predecessorTaskId = predecessorTaskId
        self.relationshipType = relationshipType
        self.lagDays = lagDays
    }
}

enum RelationshipType: String, Codable {
    case finishToStart = "PR_FS"
    case startToStart = "PR_SS"
    case finishToFinish = "PR_FF"
    case startToFinish = "PR_SF"

    init(rawP6Value: String) {
        switch rawP6Value {
        case "PR_FS": self = .finishToStart
        case "PR_SS": self = .startToStart
        case "PR_FF": self = .finishToFinish
        case "PR_SF": self = .startToFinish
        default: self = .finishToStart
        }
    }

    var displayName: String {
        switch self {
        case .finishToStart: return "FS"
        case .startToStart: return "SS"
        case .finishToFinish: return "FF"
        case .startToFinish: return "SF"
        }
    }

    var description: String {
        switch self {
        case .finishToStart: return "Finish to Start"
        case .startToStart: return "Start to Start"
        case .finishToFinish: return "Finish to Finish"
        case .startToFinish: return "Start to Finish"
        }
    }
}
