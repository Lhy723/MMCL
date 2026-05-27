import SwiftUI

struct DownloadsView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack(alignment: .center, spacing: 12) {
                Picker("下载源", selection: $store.selectedDownloadSource) {
                    ForEach(DownloadSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Button {
                    Task {
                        await store.refreshAvailableVersions()
                    }
                } label: {
                    Label("刷新版本", systemImage: "arrow.clockwise")
                }

                Button {
                    Task {
                        await store.executeQueuedDownloads()
                    }
                } label: {
                    Label("开始下载", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.downloadJobs.contains { $0.status == .queued })

                Button {
                    store.cancelDownloads()
                } label: {
                    Label("取消", systemImage: "xmark.circle")
                }
                .disabled(!store.downloadJobs.contains { $0.status == .running })

                Button {
                    store.expandSelectedInstanceAssetIndex()
                } label: {
                    Label("展开资源", systemImage: "shippingbox")
                }

                Button {
                    store.prepareNativeLibrariesForSelectedInstance()
                } label: {
                    Label("准备 Native", systemImage: "square.and.arrow.down")
                }
                .disabled(store.plannedVersionMetadata == nil)
            }

            HStack(spacing: 16) {
                Label("\(store.downloadJobs.count) 个任务", systemImage: "square.stack.3d.up")
                Label(totalByteSummary, systemImage: "externaldrive.badge.checkmark")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            DetailSection(title: "可用版本", systemImage: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.availableVersions) { version in
                        HStack {
                            Text(version.id)
                                .font(.headline)
                            Text(version.type.label)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("推荐 Java \(version.recommendedJavaMajorVersion)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ForEach(store.downloadJobs) { job in
                DownloadJobRow(job: job)
            }

            Spacer()
        }
        .padding(24)
        .navigationTitle("下载中心")
    }

    private var totalByteSummary: String {
        let totalBytes = store.downloadJobs.reduce(Int64(0)) { $0 + $1.totalBytes }
        guard totalBytes > 0 else { return "总计 0 字节" }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("下载中心")
                .font(.largeTitle.weight(.semibold))
            Text("下载任务会写入实例目录并进行 SHA-1 校验；全部完成后会自动准备 Native 并更新实例状态。")
                .foregroundStyle(.secondary)
        }
    }
}

private struct DownloadJobRow: View {
    let job: DownloadJob

    var body: some View {
        DetailSection(title: job.title, systemImage: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(job.source.rawValue)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(job.status.label)
                }
                ProgressView(value: job.progress)
                if let remoteURL = job.remoteURL {
                    Text(remoteURL.absoluteString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                if let sha1 = job.sha1 {
                    Text("SHA-1: \(sha1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text(job.destination.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct ContentProjectsView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Modrinth")
                        .font(.largeTitle.weight(.semibold))
                    Text("优先接入 Modrinth 搜索、详情和安装；CurseForge 留到后续阶段。")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(store.featuredProjects) { project in
                        ProjectTile(project: project)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Modrinth")
    }
}

private struct ProjectTile: View {
    let project: ContentProject

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.tint)
                Text(project.type.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(project.title)
                .font(.headline)
                .lineLimit(1)
            Text(project.source)
                .foregroundStyle(.secondary)
            Text(project.loaders.map(\.rawValue).joined(separator: " / "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct DiagnosticsView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("诊断日志")
                        .font(.largeTitle.weight(.semibold))
                    Text("中文诊断会聚合 Java、下载、实例文件和 Mod 冲突问题。")
                        .foregroundStyle(.secondary)
                }

                ForEach(store.diagnostics) { report in
                    DiagnosticReportView(report: report)
                }
            }
            .padding(24)
        }
        .navigationTitle("诊断日志")
    }
}

private struct DiagnosticReportView: View {
    let report: DiagnosticReport

    var body: some View {
        DetailSection(title: report.title, systemImage: iconName) {
            VStack(alignment: .leading, spacing: 10) {
                Text(report.localizedSeverity)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(report.summary)
                ForEach(report.suggestedActions, id: \.self) { action in
                    Label(action, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var iconName: String {
        switch report.severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        Form {
            Section("启动") {
                TextField("默认离线用户名", text: $store.defaultOfflineUsername)
                Stepper("默认内存：\(store.defaultMemoryMegabytes) MB", value: $store.defaultMemoryMegabytes, in: 1024...16384, step: 512)
            }

            Section("下载") {
                Picker("首选下载源", selection: $store.preferredDownloadSource) {
                    ForEach(DownloadSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 320)
    }
}
