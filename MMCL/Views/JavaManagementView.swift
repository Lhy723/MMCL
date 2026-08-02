import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct JavaManagementView: View {
    @ObservedObject var store: LauncherStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDownloadVersion = 21
    @State private var searchText = ""
    @State private var isPresentingJavaImporter = false
    @State private var importError: String?
    @State private var pendingDeletion: JavaRuntime?
    @State private var appeared = false

    private let downloadableVersions = [8, 11, 17, 21, 25]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                summary
                downloadCard
                runtimeList
            }
            .padding(24)
        }
        .navigationTitle("Java 管理")
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索 Java 版本、路径或架构")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isPresentingJavaImporter = true
                } label: {
                    Label("添加 Java", systemImage: "plus.circle")
                }
                .accessibilityLabel("添加 Java")
                .help("选择 JDK 内的 bin/java 文件")

                Button {
                    store.openPortableJavaDirectory()
                } label: {
                    Label("打开目录", systemImage: "folder")
                }
                .accessibilityLabel("打开便携 Java 目录")

                Button {
                    Task { await store.refreshJavaRuntimes() }
                } label: {
                    if store.isScanningJava {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isScanningJava)
                .accessibilityLabel(store.isScanningJava ? "正在刷新 Java" : "刷新 Java 列表")
            }
        }
        .fileImporter(
            isPresented: $isPresentingJavaImporter,
            allowedContentTypes: [.unixExecutable],
            allowsMultipleSelection: false
        ) { result in
            handleJavaImport(result)
        }
        .alert(
            "添加 Java 失败",
            isPresented: Binding(
                get: { importError != nil },
                set: { isPresented in
                    if !isPresented { importError = nil }
                }
            )
        ) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "无法添加所选 Java。")
        }
        .confirmationDialog(
            "删除 Java",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { pendingDeletion = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            if let runtime = pendingDeletion {
                Button("删除 Java \(runtime.majorVersion)", role: .destructive) {
                    withAnimation(listAnimation) {
                        store.removeJavaRuntime(runtime)
                    }
                    pendingDeletion = nil
                }
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("只会删除 MMCL 管理的便携版 JDK，不会删除系统或第三方 Java。")
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(listAnimation) {
                appeared = true
            }
        }
        .task {
            await Task.yield()
            if store.javaRuntimes.isEmpty {
                await store.refreshJavaRuntimes()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Java 管理")
                .font(.largeTitle.weight(.semibold))
            Text("管理 MMCL 可用的 Java 运行时，为不同 Minecraft 版本选择合适的 Java。")
                .foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            summaryCard(
                value: "\(store.javaRuntimes.count)",
                label: "已发现",
                systemImage: "cup.and.saucer.fill",
                tint: .accentColor
            )
            summaryCard(
                value: "\(enabledRuntimeCount)",
                label: "已启用",
                systemImage: "checkmark.circle.fill",
                tint: .green
            )
            summaryCard(
                value: "\(disabledRuntimeCount)",
                label: "已禁用",
                systemImage: "nosign",
                tint: .orange
            )
        }
    }

    private func summaryCard(
        value: String,
        label: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var downloadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("下载便携版 Java")
                        .font(.headline)
                    Text("从 Adoptium 下载与当前 Mac 架构匹配的 JDK。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Picker("版本", selection: $selectedDownloadVersion) {
                    ForEach(downloadableVersions, id: \.self) { version in
                        Text("Java \(version)").tag(version)
                    }
                }
                .pickerStyle(.menu)

                Text("架构：\(RuntimeArchitecture.currentSystem.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if store.isInstallingJDK {
                    VStack(alignment: .trailing, spacing: 3) {
                        ProgressView(value: store.jdkInstallProgress)
                            .frame(width: 130)
                        Text("正在下载并安装…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        Task {
                            await store.installJDK(majorVersion: selectedDownloadVersion)
                        }
                    } label: {
                        Label("下载并安装", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isScanningJava)
                }
            }

            Text("安装位置：\(store.portableJDKDirectory.path)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var runtimeList: some View {
        if filteredRuntimes.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "没有发现 Java" : "没有匹配的 Java",
                systemImage: "cup.and.saucer",
                description: Text(searchText.isEmpty
                    ? "可以点击「添加 Java」导入已有 JDK，或下载便携版 Java。"
                    : "试试搜索其他版本、路径或架构。")
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            ForEach(filteredRuntimes.sorted(by: runtimeSort)) { runtime in
                JavaRuntimeCard(
                    runtime: runtime,
                    isDisabled: store.isJavaRuntimeDisabled(runtime),
                    isRecommended: store.selectedInstance.map {
                        runtime.isRecommended(for: $0.gameVersion)
                    } ?? false,
                    canDelete: store.canDeleteJavaRuntime(runtime),
                    onOpenDirectory: { store.openJavaDirectory(for: runtime) },
                    onToggleDisabled: { store.toggleJavaRuntimeDisabled(runtime) },
                    onDelete: { pendingDeletion = runtime }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var filteredRuntimes: [JavaRuntime] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.javaRuntimes }
        return store.javaRuntimes.filter { runtime in
            runtime.name.localizedCaseInsensitiveContains(query)
                || runtime.version.localizedCaseInsensitiveContains(query)
                || runtime.architecture.label.localizedCaseInsensitiveContains(query)
                || runtime.executableURL.path.localizedCaseInsensitiveContains(query)
                || "Java \(runtime.majorVersion)".localizedCaseInsensitiveContains(query)
        }
    }

    private var enabledRuntimeCount: Int {
        store.javaRuntimes.filter { !store.isJavaRuntimeDisabled($0) }.count
    }

    private var disabledRuntimeCount: Int {
        store.javaRuntimes.filter { store.isJavaRuntimeDisabled($0) }.count
    }

    private var listAnimation: Animation? {
        guard !reduceMotion, store.animationDurationScale > 0 else { return nil }
        return .mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale)
    }

    private func runtimeSort(_ lhs: JavaRuntime, _ rhs: JavaRuntime) -> Bool {
        if lhs.majorVersion != rhs.majorVersion {
            return lhs.majorVersion > rhs.majorVersion
        }
        if lhs.architecture != rhs.architecture {
            return lhs.architecture.label < rhs.architecture.label
        }
        return lhs.executableURL.path.localizedStandardCompare(rhs.executableURL.path) == .orderedAscending
    }

    private func handleJavaImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importError = "没有选择 Java 文件。"
                return
            }
            guard store.addJavaRuntime(at: url) else {
                importError = "请选择 JDK 内可执行的 bin/java 文件。"
                return
            }
        case .failure(let error):
            let nsError = error as NSError
            guard nsError.domain != NSCocoaErrorDomain || nsError.code != NSUserCancelledError else {
                return
            }
            importError = error.localizedDescription
        }
    }
}

private struct JavaRuntimeCard: View {
    let runtime: JavaRuntime
    let isDisabled: Bool
    let isRecommended: Bool
    let canDelete: Bool
    let onOpenDirectory: () -> Void
    let onToggleDisabled: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isDisabled ? "nosign" : "cup.and.saucer.fill")
                .font(.title2)
                .foregroundStyle(isDisabled ? .orange : .green)
                .frame(width: 32, height: 32)
                .background((isDisabled ? Color.orange : Color.green).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(runtime.name)
                        .font(.headline)
                        .lineLimit(1)
                    if isRecommended {
                        Text("当前实例推荐")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.12), in: Capsule())
                    }
                    if isDisabled {
                        Text("已禁用")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.12), in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    Label(runtime.version, systemImage: "number")
                    Label(runtime.architecture.label, systemImage: "cpu")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(runtime.executableURL.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button(action: onOpenDirectory) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("打开 Java 目录")

                Button(action: onToggleDisabled) {
                    Image(systemName: isDisabled ? "checkmark.circle" : "nosign")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isDisabled ? .green : .orange)
                .accessibilityLabel(isDisabled ? "启用 Java" : "禁用 Java")

                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("删除 Java")
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if isDisabled {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.orange.opacity(0.35), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
        .opacity(isDisabled ? 0.72 : 1)
    }
}
