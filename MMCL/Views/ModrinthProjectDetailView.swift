import SwiftUI

private struct ModrinthVersionRequest: Equatable {
    let projectID: String
    let gameVersion: String?
    let loader: String?
}

struct ModrinthProjectDetailView: View {
    let project: ModrinthSearchResult
    @ObservedObject var store: LauncherStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var versions: [ModrinthVersion] = []
    @State private var isLoading = true
    @State private var activeVersionRequest: ModrinthVersionRequest?

    private var isModpack: Bool {
        project.projectType.caseInsensitiveCompare("modpack") == .orderedSame
    }

    private var versionRequest: ModrinthVersionRequest {
        ModrinthVersionRequest(
            projectID: project.id,
            gameVersion: isModpack ? nil : store.selectedInstance?.gameVersion,
            loader: isModpack ? nil : store.selectedInstance?.loader.modrinthLoaderName
        )
    }

    private var versionListAnimation: Animation? {
        guard !reduceMotion, store.animationDurationScale > 0 else { return nil }
        return .mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale)
    }

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
                ContentUnavailableView(
                    "没有可用版本",
                    systemImage: "package",
                    description: Text(isModpack ? "此整合包项目暂时没有可下载版本。" : "此项目没有与当前实例兼容的版本。")
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("可用版本")
                    .font(.headline)

                if isModpack {
                    versionList
                } else if store.selectedInstance == nil {
                    ContentUnavailableView("未选择实例", systemImage: "person.crop.circle.badge.questionmark", description: Text("请先在启动器页面选择一个实例"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    versionList
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("关闭") {
                    store.showingModrinthDetail = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("关闭")
                .accessibilityHint("关闭版本列表")
            }
        }
        .padding(20)
        .frame(width: 550, height: 480, alignment: .top)
        .task(id: versionRequest) {
            await loadVersions(for: versionRequest)
        }
    }

    private var versionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(versions) { version in
                    ModrinthVersionRow(
                        version: version,
                        actionTitle: isModpack ? "下载" : "安装"
                    ) {
                        guard let file = version.files.first(where: { $0.primary }) ?? version.files.first else {
                            return
                        }

                        Task {
                            if isModpack {
                                await store.downloadModrinthModpack(version: version, file: file)
                            } else if let instance = store.selectedInstance {
                                await store.installModrinthMod(version: version, file: file, for: instance)
                                store.showingModrinthDetail = false
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
        .frame(maxHeight: 300)
    }

    private func loadVersions(for request: ModrinthVersionRequest) async {
        activeVersionRequest = request
        isLoading = true
        do {
            let loadedVersions = try await store.modrinthService.fetchVersions(
                projectID: request.projectID,
                gameVersion: request.gameVersion,
                loader: request.loader
            )
            try Task.checkCancellation()
            guard activeVersionRequest == request else { return }
            withAnimation(versionListAnimation) {
                versions = loadedVersions
                isLoading = false
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, activeVersionRequest == request else { return }
            withAnimation(versionListAnimation) {
                versions = []
                isLoading = false
            }
        }
    }
}

private struct ModrinthVersionRow: View {
    let version: ModrinthVersion
    let actionTitle: String
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
            Button(actionTitle) {
                onInstall()
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("\(actionTitle)：\(version.name)")
            .accessibilityHint(actionTitle == "下载" ? "下载此整合包版本" : "安装此资源版本")
        }
        .padding(.vertical, 4)
    }
}
