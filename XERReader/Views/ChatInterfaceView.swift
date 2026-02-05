import SwiftUI

struct ChatInterfaceView: View {
    @ObservedObject var viewModel: ChatViewModel
    let context: ConversationContext
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                Text("Claude Assistant")
                    .font(.headline)
                Spacer()

                if !viewModel.hasAPIKey {
                    Label("API Key Required", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Menu {
                    Button("Clear History") {
                        viewModel.clearHistory()
                    }
                    Divider()
                    Button("Critical Path Analysis") {
                        Task { await viewModel.runAnalysis(.criticalPath, schedule: context.schedule) }
                    }
                    Button("Schedule Health Check") {
                        Task { await viewModel.runAnalysis(.scheduleHealth, schedule: context.schedule) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if viewModel.messages.isEmpty {
                            WelcomeView(context: context)
                        }

                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Analyzing...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            VStack(spacing: 8) {
                if !context.selectedTasks.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("\(context.selectedTasks.count) tasks selected")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                HStack(alignment: .bottom) {
                    TextField("Ask about the schedule...", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .onSubmit {
                            if !viewModel.inputText.isEmpty && !viewModel.isLoading {
                                Task {
                                    await viewModel.sendMessage(context: context)
                                }
                            }
                        }
                        .disabled(!viewModel.hasAPIKey)

                    Button {
                        Task {
                            await viewModel.sendMessage(context: context)
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.inputText.isEmpty || viewModel.isLoading || !viewModel.hasAPIKey)
                }
                .padding()
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 50)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .system {
                    HStack {
                        Image(systemName: "info.circle")
                        Text(message.content)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    Text(message.content)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(message.role == .user ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .foregroundColor(message.role == .user ? .white : .primary)
                        .cornerRadius(12)

                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 50)
            }
        }
    }
}

struct WelcomeView: View {
    let context: ConversationContext

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Schedule Analysis Assistant")
                .font(.title2)
                .fontWeight(.semibold)

            if let project = context.schedule.primaryProject {
                Text("Project: \(project.name)")
                    .foregroundColor(.secondary)
            }

            Text("Ask questions about your schedule, request analysis, or explore critical paths and float.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 300)

            VStack(alignment: .leading, spacing: 8) {
                Text("Try asking:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SuggestionButton(text: "What's on the critical path?")
                SuggestionButton(text: "Are there any logic issues?")
                SuggestionButton(text: "Show me tasks with high float")
                SuggestionButton(text: "Run a schedule health check")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct SuggestionButton: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(16)
    }
}

#Preview {
    ChatInterfaceView(
        viewModel: ChatViewModel(apiKey: "test"),
        context: ConversationContext(schedule: Schedule(), selectedTasks: [], analysisHistory: [])
    )
}
