import SwiftUI

struct JDKInstallSheet: View {
    @ObservedObject var store: LauncherStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVersion: Int = 21
    private let availableVersions = [8, 17, 21]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("安装 Java")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            Divider()

            installSection

            Divider()

            installedSection
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 400, alignment: .top)
    }

    // MARK: - Install

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("从 Adoptium 下载便携版 JDK")
                .font(.headline)

            Text("安装到：\(store.portableJDKDirectory.path)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Picker("版本", selection: $selectedVersion) {
                ForEach(availableVersions, id: \.self) { version in
                    Text("Java \(version)").tag(version)
                }
            }
            .pickerStyle(.segmented)

            if store.isInstallingJDK {
                VStack(spacing: 6) {
                    ProgressView(value: store.jdkInstallProgress)
                    Text("正在下载并解压...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await store.installJDK(majorVersion: selectedVersion) }
                } label: {
                    Label("安装 Java \(selectedVersion)", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Installed

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已安装的便携版 JDK")
                .font(.headline)

            let portableRuntimes = store.javaRuntimes.filter { runtime in
                runtime.name.hasPrefix("便携版")
            }

            if portableRuntimes.isEmpty {
                Text("暂无已安装的便携版 JDK")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(portableRuntimes) { runtime in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Java \(runtime.majorVersion)")
                                .font(.subheadline.weight(.medium))
                            Text(runtime.version)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(runtime.executableURL.deletingLastPathComponent().deletingLastPathComponent().path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            store.removePortableJDK(at: runtime.executableURL)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                    if runtime.id != portableRuntimes.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}
