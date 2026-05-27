import SwiftUI

struct ResourcePackListView: View {
    let instance: LauncherInstance
    @ObservedObject var store: LauncherStore
    @State private var packs: [ResourcePackInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("资源包管理")
                    .font(.headline)
                Spacer()
                Button {
                    packs = store.scanResourcePacks(for: instance)
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }

            if packs.isEmpty {
                ContentUnavailableView("没有已安装的资源包", systemImage: "photo", description: Text("将资源包放入 .minecraft/resourcepacks 目录"))
            } else {
                List(packs) { pack in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(pack.fileName)
                                .font(.body)
                            Text(ByteCountFormatter.string(fromByteCount: pack.size, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            store.deleteResourcePack(for: instance, pack: pack)
                            packs = store.scanResourcePacks(for: instance)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 500, minHeight: 400)
        .onAppear { packs = store.scanResourcePacks(for: instance) }
    }
}
