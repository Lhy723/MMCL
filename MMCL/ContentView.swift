import SwiftUI

struct ContentView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        ZStack {
            if let bgURL = store.backgroundImage.url {
                AsyncImage(url: bgURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: store.backgroundImage.blurRadius)
                        .opacity(store.backgroundImage.opacity)
                        .allowsHitTesting(false)
                } placeholder: {
                    Color.clear
                }
                .ignoresSafeArea()
            }

            NavigationSplitView {
                SidebarView(store: store)
            } detail: {
                detailView
            }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.showingCreateSheet = true
                } label: {
                    Label("新增实例", systemImage: "plus")
                }
                .help("新增实例")

                Button {
                    store.launchSelectedInstance()
                } label: {
                    Label("启动", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedInstance == nil || store.selectedJavaRuntime == nil)
                .help("启动选中的实例")

                Picker("账号", selection: $store.selectedAccountID) {
                    ForEach(store.accounts) { account in
                        Text(account.displayName).tag(Optional(account.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)
            }
        }
        .onAppear {
            store.selectFirstInstanceIfNeeded()
            Task { await store.refreshJavaRuntimes() }
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
        .sheet(isPresented: $store.showingSkinPicker) {
            SkinPickerView(store: store)
        }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch store.selectedSection {
        case .instance:
            if let instance = store.selectedInstance {
                InstanceDetailView(instance: instance, store: store)
            } else {
                EmptyStateView(title: "未选择实例", message: "从侧边栏选择一个 Minecraft 实例。", systemImage: "cube.box")
            }
        case .downloads:
            DownloadsView(store: store)
        case .content:
            ContentProjectsView(store: store)
        case .curseforge:
            CurseForgeView(store: store)
        case .diagnostics:
            DiagnosticsView(store: store)
        case .skin:
            SkinPickerView(store: store)
        case .serverList:
            ServerListView(store: store)
        case .none:
            EmptyStateView(title: "欢迎使用 MMCL", message: "选择实例、下载中心或诊断日志开始。", systemImage: "gamecontroller")
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
