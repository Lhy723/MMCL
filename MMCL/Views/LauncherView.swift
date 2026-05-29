import SwiftUI

struct LauncherView: View {
    @ObservedObject var store: LauncherStore
    @State private var launchPulse = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top)

            if let instance = store.selectedInstance {
                instanceCard(instance)
                    .id(instance.id)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                Spacer()
                launchButton
                    .padding(.horizontal)
                    .padding(.bottom)
            } else {
                ContentUnavailableView(
                    store.instances.isEmpty ? "没有实例" : "未选择实例",
                    systemImage: "cube.box",
                    description: Text(store.instances.isEmpty ? "前往下载中心创建你的第一个实例" : "从上方下拉菜单选择一个实例")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                Spacer()
            }
        }
        .animation(.mmclSpring(response: 0.5, dampingFraction: 0.8, scale: store.animationDurationScale), value: store.launcherSelectedInstanceID)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                appeared = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("启动器")
        .onChange(of: store.selectedInstance?.status) { _, newStatus in
            if newStatus == .ready {
                withAnimation(.easeOut(duration: 0.6).repeatCount(2, autoreverses: true)) {
                    launchPulse = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    launchPulse = false
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text("启动器")
                        .font(.largeTitle.weight(.semibold))
                }
                Spacer()
                Button {
                    store.openGitHubRepo()
                } label: {
                    Image(systemName: "link.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("GitHub 仓库")
            }
            instancePicker
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instancePicker: some View {
        Menu {
            Button("未选择") { store.launcherSelectedInstanceID = nil }
            ForEach(store.instances) { instance in
                Button {
                    store.launcherSelectedInstanceID = instance.id
                } label: {
                    HStack {
                        Text(instance.name)
                        if store.launcherSelectedInstanceID == instance.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(store.selectedInstance?.name ?? "未选择")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .controlSize(.large)
            .frame(maxWidth: 400, alignment: .leading)
        }
    }

    // MARK: - Instance Card

    private func instanceCard(_ instance: LauncherInstance) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(instance.blockIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.name)
                        .font(.title3.weight(.semibold))
                    Text(instance.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.selectedInstanceSettingsID = instance.id
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 16) {
                statusChip(instance)
                if let date = instance.lastPlayedAt {
                    Label(Self.dateFormatter.string(from: date), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if instance.status == .ready {
                    Label("已就绪", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if instance.status != .ready {
                downloadPrompt(instance)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func downloadPrompt(_ instance: LauncherInstance) -> some View {
        VStack(spacing: 8) {
            Text("需要下载游戏文件才能启动")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                store.selectedSection = .downloads
            } label: {
                Label("前往下载中心", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statusChip(_ instance: LauncherInstance) -> some View {
        Text(instance.status.label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor(instance.status).opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor(instance.status))
            .transition(.scale.combined(with: .opacity))
            .animation(.mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale), value: instance.status)
    }

    private func statusColor(_ status: InstanceStatus) -> Color {
        switch status {
        case .notInstalled: return .orange
        case .missingFiles: return .orange
        case .needsJava: return .orange
        case .ready: return .green
        }
    }

    // MARK: - Buttons

    private var launchButton: some View {
        Button {
            store.launchSelectedInstance()
        } label: {
            Label("启动游戏", systemImage: "play.fill")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .scaleEffect(launchPulse ? 1.02 : 1.0)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(store.selectedInstance == nil || store.selectedJavaRuntime == nil || store.selectedInstance?.status != .ready)
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
