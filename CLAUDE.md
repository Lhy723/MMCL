# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

```bash
# Build (debug)
xcodebuild build -project MMCL.xcodeproj -scheme MMCL -destination 'platform=macOS' -quiet

# Run tests
xcodebuild test -project MMCL.xcodeproj -scheme MMCL -destination 'platform=macOS' -quiet

# Run single test class
xcodebuild test -project MMCL.xcodeproj -scheme MMCL -destination 'platform=macOS' -only-testing:MMCLTests/LauncherStoreTests

# Build & run (uses script)
./script/build_and_run.sh
```

## Architecture

macOS Minecraft launcher. SwiftUI app with a **Models → Services → Store → Views** layered architecture. References PCL (Plain Craft Launcher) for interaction design and backend management patterns.

### Core layers

- **Models** (`MMCL/Models/LauncherModels.swift`): All data types — `LauncherInstance`, `VersionMetadata`, `DownloadJob`, `JavaRuntime`, `AssetIndex`, `LaunchSession`, `MinecraftAccount`, `FabricProfile`, `ModrinthVersion`, `ModInfo`, `ResourcePackInfo`, etc.
- **Services** (`MMCL/Services/LauncherServices.swift`): Protocol-based service layer.
  - `InstanceServicing` — instance creation, slug generation, JSON persistence
  - `VersionManifestServicing` — Mojang version manifest/metadata fetching
  - `DownloadServicing` — download job creation, SHA-1 execution, native library unzipping
  - `JavaRuntimeServicing` — `/usr/libexec/java_home -V` parsing, portable JDK install
  - `LaunchServicing` — command line generation, preflight checks, game launch
  - `DiagnosticServicing` — Java mismatch checks, crash log analysis
  - `FabricServicing` — Fabric loader installation via meta.fabricmc.net
  - `QuiltServicing` — Quilt loader installation via meta.quiltmc.org
  - `ForgeServicing` — Forge loader installation via promotions_slim.json
  - `NeoForgeServicing` — NeoForge loader installation via Maven
  - `ModrinthServicing` — Modrinth search, project details, version download
  - `CurseForgeServicing` — CurseForge mod search (requires API key)
  - `AuthServicing` — Microsoft OAuth device code flow, XBL/XSTS/Minecraft token exchange
- **Store** (`MMCL/Stores/LauncherStore.swift`): `@MainActor` `ObservableObject` holding all app state. Orchestrates services, manages downloads, process monitoring, account management. All `@Published` modifications must happen on main actor.
- **Views** (`MMCL/Views/`): SwiftUI views. `NavigationSplitView` layout with sidebar + detail + sheets.
  - `LauncherView` — instance picker, launch button, instance card with block icon
  - `DownloadCenterView` — TabView with 7 tabs (新建实例, Mod, 整合包, 数据包, 资源包, 光影包, 下载进度)
  - `DownloadVanillaView` — Minecraft version list, loader selection, create + download
  - `DownloadResourceSearchView` — Modrinth/CurseForge search with stagger animation
  - `DownloadProgressView` — concurrent download progress, pause/resume/cancel
  - `InstanceSettingsView` — instance config (Java, memory, JVM args, management)
  - `ModListView` — local mod management (enable/disable/delete)
  - `ResourcePackListView` / `ShaderPackListView` — resource/shader pack management
  - `ModrinthProjectDetailView` — Modrinth version picker and install
  - `LogViewerSheet` — real-time game log viewer with auto-refresh
  - `JDKInstallSheet` — portable JDK installation from Adoptium
  - `SkinPickerView` — skin management
  - `ServerListView` — multiplayer server management
  - `WorkspaceViews` — DiagnosticsView, SettingsView (accounts, appearance, JVM presets, download source, about)
  - `AnimationScale.swift` — `Animation.mmclSpring()` extension for consistent spring animations

### Key patterns

- `@MainActor` on `LauncherStore` prevents "Publishing changes from within view updates" warnings
- Services injected into `LauncherStore` via init (protocol types) for mock-based testing
- JSON uses `JSONEncoder.mmcl` / `JSONDecoder.mmcl` (ISO 8601, pretty printed)
- Instance files at `~/Library/Application Support/MMCL/Instances/{slug}/instance.json`
- Portable JDK installed to `~/Library/Application Support/MMCL/JDK/`
- Download sources: official, BMCLAPI, custom mirror
- Java recommendation: major version 8 (≤1.16), 17 (1.17–1.19), 21 (≥1.20)
- Apple Silicon auto-detection: ZGC + optimized JVM args for arm64
- Downloads execute concurrently via `TaskGroup` (max 4 parallel)
- Microsoft auth uses device code flow (browser-based OAuth)
- Mod management: toggle by renaming `.jar` ↔ `.jar.disabled`
- Instance status verified against actual files on disk at startup
- Block icons: Grass (release), CommandBlock (snapshot), CobbleStone (old), Anvil (Forge), Fabric, Egg (Quilt)
- Animations use `Animation.mmclSpring()` with configurable duration scale

## Testing

Tests use XCTest with protocol-based mocks (e.g., `MockDownloadService`, `MockVersionManifestService`, `MockInstanceService`). No external dependencies. Tests in `MMCLTests/`.

## Conventions

- UI text in Chinese; code identifiers and comments in English
- `Persistence.swift` is template CoreData — not used; app state lives in `LauncherStore`
- Project uses `PBXFileSystemSynchronizedRootGroup` — new `.swift` files auto-discovered by Xcode
- GitHub repo: `Lhy723/MMCL`
