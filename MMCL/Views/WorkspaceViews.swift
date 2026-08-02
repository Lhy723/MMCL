import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DiagnosticsView: View {
    @ObservedObject var store: LauncherStore
    @State private var selectedSeverity: DiagnosticSeverity? = nil
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top)
            filterBar
                .padding(.horizontal)
                .padding(.top, 8)
            reportList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("诊断日志")
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                appeared = true
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("诊断日志")
                .font(.largeTitle.weight(.semibold))
            Text("自动聚合 Java、下载、实例文件和 Mod 冲突问题。")
                .foregroundStyle(.secondary)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("严重程度", selection: $selectedSeverity) {
                Text("全部").tag(DiagnosticSeverity?.none)
                ForEach(DiagnosticSeverity.allCases) { severity in
                    Text(severity.localized).tag(Optional(severity))
                }
            }
            .pickerStyle(.menu)

            Spacer()

            Button {
                Task {
                    await store.runDiagnostics()
                }
            } label: {
                Label("运行诊断", systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)

            if !store.diagnostics.isEmpty {
                Button(role: .destructive) {
                    store.diagnostics.removeAll()
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var reportList: some View {
        Group {
            if filteredReports.isEmpty {
                ContentUnavailableView(
                    store.diagnostics.isEmpty ? "暂无诊断报告" : "没有匹配的报告",
                    systemImage: store.diagnostics.isEmpty ? "checkmark.shield" : "line.3.horizontal.decrease.circle",
                    description: Text(store.diagnostics.isEmpty ? "运行诊断以检查潜在问题" : "试试其他筛选条件")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredReports) { report in
                    DiagnosticReportRow(report: report)
                }
                .listStyle(.inset)
            }
        }
    }

    private var filteredReports: [DiagnosticReport] {
        if let severity = selectedSeverity {
            return store.diagnostics.filter { $0.severity == severity }
        }
        return store.diagnostics
    }
}

private struct DiagnosticReportRow: View {
    let report: DiagnosticReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                Text(report.title)
                    .font(.headline)
                Spacer()
                Text(report.localizedSeverity)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(report.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !report.suggestedActions.isEmpty {
                ForEach(report.suggestedActions, id: \.self) { action in
                    Label(action, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch report.severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch report.severity {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: LauncherStore
    @State private var selectedTab = "launch"
    @State private var appeared = false

    var body: some View {
        TabView(selection: $selectedTab) {
            LaunchSettingsTab(store: store)
                .tabItem { Label("启动", systemImage: "play.fill") }
                .tag("launch")

            JavaManagementView(store: store)
                .tabItem { Label("Java", systemImage: "cup.and.saucer.fill") }
                .tag("java")

            PersonalizationSettingsTab(store: store)
                .tabItem { Label("个性化", systemImage: "paintbrush") }
                .tag("personalization")

            OtherSettingsTab(store: store)
                .tabItem { Label("其他", systemImage: "ellipsis.circle") }
                .tag("other")
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                appeared = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Launch Settings

private struct LaunchSettingsTab: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        Form {
            Section("启动选项") {
                Picker("版本隔离", selection: $store.versionIsolation) {
                    ForEach(VersionIsolation.allCases) { v in
                        Text(v.rawValue).tag(v)
                    }
                }
                .help(store.versionIsolation.helpText)

                TextField("游戏窗口标题", text: $store.gameWindowTitle)
                    .textFieldStyle(.roundedBorder)
                    .help("留空使用默认标题")

                TextField("自定义信息", text: $store.customInfo)
                    .textFieldStyle(.roundedBorder)
                    .help("显示在启动器界面上的自定义文本")

                Picker("启动器可见性", selection: $store.launcherVisibility) {
                    ForEach(LauncherVisibility.allCases) { v in
                        Text(v.rawValue).tag(v)
                    }
                }

                Picker("进程优先级", selection: $store.processPriority) {
                    ForEach(ProcessPriority.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }

                Picker("窗口大小", selection: $store.windowSizeMode) {
                    ForEach(WindowSizeMode.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                if store.windowSizeMode == .custom {
                    HStack {
                        Text("尺寸")
                        TextField("宽", value: $store.defaultResolutionWidth, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("x")
                        TextField("高", value: $store.defaultResolutionHeight, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Section("游戏 Java") {
                Picker("运行时", selection: javaRuntimeSelection) {
                    Text("自动选择（按当前实例）").tag(JavaRuntime.ID?.none)
                    ForEach(store.javaRuntimes.filter { !store.isJavaRuntimeDisabled($0) }) { runtime in
                        Text(runtime.displayName).tag(Optional(runtime.id))
                    }
                }
                .disabled(store.selectedInstance == nil)

                if let instance = store.selectedInstance {
                    LabeledContent("当前实例", value: instance.name)
                    LabeledContent("选择模式", value: instance.profile.javaSelectionMode.label)
                } else {
                    Text("请先选择实例，再设置该实例的 Java")
                        .foregroundStyle(.secondary)
                }

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
                .disabled(store.isScanningJava)
                .accessibilityLabel(store.isScanningJava ? "正在扫描 Java" : "重新扫描 Java")

            }

            Section("内存分配") {
                Toggle("自动配置内存", isOn: $store.memoryAutoConfig)
                    .help("根据系统内存自动调整分配")

                if !store.memoryAutoConfig {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("分配内存：\(store.defaultMemoryMegabytes) MB")
                        Slider(value: Binding(
                            get: { Double(store.defaultMemoryMegabytes) },
                            set: { store.defaultMemoryMegabytes = Int($0) }
                        ), in: 512...32768, step: 256)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("系统总内存")
                        Spacer()
                        Text("\(totalMemoryMegabytes) MB")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    ProgressView(
                        value: Double(clampedMemoryMegabytes),
                        total: Double(totalMemoryMegabytes)
                    )
                    .tint(allocatedMemoryFraction > 0.85 ? .red : .accentColor)
                    .accessibilityLabel("内存分配进度")
                    .accessibilityValue("已分配 \(allocatedMemoryPercentage)%")
                    Text("已分配 \(store.defaultMemoryMegabytes) MB（\(allocatedMemoryPercentage)%）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("高级选项") {
                LabeledContent("JVM 参数") {
                    Text(store.enabledJVMArguments.joined(separator: " "))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .help("在下方 JVM 预设中管理")

                TextField("游戏参数", text: $store.gameArguments)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .help("额外的游戏启动参数")

                TextField("启动前执行命令", text: $store.preLaunchCommand)
                    .textFieldStyle(.roundedBorder)
                    .help("启动游戏前执行的 shell 命令")

                Text("macOS 优化：启动时优先选择与系统架构匹配的 Java。图形后端由 Minecraft/LWJGL 根据版本自动选择 OpenGL 或 MoltenVK。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("JVM 预设") {
                    ForEach(store.jvmPresets) { preset in
                        HStack {
                            Toggle(preset.name, isOn: Binding(
                                get: { preset.isEnabled },
                                set: { newValue in
                                    store.setJVMPresetEnabled(id: preset.id, enabled: newValue)
                                }
                            ))
                            Spacer()
                            Text(preset.arguments.joined(separator: " "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }

        .formStyle(.grouped)
        .animation(.mmclSpring(response: 0.35, dampingFraction: 0.85, scale: store.animationDurationScale), value: store.windowSizeMode)
        .animation(.mmclSpring(response: 0.35, dampingFraction: 0.85, scale: store.animationDurationScale), value: store.memoryAutoConfig)
    }

    private var totalMemoryMegabytes: Int {
        let divisor: UInt64 = 1024 * 1024
        return max(Int(ProcessInfo.processInfo.physicalMemory / divisor), 1)
    }

    private var clampedMemoryMegabytes: Int {
        min(max(store.defaultMemoryMegabytes, 0), totalMemoryMegabytes)
    }

    private var allocatedMemoryFraction: Double {
        min(max(Double(store.defaultMemoryMegabytes) / Double(totalMemoryMegabytes), 0), 1)
    }

    private var allocatedMemoryPercentage: String {
        String(format: "%.0f", allocatedMemoryFraction * 100)
    }

    private var javaRuntimeSelection: Binding<JavaRuntime.ID?> {
        Binding(
            get: {
                guard let instance = store.selectedInstance,
                      instance.profile.javaSelectionMode == .manual else { return nil }
                return instance.profile.javaRuntimeID
            },
            set: { runtimeID in
                store.setJavaSelectionForSelectedInstance(runtimeID: runtimeID)
            }
        )
    }
}

// MARK: - Personalization Settings

private struct PersonalizationSettingsTab: View {
    @ObservedObject var store: LauncherStore
    @State private var isPresentingBackgroundImporter = false

    var body: some View {
        Form {
            Section("外观") {
                Picker("配色方案", selection: $store.colorScheme) {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Text(scheme.rawValue).tag(scheme)
                    }
                }

                Button {
                    isPresentingBackgroundImporter = true
                } label: {
                    Label(store.backgroundImage.url != nil ? "更换背景" : "选择背景图片", systemImage: "photo")
                }
                .accessibilityLabel(store.backgroundImage.url != nil ? "更换背景图片" : "选择背景图片")

                if store.backgroundImage.url != nil {
                    Button("移除背景") {
                        store.setBackgroundImage(nil)
                    }
                    .foregroundStyle(.red)

                    Slider(value: Binding(
                        get: { store.backgroundImage.opacity },
                        set: { store.setBackgroundOpacity($0) }
                    ), in: 0...1, step: 0.05) {
                        Text("不透明度：\(Int(store.backgroundImage.opacity * 100))%")
                    }

                    Slider(value: Binding(
                        get: { Float(store.backgroundImage.blurRadius) },
                        set: { store.setBackgroundBlur(CGFloat($0)) }
                    ), in: 0...20, step: 1) {
                        Text("模糊半径：\(Int(store.backgroundImage.blurRadius))")
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Section("动画") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("动画时长")
                        Spacer()
                        Text(store.animationDurationScale == 0 ? "关闭" :
                             store.animationDurationScale == 0.5 ? "快" :
                             store.animationDurationScale == 1.0 ? "正常" :
                             store.animationDurationScale == 1.5 ? "慢" : "自定义")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.animationDurationScale, in: 0...2, step: 0.25)
                    Text("0 = 关闭动画，1 = 正常，2 = 两倍时长")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("语言") {
                Picker("界面语言", selection: $store.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
            }

            Section("账号") {
                ForEach(store.accounts) { account in
                    AccountRow(account: account, store: store)
                }

                Button("添加离线账号") {
                    store.addOfflineAccount(username: store.defaultOfflineUsername)
                }

                Button {
                    Task { await store.startMicrosoftLogin() }
                } label: {
                    if store.isLoggingIn {
                        ProgressView()
                    } else {
                        Label("Microsoft 登录", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                .disabled(store.isLoggingIn)
                .accessibilityLabel(store.isLoggingIn ? "正在进行 Microsoft 登录" : "Microsoft 登录")

                if !store.deviceCodeMessage.isEmpty {
                    Text(store.deviceCodeMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isPresentingBackgroundImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                store.setBackgroundImage(url)
            }
        }
        .animation(.mmclSpring(response: 0.35, dampingFraction: 0.85, scale: store.animationDurationScale), value: store.backgroundImage.url != nil)
    }
}

// MARK: - Other Settings

private struct OtherSettingsTab: View {
    @ObservedObject var store: LauncherStore
    @State private var isPresentingProfileImporter = false

    var body: some View {
        Form {
            Section("下载") {
                Picker("文件下载源", selection: $store.fileDownloadSourceMode) {
                    ForEach(FileDownloadSourceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("版本列表源", selection: $store.versionListSourceMode) {
                    ForEach(VersionListSourceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("最大线程数：\(store.maxDownloadThreads)")
                    Slider(value: Binding(
                        get: { Double(store.maxDownloadThreads) },
                        set: { store.maxDownloadThreads = Int($0) }
                    ), in: 1...255, step: 1)
                    Text("通常 64 线程已足够")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.downloadSpeedLimit == 0 ? "速度限制：不限制" : "速度限制：\(store.downloadSpeedLimit) KB/s")
                    Slider(value: Binding(
                        get: { Double(store.downloadSpeedLimit) },
                        set: { store.downloadSpeedLimit = Int($0) }
                    ), in: 0...4096, step: 64)
                }
            }

            Section("社区资源") {
                Picker("来源", selection: $store.communitySourceMode) {
                    ForEach(CommunitySourceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("文件名格式", selection: $store.filenameFormat) {
                    ForEach(FilenameFormat.allCases) { fmt in
                        Text(fmt.rawValue).tag(fmt)
                    }
                }

                Picker("Mod 管理样式", selection: $store.modListDisplayStyle) {
                    ForEach(ModListDisplayStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
            }

            Section("CurseForge API") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CurseForge API Key")
                        .font(.headline)
                    Text("可选。填入后可同时搜索 CurseForge 资源。从 console.curseforge.com 获取。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("输入 API Key", text: $store.curseForgeApiKey)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("配置管理") {
                Button {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.json]
                    panel.nameFieldStringValue = "mmcl_profile_export.json"
                    panel.begin { response in
                        if response == .OK, let url = panel.url {
                            store.exportProfile(to: url)
                        }
                    }
                } label: {
                    Label("导出配置", systemImage: "square.and.arrow.up")
                }

                Button {
                    isPresentingProfileImporter = true
                } label: {
                    Label("导入配置", systemImage: "square.and.arrow.down")
                }
            }

            Section("关于") {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MMCL")
                            .font(.title2.weight(.semibold))
                        Text("Melody Minecraft Launcher")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack {
                    Text("当前版本")
                    Spacer()
                    Text(store.currentVersion)
                }
                Button {
                    Task { await store.checkForUpdates() }
                } label: {
                    if store.isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Label("检查更新", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isCheckingForUpdates || store.isDownloadingUpdate)
                .accessibilityLabel(store.isCheckingForUpdates ? "正在检查更新" : "检查更新")

                Button {
                    store.openGitHubRepo()
                } label: {
                    Label("GitHub 仓库", systemImage: "link")
                }

                Text("如果 MMCL 对你有帮助，欢迎去 GitHub 点个 star (◕ᴗ◕✿)\n一个人开发不容易，你的支持是我持续更新的最大动力！")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)

                if store.updateAvailable, let v = store.latestVersion {
                    Text("新版本可用：\(v)")
                        .foregroundStyle(.blue)
                    if let notes = store.updateRelease?.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                       !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                    if store.updateDownloadURL != nil {
                        Button {
                            Task { await store.downloadAndInstallUpdate() }
                        } label: {
                            Label(
                                store.isDownloadingUpdate ? "下载并安装中..." : "安装并重启",
                                systemImage: "arrow.down.circle.fill"
                            )
                        }
                        .disabled(store.isDownloadingUpdate)
                    } else {
                        Text("当前 Release 未提供 ZIP 自动更新包，请手动安装。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("打开 Release 页面") {
                        store.openLatestRelease()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isPresentingProfileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                store.importProfile(from: url)
            }
        }
    }
}

private struct AccountRow: View {
    let account: MinecraftAccount
    @ObservedObject var store: LauncherStore
    @State private var isEditing = false
    @State private var editUsername: String = ""

    var body: some View {
        HStack {
            if isEditing && account.type == .offline {
                TextField("用户名", text: $editUsername)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save() }
                Button("保存") { save() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("取消") { isEditing = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Text(account.displayName)
                Spacer()
                Text(account.type == .microsoft ? "在线" : "离线")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if account.type == .offline {
                    Button {
                        editUsername = account.username
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("编辑离线账号")
                    .accessibilityHint("修改此账号的用户名")
                }
                Button(role: .destructive) {
                    store.deleteAccount(account)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除账号")
                .accessibilityHint("从 MMCL 中移除此账号")
            }
        }
    }

    private func save() {
        let name = editUsername.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.updateAccountUsername(account, newUsername: name)
        isEditing = false
    }
}
