import SwiftUI

struct ShaderPackListView: View {
    let instance: LauncherInstance
    @ObservedObject var store: LauncherStore
    @State private var packs: [ShaderPackInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已安装光影包")
                    .font(.headline)
                Spacer()
                Button {
                    packs = store.scanShaderPacks(for: instance)
                } label: { Label("刷新", systemImage: "arrow.clockwise") }
            }
            if packs.isEmpty {
                ContentUnavailableView("没有已安装的光影包", systemImage: "sun.max", description: Text("手动将光影包放入 shaderpacks 目录"))
            } else {
                List(packs) { pack in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(pack.fileName).font(.body)
                            Text(ByteCountFormatter.string(fromByteCount: pack.size, countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            store.deleteShaderPack(for: instance, pack: pack)
                            packs = store.scanShaderPacks(for: instance)
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 500, minHeight: 400)
        .onAppear { packs = store.scanShaderPacks(for: instance) }
    }
}
