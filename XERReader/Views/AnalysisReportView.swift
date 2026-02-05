import SwiftUI
import AppKit

struct AnalysisReportView: View {
    let schedule: Schedule
    let results: [AnalysisResult]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReportType: ReportType = .summary
    @State private var isExporting = false
    @State private var exportError: String?

    private let analyzer: ScheduleAnalyzer

    init(schedule: Schedule, results: [AnalysisResult]) {
        self.schedule = schedule
        self.results = results
        self.analyzer = ScheduleAnalyzer(schedule: schedule)
    }

    var body: some View {
        NavigationStack {
            HSplitView {
                // Report type selector
                List(ReportType.allCases, id: \.self, selection: $selectedReportType) { type in
                    Label(type.rawValue, systemImage: type.icon)
                }
                .listStyle(.sidebar)
                .frame(width: 180)

                // Report content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedReportType {
                        case .summary:
                            SummaryReportSection(schedule: schedule, analyzer: analyzer)
                        case .criticalPath:
                            CriticalPathReportSection(analyzer: analyzer)
                        case .float:
                            FloatReportSection(analyzer: analyzer)
                        case .logic:
                            LogicReportSection(analyzer: analyzer)
                        case .dcma:
                            DCMAReportSection(analyzer: analyzer)
                        case .resources:
                            ResourceReportSection(analyzer: analyzer)
                        case .history:
                            HistoryReportSection(results: results)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Schedule Analysis")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        exportReport()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isExporting)
                }
            }
            .alert("Export Error", isPresented: .constant(exportError != nil)) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "Unknown error")
            }
        }
    }

    private func exportReport() {
        isExporting = true
        exportError = nil

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Schedule_Analysis_Report.txt"
        panel.title = "Export Analysis Report"
        panel.message = "Choose a location to save the schedule analysis report"

        panel.begin { response in
            isExporting = false

            guard response == .OK, let url = panel.url else { return }

            do {
                let reportContent = generateReportContent()
                try reportContent.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                exportError = "Failed to export report: \(error.localizedDescription)"
            }
        }
    }

    private func generateReportContent() -> String {
        var report = """
        ================================================================================
        SCHEDULE ANALYSIS REPORT
        Generated: \(Date().formatted(date: .long, time: .shortened))
        ================================================================================

        """

        // Project Information
        if let project = schedule.primaryProject {
            report += """

            PROJECT INFORMATION
            --------------------------------------------------------------------------------
            Name:       \(project.name)
            Start:      \(project.planStartDate?.formatted(date: .long, time: .omitted) ?? "N/A")
            End:        \(project.planEndDate?.formatted(date: .long, time: .omitted) ?? "N/A")
            Data Date:  \(project.dataDate?.formatted(date: .long, time: .omitted) ?? "N/A")

            """
        }

        // Statistics
        report += """

        SCHEDULE STATISTICS
        --------------------------------------------------------------------------------
        Total Activities:     \(schedule.taskCount)
        Critical Activities:  \(schedule.criticalTasks.count)
        Milestones:          \(schedule.milestones.count)
        Relationships:       \(schedule.relationships.count)
        Resources:           \(schedule.resources.count)

        """

        // Critical Path
        let criticalPath = analyzer.getCriticalPath()
        report += """

        CRITICAL PATH ANALYSIS
        --------------------------------------------------------------------------------
        Critical Activities: \(criticalPath.taskCount)
        Total Duration:      \(criticalPath.totalDurationDays) days

        Critical Activities:
        """
        for task in criticalPath.tasks.prefix(20) {
            report += "\n  • \(task.taskCode): \(task.name) (\(task.durationDays)d)"
        }
        if criticalPath.tasks.count > 20 {
            report += "\n  ... and \(criticalPath.tasks.count - 20) more"
        }

        // Float Analysis
        let floatAnalysis = analyzer.analyzeFloat()
        report += """


        FLOAT ANALYSIS
        --------------------------------------------------------------------------------
        High Float (>5 days):  \(floatAnalysis.highFloatTasks.count) activities
        Near Critical:         \(floatAnalysis.nearCriticalTasks.count) activities
        Negative Float:        \(floatAnalysis.negativeFloatTasks.count) activities

        """
        if !floatAnalysis.negativeFloatTasks.isEmpty {
            report += "Negative Float Activities:\n"
            for task in floatAnalysis.negativeFloatTasks.prefix(10) {
                report += "  • \(task.taskCode): \(task.name) (\(task.totalFloatDays)d float)\n"
            }
        }

        // Logic Check
        let logicCheck = analyzer.checkLogic()
        report += """

        LOGIC CHECK
        --------------------------------------------------------------------------------
        Open Starts (no predecessors):  \(logicCheck.openStarts.count)
        Open Ends (no successors):      \(logicCheck.openEnds.count)
        Dangling References:            \(logicCheck.danglingRelationships)

        """

        // DCMA 14-Point
        let dcma = analyzer.performDCMACheck()
        report += """

        DCMA 14-POINT ASSESSMENT
        --------------------------------------------------------------------------------
        Overall Score: \(String(format: "%.0f%%", dcma.overallScore))
        Checks Passed: \(dcma.passedCount) of \(dcma.totalChecks)

        Check Results:
        """
        for check in dcma.checks {
            let status = check.passed ? "PASS" : "FAIL"
            report += "\n  [\(status)] \(check.name): \(check.actualValue) (threshold: \(check.threshold))"
        }

        // Analysis History
        if !results.isEmpty {
            report += """


            ANALYSIS HISTORY
            --------------------------------------------------------------------------------
            """
            for result in results {
                report += "\n\n[\(result.timestamp.formatted())] \(result.title)\n"
                report += result.summary
            }
        }

        report += """


        ================================================================================
        END OF REPORT
        ================================================================================
        """

        return report
    }
}

enum ReportType: String, CaseIterable {
    case summary = "Summary"
    case criticalPath = "Critical Path"
    case float = "Float Analysis"
    case logic = "Logic Check"
    case dcma = "DCMA 14-Point"
    case resources = "Resources"
    case history = "History"

    var icon: String {
        switch self {
        case .summary: return "doc.text"
        case .criticalPath: return "arrow.right.circle"
        case .float: return "clock"
        case .logic: return "link"
        case .dcma: return "checkmark.shield"
        case .resources: return "person.3"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

struct SummaryReportSection: View {
    let schedule: Schedule
    let analyzer: ScheduleAnalyzer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Schedule Summary")
                .font(.title)

            if let project = schedule.primaryProject {
                GroupBox("Project Information") {
                    Grid(alignment: .leading, verticalSpacing: 8) {
                        GridRow {
                            Text("Name:").foregroundColor(.secondary)
                            Text(project.name)
                        }
                        GridRow {
                            Text("Start:").foregroundColor(.secondary)
                            Text(project.planStartDate?.formatted(date: .long, time: .omitted) ?? "-")
                        }
                        GridRow {
                            Text("End:").foregroundColor(.secondary)
                            Text(project.planEndDate?.formatted(date: .long, time: .omitted) ?? "-")
                        }
                        GridRow {
                            Text("Data Date:").foregroundColor(.secondary)
                            Text(project.dataDate?.formatted(date: .long, time: .omitted) ?? "-")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox("Statistics") {
                Grid(alignment: .leading, verticalSpacing: 8) {
                    GridRow {
                        Text("Total Activities:").foregroundColor(.secondary)
                        Text("\(schedule.taskCount)")
                    }
                    GridRow {
                        Text("Critical Activities:").foregroundColor(.secondary)
                        Text("\(schedule.criticalTasks.count)")
                            .foregroundColor(schedule.criticalTasks.count > 0 ? .red : .primary)
                    }
                    GridRow {
                        Text("Milestones:").foregroundColor(.secondary)
                        Text("\(schedule.milestones.count)")
                    }
                    GridRow {
                        Text("Relationships:").foregroundColor(.secondary)
                        Text("\(schedule.relationships.count)")
                    }
                    GridRow {
                        Text("Resources:").foregroundColor(.secondary)
                        Text("\(schedule.resources.count)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            let dcma = analyzer.performDCMACheck()
            GroupBox("Health Score") {
                VStack(alignment: .leading) {
                    HStack {
                        Text(String(format: "%.0f%%", dcma.overallScore))
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(dcma.overallScore >= 80 ? .green : dcma.overallScore >= 60 ? .orange : .red)

                        VStack(alignment: .leading) {
                            Text("DCMA Score")
                                .font(.headline)
                            Text("\(dcma.passedCount) of \(dcma.totalChecks) checks passed")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct CriticalPathReportSection: View {
    let analyzer: ScheduleAnalyzer

    var body: some View {
        let result = analyzer.getCriticalPath()

        VStack(alignment: .leading, spacing: 16) {
            Text("Critical Path Analysis")
                .font(.title)

            Text("\(result.taskCount) critical activities totaling \(result.totalDurationDays) days")
                .foregroundColor(.secondary)

            GroupBox("Critical Activities") {
                if result.tasks.isEmpty {
                    Text("No critical activities found")
                        .foregroundColor(.secondary)
                } else {
                    Table(result.tasks) {
                        TableColumn("Code", value: \.taskCode)
                        TableColumn("Name", value: \.name)
                        TableColumn("Start") { task in
                            Text(task.targetStartDate?.formatted(date: .abbreviated, time: .omitted) ?? "-")
                        }
                        TableColumn("Duration") { task in
                            Text("\(task.durationDays)d")
                        }
                    }
                    .frame(height: min(CGFloat(result.tasks.count * 30 + 40), 400))
                }
            }
        }
    }
}

struct FloatReportSection: View {
    let analyzer: ScheduleAnalyzer

    var body: some View {
        let result = analyzer.analyzeFloat()

        VStack(alignment: .leading, spacing: 16) {
            Text("Float Analysis")
                .font(.title)

            HStack(spacing: 20) {
                StatCard(title: "High Float (>5d)", value: "\(result.highFloatTasks.count)", color: .blue)
                StatCard(title: "Near Critical", value: "\(result.nearCriticalTasks.count)", color: .orange)
                StatCard(title: "Negative Float", value: "\(result.negativeFloatTasks.count)", color: .red)
            }

            if !result.negativeFloatTasks.isEmpty {
                GroupBox("Negative Float Tasks") {
                    Table(result.negativeFloatTasks) {
                        TableColumn("Code", value: \.taskCode)
                        TableColumn("Name", value: \.name)
                        TableColumn("Float") { task in
                            Text("\(task.totalFloatDays)d")
                                .foregroundColor(.red)
                        }
                    }
                    .frame(height: min(CGFloat(result.negativeFloatTasks.count * 30 + 40), 300))
                }
            }
        }
    }
}

struct LogicReportSection: View {
    let analyzer: ScheduleAnalyzer

    var body: some View {
        let result = analyzer.checkLogic()

        VStack(alignment: .leading, spacing: 16) {
            Text("Logic Check")
                .font(.title)

            HStack(spacing: 20) {
                StatCard(title: "Open Starts", value: "\(result.openStarts.count)",
                        color: result.openStarts.isEmpty ? .green : .orange)
                StatCard(title: "Open Ends", value: "\(result.openEnds.count)",
                        color: result.openEnds.isEmpty ? .green : .orange)
                StatCard(title: "Dangling Refs", value: "\(result.danglingRelationships)",
                        color: result.danglingRelationships == 0 ? .green : .red)
            }

            if !result.openStarts.isEmpty {
                GroupBox("Tasks Without Predecessors (Open Starts)") {
                    ForEach(result.openStarts.prefix(10)) { task in
                        Text("• \(task.taskCode): \(task.name)")
                    }
                    if result.openStarts.count > 10 {
                        Text("... and \(result.openStarts.count - 10) more")
                            .foregroundColor(.secondary)
                    }
                }
            }

            if !result.openEnds.isEmpty {
                GroupBox("Tasks Without Successors (Open Ends)") {
                    ForEach(result.openEnds.prefix(10)) { task in
                        Text("• \(task.taskCode): \(task.name)")
                    }
                    if result.openEnds.count > 10 {
                        Text("... and \(result.openEnds.count - 10) more")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct DCMAReportSection: View {
    let analyzer: ScheduleAnalyzer

    var body: some View {
        let result = analyzer.performDCMACheck()

        VStack(alignment: .leading, spacing: 16) {
            Text("DCMA 14-Point Assessment")
                .font(.title)

            Text(result.summary)
                .font(.headline)
                .foregroundColor(result.overallScore >= 80 ? .green : result.overallScore >= 60 ? .orange : .red)

            GroupBox("Check Results") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Check").fontWeight(.semibold)
                        Text("Threshold").fontWeight(.semibold)
                        Text("Actual").fontWeight(.semibold)
                        Text("Status").fontWeight(.semibold)
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(result.checks) { check in
                        GridRow {
                            HStack {
                                Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(check.passed ? .green : .red)
                                Text(check.name)
                            }
                            Text(check.threshold)
                            Text(check.actualValue)
                            Text(check.passed ? "Pass" : "Fail")
                                .foregroundColor(check.passed ? .green : .red)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ResourceReportSection: View {
    let analyzer: ScheduleAnalyzer

    var body: some View {
        let result = analyzer.analyzeResourceLoading()

        VStack(alignment: .leading, spacing: 16) {
            Text("Resource Analysis")
                .font(.title)

            HStack(spacing: 20) {
                StatCard(title: "Total Resources", value: "\(result.totalResources)", color: .blue)
                StatCard(title: "Assignments", value: "\(result.totalAssignments)", color: .green)
                StatCard(title: "Over-Allocated", value: "\(result.overAllocatedResources.count)", color: .red)
            }

            if !result.overAllocatedResources.isEmpty {
                GroupBox("Over-Allocated Resources") {
                    ForEach(result.overAllocatedResources, id: \.resource.id) { util in
                        HStack {
                            Text(util.resource.name)
                            Spacer()
                            Text("\(util.assignmentCount) assignments")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct HistoryReportSection: View {
    let results: [AnalysisResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Analysis History")
                .font(.title)

            if results.isEmpty {
                Text("No analysis has been run yet.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(results) { result in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(result.title)
                                    .font(.headline)
                                Spacer()
                                Text(result.timestamp.formatted())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(result.summary)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack {
            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 100)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    AnalysisReportView(schedule: Schedule(), results: [])
}
