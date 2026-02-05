import Foundation

struct Schedule: Codable, Equatable {
    var projects: [Project] = []
    var tasks: [ScheduleTask] = []
    var relationships: [Relationship] = []
    var resources: [Resource] = []
    var resourceAssignments: [ResourceAssignment] = []
    var calendars: [WorkCalendar] = []
    var wbsElements: [WBSElement] = []
    var activityCodeTypes: [ActivityCodeType] = []
    var activityCodes: [ActivityCode] = []
    var taskActivityCodes: [TaskActivityCode] = []

    var primaryProject: Project? {
        projects.first
    }

    var taskCount: Int {
        tasks.count
    }

    var milestones: [ScheduleTask] {
        tasks.filter { $0.taskType == .startMilestone || $0.taskType == .finishMilestone }
    }

    var criticalTasks: [ScheduleTask] {
        tasks.filter { $0.isCritical }
    }

    /// Get activity code types that have assignments (for grouping options)
    var availableGroupingCodeTypes: [ActivityCodeType] {
        let usedTypeIds = Set(taskActivityCodes.map { $0.typeId })
        return activityCodeTypes.filter { usedTypeIds.contains($0.id) }
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    /// Get activity codes for a specific type
    func activityCodes(forType typeId: String) -> [ActivityCode] {
        activityCodes.filter { $0.typeId == typeId }
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    /// Get activity code assignments for a task
    func activityCodeAssignments(forTask taskId: String) -> [TaskActivityCode] {
        taskActivityCodes.filter { $0.taskId == taskId }
    }

    /// Get the activity code value for a task and code type
    func activityCode(forTask taskId: String, typeId: String) -> ActivityCode? {
        guard let assignment = taskActivityCodes.first(where: { $0.taskId == taskId && $0.typeId == typeId }) else {
            return nil
        }
        return activityCodes.first { $0.id == assignment.codeId }
    }

    /// Group tasks by activity code type
    func tasksGroupedByActivityCode(typeId: String) -> [TaskGroup] {
        let codes = activityCodes(forType: typeId)
        var groups: [TaskGroup] = []

        for code in codes {
            let taskIds = taskActivityCodes
                .filter { $0.typeId == typeId && $0.codeId == code.id }
                .map { $0.taskId }
            let matchingTasks = tasks.filter { taskIds.contains($0.id) }

            if !matchingTasks.isEmpty {
                groups.append(TaskGroup(
                    id: code.id,
                    name: code.displayName,
                    color: code.color,
                    tasks: matchingTasks
                ))
            }
        }

        // Add unassigned tasks
        let assignedTaskIds = Set(taskActivityCodes.filter { $0.typeId == typeId }.map { $0.taskId })
        let unassignedTasks = tasks.filter { !assignedTaskIds.contains($0.id) }
        if !unassignedTasks.isEmpty {
            groups.append(TaskGroup(
                id: "unassigned",
                name: "Unassigned",
                color: nil,
                tasks: unassignedTasks
            ))
        }

        return groups
    }

    /// Group tasks by WBS
    func tasksGroupedByWBS() -> [TaskGroup] {
        var groups: [TaskGroup] = []

        for wbs in wbsElements.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
            let matchingTasks = tasks.filter { $0.wbsId == wbs.id }
            if !matchingTasks.isEmpty {
                groups.append(TaskGroup(
                    id: wbs.id,
                    name: wbs.name,
                    color: nil,
                    tasks: matchingTasks
                ))
            }
        }

        // Add tasks without WBS
        let unassignedTasks = tasks.filter { $0.wbsId == nil }
        if !unassignedTasks.isEmpty {
            groups.append(TaskGroup(
                id: "no-wbs",
                name: "No WBS",
                color: nil,
                tasks: unassignedTasks
            ))
        }

        return groups
    }

    /// Group tasks by status
    func tasksGroupedByStatus() -> [TaskGroup] {
        let statuses: [TaskStatus] = [.notStarted, .active, .complete]
        return statuses.compactMap { status in
            let matchingTasks = tasks.filter { $0.status == status }
            guard !matchingTasks.isEmpty else { return nil }
            return TaskGroup(
                id: status.rawValue,
                name: status.displayName,
                color: nil,
                tasks: matchingTasks
            )
        }
    }
}

struct Project: Codable, Equatable, Identifiable {
    let id: String
    let shortName: String
    let name: String
    let planStartDate: Date?
    let planEndDate: Date?
    let dataDate: Date?

    init(id: String, shortName: String, name: String = "",
         planStartDate: Date? = nil, planEndDate: Date? = nil, dataDate: Date? = nil) {
        self.id = id
        self.shortName = shortName
        self.name = name.isEmpty ? shortName : name
        self.planStartDate = planStartDate
        self.planEndDate = planEndDate
        self.dataDate = dataDate
    }
}

struct WBSElement: Codable, Equatable, Identifiable {
    let id: String
    let projectId: String
    let parentId: String?
    let name: String
    let shortName: String
    let sequenceNumber: Int

    init(id: String, projectId: String, parentId: String?, name: String, shortName: String, sequenceNumber: Int = 0) {
        self.id = id
        self.projectId = projectId
        self.parentId = parentId
        self.name = name
        self.shortName = shortName
        self.sequenceNumber = sequenceNumber
    }
}
