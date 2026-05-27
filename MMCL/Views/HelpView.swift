import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("MMCL 帮助")
                    .font(.largeTitle.weight(.semibold))

                HelpSection(title: "快速开始", icon: "rocket") {
                    HelpItem(title: "创建实例", text: "点击工具栏「新增实例」或 Cmd+N，选择游戏版本和加载器。")
                    HelpItem(title: "安装游戏", text: "选择实例，点击「生成安装计划」，然后在下载中心开始下载。")
                    HelpItem(title: "启动游戏", text: "下载完成后，点击「启动」按钮。")
                }

                HelpSection(title: "加载器", icon: "shippingbox") {
                    HelpItem(title: "Fabric", text: "现代轻量级加载器，推荐用于大多数 Mod。需要先安装原版。")
                    HelpItem(title: "Forge", text: "经典 Mod 加载器，兼容性最广。")
                    HelpItem(title: "NeoForge", text: "Forge 的社区分支，更新更活跃。")
                    HelpItem(title: "Quilt", text: "Fabric 的社区分支，正在发展中。")
                }

                HelpSection(title: "Mod 管理", icon: "puzzlepiece.extension") {
                    HelpItem(title: "安装 Mod", text: "在 Modrinth 或 CurseForge 页面搜索，选择版本后点击安装。")
                    HelpItem(title: "管理 Mod", text: "在实例详情页点击「管理 Mod」，可以启用、禁用或删除 Mod。")
                }

                HelpSection(title: "账号", icon: "person.circle") {
                    HelpItem(title: "离线登录", text: "在设置中添加离线账号，输入用户名即可。")
                    HelpItem(title: "正版登录", text: "点击「Microsoft 登录」，在浏览器中输入设备代码完成授权。")
                }

                HelpSection(title: "故障排除", icon: "wrench") {
                    HelpItem(title: "检查实例", text: "点击「检查实例」可以诊断文件缺失和 Java 版本问题。")
                    HelpItem(title: "崩溃分析", text: "点击「崩溃分析」自动分析最新崩溃日志。")
                    HelpItem(title: "诊断日志", text: "在侧边栏打开诊断日志查看所有操作记录。")
                }
            }
            .padding(24)
        }
        .frame(width: 600, height: 500)
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.title3.weight(.semibold))
            content
                .padding(.leading, 20)
        }
    }
}

private struct HelpItem: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
