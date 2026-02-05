import Foundation

/// Activity Code Type - defines a grouping category (e.g., "Phase", "Area", "Discipline")
struct ActivityCodeType: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let shortLength: Int
    let sequenceNumber: Int
    let projectId: String?
    let scope: ActivityCodeScope

    init(id: String, name: String, shortLength: Int = 10, sequenceNumber: Int = 0,
         projectId: String? = nil, scope: ActivityCodeScope = .project) {
        self.id = id
        self.name = name
        self.shortLength = shortLength
        self.sequenceNumber = sequenceNumber
        self.projectId = projectId
        self.scope = scope
    }
}

enum ActivityCodeScope: String, Codable {
    case global = "AS_Global"
    case eps = "AS_EPS"
    case project = "AS_Project"

    init(rawP6Value: String) {
        switch rawP6Value {
        case "AS_Global": self = .global
        case "AS_EPS": self = .eps
        case "AS_Project": self = .project
        default: self = .project
        }
    }
}

/// Activity Code Value - a specific value within an activity code type (e.g., "Design" under "Phase")
struct ActivityCode: Codable, Equatable, Identifiable {
    let id: String
    let typeId: String
    let parentId: String?
    let name: String
    let shortName: String
    let sequenceNumber: Int
    let color: String?

    init(id: String, typeId: String, parentId: String? = nil, name: String,
         shortName: String, sequenceNumber: Int = 0, color: String? = nil) {
        self.id = id
        self.typeId = typeId
        self.parentId = parentId
        self.name = name
        self.shortName = shortName
        self.sequenceNumber = sequenceNumber
        self.color = color
    }

    var displayName: String {
        name.isEmpty ? shortName : name
    }
}

/// Links a task to an activity code value
struct TaskActivityCode: Codable, Equatable, Identifiable {
    var id: String { "\(taskId)-\(codeId)" }

    let taskId: String
    let typeId: String
    let codeId: String
    let projectId: String

    init(taskId: String, typeId: String, codeId: String, projectId: String) {
        self.taskId = taskId
        self.typeId = typeId
        self.codeId = codeId
        self.projectId = projectId
    }
}

/// Grouping configuration for schedule view
struct GroupingConfiguration: Equatable {
    var primaryGrouping: GroupingOption = .none
    var secondaryGrouping: GroupingOption = .none
    var expandedGroups: Set<String> = []

    enum GroupingOption: Equatable, Hashable {
        case none
        case wbs
        case activityCode(typeId: String, typeName: String)
        case status
        case critical

        var displayName: String {
            switch self {
            case .none: return "No Grouping"
            case .wbs: return "WBS"
            case .activityCode(_, let name): return name
            case .status: return "Status"
            case .critical: return "Critical Path"
            }
        }

        static func == (lhs: GroupingOption, rhs: GroupingOption) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none), (.wbs, .wbs), (.status, .status), (.critical, .critical):
                return true
            case (.activityCode(let id1, _), .activityCode(let id2, _)):
                return id1 == id2
            default:
                return false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case .none: hasher.combine("none")
            case .wbs: hasher.combine("wbs")
            case .activityCode(let id, _): hasher.combine("activityCode-\(id)")
            case .status: hasher.combine("status")
            case .critical: hasher.combine("critical")
            }
        }
    }
}

/// A group of tasks for display
struct TaskGroup: Identifiable {
    let id: String
    let name: String
    let color: String?
    let tasks: [ScheduleTask]
    let level: Int
    var isExpanded: Bool

    var taskCount: Int { tasks.count }

    var totalDuration: Int {
        tasks.reduce(0) { $0 + $1.durationDays }
    }

    var criticalCount: Int {
        tasks.filter { $0.isCritical }.count
    }

    init(id: String, name: String, color: String? = nil, tasks: [ScheduleTask], level: Int = 0, isExpanded: Bool = true) {
        self.id = id
        self.name = name
        self.color = color
        self.tasks = tasks
        self.level = level
        self.isExpanded = isExpanded
    }
}
