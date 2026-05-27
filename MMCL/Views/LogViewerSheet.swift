import SwiftUI

struct LogViewerSheet: View {
    let instance: LauncherInstance
    @ObservedObject var store: LauncherStore
    @State private var logContent: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("启动日志 — \(instance.name)")
                .font(.headline)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(logContent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .id("bottom")
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Spacer()
                Button("关闭") {
                    store.showingLogSheet = false
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 700, height: 500)
        .onAppear {
            logContent = store.loadLogContent(for: instance)
        }
    }
}
