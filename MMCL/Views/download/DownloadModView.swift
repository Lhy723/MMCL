import SwiftUI

struct DownloadModView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        DownloadResourceSearchView(
            store: store,
            title: "Mod",
            icon: "puzzlepiece.extension",
            projectType: "mod",
            showLoaderFilter: true
        )
    }
}
