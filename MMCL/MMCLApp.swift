import SwiftUI
import AppKit

@main
struct MMCLApp: App {
    @NSApplicationDelegateAdaptor(MMCLTestAwareAppDelegate.self) private var appDelegate
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

private final class MMCLTestAwareAppDelegate: NSObject, NSApplicationDelegate {
    private var isHeadlessUnitTestHost: Bool {
        let isXCTestProcess = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isUITestLaunch = ProcessInfo.processInfo.arguments.contains("--mmcl-ui-testing")
        return isXCTestProcess && !isUITestLaunch
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !isHeadlessUnitTestHost
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard isHeadlessUnitTestHost else { return }

        NSApp.setActivationPolicy(.prohibited)
        NSApp.windows.forEach { $0.orderOut(nil) }
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
