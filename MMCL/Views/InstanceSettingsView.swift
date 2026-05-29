import SwiftUI

struct InstanceSettingsView: View {
    let instance: LauncherInstance
    @ObservedObject var store: LauncherStore
    @State private var appeared = false

    @State private var offlineUsername: String
    @State private var memoryMegabytes: Int
    @State private var jvmArgumentsText: String

    init(instance: LauncherInstance, store: LauncherStore) {
        self.instance = instance
        self.store = store
        _offlineUsername = State(initialValue: instance.profile.offlineUsername)
        _memoryMegabytes = State(initialValue: instance.profile.memoryMegabytes)
        _jvmArgumentsText = State(initialValue: instance.profile.jvmArguments.joined(separator: " "))
    }

    var body: some View {
        List {
            basicInfoSection
            javaSection
            launchConfigSection
            managementSection
            advancedSection
        }
        .listStyle(.inset)
        .navigationTitle(instance.name)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                appeared = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    store.selectedInstanceSettingsID = nil
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
            }
        }
    }

    // MARK: - Basic Info

    private var basicInfoSection: some View {
        Section("基本信息") {
            LabeledContent("版本", value: instance.gameVersion)
            LabeledContent("加载器", value: instance.loader.rawValue)
            LabeledContent("状态", value: instance.status.label)
            LabeledContent("推荐 Java", value: "Java \(JavaRuntime.recommendedMajorVersion(for: instance.gameVersion))")
            if let date = instance.lastPlayedAt {
                LabeledContent("上次游玩", value: Self.dateFormatter.string(from: date))
            }
        }
    }

    // MARK: - Java Runtime

    private var javaSection: some View {
        Section("Java 运行时") {
            Picker("运行时", selection: $store.selectedJavaRuntimeID) {
                Text("自动选择").tag(JavaRuntime.ID?.none)
                ForEach(store.javaRuntimes) { runtime in
                    Text(runtime.displayName).tag(Optional(runtime.id))
                }
            }
            .pickerStyle(.menu)

            if let runtime = store.selectedJavaRuntime {
                LabeledContent("版本", value: runtime.version)
                LabeledContent("架构", value: runtime.architecture.label)
                LabeledContent("匹配", value: runtime.isRecommended(for: instance.gameVersion) ? "推荐" : "不推荐")
                    .foregroundStyle(runtime.isRecommended(for: instance.gameVersion) ? .green : .orange)
            } else {
                Text("未发现 Java 运行时")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await store.refreshJavaRuntimes() }
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.isScanningJava)
        }
    }

    // MARK: - Launch Config

    private var launchConfigSection: some View {
        Section("启动配置") {
            TextField("离线用户名", text: $offlineUsername)
                .onChange(of: offlineUsername) { _, _ in
                    saveProfile()
                }

            HStack {
                Text("内存")
                Spacer()
                TextField("MB", value: $memoryMegabytes, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: memoryMegabytes) { _, _ in
                        saveProfile()
                    }
                Text("MB")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("JVM 参数")
                    .foregroundStyle(.secondary)
                TextField("-XX:+UseG1GC ...", text: $jvmArgumentsText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: jvmArgumentsText) { _, _ in
                        saveProfile()
                    }
            }
        }
    }

    // MARK: - Management

    private var managementSection: some View {
        Section("内容管理") {
            Button {
                store.showingModList = true
            } label: {
                Label("管理 Mod", systemImage: "puzzlepiece.extension")
            }

            Button {
                store.showingResourcePacks = true
            } label: {
                Label("管理资源包", systemImage: "photo")
            }

            Button {
                store.showingShaderPacks = true
            } label: {
                Label("管理光影", systemImage: "sun.max")
            }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        Section("操作") {
            Button {
                store.showingLogSheet = true
            } label: {
                Label("查看日志", systemImage: "doc.text.magnifyingglass")
            }

            Button {
                store.showingRenameSheet = true
            } label: {
                Label("重命名", systemImage: "pencil")
            }

            if instance.loader == .fabric {
                Button { Task { await store.installFabricLoader(for: instance) } } label: {
                    Label("安装 Fabric", systemImage: "shippingbox")
                }
            }
            if instance.loader == .quilt {
                Button { Task { await store.installQuiltLoader(for: instance) } } label: {
                    Label("安装 Quilt", systemImage: "shippingbox")
                }
            }
            if instance.loader == .forge {
                Button { Task { await store.installForgeLoader(for: instance) } } label: {
                    Label("安装 Forge", systemImage: "hammer")
                }
                Button { Task { await store.installNeoForgeLoader(for: instance) } } label: {
                    Label("安装 NeoForge", systemImage: "hammer.fill")
                }
            }

            Divider()

            Button(role: .destructive) {
                store.deleteInstance(instance)
                store.selectedInstanceSettingsID = nil
            } label: {
                Label("删除实例", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func saveProfile() {
        let args = jvmArgumentsText
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        store.saveInstanceProfile(instance, profile: LaunchProfile(
            offlineUsername: offlineUsername,
            memoryMegabytes: max(512, memoryMegabytes),
            jvmArguments: args,
            resolutionWidth: instance.profile.resolutionWidth,
            resolutionHeight: instance.profile.resolutionHeight
        ))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
