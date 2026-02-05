import SwiftUI

struct ContentView: View {
    @Binding var document: XERDocument
    @StateObject private var scheduleVM: ScheduleViewModel
    @StateObject private var chatVM: ChatViewModel
    @State private var showingSettings = false
    @State private var showingAnalysis = false
    @State private var selectedAnalysisType: AnalysisType?

    init(document: Binding<XERDocument>) {
        self._document = document
        self._scheduleVM = StateObject(wrappedValue: ScheduleViewModel(schedule: document.wrappedValue.schedule))
        let apiKey = KeychainService.getAPIKey() ?? ""
        self._chatVM = StateObject(wrappedValue: ChatViewModel(apiKey: apiKey))
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar - Schedule Overview
            ScheduleSidebar(viewModel: scheduleVM)
                .frame(minWidth: 200)
        } detail: {
            // Main content area
            HSplitView {
                // Left: Schedule View (Table or Gantt)
                Group {
                    switch scheduleVM.viewMode {
                    case .table:
                        ScheduleTableView(viewModel: scheduleVM)
                    case .gantt:
                        GanttChartView(viewModel: scheduleVM)
                    }
                }
                .frame(minWidth: 400)

                // Right: Chat Interface
                ChatInterfaceView(
                    viewModel: chatVM,
                    context: ConversationContext(
                        schedule: scheduleVM.schedule,
                        selectedTasks: scheduleVM.selectedTasks,
                        analysisHistory: chatVM.analysisResults
                    )
                )
                .frame(minWidth: 300, idealWidth: 400)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                // View Mode Toggle
                Picker("View", selection: $scheduleVM.viewMode) {
                    ForEach(ScheduleViewModel.ViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode == .table ? "tablecells" : "chart.bar.xaxis")
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Switch between Table and Gantt views")

                // Grouping Picker
                Menu {
                    ForEach(scheduleVM.availableGroupingOptions, id: \.displayName) { option in
                        Button {
                            scheduleVM.setGrouping(option)
                        } label: {
                            if scheduleVM.groupingConfig.primaryGrouping == option {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }

                    if scheduleVM.groupingConfig.primaryGrouping != .none {
                        Divider()
                        Button("Expand All") {
                            scheduleVM.expandAllGroups()
                        }
                        Button("Collapse All") {
                            scheduleVM.collapseAllGroups()
                        }
                    }
                } label: {
                    Label("Group By", systemImage: "rectangle.3.group")
                }
                .help("Group activities by category")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAnalysis = true
                } label: {
                    Label("Analyze", systemImage: "chart.bar.doc.horizontal")
                }

                Menu {
                    Button("Critical Path") {
                        Task { await chatVM.runAnalysis(.criticalPath, schedule: scheduleVM.schedule) }
                    }
                    Button("Float Analysis") {
                        Task { await chatVM.runAnalysis(.floatAnalysis, schedule: scheduleVM.schedule) }
                    }
                    Button("Logic Check") {
                        Task { await chatVM.runAnalysis(.logicCheck, schedule: scheduleVM.schedule) }
                    }
                    Button("DCMA 14-Point") {
                        Task { await chatVM.runAnalysis(.scheduleHealth, schedule: scheduleVM.schedule) }
                    }
                    Divider()
                    Button("Resource Loading") {
                        Task { await chatVM.runAnalysis(.resourceLoading, schedule: scheduleVM.schedule) }
                    }
                } label: {
                    Label("Quick Analysis", systemImage: "wand.and.stars")
                }

                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .frame(minWidth: 400, minHeight: 300)
        }
        .sheet(isPresented: $showingAnalysis) {
            AnalysisReportView(schedule: scheduleVM.schedule, results: chatVM.analysisResults)
                .frame(minWidth: 600, minHeight: 500)
        }
        .onReceive(NotificationCenter.default.publisher(for: .analyzeSchedule)) { _ in
            showingAnalysis = true
        }
        .onChange(of: document.schedule) { _, newSchedule in
            scheduleVM.schedule = newSchedule
        }
        .onAppear {
            if let apiKey = KeychainService.getAPIKey() {
                chatVM.updateAPIKey(apiKey)
            }
        }
    }
}

struct ScheduleSidebar: View {
    @ObservedObject var viewModel: ScheduleViewModel

    var body: some View {
        List {
            if let project = viewModel.schedule.primaryProject {
                Section("Project") {
                    LabeledContent("Name", value: project.name)
                    if let start = project.planStartDate {
                        LabeledContent("Start", value: start.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let end = project.planEndDate {
                        LabeledContent("End", value: end.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let dataDate = project.dataDate {
                        LabeledContent("Data Date", value: dataDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }

            Section("Statistics") {
                LabeledContent("Activities", value: "\(viewModel.schedule.taskCount)")
                LabeledContent("Critical", value: "\(viewModel.schedule.criticalTasks.count)")
                LabeledContent("Milestones", value: "\(viewModel.schedule.milestones.count)")
                LabeledContent("Resources", value: "\(viewModel.schedule.resources.count)")
                LabeledContent("Relationships", value: "\(viewModel.schedule.relationships.count)")
            }

            Section("Progress") {
                LabeledContent("Complete", value: String(format: "%.1f%%", viewModel.completedPercentage))
                ProgressView(value: viewModel.completedPercentage / 100)
            }

            Section("Filters") {
                Toggle("Critical Only", isOn: $viewModel.showCriticalOnly)

                Picker("Status", selection: $viewModel.filterStatus) {
                    Text("All").tag(TaskStatus?.none)
                    ForEach([TaskStatus.notStarted, .active, .complete], id: \.self) { status in
                        Text(status.displayName).tag(TaskStatus?.some(status))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

#Preview {
    ContentView(document: .constant(XERDocument()))
}
