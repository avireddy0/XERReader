import SwiftUI

struct GanttChartView: View {
    @ObservedObject var viewModel: ScheduleViewModel
    @State private var scale: Double = 1.0
    @State private var scrollOffset: CGFloat = 0
    @State private var hoveredTaskId: String?

    private let rowHeight: CGFloat = 28
    private let taskNameWidth: CGFloat = 250
    private let dayWidth: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header with timeline
                timelineHeader
                    .frame(height: 50)

                Divider()

                // Gantt content
                ScrollView([.horizontal, .vertical]) {
                    HStack(spacing: 0) {
                        // Task names column (fixed)
                        taskNamesColumn
                            .frame(width: taskNameWidth)

                        Divider()

                        // Gantt bars
                        ganttBarsView
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Timeline Header

    private var timelineHeader: some View {
        HStack(spacing: 0) {
            // Task name header
            Text("Activity")
                .font(.headline)
                .frame(width: taskNameWidth, alignment: .leading)
                .padding(.horizontal, 8)

            Divider()

            // Date headers
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(dateRange, id: \.self) { date in
                        VStack(spacing: 2) {
                            if isFirstOfMonth(date) {
                                Text(monthYearFormatter.string(from: date))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            } else {
                                Text("")
                                    .font(.caption2)
                            }
                            Text(dayFormatter.string(from: date))
                                .font(.caption2)
                                .foregroundColor(isWeekend(date) ? .secondary : .primary)
                        }
                        .frame(width: dayWidth * scale)
                        .background(isWeekend(date) ? Color.gray.opacity(0.1) : Color.clear)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Task Names Column

    private var taskNamesColumn: some View {
        LazyVStack(spacing: 0) {
            ForEach(displayItems, id: \.id) { item in
                switch item {
                case .group(let group):
                    groupRow(group)
                case .task(let task):
                    taskNameRow(task)
                }
            }
        }
    }

    private func groupRow(_ group: TaskGroup) -> some View {
        HStack {
            Button {
                viewModel.toggleGroupExpansion(group.id)
            } label: {
                Image(systemName: viewModel.isGroupExpanded(group.id) ? "chevron.down" : "chevron.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Text(group.name)
                .fontWeight(.semibold)
                .lineLimit(1)

            Spacer()

            Text("\(group.taskCount)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.leading, CGFloat(group.level) * 16)
        .frame(height: rowHeight)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func taskNameRow(_ task: ScheduleTask) -> some View {
        HStack {
            if task.isCritical {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
            }

            Text(task.taskCode)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(task.name)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.leading, viewModel.groupingConfig.primaryGrouping != .none ? 24 : 0)
        .frame(height: rowHeight)
        .background(
            hoveredTaskId == task.id ? Color.accentColor.opacity(0.1) : Color.clear
        )
        .onHover { isHovered in
            hoveredTaskId = isHovered ? task.id : nil
        }
    }

    // MARK: - Gantt Bars

    private var ganttBarsView: some View {
        LazyVStack(spacing: 0) {
            ForEach(displayItems, id: \.id) { item in
                switch item {
                case .group(let group):
                    groupSummaryBar(group)
                case .task(let task):
                    taskBar(task)
                }
            }
        }
        .frame(width: CGFloat(dateRange.count) * dayWidth * scale)
    }

    private func groupSummaryBar(_ group: TaskGroup) -> some View {
        GeometryReader { geo in
            if let start = group.tasks.compactMap({ $0.targetStartDate }).min(),
               let end = group.tasks.compactMap({ $0.targetEndDate }).max() {
                let startOffset = daysBetween(projectStart, start)
                let duration = daysBetween(start, end)

                // Summary bar (diamond ends)
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: CGFloat(duration) * dayWidth * scale, height: 8)

                    // Start diamond
                    Diamond()
                        .fill(Color.gray)
                        .frame(width: 10, height: 10)
                        .offset(x: -CGFloat(duration) * dayWidth * scale / 2)

                    // End diamond
                    Diamond()
                        .fill(Color.gray)
                        .frame(width: 10, height: 10)
                        .offset(x: CGFloat(duration) * dayWidth * scale / 2)
                }
                .offset(x: CGFloat(startOffset) * dayWidth * scale + CGFloat(duration) * dayWidth * scale / 2)
            }
        }
        .frame(height: rowHeight)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func taskBar(_ task: ScheduleTask) -> some View {
        GeometryReader { geo in
            if let start = task.targetStartDate, let end = task.targetEndDate {
                let startOffset = daysBetween(projectStart, start)
                let duration = max(1, daysBetween(start, end))

                // Task bar
                ZStack(alignment: .leading) {
                    // Background bar
                    RoundedRectangle(cornerRadius: 3)
                        .fill(task.isCritical ? Color.red.opacity(0.8) : Color.accentColor.opacity(0.8))
                        .frame(width: CGFloat(duration) * dayWidth * scale, height: 16)

                    // Progress fill
                    if task.percentComplete > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(task.isCritical ? Color.red : Color.accentColor)
                            .frame(width: CGFloat(duration) * dayWidth * scale * task.percentComplete / 100, height: 16)
                    }

                    // Milestone diamond
                    if task.taskType == .startMilestone || task.taskType == .finishMilestone {
                        Diamond()
                            .fill(task.isCritical ? Color.red : Color.accentColor)
                            .frame(width: 14, height: 14)
                    }
                }
                .offset(x: CGFloat(startOffset) * dayWidth * scale)
                .help("\(task.name)\n\(dateFormatter.string(from: start)) - \(dateFormatter.string(from: end))\n\(Int(task.percentComplete))% complete")
            }
        }
        .frame(height: rowHeight)
        .background(
            hoveredTaskId == task.id ? Color.accentColor.opacity(0.05) : Color.clear
        )
    }

    // MARK: - Display Items

    private enum DisplayItem: Identifiable {
        case group(TaskGroup)
        case task(ScheduleTask)

        var id: String {
            switch self {
            case .group(let g): return "group-\(g.id)"
            case .task(let t): return "task-\(t.id)"
            }
        }
    }

    private var displayItems: [DisplayItem] {
        var items: [DisplayItem] = []

        if viewModel.groupingConfig.primaryGrouping == .none {
            items = viewModel.filteredTasks.map { .task($0) }
        } else {
            for group in viewModel.taskGroups {
                items.append(.group(group))
                if viewModel.isGroupExpanded(group.id) {
                    items.append(contentsOf: group.tasks.map { .task($0) })
                }
            }
        }

        return items
    }

    // MARK: - Date Calculations

    private var projectStart: Date {
        viewModel.schedule.tasks.compactMap { $0.targetStartDate }.min() ?? Date()
    }

    private var projectEnd: Date {
        viewModel.schedule.tasks.compactMap { $0.targetEndDate }.max() ?? Date()
    }

    private var dateRange: [Date] {
        var dates: [Date] = []
        var current = Calendar.current.startOfDay(for: projectStart)
        let end = Calendar.current.startOfDay(for: projectEnd)

        while current <= end {
            dates.append(current)
            current = Calendar.current.date(byAdding: .day, value: 1, to: current) ?? end
        }

        return dates
    }

    private func daysBetween(_ start: Date, _ end: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start),
                                         to: Calendar.current.startOfDay(for: end)).day ?? 0
    }

    private func isWeekend(_ date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    private func isFirstOfMonth(_ date: Date) -> Bool {
        Calendar.current.component(.day, from: date) == 1
    }

    // MARK: - Formatters

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()
}

// MARK: - Diamond Shape

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    GanttChartView(viewModel: ScheduleViewModel())
}
