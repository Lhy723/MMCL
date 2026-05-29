import SwiftUI

struct DownloadResourcePackView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        DownloadResourceSearchView(
            store: store,
            title: "资源包",
            icon: "photo.stack",
            projectType: "resourcepack",
            showLoaderFilter: false
        )
    }
}
