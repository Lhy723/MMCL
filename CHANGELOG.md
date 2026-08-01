# Changelog

MMCL 的版本变更记录。格式参考 [Keep a Changelog](https://keepachangelog.com/)，版本号遵循语义化版本。

## [0.1.1] - 2026-08-01

0.1.1 是在 0.1.0 基础上的稳定性与发布流程更新，重点修复了“界面显示完成但实际无法启动/安装”的问题。

### 新增

- Microsoft 账号真正参与 Minecraft 启动，使用真实用户名、UUID、Access Token、XUID 和 `msa` 用户类型。
- Microsoft 账号启动前的令牌过期检测与 Refresh Token 刷新。
- Fabric、Quilt、Forge 和 NeoForge 的加载器版本元数据、依赖和启动配置处理。
- 应用内 GitHub Releases 更新检查，支持读取正式版 Release 的 ZIP 更新包。
- ZIP 更新包校验、应用包验证、旧进程等待、应用替换和自动重启。
- Release 工作流同时生成 `.zip` 自动更新包和 `.dmg` 手动安装包。

### 修复

- 修复加载器实例启动时错误读取原版版本 JSON 的问题。
- 修复加载器安装完成但缺少核心库、主类或处理器配置的问题。
- 修复 Mod 启用、禁用和删除时重复拼接 `.jar` 导致操作无效的问题。
- 修复取消下载后活动槽位不释放、排队任务重新启动和队列卡死的问题。
- 修复资源索引展开使用游戏版本名而不是 `assetIndex.id` 的问题。
- 修复便携 JDK 解压失败仍显示安装完成的问题；现在会校验 HTTP 状态、tar 退出状态和可执行的 `bin/java`。
- 修复实例复制时目录和持久化数据相互覆盖的问题。
- 修复更新检查缺少 HTTP 状态校验、错误选择源码 ZIP、下载后只打开 DMG 且不会自动重启的问题。

### 安全与工程

- Microsoft 凭据继续使用 macOS Keychain 持久化，不写入普通 JSON 配置。
- 应用版本统一为 `0.1.1`，Build Number 更新为 `2`，最低支持 macOS 14.0。
- 补充更新服务、应用替换、Release 解析和 JDK 安装失败路径的回归测试。

## [0.1.0] - 2026-05-29

首个公开版本，提供 Minecraft 实例管理、原版与 Mod 加载器安装、Modrinth/CurseForge 搜索、Java 管理、Microsoft OAuth 登录、离线账号、资源包/光影包管理和基础 GitHub Release 检查能力。

[0.1.1]: https://github.com/Lhy723/MMCL/releases/tag/v0.1.1
[0.1.0]: https://github.com/Lhy723/MMCL/releases/tag/v0.1.0
