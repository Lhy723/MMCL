import SwiftUI

struct InstanceDetailView: View {
    let instance: LauncherInstance
    @ObservedObject var store: LauncherStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                configuration
                runtimeSelection
                launchPreview
                directories
                plannedActions
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
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
    }

    private var configuration: some View {
        DetailSection(title: "启动配置", systemImage: "slider.horizontal.3") {
            InfoGrid(rows: [
                ("离线用户名", instance.profile.offlineUsername),
                ("内存", "\(instance.profile.memoryMegabytes) MB"),
                ("JVM 参数", instance.profile.jvmArguments.isEmpty ? "未设置" : instance.profile.jvmArguments.joined(separator: " ")),
                ("推荐 Java", "Java \(JavaRuntime.recommendedMajorVersion(for: instance.gameVersion))"),
                ("上次游玩", instance.lastPlayedAt.map(Self.dateFormatter.string(from:)) ?? "从未启动")
            ])
        }
    }

    private var runtimeSelection: some View {
        DetailSection(title: "Java 运行时", systemImage: "cup.and.saucer") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("运行时", selection: $store.selectedJavaRuntimeID) {
                    ForEach(store.javaRuntimes) { runtime in
                        Text(runtime.displayName).tag(Optional(runtime.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 420, alignment: .leading)

                Button {
                    Task {
                        await store.refreshJavaRuntimes()
                    }
                } label: {
                    Label("重新扫描 Java", systemImage: "arrow.clockwise")
                }

                if let runtime = store.selectedJavaRuntime {
                    InfoGrid(rows: [
                        ("版本", runtime.version),
                        ("架构", runtime.architecture.label),
                        ("路径", runtime.executableURL.path),
                        ("匹配状态", runtime.isRecommended(for: instance.gameVersion) ? "推荐" : "不推荐")
                    ])
                } else {
                    Text("尚未发现 Java 运行时。后续阶段会接入自动扫描。")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var launchPreview: some View {
        DetailSection(title: "启动命令预览", systemImage: "terminal") {
            if let preview = store.launchPreviewForSelectedInstance() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("该命令用于校验参数生成；真实启动会在下载与文件校验完成后接入。")
                        .foregroundStyle(.secondary)
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

    private var directories: some View {
        DetailSection(title: "文件边界", systemImage: "folder") {
            VStack(alignment: .leading, spacing: 8) {
                PathRow(title: "实例目录", path: instance.rootDirectory.path)
                PathRow(title: "Minecraft", path: instance.rootDirectory.appendingPathComponent(".minecraft").path)
                PathRow(title: "日志", path: instance.rootDirectory.appendingPathComponent("logs").path)
                PathRow(title: "模组", path: instance.rootDirectory.appendingPathComponent("mods").path)
            }
        }
    }

    private var plannedActions: some View {
        DetailSection(title: "Phase 0 操作", systemImage: "checklist") {
            HStack(spacing: 12) {
                Button {
                    Task {
                        await store.planVanillaInstallFromRemoteMetadata(for: instance)
                    }
                } label: {
                    Label("生成安装计划", systemImage: "list.bullet.clipboard")
                }

                Button {
                    store.launchSelectedInstance()
                } label: {
                    Label("启动", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedJavaRuntime == nil)

                Button {
                    store.prepareNativeLibrariesForSelectedInstance()
                } label: {
                    Label("准备 Native", systemImage: "square.and.arrow.down")
                }
                .disabled(store.plannedVersionMetadata == nil)

                Button {
                    store.inspectSelectedInstance()
                } label: {
                    Label("检查实例", systemImage: "checklist")
                }
                .disabled(store.selectedJavaRuntime == nil)

                Button {
                    Task {
                        await store.repairSelectedInstance()
                    }
                } label: {
                    Label("生成修复任务", systemImage: "wrench.and.screwdriver")
                }

                Button {
                    store.showingLogSheet = true
                } label: {
                    Label("打开日志", systemImage: "doc.text.magnifyingglass")
                }

                if instance.loader == .fabric {
                    Button {
                        Task {
                            await store.installFabricLoader(for: instance)
                        }
                    } label: {
                        Label("安装 Fabric", systemImage: "shippingbox")
                    }
                }

                if instance.loader == .quilt {
                    Button {
                        Task { await store.installQuiltLoader(for: instance) }
                    } label: {
                        Label("安装 Quilt", systemImage: "shippingbox")
                    }
                }

                if instance.loader == .forge {
                    Button {
                        Task { await store.installForgeLoader(for: instance) }
                    } label: {
                        Label("安装 Forge", systemImage: "hammer")
                    }
                }
            }

            if let session = store.currentLaunchSession {
                InfoGrid(rows: [
                    ("最近进程", "\(session.processIdentifier)"),
                    ("启动日志", session.logFileURL.path)
                ])
            }

            Text("安装计划会从 Mojang 版本元数据生成；启动会调用选中的 Java 并写入 latest.log。")
            Text("已具备在线 manifest 拉取、Java 输出解析、下载执行和 SHA-1 校验基础。")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct DetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
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

private struct InfoGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Text(row.1)
                        .textSelection(.enabled)
                }
            }
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
