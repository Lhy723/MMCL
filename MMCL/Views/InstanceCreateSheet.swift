import SwiftUI

struct InstanceCreateSheet: View {
    @ObservedObject var store: LauncherStore
    @State private var name: String = "新实例"
    @State private var selectedVersionID: String = ""
    @State private var loader: GameLoader = .vanilla
    @State private var memory: Int = 4096
    @State private var username: String = "Steve"
    @State private var jvmArgs: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新增实例")
                .font(.largeTitle.weight(.semibold))

            Form {
                Section("基本信息") {
                    TextField("实例名称", text: $name)

                    Picker("游戏版本", selection: $selectedVersionID) {
                        ForEach(store.availableVersions) { version in
                            Text("\(version.id) · \(version.type.label)").tag(version.id)
                        }
                    }

                    Picker("加载器", selection: $loader) {
                        ForEach(GameLoader.allCases) { gameLoader in
                            Text(gameLoader.rawValue).tag(gameLoader)
                        }
                    }
                }

                Section("启动配置") {
                    Stepper("内存：\(memory) MB", value: $memory, in: 1024...16384, step: 512)
                    TextField("离线用户名", text: $username)
                    TextField("JVM 参数（可选）", text: $jvmArgs)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") {
                    store.showingCreateSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("创建") {
                    let args = jvmArgs
                        .split(separator: " ")
                        .map(String.init)
                        .filter { !$0.isEmpty }
                    store.createInstance(
                        name: name,
                        gameVersion: selectedVersionID,
                        loader: loader,
                        memory: memory,
                        username: username,
                        jvmArgs: args
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedVersionID.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 520)
        .onAppear {
            if selectedVersionID.isEmpty {
                selectedVersionID = store.availableVersions.first?.id ?? ""
            }
        }
    }
}
