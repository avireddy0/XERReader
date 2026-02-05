import SwiftUI
import Combine

@MainActor
class ScheduleViewModel: ObservableObject {
    @Published var schedule: Schedule
    @Published var selectedTaskIds: Set<String> = []
    @Published var searchText: String = ""
    @Published var sortOrder: SortOrder = .byTaskCode
    @Published var sortAscending: Bool = true
    @Published var filterStatus: TaskStatus? = nil
    @Published var showCriticalOnly: Bool = false
    @Published var groupingConfig: GroupingConfiguration = GroupingConfiguration()
    @Published var viewMode: ViewMode = .table

    private var cancellables = Set<AnyCancellable>()

    init(schedule: Schedule = Schedule()) {
        self.schedule = schedule
    }

    enum ViewMode: String, CaseIterable {
        case table = "Table"
        case gantt = "Gantt"
    }

    var selectedTasks: [ScheduleTask] {
        schedule.tasks.filter { selectedTaskIds.contains($0.id) }
    }

    var filteredTasks: [ScheduleTask] {
        var tasks = schedule.tasks

        // Filter by search text
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            tasks = tasks.filter {
                $0.name.lowercased().contains(search) ||
                $0.taskCode.lowercased().contains(search)
            }
        }

        // Filter by status
        if let status = filterStatus {
            tasks = tasks.filter { $0.status == status }
        }

        // Filter critical only
        if showCriticalOnly {
            tasks = tasks.filter { $0.isCritical }
        }

        // Sort
        tasks = sortTasks(tasks)

        return tasks
    }

    private func sortTasks(_ tasks: [ScheduleTask]) -> [ScheduleTask] {
        let sorted: [ScheduleTask]

        switch sortOrder {
        case .byTaskCode:
            sorted = tasks.sorted { $0.taskCode.localizedCompare($1.taskCode) == .orderedAscending }
        case .byName:
            sorted = tasks.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .byStartDate:
            sorted = tasks.sorted {
                ($0.targetStartDate ?? .distantFuture) < ($1.targetStartDate ?? .distantFuture)
            }
        case .byEndDate:
            sorted = tasks.sorted {
                ($0.targetEndDate ?? .distantFuture) < ($1.targetEndDate ?? .distantFuture)
            }
        case .byDuration:
            sorted = tasks.sorted { $0.targetDuration < $1.targetDuration }
        case .byFloat:
            sorted = tasks.sorted { $0.totalFloat < $1.totalFloat }
        case .byStatus:
            sorted = tasks.sorted { $0.status.rawValue < $1.status.rawValue }
        }

        return sortAscending ? sorted : sorted.reversed()
    }

    func toggleSelection(_ taskId: String) {
        if selectedTaskIds.contains(taskId) {
            selectedTaskIds.remove(taskId)
        } else {
            selectedTaskIds.insert(taskId)
        }
    }

    func selectAll() {
        selectedTaskIds = Set(filteredTasks.map { $0.id })
    }

    func clearSelection() {
        selectedTaskIds.removeAll()
    }

    func task(byId id: String) -> ScheduleTask? {
        schedule.tasks.first { $0.id == id }
    }

    func predecessors(of task: ScheduleTask) -> [ScheduleTask] {
        let predIds = schedule.relationships
            .filter { $0.taskId == task.id }
            .map { $0.predecessorTaskId }
        return schedule.tasks.filter { predIds.contains($0.id) }
    }

    func successors(of task: ScheduleTask) -> [ScheduleTask] {
        let succIds = schedule.relationships
            .filter { $0.predecessorTaskId == task.id }
            .map { $0.taskId }
        return schedule.tasks.filter { succIds.contains($0.id) }
    }

    func resources(for task: ScheduleTask) -> [Resource] {
        let assignments = schedule.resourceAssignments.filter { $0.taskId == task.id }
        let resourceIds = assignments.map { $0.resourceId }
        return schedule.resources.filter { resourceIds.contains($0.id) }
    }

    func wbs(for task: ScheduleTask) -> WBSElement? {
        guard let wbsId = task.wbsId else { return nil }
        return schedule.wbsElements.first { $0.id == wbsId }
    }

    // Statistics
    var totalDuration: Int {
        guard let start = schedule.primaryProject?.planStartDate,
              let end = schedule.primaryProject?.planEndDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }

    var completedPercentage: Double {
        guard !schedule.tasks.isEmpty else { return 0 }
        let completed = schedule.tasks.filter { $0.status == .complete }.count
        return Double(completed) / Double(schedule.tasks.count) * 100
    }

    var criticalPathLength: Int {
        schedule.criticalTasks.reduce(0) { $0 + $1.durationDays }
    }

    // MARK: - Grouping

    var availableGroupingOptions: [GroupingConfiguration.GroupingOption] {
        var options: [GroupingConfiguration.GroupingOption] = [.none, .wbs, .status, .critical]

        // Add activity code types
        for codeType in schedule.availableGroupingCodeTypes {
            options.append(.activityCode(typeId: codeType.id, typeName: codeType.name))
        }

        return options
    }

    var taskGroups: [TaskGroup] {
        switch groupingConfig.primaryGrouping {
        case .none:
            return []
        case .wbs:
            return schedule.tasksGroupedByWBS().map { group in
                var g = group
                g.isExpanded = groupingConfig.expandedGroups.contains(group.id)
                return g
            }
        case .status:
            return schedule.tasksGroupedByStatus().map { group in
                var g = group
                g.isExpanded = groupingConfig.expandedGroups.contains(group.id)
                return g
            }
        case .critical:
            let critical = filteredTasks.filter { $0.isCritical }
            let nonCritical = filteredTasks.filter { !$0.isCritical }
            var groups: [TaskGroup] = []
            if !critical.isEmpty {
                groups.append(TaskGroup(id: "critical", name: "Critical Path", tasks: critical,
                                        isExpanded: groupingConfig.expandedGroups.contains("critical")))
            }
            if !nonCritical.isEmpty {
                groups.append(TaskGroup(id: "non-critical", name: "Non-Critical", tasks: nonCritical,
                                        isExpanded: groupingConfig.expandedGroups.contains("non-critical")))
            }
            return groups
        case .activityCode(let typeId, _):
            return schedule.tasksGroupedByActivityCode(typeId: typeId).map { group in
                var g = group
                g.isExpanded = groupingConfig.expandedGroups.contains(group.id)
                return g
            }
        }
    }

    func setGrouping(_ option: GroupingConfiguration.GroupingOption) {
        groupingConfig.primaryGrouping = option
        // Expand all groups by default
        if option != .none {
            groupingConfig.expandedGroups = Set(taskGroups.map { $0.id })
        }
    }

    func toggleGroupExpansion(_ groupId: String) {
        if groupingConfig.expandedGroups.contains(groupId) {
            groupingConfig.expandedGroups.remove(groupId)
        } else {
            groupingConfig.expandedGroups.insert(groupId)
        }
    }

    func isGroupExpanded(_ groupId: String) -> Bool {
        groupingConfig.expandedGroups.contains(groupId)
    }

    func expandAllGroups() {
        groupingConfig.expandedGroups = Set(taskGroups.map { $0.id })
    }

    func collapseAllGroups() {
        groupingConfig.expandedGroups.removeAll()
    }

    // MARK: - Activity Codes

    func activityCode(for task: ScheduleTask, typeId: String) -> ActivityCode? {
        schedule.activityCode(forTask: task.id, typeId: typeId)
    }

    func activityCodeTypes() -> [ActivityCodeType] {
        schedule.activityCodeTypes
    }
}

enum SortOrder: String, CaseIterable {
    case byTaskCode = "Task Code"
    case byName = "Name"
    case byStartDate = "Start Date"
    case byEndDate = "End Date"
    case byDuration = "Duration"
    case byFloat = "Float"
    case byStatus = "Status"
}
