import SwiftUI

struct DownloadDataPackView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        DownloadResourceSearchView(
            store: store,
            title: "数据包",
            icon: "doc.text",
            projectType: "datapack",
            showLoaderFilter: false
        )
    }
}
