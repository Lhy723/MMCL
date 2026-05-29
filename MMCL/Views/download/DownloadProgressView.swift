import SwiftUI

struct DownloadProgressView: View {
    @ObservedObject var store: LauncherStore
    @State private var expandedGroupIDs: Set<UUID> = []
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top)
            controlBar
                .padding(.horizontal)
                .padding(.top, 8)
            groupList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("下载进度")
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                appeared = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("下载进度")
                .font(.largeTitle.weight(.semibold))
            Text("实时查看所有下载任务的状态和进度。")
                .foregroundStyle(.secondary)
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Label("\(store.taskGroups.count) 个任务", systemImage: "square.stack.3d.up")
            Label(store.speedTracker.bytesPerSecond > 0
                  ? ByteCountFormatter.string(fromByteCount: store.speedTracker.bytesPerSecond, countStyle: .file) + "/s"
                  : "等待中",
                  systemImage: "speedometer")
            Label("\(store.downloadJobs.filter { $0.status == .completed }.count)/\(store.downloadJobs.count) 文件",
                  systemImage: "doc")
            Spacer()
            if store.downloadJobs.contains(where: { $0.status == .running }) {
                Button("暂停全部") { store.pauseDownloads() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if store.downloadJobs.contains(where: { $0.status == .paused }) {
                Button("继续全部") { store.resumeDownloads() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if store.downloadJobs.contains(where: { $0.status.isActive }) {
                Button(role: .destructive) {
                    store.cancelDownloads()
                } label: {
                    Text("取消全部")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var groupList: some View {
        if store.taskGroups.isEmpty {
            ContentUnavailableView("暂无下载任务", systemImage: "arrow.down.circle", description: Text("在原版游戏、Mod 等标签页中添加下载任务"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(store.taskGroups) { group in
                    TaskGroupRow(
                        group: group,
                        isExpanded: expandedGroupIDs.contains(group.id),
                        animationScale: store.animationDurationScale,
                        onToggle: {
                            withAnimation(.mmclSpring(response: 0.35, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                                if expandedGroupIDs.contains(group.id) {
                                    expandedGroupIDs.remove(group.id)
                                } else {
                                    expandedGroupIDs.insert(group.id)
                                }
                            }
                        },
                        onPauseGroup: { store.pauseGroup(group) },
                        onResumeGroup: { store.resumeGroup(group) },
                        onCancelGroup: { store.cancelGroup(group) },
                        onPauseJob: { store.pauseJob(id: $0) },
                        onResumeJob: { store.resumeJob(id: $0) },
                        onCancelJob: { store.cancelJob(id: $0) }
                    )
                    .animation(.mmclSpring(response: 0.4, dampingFraction: 0.9, scale: store.animationDurationScale), value: group.status)
                }
            }
            .listStyle(.inset)
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Task Group Row

private let maxVisibleJobs = 20

private struct TaskGroupRow: View {
    let group: DownloadTaskGroup
    let isExpanded: Bool
    let animationScale: Double
    let onToggle: () -> Void
    let onPauseGroup: () -> Void
    let onResumeGroup: () -> Void
    let onCancelGroup: () -> Void
    let onPauseJob: (UUID) -> Void
    let onResumeJob: (UUID) -> Void
    let onCancelJob: (UUID) -> Void

    private var activeJobs: [DownloadJob] {
        group.jobs.filter { $0.status == .running || $0.status == .paused }
    }
    private var failedJobs: [DownloadJob] {
        group.jobs.filter { $0.status == .failed }
    }
    private var completedJobs: [DownloadJob] {
        group.jobs.filter { $0.status == .completed }
    }
    private var queuedJobs: [DownloadJob] {
        group.jobs.filter { $0.status == .queued }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        statusIcon
                        Text(group.name)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        groupControlButtons
                        Text(statusLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: group.progress)
                        .animation(.mmclSpring(response: 0.4, dampingFraction: 0.9, scale: animationScale), value: group.progress)

                    HStack(spacing: 12) {
                        Text("\(group.completedCount)/\(group.jobs.count) 文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if group.totalBytes > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: group.completedBytes, countStyle: .file) + " / " +
                                 ByteCountFormatter.string(fromByteCount: group.totalBytes, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(group.progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if let currentFile = group.currentFileName {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text(currentFile)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.top, 4)
                expandedDetail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var groupControlButtons: some View {
        if group.status == .running {
            Button {
                onPauseGroup()
            } label: {
                Image(systemName: "pause.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("暂停此任务")
        }
        if group.status == .paused {
            Button {
                onResumeGroup()
            } label: {
                Image(systemName: "play.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("继续此任务")
        }
        if group.status.isActive {
            Button(role: .destructive) {
                onCancelGroup()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("取消此任务")
        }
    }

    @ViewBuilder
    private var expandedDetail: some View {
        VStack(spacing: 0) {
            let visibleJobs = visibleExpandedJobs
            ForEach(visibleJobs) { job in
                jobRow(job)
                    .transition(.move(edge: .top).combined(with: .opacity))
                if job.id != visibleJobs.last?.id {
                    Divider()
                        .padding(.leading, 28)
                }
            }

            if !completedJobs.isEmpty || !queuedJobs.isEmpty {
                collapsedSummary
                    .padding(.top, 4)
            }
        }
        .padding(.top, 6)
    }

    private var visibleExpandedJobs: [DownloadJob] {
        var result: [DownloadJob] = []
        result.append(contentsOf: activeJobs)
        result.append(contentsOf: failedJobs)
        if result.count < maxVisibleJobs {
            let remaining = maxVisibleJobs - result.count
            result.append(contentsOf: Array(queuedJobs.prefix(remaining)))
        }
        return result
    }

    private var collapsedSummary: some View {
        HStack(spacing: 8) {
            if !completedJobs.isEmpty {
                Label("\(completedJobs.count) 已完成", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if !queuedJobs.isEmpty {
                Label("\(queuedJobs.count) 等待中", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func jobRow(_ job: DownloadJob) -> some View {
        HStack(spacing: 8) {
            jobStatusIcon(job)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title)
                    .font(.caption)
                    .lineLimit(1)
                if job.status == .running && job.totalBytes > 0 {
                    ProgressView(value: job.progress)
                        .frame(height: 4)
                }
            }
            Spacer()
            if job.status == .running {
                Button {
                    onCancelJob(job.id)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("取消此文件")
                if job.totalBytes > 0 {
                    Text("\(Int(job.progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else if job.status == .paused {
                Button {
                    onResumeJob(job.id)
                } label: {
                    Image(systemName: "play.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("继续此文件")
            } else if job.status == .completed {
                Text(ByteCountFormatter.string(fromByteCount: job.totalBytes, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if job.status == .failed {
                Text("失败")
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else if job.status == .queued {
                Text("等待中")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch group.status {
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .transition(.scale.combined(with: .opacity))
        case .paused:
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
        case .queued:
            Image(systemName: "clock.fill")
                .foregroundStyle(.secondary)
        }
    }

    private func jobStatusIcon(_ job: DownloadJob) -> some View {
        Group {
            switch job.status {
            case .running:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .transition(.scale.combined(with: .opacity))
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
            case .queued:
                Image(systemName: "clock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .frame(width: 16)
    }

    private var statusLabel: String {
        switch group.status {
        case .running:
            return "下载中"
        case .completed:
            return "已完成"
        case .failed:
            return "失败 \(group.failedCount) 个"
        case .paused:
            return "已暂停"
        case .queued:
            return "等待中"
        }
    }
}
