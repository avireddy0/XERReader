import SwiftUI

@main
struct XERReaderApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: XERDocument()) { file in
            ContentView(document: file.$document)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Analyze Schedule...") {
                    NotificationCenter.default.post(name: .analyzeSchedule, object: nil)
                }
                .keyboardShortcut("A", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let analyzeSchedule = Notification.Name("analyzeSchedule")
}
