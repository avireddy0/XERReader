import Foundation

struct XERParser {
    // MARK: - Constants for DoS Prevention
    static let maxFileSizeBytes = 100 * 1024 * 1024 // 100 MB
    static let maxRowCount = 1_000_000

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    func parse(data: Data) throws -> Schedule {
        // Security: Check file size to prevent DoS
        let fileSizeMB = data.count / (1024 * 1024)
        if data.count > Self.maxFileSizeBytes {
            throw XERParseError.fileTooLarge(sizeMB: fileSizeMB, maxMB: Self.maxFileSizeBytes / (1024 * 1024))
        }

        // Try Windows-1252 first (common for P6), then UTF-8
        guard let content = String(data: data, encoding: .windowsCP1252)
                         ?? String(data: data, encoding: .utf8) else {
            throw XERParseError.encodingError
        }

        // Parse into table structures
        let tables = try parseTablesFromContent(content)

        // Validate we have required tables
        guard tables["PROJECT"] != nil else {
            throw XERParseError.missingRequiredTable("PROJECT")
        }

        return buildSchedule(from: tables)
    }

    private func parseTablesFromContent(_ content: String) throws -> [String: XERTable] {
        var tables: [String: XERTable] = [:]
        var currentTableName: String?
        var currentFields: [String] = []
        var currentRows: [[String: String]] = []
        var totalRowCount = 0

        // Handle both \r\n and \n line endings
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            // Security: Check row count to prevent DoS
            if totalRowCount > Self.maxRowCount {
                throw XERParseError.tooManyRows(count: totalRowCount, max: Self.maxRowCount)
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("%T") {
                // Save previous table if exists
                if let tableName = currentTableName {
                    tables[tableName] = XERTable(name: tableName, fields: currentFields, rows: currentRows)
                }
                // Start new table
                let parts = trimmed.components(separatedBy: "\t")
                currentTableName = parts.count > 1 ? parts[1] : nil
                currentFields = []
                currentRows = []

            } else if trimmed.hasPrefix("%F") {
                // Field definitions
                currentFields = Array(trimmed.components(separatedBy: "\t").dropFirst())

            } else if trimmed.hasPrefix("%R") {
                // Data row
                let values = Array(trimmed.components(separatedBy: "\t").dropFirst())
                guard !currentFields.isEmpty else { continue }

                var row: [String: String] = [:]
                for (index, field) in currentFields.enumerated() {
                    if index < values.count {
                        row[field] = values[index]
                    }
                }
                currentRows.append(row)
                totalRowCount += 1

            } else if trimmed.hasPrefix("%E") {
                // End marker - save current table
                if let tableName = currentTableName {
                    tables[tableName] = XERTable(name: tableName, fields: currentFields, rows: currentRows)
                }
                currentTableName = nil
                currentFields = []
                currentRows = []
            }
        }

        // Don't forget last table if file doesn't end with %E
        if let tableName = currentTableName, !currentRows.isEmpty {
            tables[tableName] = XERTable(name: tableName, fields: currentFields, rows: currentRows)
        }

        return tables
    }

    private func buildSchedule(from tables: [String: XERTable]) -> Schedule {
        var schedule = Schedule()

        schedule.projects = parseProjects(from: tables["PROJECT"])
        schedule.wbsElements = parseWBSElements(from: tables["PROJWBS"])
        schedule.calendars = parseCalendars(from: tables["CALENDAR"])
        schedule.tasks = parseTasks(from: tables["TASK"])
        schedule.relationships = parseRelationships(from: tables["TASKPRED"])
        schedule.resources = parseResources(from: tables["RSRC"])
        schedule.resourceAssignments = parseResourceAssignments(from: tables["TASKRSRC"])
        schedule.activityCodeTypes = parseActivityCodeTypes(from: tables["ACTVTYPE"])
        schedule.activityCodes = parseActivityCodes(from: tables["ACTVCODE"])
        schedule.taskActivityCodes = parseTaskActivityCodes(from: tables["TASKACTV"])

        calculateCriticalPath(&schedule)

        return schedule
    }

    // MARK: - Table Parsing Methods

    private func parseProjects(from table: XERTable?) -> [Project] {
        guard let table = table else { return [] }
        return table.rows.compactMap { row in
            guard let projId = row["proj_id"] else { return nil }
            return Project(
                id: projId,
                shortName: row["proj_short_name"] ?? "",
                name: row["proj_name"] ?? row["proj_short_name"] ?? "",
                planStartDate: parseDate(row["plan_start_date"]),
                planEndDate: parseDate(row["plan_end_date"]),
                dataDate: parseDate(row["last_recalc_date"])
            )
        }
    }

    private func parseWBSElements(from table: XERTable?) -> [WBSElement] {
        guard let table = table else { return [] }
        return table.rows.compactMap { row in
            guard let wbsId = row["wbs_id"] else { return nil }
            return WBSElement(
                id: wbsId,
                projectId: row["proj_id"] ?? "",
                parentId: row["parent_wbs_id"],
                name: row["wbs_name"] ?? "",
                shortName: row["wbs_short_name"] ?? "",
                sequenceNumber: Int(row["seq_num"] ?? "0") ?? 0
            )
        }
    }

    private func parseCalendars(from table: XERTable?) -> [WorkCalendar] {
        guard let table = table else { return [] }
        return table.rows.compactMap { row in
            guard let clndrId = row["clndr_id"] else { return nil }
            return WorkCalendar(
                id: clndrId,
                name: row["clndr_name"] ?? "",
                projectId: row["proj_id"],
                isDefault: row["default_flag"] == "Y",
                hoursPerDay: Double(row["day_hr_cnt"] ?? "8") ?? 8,
                hoursPerWeek: Double(row["week_hr_cnt"] ?? "40") ?? 40,
                hoursPerMonth: Double(row["month_hr_cnt"] ?? "172") ?? 172,
                hoursPerYear: Double(row["year_hr_cnt"] ?? "2080") ?? 2080
            )
        }
    }

    private func parseTasks(from table: XERTable?) -> [ScheduleTask] {
        guard let table = table else { return [] }
        return table.rows.compactMap { row in
            guard let taskId = row["task_id"] else { return nil }
            return ScheduleTask(
                id: taskId,
                projectId: row["proj_id"] ?? "",
                wbsId: row["wbs_id"],
                taskCode: row["task_code"] ?? "",
                name: row["task_name"] ?? "",
                taskType: TaskType(rawP6Value: row["task_type"] ?? "TT_Task"),
                status: TaskStatus(rawP6Value: row["status_code"] ?? "TK_NotStart"),
                percentComplete: Double(row["phys_complete_pct"] ?? "0") ?? 0,
                targetStartDate: parseDate(row["target_start_date"]),
                targetEndDate: parseDate(row["target_end_date"]),
                actualStartDate: parseDate(row["act_start_date"]),
                actualEndDate: parseDate(row["act_end_date"]),
                targetDuration: Double(row["target_drtn_hr_cnt"] ?? "0") ?? 0,
                remainingDuration: Double(row["remain_drtn_hr_cnt"] ?? "0") ?? 0
            )
        }
    }

    private func parseRelationships(from table: XERTable?) -> [Relationship] {
        guard let table = table else { return [] }
        return table.rows.compactMap { row in
            guard let taskId = row["task_id"],
                  let predTaskId = row["pred_task_id"] else { return nil }
            let lagHours = Double(row["lag_hr_cnt"] ?? "0") ?? 0
            return Relationship(
                taskId: taskId,
                predecessorTaskId: predTaskId,
                relationshipType: RelationshipType(rawP6Value: row["pred_type"] ?? "PR_FS"),
                lagDays: lagHours / 8
            )
        }
    }

    private func parseResources(from table: XERTable?) -> [Resource] {
        guard let table = table else { return [] }
        return table.rows.compactMap { row in
            guard let rsrcId = row["rsrc_id"] else { return nil }
            return Resource(
                id: rsrcId,
                shortName: row["rsrc_short_name"] ?? "",
                name: row["rsrc_name"] ?? "",
                resourceType: ResourceType(rawP6Value: row["rsrc_type"] ?? "RT_Labor"),
                unitOfMeasure: row["unit_name"],
                defaultUnitsPerTime: Double(row["def_qty_per_hr"] ?? "1") ?? 1
            )
        }
    }

    private func parseResourceAssignments(from table: XERTable?) -> [ResourceAssignment] {
        guard let table = table else { return [] }
        return table.rows.compactMap { row in
            guard let taskId = row["task_id"],
                  let rsrcId = row["rsrc_id"] else { return nil }
            return ResourceAssignment(
                taskId: taskId,
                resourceId: rsrcId,
                projectId: row["proj_id"] ?? "",
                targetQuantity: Double(row["target_qty"] ?? "0") ?? 0,
                actualQuantity: Double(row["act_reg_qty"] ?? "0") ?? 0,
                remainingQuantity: Double(row["remain_qty"] ?? "0") ?? 0,
                targetCost: Double(row["target_cost"] ?? "0") ?? 0,
                actualCost: Double(row["act_reg_cost"] ?? "0") ?? 0
            )
        }
    }

    private func parseActivityCodeTypes(from table: XERTable?) -> [ActivityCodeType] {
        guard let table = table else { return [] }
        return table.rows.compactMap { row in
            guard let typeId = row["actv_code_type_id"] else { return nil }
            return ActivityCodeType(
                id: typeId,
                name: row["actv_code_type"] ?? "",
                shortLength: Int(row["actv_short_len"] ?? "10") ?? 10,
                sequenceNumber: Int(row["seq_num"] ?? "0") ?? 0,
                projectId: row["proj_id"],
                scope: ActivityCodeScope(rawP6Value: row["actv_code_type_scope"] ?? "AS_Project")
            )
        }
    }

    private func parseActivityCodes(from table: XERTable?) -> [ActivityCode] {
        guard let table = table else { return [] }
        return table.rows.compactMap { row in
            guard let codeId = row["actv_code_id"] else { return nil }
            return ActivityCode(
                id: codeId,
                typeId: row["actv_code_type_id"] ?? "",
                parentId: row["parent_actv_code_id"],
                name: row["actv_code_name"] ?? "",
                shortName: row["short_name"] ?? "",
                sequenceNumber: Int(row["seq_num"] ?? "0") ?? 0,
                color: row["color"]
            )
        }
    }

    private func parseTaskActivityCodes(from table: XERTable?) -> [TaskActivityCode] {
        guard let table = table else { return [] }
        return table.rows.compactMap { row in
            guard let taskId = row["task_id"],
                  let codeId = row["actv_code_id"] else { return nil }
            return TaskActivityCode(
                taskId: taskId,
                typeId: row["actv_code_type_id"] ?? "",
                codeId: codeId,
                projectId: row["proj_id"] ?? ""
            )
        }
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string = string, !string.isEmpty else { return nil }
        return dateFormatter.date(from: string)
    }

    // MARK: - Critical Path Calculation

    private func calculateCriticalPath(_ schedule: inout Schedule) {
        let context = CPMContext(schedule: schedule)

        runForwardPass(schedule: &schedule, context: context)
        runBackwardPass(schedule: &schedule, context: context)
    }

    /// Context for Critical Path Method calculations
    private struct CPMContext {
        let taskById: [String: Int]
        let predecessors: [String: [Relationship]]
        let successors: [String: [Relationship]]

        init(schedule: Schedule) {
            var taskById: [String: Int] = [:]
            for (index, task) in schedule.tasks.enumerated() {
                taskById[task.id] = index
            }
            self.taskById = taskById

            var predecessors: [String: [Relationship]] = [:]
            var successors: [String: [Relationship]] = [:]
            for rel in schedule.relationships {
                predecessors[rel.taskId, default: []].append(rel)
                successors[rel.predecessorTaskId, default: []].append(rel)
            }
            self.predecessors = predecessors
            self.successors = successors
        }
    }

    private func runForwardPass(schedule: inout Schedule, context: CPMContext) {
        var visited = Set<String>()

        for task in schedule.tasks {
            processForwardPass(
                taskId: task.id,
                schedule: &schedule,
                context: context,
                visited: &visited
            )
        }
    }

    private func processForwardPass(
        taskId: String,
        schedule: inout Schedule,
        context: CPMContext,
        visited: inout Set<String>
    ) {
        guard !visited.contains(taskId),
              let index = context.taskById[taskId] else { return }

        // First process all predecessors
        for rel in context.predecessors[taskId] ?? [] {
            processForwardPass(
                taskId: rel.predecessorTaskId,
                schedule: &schedule,
                context: context,
                visited: &visited
            )
        }

        visited.insert(taskId)
        var task = schedule.tasks[index]

        // Calculate early start based on predecessors
        var earlyStart = task.targetStartDate ?? Date.distantPast

        for rel in context.predecessors[taskId] ?? [] {
            guard let predIndex = context.taskById[rel.predecessorTaskId] else { continue }
            let predTask = schedule.tasks[predIndex]

            let predDate = calculatePredecessorDate(
                relationship: rel,
                predecessorTask: predTask,
                currentTaskDuration: task.targetDuration
            )

            let withLag = predDate.addingTimeInterval(rel.lagDays * 24 * 3600)
            if withLag > earlyStart {
                earlyStart = withLag
            }
        }

        task.earlyStartDate = earlyStart
        task.earlyEndDate = earlyStart.addingTimeInterval(task.targetDuration * 3600)
        schedule.tasks[index] = task
    }

    private func calculatePredecessorDate(
        relationship: Relationship,
        predecessorTask: ScheduleTask,
        currentTaskDuration: Double
    ) -> Date {
        switch relationship.relationshipType {
        case .finishToStart:
            return predecessorTask.earlyEndDate ?? predecessorTask.targetEndDate ?? Date.distantPast
        case .startToStart:
            return predecessorTask.earlyStartDate ?? predecessorTask.targetStartDate ?? Date.distantPast
        case .finishToFinish:
            return (predecessorTask.earlyEndDate ?? predecessorTask.targetEndDate ?? Date.distantPast)
                .addingTimeInterval(-currentTaskDuration * 3600)
        case .startToFinish:
            return (predecessorTask.earlyStartDate ?? predecessorTask.targetStartDate ?? Date.distantPast)
                .addingTimeInterval(-currentTaskDuration * 3600)
        }
    }

    private func runBackwardPass(schedule: inout Schedule, context: CPMContext) {
        var visited = Set<String>()
        let projectEnd = schedule.tasks.compactMap { $0.earlyEndDate }.max() ?? Date()

        for task in schedule.tasks {
            processBackwardPass(
                taskId: task.id,
                schedule: &schedule,
                context: context,
                visited: &visited,
                projectEnd: projectEnd
            )
        }
    }

    private func processBackwardPass(
        taskId: String,
        schedule: inout Schedule,
        context: CPMContext,
        visited: inout Set<String>,
        projectEnd: Date
    ) {
        guard !visited.contains(taskId),
              let index = context.taskById[taskId] else { return }

        // First process all successors
        for rel in context.successors[taskId] ?? [] {
            processBackwardPass(
                taskId: rel.taskId,
                schedule: &schedule,
                context: context,
                visited: &visited,
                projectEnd: projectEnd
            )
        }

        visited.insert(taskId)
        var task = schedule.tasks[index]

        // Calculate late finish based on successors
        var lateFinish = projectEnd

        for rel in context.successors[taskId] ?? [] {
            guard let succIndex = context.taskById[rel.taskId] else { continue }
            let succTask = schedule.tasks[succIndex]

            let succDate = calculateSuccessorDate(
                relationship: rel,
                successorTask: succTask,
                currentTaskDuration: task.targetDuration,
                projectEnd: projectEnd
            )

            let withLag = succDate.addingTimeInterval(-rel.lagDays * 24 * 3600)
            if withLag < lateFinish {
                lateFinish = withLag
            }
        }

        task.lateEndDate = lateFinish
        task.lateStartDate = lateFinish.addingTimeInterval(-task.targetDuration * 3600)

        // Calculate float
        if let earlyStart = task.earlyStartDate, let lateStart = task.lateStartDate {
            task.totalFloat = lateStart.timeIntervalSince(earlyStart) / 3600 // hours
        }

        schedule.tasks[index] = task
    }

    private func calculateSuccessorDate(
        relationship: Relationship,
        successorTask: ScheduleTask,
        currentTaskDuration: Double,
        projectEnd: Date
    ) -> Date {
        switch relationship.relationshipType {
        case .finishToStart:
            return successorTask.lateStartDate ?? successorTask.targetStartDate ?? projectEnd
        case .startToStart:
            return (successorTask.lateStartDate ?? successorTask.targetStartDate ?? projectEnd)
                .addingTimeInterval(currentTaskDuration * 3600)
        case .finishToFinish:
            return successorTask.lateEndDate ?? successorTask.targetEndDate ?? projectEnd
        case .startToFinish:
            return successorTask.lateEndDate ?? successorTask.targetEndDate ?? projectEnd
        }
    }
}

struct XERTable {
    let name: String
    let fields: [String]
    let rows: [[String: String]]
}
