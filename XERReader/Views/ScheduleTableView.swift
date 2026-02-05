import SwiftUI

struct ScheduleTableView: View {
    @ObservedObject var viewModel: ScheduleViewModel
    @State private var sortOrder = [KeyPathComparator(\ScheduleTask.taskCode)]

    var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search tasks...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .frame(height: 20)

                Picker("Sort", selection: $viewModel.sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .frame(width: 120)

                Button {
                    viewModel.sortAscending.toggle()
                } label: {
                    Image(systemName: viewModel.sortAscending ? "arrow.up" : "arrow.down")
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 20)

                Text("\(viewModel.filteredTasks.count) tasks")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Table
            Table(viewModel.filteredTasks, selection: $viewModel.selectedTaskIds) {
                TableColumn("Code", value: \.taskCode)
                    .width(min: 80, ideal: 100)

                TableColumn("Name", value: \.name)
                    .width(min: 150, ideal: 250)

                TableColumn("Start") { task in
                    Text(task.targetStartDate?.formatted(date: .abbreviated, time: .omitted) ?? "-")
                }
                .width(min: 80, ideal: 100)

                TableColumn("Finish") { task in
                    Text(task.targetEndDate?.formatted(date: .abbreviated, time: .omitted) ?? "-")
                }
                .width(min: 80, ideal: 100)

                TableColumn("Duration") { task in
                    Text("\(task.durationDays)d")
                }
                .width(min: 50, ideal: 60)

                TableColumn("Float") { task in
                    HStack {
                        Text("\(task.totalFloatDays)d")
                        if task.isCritical {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
                .width(min: 50, ideal: 70)

                TableColumn("Status") { task in
                    StatusBadge(status: task.status)
                }
                .width(min: 80, ideal: 100)

                TableColumn("%") { task in
                    ProgressView(value: task.percentComplete / 100)
                        .frame(width: 60)
                }
                .width(min: 60, ideal: 80)
            }
            .contextMenu(forSelectionType: String.self) { selection in
                if !selection.isEmpty {
                    Button("Ask Claude about selection") {
                        // Handled by chat view
                    }
                    Divider()
                    Button("Show Predecessors") { }
                    Button("Show Successors") { }
                    Divider()
                    Button("Copy Task Codes") {
                        let codes = selection.compactMap { id in
                            viewModel.task(byId: id)?.taskCode
                        }.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(codes, forType: .string)
                    }
                }
            } primaryAction: { selection in
                // Double-click action - could show detail
            }

            // Selection summary bar
            if !viewModel.selectedTaskIds.isEmpty {
                HStack {
                    Text("\(viewModel.selectedTaskIds.count) selected")

                    Spacer()

                    Button("Clear") {
                        viewModel.clearSelection()
                    }
                    .buttonStyle(.link)

                    Button("Select All") {
                        viewModel.selectAll()
                    }
                    .buttonStyle(.link)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
            }
        }
    }
}

struct StatusBadge: View {
    let status: TaskStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(4)
    }

    var backgroundColor: Color {
        switch status {
        case .notStarted: return Color.gray.opacity(0.2)
        case .active: return Color.blue.opacity(0.2)
        case .complete: return Color.green.opacity(0.2)
        }
    }

    var foregroundColor: Color {
        switch status {
        case .notStarted: return .gray
        case .active: return .blue
        case .complete: return .green
        }
    }
}

#Preview {
    ScheduleTableView(viewModel: ScheduleViewModel())
}
