import SwiftUI

struct ContentView: View {
    @ObservedObject var store: LauncherStore

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
                        .blur(radius: store.backgroundImage.blurRadius)
                        .opacity(store.backgroundImage.opacity)
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
                    store.launchSelectedInstance()
                } label: {
                    Label("启动", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedInstance == nil || store.selectedJavaRuntime == nil || store.selectedInstance?.status != .ready)
                .help("启动选中的实例")

                Menu {
                    ForEach(store.accounts) { account in
                        Button {
                            store.selectedAccountID = account.id
                        } label: {
                            HStack {
                                Text(account.displayName)
                                if store.selectedAccountID == account.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.circle")
                        Text(store.accounts.first(where: { $0.id == store.selectedAccountID })?.displayName ?? "账号")
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 180)
                }
            }
        }
        .onAppear {
            Task.detached {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    store.selectFirstInstanceIfNeeded()
                    store.verifyInstanceStatuses()
                }
                await store.refreshJavaRuntimes()
                await store.checkForUpdates()
            }
        }
        .onChange(of: store.launcherSelectedInstanceID) { _, newID in
            if let id = newID {
                UserDefaults.standard.set(id.uuidString, forKey: "lastSelectedInstanceID")
            }
        }
        .sheet(isPresented: $store.showingCreateSheet) {
            InstanceCreateSheet(store: store)
        }
        .sheet(isPresented: $store.showingLogSheet) {
            if let instance = store.selectedInstance {
                LogViewerSheet(instance: instance, store: store)
            }
        }
        .sheet(isPresented: $store.showingModrinthDetail) {
            if let project = store.selectedModrinthProject {
                ModrinthProjectDetailView(project: project, store: store)
            }
        }
        .sheet(isPresented: $store.showingRenameSheet) {
            if let instance = store.selectedInstance {
                InstanceRenameSheet(instance: instance, store: store)
            }
        }
        .sheet(isPresented: $store.showingModList) {
            if let instance = store.selectedInstance {
                ModListView(instance: instance, store: store)
            }
        }
        .sheet(isPresented: $store.showingResourcePacks) {
            if let instance = store.selectedInstance {
                ResourcePackListView(instance: instance, store: store)
            }
        }
        .sheet(isPresented: $store.showingShaderPacks) {
            if let instance = store.selectedInstance {
                ShaderPackListView(instance: instance, store: store)
            }
        }
        .sheet(isPresented: $store.showingJDKInstall) {
            JDKInstallSheet(store: store)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let settingsID = store.selectedInstanceSettingsID,
           let instance = store.instances.first(where: { $0.id == settingsID }) {
            InstanceSettingsView(instance: instance, store: store)
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
