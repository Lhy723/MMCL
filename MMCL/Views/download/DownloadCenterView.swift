import SwiftUI

struct DownloadCenterView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        TabView(selection: $store.selectedDownloadTab) {
            DownloadVanillaView(store: store)
                .tabItem { Label("原版游戏", systemImage: "cube.box") }
                .tag(DownloadTabType.vanilla)

            DownloadModView(store: store)
                .tabItem { Label("Mod", systemImage: "puzzlepiece.extension") }
                .tag(DownloadTabType.mod)

            DownloadModpackView(store: store)
                .tabItem { Label("整合包", systemImage: "shippingbox") }
                .tag(DownloadTabType.modpack)

            DownloadDataPackView(store: store)
                .tabItem { Label("数据包", systemImage: "doc.text") }
                .tag(DownloadTabType.dataPack)

            DownloadResourcePackView(store: store)
                .tabItem { Label("资源包", systemImage: "photo.stack") }
                .tag(DownloadTabType.resourcePack)

            DownloadShaderView(store: store)
                .tabItem { Label("光影包", systemImage: "sparkles") }
                .tag(DownloadTabType.shader)

            DownloadProgressView(store: store)
                .tabItem { Label("下载进度", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(DownloadTabType.progress)
        }
    }
}
