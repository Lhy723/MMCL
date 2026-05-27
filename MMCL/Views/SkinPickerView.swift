import SwiftUI
import UniformTypeIdentifiers

struct SkinPickerView: View {
    @ObservedObject var store: LauncherStore
    @State private var newSkinName: String = ""
    @State private var newSkinModel: SkinInfo.SkinModel = .steve
    @State private var showFilePicker = false
    @State private var importSourceURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("皮肤管理")
                .font(.largeTitle.weight(.semibold))

            if let account = store.selectedAccount {
                Text("当前账号：\(account.displayName)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("皮肤名称", text: $newSkinName)
                    .frame(maxWidth: 200)
                Picker("模型", selection: $newSkinModel) {
                    ForEach(SkinInfo.SkinModel.allCases, id: \.self) { model in
                        Text(model.label).tag(model)
                    }
                }
                .frame(maxWidth: 120)
                Button("导入皮肤") {
                    showFilePicker = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(newSkinName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            if store.availableSkins.isEmpty {
                Text("暂无皮肤。点击「导入皮肤」添加。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 120), spacing: 16)
                    ], spacing: 16) {
                        ForEach(store.availableSkins) { skin in
                            SkinCard(skin: skin) {
                                store.applySkin(skin)
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("关闭") {
                    store.showingSkinPicker = false
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 480)
        .onAppear {
            if let account = store.selectedAccount {
                store.scanSkinsForAccount(account)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType.png]
        ) { result in
            if case .success(let url) = result {
                store.importSkinFromPicker(
                    sourceURL: url,
                    name: newSkinName,
                    model: newSkinModel
                )
                newSkinName = ""
            }
        }
    }
}

private struct SkinCard: View {
    let skin: SkinInfo
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(skin.model == .alex ? Color.blue.opacity(0.3) : Color.green.opacity(0.3))
                .frame(width: 80, height: 120)
                .overlay(
                    VStack {
                        Image(systemName: "person.fill")
                            .font(.largeTitle)
                        Text(skin.model.label)
                            .font(.caption)
                    }
                )

            Text(skin.name)
                .font(.caption)
                .lineLimit(1)

            Button("应用") {
                onApply()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(skin.isApplied)
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(skin.isApplied ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}
