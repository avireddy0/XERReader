import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var showingAPIKey: Bool = false
    @State private var saveStatus: SaveStatus = .none
    @State private var selectedModel: String = "claude-opus-4-5-20251101"

    let availableModels = [
        "claude-opus-4-5-20251101",
        "claude-sonnet-4-5-20250929",
        "claude-3-5-sonnet-20241022"
    ]

    var body: some View {
        TabView {
            // API Settings
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Anthropic API Key")
                            .font(.headline)

                        HStack {
                            if showingAPIKey {
                                TextField("sk-ant-...", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("sk-ant-...", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button {
                                showingAPIKey.toggle()
                            } label: {
                                Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }

                        Text("Your API key is stored securely in the macOS Keychain.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button("Save API Key") {
                                saveAPIKey()
                            }
                            .disabled(apiKey.isEmpty)

                            if KeychainService.hasAPIKey {
                                Button("Delete Key", role: .destructive) {
                                    deleteAPIKey()
                                }
                            }

                            Spacer()

                            switch saveStatus {
                            case .none:
                                EmptyView()
                            case .saving:
                                ProgressView()
                                    .scaleEffect(0.7)
                            case .saved:
                                Label("Saved", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            case .error(let message):
                                Label(message, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    Text("Claude Opus 4.5 provides the most capable analysis.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Link(destination: URL(string: "https://console.anthropic.com/")!) {
                        Label("Get API Key from Anthropic Console", systemImage: "arrow.up.right.square")
                    }

                    Link(destination: URL(string: "https://docs.anthropic.com/")!) {
                        Label("API Documentation", systemImage: "book")
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("API", systemImage: "key")
            }

            // About
            VStack(spacing: 20) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                Text("XER Reader")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Version 1.0.0")
                    .foregroundColor(.secondary)

                Text("A native macOS app for reading Primavera P6 XER schedule files with Claude AI-powered analysis.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                    .foregroundColor(.secondary)

                Divider()
                    .frame(width: 200)

                VStack(spacing: 8) {
                    Text("Features")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 4) {
                        FeatureRow(icon: "doc.text", text: "Parse XER files natively")
                        FeatureRow(icon: "chart.bar", text: "Critical path analysis")
                        FeatureRow(icon: "bubble.left.and.bubble.right", text: "AI-powered Q&A")
                        FeatureRow(icon: "checkmark.shield", text: "DCMA 14-point health check")
                    }
                }

                Spacer()
            }
            .padding(40)
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            loadAPIKey()
        }
    }

    private func loadAPIKey() {
        if let key = KeychainService.getAPIKey() {
            apiKey = key
        }
    }

    private func saveAPIKey() {
        saveStatus = .saving
        do {
            try KeychainService.saveAPIKey(apiKey)
            saveStatus = .saved
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveStatus = .none
            }
        } catch {
            saveStatus = .error(error.localizedDescription)
        }
    }

    private func deleteAPIKey() {
        do {
            try KeychainService.deleteAPIKey()
            apiKey = ""
            saveStatus = .saved
        } catch {
            saveStatus = .error(error.localizedDescription)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.accentColor)
            Text(text)
        }
    }
}

enum SaveStatus: Equatable {
    case none
    case saving
    case saved
    case error(String)
}

#Preview {
    SettingsView()
}
