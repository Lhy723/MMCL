import SwiftUI

struct InstanceRenameSheet: View {
    let instance: LauncherInstance
    @ObservedObject var store: LauncherStore
    @State private var newName: String

    init(instance: LauncherInstance, store: LauncherStore) {
        self.instance = instance
        self.store = store
        _newName = State(initialValue: instance.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("重命名实例")
                .font(.headline)
            TextField("新名称", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { store.showingRenameSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("确定") {
                    store.renameInstance(instance, to: newName)
                    store.showingRenameSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 350)
    }
}
