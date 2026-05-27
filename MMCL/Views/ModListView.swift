import SwiftUI

struct ModListView: View {
    let instance: LauncherInstance
    @ObservedObject var store: LauncherStore
    @State private var mods: [ModInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已安装 Mod")
                    .font(.headline)
                Spacer()
                Button {
                    mods = store.scanInstalledMods(for: instance)
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }

            if mods.isEmpty {
                ContentUnavailableView("没有已安装的 Mod", systemImage: "puzzlepiece.extension", description: Text("从 Modrinth 下载 Mod 或手动放入 mods 目录"))
            } else {
                List(mods) { mod in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(mod.fileName)
                                .font(.body)
                            Text(ByteCountFormatter.string(fromByteCount: mod.size, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { mod.isEnabled },
                            set: { _ in
                                store.toggleMod(for: instance, mod: mod)
                                mods = store.scanInstalledMods(for: instance)
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        Button(role: .destructive) {
                            store.deleteMod(for: instance, mod: mod)
                            mods = store.scanInstalledMods(for: instance)
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
        .onAppear { mods = store.scanInstalledMods(for: instance) }
    }
}
