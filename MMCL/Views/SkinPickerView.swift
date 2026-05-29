import SwiftUI
import UniformTypeIdentifiers

struct SkinPickerView: View {
    @ObservedObject var store: LauncherStore
    @State private var newSkinName: String = ""
    @State private var newSkinModel: SkinInfo.SkinModel = .steve
    @State private var showFilePicker = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top)
            importBar
                .padding(.horizontal)
                .padding(.top, 8)
            skinGrid
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("皮肤管理")
        .frame(maxHeight: .infinity, alignment: .top)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                appeared = true
            }
        }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("皮肤管理")
                .font(.largeTitle.weight(.semibold))
            if let account = store.selectedAccount {
                Text("当前账号：\(account.displayName)")
                    .foregroundStyle(.secondary)
            } else {
                Text("管理 Minecraft 玩家皮肤。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var importBar: some View {
        HStack(spacing: 12) {
            TextField("皮肤名称", text: $newSkinName)
                .textFieldStyle(.roundedBorder)

            Picker("模型", selection: $newSkinModel) {
                ForEach(SkinInfo.SkinModel.allCases, id: \.self) { model in
                    Text(model.label).tag(model)
                }
            }
            .pickerStyle(.menu)

            Button {
                showFilePicker = true
            } label: {
                Label("导入皮肤", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(newSkinName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var skinGrid: some View {
        Group {
            if store.availableSkins.isEmpty {
                ContentUnavailableView("暂无皮肤", systemImage: "person.crop.rectangle", description: Text("输入名称并导入 PNG 皮肤文件"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.availableSkins) { skin in
                    SkinRow(skin: skin) {
                        store.applySkin(skin)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct SkinRow: View {
    let skin: SkinInfo
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(skin.model == .alex ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                .frame(width: 48, height: 64)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(skin.name)
                    .font(.headline)
                Text(skin.model.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if skin.isApplied {
                Label("已应用", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("应用") {
                    onApply()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
