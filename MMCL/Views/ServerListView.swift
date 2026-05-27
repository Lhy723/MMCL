import SwiftUI

struct ServerListView: View {
    @ObservedObject var store: LauncherStore
    @State private var showingAddSheet = false
    @State private var newServerName: String = ""
    @State private var newServerAddress: String = ""
    @State private var newServerPort: String = "25565"
    @State private var editingServerID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("服务器列表")
                .font(.largeTitle.weight(.semibold))

            if let instance = store.selectedInstance {
                Text("实例：\(instance.name)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    showingAddSheet = true
                    newServerName = ""
                    newServerAddress = ""
                    newServerPort = "25565"
                    editingServerID = nil
                } label: {
                    Label("添加服务器", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    store.pingAllServers()
                } label: {
                    Label("全部 Ping", systemImage: "arrow.clockwise")
                }

                Spacer()
            }

            if store.serverList.isEmpty {
                Text("暂无服务器。点击「添加服务器」开始。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedServers) { server in
                        ServerRow(server: server) {
                            if let instance = store.selectedInstance {
                                store.deleteServer(server, for: instance)
                            }
                        } onPing: {
                            store.pingServer(server)
                        } onEdit: {
                            newServerName = server.name
                            newServerAddress = server.address
                            newServerPort = "\(server.port)"
                            editingServerID = server.id
                            showingAddSheet = true
                        } onToggleFavorite: {
                            if let instance = store.selectedInstance {
                                store.toggleServerFavorite(server, for: instance)
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .navigationTitle("服务器列表")
        .sheet(isPresented: $showingAddSheet) {
            VStack(alignment: .leading, spacing: 18) {
                Text(editingServerID == nil ? "添加服务器" : "编辑服务器")
                    .font(.title2.weight(.semibold))

                Form {
                    Section("服务器信息") {
                        TextField("名称", text: $newServerName)
                        TextField("地址", text: $newServerAddress)
                            .font(.system(.body, design: .monospaced))
                        TextField("端口", text: $newServerPort)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .formStyle(.grouped)

                HStack {
                    Spacer()
                    Button("取消") {
                        showingAddSheet = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(editingServerID == nil ? "添加" : "保存") {
                        guard let instance = store.selectedInstance else { return }
                        let port = Int(newServerPort) ?? 25565
                        if let editID = editingServerID,
                           let index = store.serverList.firstIndex(where: { $0.id == editID }) {
                            var updated = store.serverList[index]
                            updated.name = newServerName
                            updated.address = newServerAddress
                            updated.port = port
                            store.updateServer(updated, for: instance)
                        } else {
                            store.addServer(
                                name: newServerName,
                                address: newServerAddress,
                                port: port,
                                for: instance
                            )
                        }
                        showingAddSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newServerName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              newServerAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 420, height: 320)
        }
        .onAppear {
            if let instance = store.selectedInstance {
                store.loadServerList(for: instance)
            }
        }
    }

    private var sortedServers: [ServerInfo] {
        store.serverList.sorted { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            return a.name < b.name
        }
    }
}

private struct ServerRow: View {
    let server: ServerInfo
    let onDelete: () -> Void
    let onPing: () -> Void
    let onEdit: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if server.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                    Text(server.name)
                        .font(.headline)
                }
                Text(server.fullAddress)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let ping = server.pingResult {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(ping.playerCount)/\(ping.maxPlayers)")
                        .font(.caption)
                    Text("\(ping.pingMs) ms")
                        .font(.caption)
                        .foregroundStyle(ping.pingMs < 100 ? .green : ping.pingMs < 300 ? .orange : .red)
                }
            } else {
                Text("未 Ping")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Menu {
                Button("Ping") { onPing() }
                Button("编辑") { onEdit() }
                Button(server.isFavorite ? "取消收藏" : "收藏") { onToggleFavorite() }
                Divider()
                Button("删除", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .padding(.vertical, 4)
    }
}
