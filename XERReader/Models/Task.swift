import Foundation

struct ScheduleTask: Codable, Equatable, Identifiable {
    let id: String
    let projectId: String
    let wbsId: String?
    let taskCode: String
    let name: String
    let taskType: TaskType
    let status: TaskStatus
    let percentComplete: Double

    // Target dates (baseline)
    let targetStartDate: Date?
    let targetEndDate: Date?

    // Early dates (calculated)
    var earlyStartDate: Date?
    var earlyEndDate: Date?

    // Late dates (calculated)
    var lateStartDate: Date?
    var lateEndDate: Date?

    // Actual dates
    let actualStartDate: Date?
    let actualEndDate: Date?

    // Duration
    let targetDuration: Double // hours
    let remainingDuration: Double // hours

    // Float (slack)
    var totalFloat: Double = 0 // hours
    var freeFloat: Double = 0 // hours

    var isCritical: Bool {
        totalFloat <= 0
    }

    var durationDays: Int {
        Int(targetDuration / 8)
    }

    var totalFloatDays: Int {
        Int(totalFloat / 8)
    }

    init(id: String, projectId: String, wbsId: String?, taskCode: String, name: String,
         taskType: TaskType, status: TaskStatus, percentComplete: Double,
         targetStartDate: Date?, targetEndDate: Date?,
         actualStartDate: Date? = nil, actualEndDate: Date? = nil,
         targetDuration: Double, remainingDuration: Double) {
        self.id = id
        self.projectId = projectId
        self.wbsId = wbsId
        self.taskCode = taskCode
        self.name = name
        self.taskType = taskType
        self.status = status
        self.percentComplete = percentComplete
        self.targetStartDate = targetStartDate
        self.targetEndDate = targetEndDate
        self.actualStartDate = actualStartDate
        self.actualEndDate = actualEndDate
        self.targetDuration = targetDuration
        self.remainingDuration = remainingDuration
    }
}

enum TaskType: String, Codable {
    case taskDependent = "TT_Task"
    case resourceDependent = "TT_Rsrc"
    case levelOfEffort = "TT_LOE"
    case startMilestone = "TT_Mile"
    case finishMilestone = "TT_FinMile"
    case wbsSummary = "TT_WBS"

    init(rawP6Value: String) {
        switch rawP6Value {
        case "TT_Task": self = .taskDependent
        case "TT_Rsrc": self = .resourceDependent
        case "TT_LOE": self = .levelOfEffort
        case "TT_Mile": self = .startMilestone
        case "TT_FinMile": self = .finishMilestone
        case "TT_WBS": self = .wbsSummary
        default: self = .taskDependent
        }
    }
}

enum TaskStatus: String, Codable {
    case notStarted = "TK_NotStart"
    case active = "TK_Active"
    case complete = "TK_Complete"

    init(rawP6Value: String) {
        switch rawP6Value {
        case "TK_NotStart": self = .notStarted
        case "TK_Active": self = .active
        case "TK_Complete": self = .complete
        default: self = .notStarted
        }
    }

    var displayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .active: return "In Progress"
        case .complete: return "Complete"
        }
    }
}
