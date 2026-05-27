import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        List(selection: $store.selectedSection) {
            Section("实例") {
                ForEach(store.instances) { instance in
                    InstanceSidebarRow(instance: instance)
                        .tag(LauncherStore.Section.instance(instance.id))
                        .contextMenu {
                            Button {
                                store.showingRenameSheet = true
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            Button {
                                store.copyInstance(instance)
                            } label: {
                                Label("复制实例", systemImage: "doc.on.doc")
                            }
                            Button(role: .destructive) {
                                store.deleteInstance(instance)
                            } label: {
                                Label("删除实例", systemImage: "trash")
                            }
                        }
                }
            }

            Section("工作区") {
                Label("下载中心", systemImage: "arrow.down.circle")
                    .tag(LauncherStore.Section.downloads)
                Label("Modrinth", systemImage: "square.grid.2x2")
                    .tag(LauncherStore.Section.content)
                Label("诊断日志", systemImage: "stethoscope")
                    .tag(LauncherStore.Section.diagnostics)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MMCL")
        .accessibilityIdentifier("MMCLSidebar")
    }
}

private struct InstanceSidebarRow: View {
    let instance: LauncherInstance

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name)
                    .lineLimit(1)
                Text(instance.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var iconName: String {
        switch instance.loader {
        case .vanilla: return "cube.box"
        case .fabric, .quilt: return "shippingbox"
        case .forge: return "hammer"
        }
    }
}
