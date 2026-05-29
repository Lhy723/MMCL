import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        List(selection: $store.selectedSection) {
            Section("启动") {
                Label("启动器", systemImage: "play.square.stack")
                    .tag(LauncherStore.Section.launcher)
            }

            Section("工作区") {
                Label("下载中心", systemImage: "arrow.down.circle")
                    .tag(LauncherStore.Section.downloads)
                Label("诊断日志", systemImage: "stethoscope")
                    .tag(LauncherStore.Section.diagnostics)
                Label("皮肤管理", systemImage: "figure.stand")
                    .tag(LauncherStore.Section.skin)
                Label("服务器列表", systemImage: "server.rack")
                    .tag(LauncherStore.Section.serverList)
                Label("设置", systemImage: "gearshape")
                    .tag(LauncherStore.Section.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MMCL")
        .accessibilityIdentifier("MMCLSidebar")
    }
}
