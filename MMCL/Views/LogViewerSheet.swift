import SwiftUI

struct LogViewerSheet: View {
    let instance: LauncherInstance
    @ObservedObject var store: LauncherStore

    var body: some View {
        Text("日志查看器")
    }
}
