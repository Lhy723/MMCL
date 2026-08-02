import SwiftUI

struct LogViewerSheet: View {
    let instance: LauncherInstance
    @ObservedObject var store: LauncherStore
    @State private var logContent: String = ""
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("启动日志 — \(instance.name)")
                    .font(.headline)
                Spacer()
                Button {
                    Task { logContent = await loadLogContent() }
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
                .task(id: instance.id) {
                    logContent = await loadLogContent()
                    proxy.scrollTo("bottom", anchor: .bottom)

                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        } catch {
                            return
                        }

                        let newContent = await loadLogContent()
                        guard newContent != logContent else { continue }
                        logContent = newContent
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
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
        .frame(minWidth: 700, minHeight: 500, alignment: .top)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                appeared = true
            }
        }
    }

    private func loadLogContent() async -> String {
        let logURL = instance.rootDirectory.appendingPathComponent("logs/latest.log")
        return await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: logURL) else {
                return "暂无日志"
            }
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
