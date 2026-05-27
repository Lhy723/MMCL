import SwiftUI

@main
struct MMCLApp: App {
    @StateObject private var store = LauncherStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 920, minHeight: 620)
                .preferredColorScheme(store.colorScheme.swiftUIScheme)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("新增实例") {
                    store.showingCreateSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
