import SwiftUI

struct DownloadModpackView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        DownloadResourceSearchView(
            store: store,
            title: "整合包",
            icon: "shippingbox",
            projectType: "modpack",
            showLoaderFilter: false
        )
    }
}
