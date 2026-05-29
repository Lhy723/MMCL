import SwiftUI

struct ModrinthProjectDetailView: View {
    let project: ModrinthSearchResult
    @ObservedObject var store: LauncherStore
    @State private var versions: [ModrinthVersion] = []
    @State private var visibleIDs: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(project.title)
                    .font(.largeTitle.weight(.semibold))
                Text(project.description)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label("\(project.downloads)", systemImage: "arrow.down")
                        .foregroundStyle(.secondary)
                    Text(project.projectType)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                .font(.caption)
            }

            if isLoading {
                ProgressView("加载版本列表...")
            } else if versions.isEmpty {
                ContentUnavailableView("没有可用版本", systemImage: "package", description: Text("此项目没有与当前实例兼容的版本。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("可用版本")
                    .font(.headline)

                if store.selectedInstance == nil {
                    ContentUnavailableView("未选择实例", systemImage: "person.crop.circle.badge.questionmark", description: Text("请先在启动器页面选择一个实例"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(versions) { version in
                                ModrinthVersionRow(version: version) {
                                    if let file = version.files.first(where: { $0.primary }) ?? version.files.first,
                                       let instance = store.selectedInstance {
                                        Task {
                                            await store.installModrinthMod(version: version, file: file, for: instance)
                                            store.showingModrinthDetail = false
                                        }
                                    }
                                }
                                .opacity(visibleIDs.contains(version.id) ? 1 : 0)
                                .offset(x: visibleIDs.contains(version.id) ? 0 : 20)
                                .onAppear {
                                    if !visibleIDs.contains(version.id) {
                                        withAnimation(.mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                                            visibleIDs.insert(version.id)
                                        }
                                    }
                                }
                                .onDisappear {
                                    visibleIDs.remove(version.id)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("关闭") {
                    store.showingModrinthDetail = false
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 550, height: 480, alignment: .top)
        .task {
            await loadVersions()
        }
    }

    private func loadVersions() async {
        isLoading = true
        do {
            let loaderFilter: String? = store.selectedInstance.flatMap { instance in
                loaderName(for: instance.loader)
            }
            versions = try await store.modrinthService.fetchVersions(
                projectID: project.id,
                gameVersion: store.selectedInstance?.gameVersion,
                loader: loaderFilter
            )
        } catch {
            versions = []
        }
        isLoading = false
    }

    private func loaderName(for loader: GameLoader) -> String? {
        switch loader {
        case .vanilla: return nil
        case .fabric: return "fabric"
        case .quilt: return "quilt"
        case .forge: return "forge"
        }
    }
}

private struct ModrinthVersionRow: View {
    let version: ModrinthVersion
    let onInstall: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(version.name)
                    .font(.headline)
                Text(version.versionNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(version.loaders.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(version.gameVersions.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("安装") {
                onInstall()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}
