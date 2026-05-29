import SwiftUI

@main
struct MMCLApp: App {
    @StateObject private var store = LauncherStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 920, minHeight: 620)
                .modifier(ConditionalColorScheme(scheme: store.colorScheme))
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
            TabView {
                SettingsView(store: store)
                    .tabItem { Label("通用", systemImage: "gear") }
                HelpView()
                    .tabItem { Label("帮助", systemImage: "questionmark.circle") }
            }
        }
    }
}

private struct ConditionalColorScheme: ViewModifier {
    let scheme: AppColorScheme

    func body(content: Content) -> some View {
        if let colorScheme = scheme.swiftUIScheme {
            content.preferredColorScheme(colorScheme)
        } else {
            content
        }
    }
}
