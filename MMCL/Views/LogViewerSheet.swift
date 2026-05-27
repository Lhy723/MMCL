import SwiftUI

struct LogViewerSheet: View {
    let instance: LauncherInstance
    @ObservedObject var store: LauncherStore
    @State private var logContent: String = ""
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("启动日志 — \(instance.name)")
                    .font(.headline)
                Spacer()
                Button {
                    logContent = store.loadLogContent(for: instance)
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(logContent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .id("bottom")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    logContent = store.loadLogContent(for: instance)
                    proxy.scrollTo("bottom", anchor: .bottom)
                    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        let newContent = store.loadLogContent(for: instance)
                        if newContent != logContent {
                            logContent = newContent
                            DispatchQueue.main.async {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .onDisappear {
                    timer?.invalidate()
                    timer = nil
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
    }
}
