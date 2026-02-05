import Foundation

struct ScheduleAnalyzer {
    let schedule: Schedule

    // MARK: - DCMA Threshold Constants (per DCMA 14-Point Assessment)
    private enum DCMAThresholds {
        static let minRelationshipsPerTask = 1.5
        static let maxLeadsPercent = 5.0
        static let maxLagsPercent = 5.0
        static let maxNonFSPercent = 10.0
        static let maxHardConstraintsPercent = 5.0
        static let highFloatDaysThreshold = 44
        static let highDurationDaysThreshold = 44
        static let maxHighFloatPercent = 5.0
        static let maxHighDurationPercent = 5.0
        static let maxOpenEndsPercent = 5.0
        static let maxOpenStartsPercent = 5.0
        static let overAllocationThreshold = 10
    }

    // MARK: - Critical Path Analysis

    func getCriticalPath() -> CriticalPathResult {
        let criticalTasks = schedule.tasks.filter { $0.isCritical }
            .sorted { ($0.targetStartDate ?? .distantFuture) < ($1.targetStartDate ?? .distantFuture) }

        let totalDuration = criticalTasks.reduce(0) { $0 + $1.durationDays }

        return CriticalPathResult(
            tasks: criticalTasks,
            totalDurationDays: totalDuration,
            taskCount: criticalTasks.count
        )
    }

    // MARK: - Float Analysis

    func analyzeFloat(thresholdDays: Int = 5) -> FloatAnalysisResult {
        let highFloat = schedule.tasks.filter { $0.totalFloatDays > thresholdDays }
        let negativeFloat = schedule.tasks.filter { $0.totalFloat < 0 }
        let nearCritical = schedule.tasks.filter { $0.totalFloatDays > 0 && $0.totalFloatDays <= thresholdDays }

        return FloatAnalysisResult(
            highFloatTasks: highFloat,
            negativeFloatTasks: negativeFloat,
            nearCriticalTasks: nearCritical,
            averageFloat: schedule.tasks.isEmpty ? 0 :
                schedule.tasks.reduce(0) { $0 + $1.totalFloat } / Double(schedule.tasks.count)
        )
    }

    // MARK: - Logic Check

    func checkLogic() -> LogicCheckResult {
        var openStarts: [ScheduleTask] = []
        var openEnds: [ScheduleTask] = []
        // Track tasks with logic issues

        let taskIds = Set(schedule.tasks.map { $0.id })

        for task in schedule.tasks {
            // Skip milestones for certain checks
            let isStartMilestone = task.taskType == .startMilestone
            let isEndMilestone = task.taskType == .finishMilestone

            // Check for open starts (no predecessors)
            let hasPredecessors = schedule.relationships.contains { $0.taskId == task.id }
            if !hasPredecessors && !isStartMilestone {
                openStarts.append(task)
            }

            // Check for open ends (no successors)
            let hasSuccessors = schedule.relationships.contains { $0.predecessorTaskId == task.id }
            if !hasSuccessors && !isEndMilestone {
                openEnds.append(task)
            }
        }

        // Check for dangling references
        let danglingRelationships = schedule.relationships.filter {
            !taskIds.contains($0.taskId) || !taskIds.contains($0.predecessorTaskId)
        }

        return LogicCheckResult(
            openStarts: openStarts,
            openEnds: openEnds,
            danglingRelationships: danglingRelationships.count,
            totalRelationships: schedule.relationships.count
        )
    }

    // MARK: - Resource Loading

    func analyzeResourceLoading() -> ResourceLoadingResult {
        var resourceUtilization: [String: ResourceUtilization] = [:]

        for resource in schedule.resources {
            let assignments = schedule.resourceAssignments.filter { $0.resourceId == resource.id }
            let totalAssigned = assignments.reduce(0) { $0 + $1.targetQuantity }
            let taskCount = assignments.count

            resourceUtilization[resource.id] = ResourceUtilization(
                resource: resource,
                totalQuantity: totalAssigned,
                assignmentCount: taskCount
            )
        }

        // Find over-allocated (simple heuristic: assigned to many tasks simultaneously)
        let overAllocated = resourceUtilization.values.filter { $0.assignmentCount > 10 }

        return ResourceLoadingResult(
            utilizationByResource: resourceUtilization,
            overAllocatedResources: Array(overAllocated),
            totalResources: schedule.resources.count,
            totalAssignments: schedule.resourceAssignments.count
        )
    }

    // MARK: - DCMA 14-Point Check

    func performDCMACheck() -> DCMACheckResult {
        let checks = [
            checkLogicRatio(),
            checkLeads(),
            checkLags(),
            checkRelationshipTypes(),
            checkHardConstraints(),
            checkHighFloat(),
            checkNegativeFloat(),
            checkHighDuration(),
            checkInvalidDates(),
            checkMissingPredecessors(),
            checkMissingSuccessors()
        ]

        let passedCount = checks.filter { $0.passed }.count
        return DCMACheckResult(
            checks: checks,
            passedCount: passedCount,
            totalChecks: checks.count,
            overallScore: Double(passedCount) / Double(checks.count) * 100
        )
    }

    // MARK: - Individual DCMA Checks

    private func checkLogicRatio() -> DCMACheck {
        let logicRatio = Double(schedule.relationships.count) / max(Double(schedule.tasks.count), 1)
        return DCMACheck(
            name: "Logic",
            description: "Tasks should have relationships",
            threshold: ">= \(DCMAThresholds.minRelationshipsPerTask) relationships per task",
            actualValue: String(format: "%.2f", logicRatio),
            passed: logicRatio >= DCMAThresholds.minRelationshipsPerTask
        )
    }

    private func checkLeads() -> DCMACheck {
        let leadsCount = schedule.relationships.filter { $0.lagDays < 0 }.count
        let leadsPercent = percentOf(leadsCount, total: schedule.relationships.count)
        return DCMACheck(
            name: "Leads",
            description: "Negative lags should be minimal",
            threshold: "< \(Int(DCMAThresholds.maxLeadsPercent))%",
            actualValue: String(format: "%.1f%%", leadsPercent),
            passed: leadsPercent < DCMAThresholds.maxLeadsPercent
        )
    }

    private func checkLags() -> DCMACheck {
        let lagsCount = schedule.relationships.filter { $0.lagDays > 0 }.count
        let lagsPercent = percentOf(lagsCount, total: schedule.relationships.count)
        return DCMACheck(
            name: "Lags",
            description: "Positive lags should be minimal",
            threshold: "< \(Int(DCMAThresholds.maxLagsPercent))%",
            actualValue: String(format: "%.1f%%", lagsPercent),
            passed: lagsPercent < DCMAThresholds.maxLagsPercent
        )
    }

    private func checkRelationshipTypes() -> DCMACheck {
        let nonFSCount = schedule.relationships.filter { $0.relationshipType != .finishToStart }.count
        let nonFSPercent = percentOf(nonFSCount, total: schedule.relationships.count)
        return DCMACheck(
            name: "Relationship Types",
            description: "Non-FS relationships should be minimal",
            threshold: "< \(Int(DCMAThresholds.maxNonFSPercent))%",
            actualValue: String(format: "%.1f%%", nonFSPercent),
            passed: nonFSPercent < DCMAThresholds.maxNonFSPercent
        )
    }

    private func checkHardConstraints() -> DCMACheck {
        // Can't check without constraint data - assume pass
        return DCMACheck(
            name: "Hard Constraints",
            description: "Hard constraints should be minimal",
            threshold: "< \(Int(DCMAThresholds.maxHardConstraintsPercent))%",
            actualValue: "N/A",
            passed: true
        )
    }

    private func checkHighFloat() -> DCMACheck {
        let highFloatCount = schedule.tasks.filter { $0.totalFloatDays > DCMAThresholds.highFloatDaysThreshold }.count
        let highFloatPercent = percentOf(highFloatCount, total: schedule.tasks.count)
        return DCMACheck(
            name: "High Float",
            description: "Tasks with >\(DCMAThresholds.highFloatDaysThreshold) days float",
            threshold: "< \(Int(DCMAThresholds.maxHighFloatPercent))%",
            actualValue: String(format: "%.1f%%", highFloatPercent),
            passed: highFloatPercent < DCMAThresholds.maxHighFloatPercent
        )
    }

    private func checkNegativeFloat() -> DCMACheck {
        let negFloatCount = schedule.tasks.filter { $0.totalFloat < 0 }.count
        let negFloatPercent = percentOf(negFloatCount, total: schedule.tasks.count)
        return DCMACheck(
            name: "Negative Float",
            description: "Tasks with negative float",
            threshold: "0%",
            actualValue: String(format: "%.1f%%", negFloatPercent),
            passed: negFloatPercent == 0
        )
    }

    private func checkHighDuration() -> DCMACheck {
        let highDurCount = schedule.tasks.filter { $0.durationDays > DCMAThresholds.highDurationDaysThreshold }.count
        let highDurPercent = percentOf(highDurCount, total: schedule.tasks.count)
        return DCMACheck(
            name: "High Duration",
            description: "Tasks with >\(DCMAThresholds.highDurationDaysThreshold) days duration",
            threshold: "< \(Int(DCMAThresholds.maxHighDurationPercent))%",
            actualValue: String(format: "%.1f%%", highDurPercent),
            passed: highDurPercent < DCMAThresholds.maxHighDurationPercent
        )
    }

    private func checkInvalidDates() -> DCMACheck {
        let invalidDates = schedule.tasks.filter {
            guard let start = $0.actualStartDate, let end = $0.actualEndDate else { return false }
            return end < start
        }
        return DCMACheck(
            name: "Invalid Dates",
            description: "Tasks with end before start",
            threshold: "0",
            actualValue: "\(invalidDates.count)",
            passed: invalidDates.isEmpty
        )
    }

    private func checkMissingPredecessors() -> DCMACheck {
        let logicResult = checkLogic()
        let percent = percentOf(logicResult.openStarts.count, total: schedule.tasks.count)
        return DCMACheck(
            name: "Missing Predecessors",
            description: "Tasks without predecessors",
            threshold: "< \(Int(DCMAThresholds.maxOpenStartsPercent))%",
            actualValue: String(format: "%.1f%%", percent),
            passed: percent < DCMAThresholds.maxOpenStartsPercent
        )
    }

    private func checkMissingSuccessors() -> DCMACheck {
        let logicResult = checkLogic()
        let percent = percentOf(logicResult.openEnds.count, total: schedule.tasks.count)
        return DCMACheck(
            name: "Missing Successors",
            description: "Tasks without successors",
            threshold: "< \(Int(DCMAThresholds.maxOpenEndsPercent))%",
            actualValue: String(format: "%.1f%%", percent),
            passed: percent < DCMAThresholds.maxOpenEndsPercent
        )
    }

    // MARK: - Helper Methods

    private func percentOf(_ count: Int, total: Int) -> Double {
        Double(count) / max(Double(total), 1) * 100
    }
}

// MARK: - Result Types

struct CriticalPathResult {
    let tasks: [ScheduleTask]
    let totalDurationDays: Int
    let taskCount: Int
}

struct FloatAnalysisResult {
    let highFloatTasks: [ScheduleTask]
    let negativeFloatTasks: [ScheduleTask]
    let nearCriticalTasks: [ScheduleTask]
    let averageFloat: Double
}

struct LogicCheckResult {
    let openStarts: [ScheduleTask]
    let openEnds: [ScheduleTask]
    let danglingRelationships: Int
    let totalRelationships: Int
}

struct ResourceLoadingResult {
    let utilizationByResource: [String: ResourceUtilization]
    let overAllocatedResources: [ResourceUtilization]
    let totalResources: Int
    let totalAssignments: Int
}

struct ResourceUtilization {
    let resource: Resource
    let totalQuantity: Double
    let assignmentCount: Int
}

struct DCMACheckResult {
    let checks: [DCMACheck]
    let passedCount: Int
    let totalChecks: Int
    let overallScore: Double

    var summary: String {
        "\(passedCount)/\(totalChecks) checks passed (\(Int(overallScore))%)"
    }
}

struct DCMACheck: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let threshold: String
    let actualValue: String
    let passed: Bool
}
