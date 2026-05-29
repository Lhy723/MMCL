import SwiftUI

struct DownloadShaderView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        DownloadResourceSearchView(
            store: store,
            title: "光影包",
            icon: "sparkles",
            projectType: "shader",
            showLoaderFilter: false
        )
    }
}
