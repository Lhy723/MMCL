import SwiftUI

struct ContentView: View {
    @ObservedObject var store: LauncherStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            detailView
        }
        .background {
            if let bgURL = store.backgroundImage.url {
                AsyncImage(url: bgURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: reduceTransparency ? 0 : store.backgroundImage.blurRadius)
                        .opacity(reduceTransparency ? min(store.backgroundImage.opacity, 0.35) : store.backgroundImage.opacity)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                } placeholder: {
                    Color.clear
                }
                .ignoresSafeArea()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await store.launchSelectedInstance() }
                } label: {
                    Label("启动", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedInstance == nil || store.selectedJavaRuntime == nil || store.selectedInstance?.status != .ready)
                .help("启动选中的实例")

                Picker(selection: $store.selectedAccountID) {
                    Text("未选择").tag(MinecraftAccount.ID?.none)
                    ForEach(store.accounts) { account in
                        Text(account.displayName).tag(Optional(account.id))
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.circle")
                        Text(store.accounts.first(where: { $0.id == store.selectedAccountID })?.displayName ?? "账号")
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 180)
                }
                .accessibilityLabel("当前账号")
                .pickerStyle(.menu)
            }
        }
        .task {
            await Task.yield()
            store.selectFirstInstanceIfNeeded()
            store.verifyInstanceStatuses()
            await store.refreshJavaRuntimes()
            guard !Task.isCancelled else { return }
            await store.checkForUpdates(showDiagnostics: false)
        }
        .onChange(of: store.launcherSelectedInstanceID) { _, newID in
            if let id = newID {
                UserDefaults.standard.set(id.uuidString, forKey: "lastSelectedInstanceID")
            }
        }
        .sheet(item: $store.presentedSheet) { sheet in
            presentedSheetContent(sheet)
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let settingsID = store.selectedInstanceSettingsID,
           let instance = store.instances.first(where: { $0.id == settingsID }) {
            InstanceSettingsView(instance: instance, store: store)
                .id(settingsID)
        } else {
            switch store.selectedSection {
            case .launcher:
                LauncherView(store: store)
            case .downloads:
                DownloadCenterView(store: store)
            case .diagnostics:
                DiagnosticsView(store: store)
            case .skin:
                SkinPickerView(store: store)
            case .serverList:
                ServerListView(store: store)
            case .settings:
                SettingsView(store: store)
            case .none:
                EmptyStateView(title: "欢迎使用 MMCL", message: "选择实例、下载中心或诊断日志开始。", systemImage: "gamecontroller")
            }
        }
    }

    @ViewBuilder
    private func presentedSheetContent(_ sheet: LauncherStore.PresentedSheet) -> some View {
        switch sheet {
        case .createInstance:
            InstanceCreateSheet(store: store)
        case .log(let instanceID):
            if let instance = store.instances.first(where: { $0.id == instanceID }) {
                LogViewerSheet(instance: instance, store: store)
            } else {
                EmptyStateView(title: "实例不存在", message: "无法读取日志所属的实例。", systemImage: "doc.text.magnifyingglass")
            }
        case .modrinth(let project):
            ModrinthProjectDetailView(project: project, store: store)
        case .rename(let instanceID):
            if let instance = store.instances.first(where: { $0.id == instanceID }) {
                InstanceRenameSheet(instance: instance, store: store)
            } else {
                EmptyStateView(title: "实例不存在", message: "无法读取要重命名的实例。", systemImage: "exclamationmark.triangle")
            }
        case .mods(let instanceID):
            if let instance = store.instances.first(where: { $0.id == instanceID }) {
                ModListView(instance: instance, store: store)
            } else {
                EmptyStateView(title: "实例不存在", message: "无法读取 Mod 所属的实例。", systemImage: "puzzlepiece.extension")
            }
        case .resourcePacks(let instanceID):
            if let instance = store.instances.first(where: { $0.id == instanceID }) {
                ResourcePackListView(instance: instance, store: store)
            } else {
                EmptyStateView(title: "实例不存在", message: "无法读取资源包所属的实例。", systemImage: "photo.stack")
            }
        case .shaderPacks(let instanceID):
            if let instance = store.instances.first(where: { $0.id == instanceID }) {
                ShaderPackListView(instance: instance, store: store)
            } else {
                EmptyStateView(title: "实例不存在", message: "无法读取光影包所属的实例。", systemImage: "sparkles")
            }
        case .jdkInstall:
            JDKInstallSheet(store: store)
        }
    }
}

private struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView(store: LauncherStore())
}
