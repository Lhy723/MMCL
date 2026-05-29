import SwiftUI

struct InstanceDetailView: View {
    let instance: LauncherInstance
    @ObservedObject var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top)

            List {
                Section("启动配置") {
                    configurationContent
                }

                Section("Java 运行时") {
                    runtimeContent
                }

                Section("启动命令预览") {
                    launchPreviewContent
                }

                Section("文件目录") {
                    directoriesContent
                }

                Section("操作") {
                    operationsContent
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle(instance.name)
        .accessibilityIdentifier("InstanceDetail")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "play.square.stack")
                .font(.system(size: 38))
                .foregroundStyle(.tint)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 8) {
                Text(instance.name)
                    .font(.largeTitle.weight(.semibold))
                Text(instance.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                StatusPill(status: instance.status)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var configurationContent: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
            GridRow {
                Text("离线用户名").foregroundStyle(.secondary)
                Text(instance.profile.offlineUsername)
            }
            GridRow {
                Text("内存").foregroundStyle(.secondary)
                Text("\(instance.profile.memoryMegabytes) MB")
            }
            GridRow {
                Text("JVM 参数").foregroundStyle(.secondary)
                Text(instance.profile.jvmArguments.isEmpty ? "未设置" : instance.profile.jvmArguments.joined(separator: " "))
            }
            GridRow {
                Text("推荐 Java").foregroundStyle(.secondary)
                Text("Java \(JavaRuntime.recommendedMajorVersion(for: instance.gameVersion))")
            }
            GridRow {
                Text("上次游玩").foregroundStyle(.secondary)
                Text(instance.lastPlayedAt.map(Self.dateFormatter.string(from:)) ?? "从未启动")
            }
        }
    }

    private var runtimeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("运行时", selection: $store.selectedJavaRuntimeID) {
                ForEach(store.javaRuntimes) { runtime in
                    Text(runtime.displayName).tag(Optional(runtime.id))
                }
            }
            .pickerStyle(.menu)

            Button {
                Task { await store.refreshJavaRuntimes() }
            } label: {
                if store.isScanningJava {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("重新扫描 Java", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(store.isScanningJava)

            if let runtime = store.selectedJavaRuntime {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                    GridRow {
                        Text("版本").foregroundStyle(.secondary)
                        Text(runtime.version)
                    }
                    GridRow {
                        Text("架构").foregroundStyle(.secondary)
                        Text(runtime.architecture.label)
                    }
                    GridRow {
                        Text("路径").foregroundStyle(.secondary)
                        Text(runtime.executableURL.path).textSelection(.enabled)
                    }
                    GridRow {
                        Text("匹配状态").foregroundStyle(.secondary)
                        Text(runtime.isRecommended(for: instance.gameVersion) ? "推荐" : "不推荐")
                    }
                }
            } else {
                Text("尚未发现 Java 运行时。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var launchPreviewContent: some View {
        Group {
            if let preview = store.launchPreviewForSelectedInstance() {
                VStack(alignment: .leading, spacing: 8) {
                    Text(preview.commandLine)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(8)
                }
            } else {
                Text("请选择实例和 Java 运行时以生成启动预览。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var directoriesContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            PathRow(title: "实例目录", path: instance.rootDirectory.path)
            PathRow(title: "Minecraft", path: instance.rootDirectory.appendingPathComponent(".minecraft").path)
            PathRow(title: "日志", path: instance.rootDirectory.appendingPathComponent("logs").path)
            PathRow(title: "模组", path: instance.rootDirectory.appendingPathComponent("mods").path)
        }
    }

    private var operationsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Primary actions
            HStack(spacing: 12) {
                Button {
                    store.launchSelectedInstance()
                } label: {
                    Label("启动游戏", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedJavaRuntime == nil)

                Button {
                    store.showingLogSheet = true
                } label: {
                    Label("查看日志", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)

                Button {
                    store.showingModList = true
                } label: {
                    Label("管理 Mod", systemImage: "puzzlepiece.extension")
                }
                .buttonStyle(.bordered)

                Button {
                    store.showingResourcePacks = true
                } label: {
                    Label("资源包", systemImage: "photo")
                }
                .buttonStyle(.bordered)
            }

            // Secondary actions
            HStack(spacing: 12) {
                Button {
                    store.showingShaderPacks = true
                } label: {
                    Label("管理光影", systemImage: "sun.max")
                }
                .buttonStyle(.bordered)

                Button {
                    store.analyzeCrash(for: instance)
                } label: {
                    Label("崩溃分析", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await store.planVanillaInstallFromRemoteMetadata(for: instance) }
                } label: {
                    Label("生成安装计划", systemImage: "list.bullet.clipboard")
                }
                .buttonStyle(.bordered)

                Button {
                    store.prepareNativeLibrariesForSelectedInstance()
                } label: {
                    Label("准备 Native", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(store.plannedVersionMetadata == nil)
            }

            // Loader-specific actions
            if instance.loader == .fabric || instance.loader == .quilt || instance.loader == .forge {
                Divider()
                HStack(spacing: 12) {
                    if instance.loader == .fabric {
                        Button { Task { await store.installFabricLoader(for: instance) } } label: {
                            Label("安装 Fabric", systemImage: "shippingbox")
                        }
                        .buttonStyle(.bordered)
                    }
                    if instance.loader == .quilt {
                        Button { Task { await store.installQuiltLoader(for: instance) } } label: {
                            Label("安装 Quilt", systemImage: "shippingbox")
                        }
                        .buttonStyle(.bordered)
                    }
                    if instance.loader == .forge {
                        Button { Task { await store.installForgeLoader(for: instance) } } label: {
                            Label("安装 Forge", systemImage: "hammer")
                        }
                        .buttonStyle(.bordered)
                        Button { Task { await store.installNeoForgeLoader(for: instance) } } label: {
                            Label("安装 NeoForge", systemImage: "hammer.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            // Launch session info
            if let session = store.currentLaunchSession {
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                    GridRow {
                        Text("最近进程").foregroundStyle(.secondary)
                        Text("\(session.processIdentifier)")
                    }
                    GridRow {
                        Text("启动日志").foregroundStyle(.secondary)
                        Text(session.logFileURL.path).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct StatusPill: View {
    let status: InstanceStatus

    var body: some View {
        Label(status.label, systemImage: iconName)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }

    private var iconName: String {
        switch status {
        case .ready: return "checkmark.circle.fill"
        case .missingFiles: return "exclamationmark.triangle.fill"
        case .needsJava: return "cup.and.saucer.fill"
        case .notInstalled: return "arrow.down.circle.fill"
        }
    }
}

private struct PathRow: View {
    let title: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(path)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}
