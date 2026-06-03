# OpenWith 实施计划（图片「打开方式」）

> **For agentic workers:** REQUIRED SUB-SKILL: 用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐 task 实施。Steps 用 `- [ ]` checkbox 跟踪。
> 设计源：`specs/OpenWith.md`。本项目**无 XCTest target → 跳 TDD**（CLAUDE.md 例外）；每 task 验收 = `make build` BUILD SUCCEEDED + 收尾走 `./scripts/verify.sh` 三段 + PENDING 人工清单。

**Goal:** 让 Glance 在 Finder「打开方式」/ Dock 拖放 / 拖图到窗口接收图片，单图直接进 QuickViewer 看；按需把图所在文件夹融入现有浏览。

**Architecture:** `AppDelegate.application(_:open:)` 收到 URL → 写单例 `ExternalOpenCoordinator.pendingOpen` → `ContentView` 观察后用独立 `externalOpenUrls` `@State` 驱动现有 `QuickViewerOverlay`（不碰 `folderStore.images`/IndexStore）。Slice 2 在 QV 加「浏览所在文件夹」入口，按需 `NSOpenPanel` 授权父目录后复用 `FolderStore.addFolder(from:)`。

**Tech Stack:** SwiftUI + AppKit（NSApplicationDelegate / NSOpenPanel / NSAlert）+ UniformTypeIdentifiers + 沙盒 Security Scoped Resource。

**起点：** working tree 已有 spike 代码（`Glance/Info.plist` + pbxproj 两处 `INFOPLIST_FILE` + `GlanceApp.swift` 的 `application(_:open:)` alert 块）。Slice 1 把 alert 块转正，Info.plist + pbxproj 直接沿用。

---

## 文件结构

| 文件 | 职责 | 动作 |
|------|------|------|
| `Glance/Info.plist` | 文档类型声明（CFBundleDocumentTypes） | 已 spike 创建，沿用 |
| `Glance.xcodeproj/project.pbxproj` | `INFOPLIST_FILE` 两处（Debug/Release） | 已 spike 改，沿用 |
| `Glance/ExternalOpen/ExternalOpenCoordinator.swift` | AppDelegate→SwiftUI 单向桥（单例 ObservableObject） | 新建（Slice 1） |
| `Glance/GlanceApp.swift` | AppDelegate 转正 + 注入 coordinator | 改（Slice 1） |
| `Glance/ContentView.swift` | externalOpenUrls 状态 + QV 图源 + 触发 + 关闭仲裁 | 改（Slice 1 + Slice 2 handler） |
| `Glance/QuickViewer/QuickViewerOverlay.swift` | 「浏览所在文件夹」入口按钮 | 改（Slice 2） |

---

# Slice 1 — 亮起来 + 看单图

> 端到端可 ship：Finder「打开方式」不再灰 + 单图/多图打开直接进 QuickViewer 看图。

## Task 1.1: ExternalOpenCoordinator（桥）

**Files:**
- Create: `Glance/ExternalOpen/ExternalOpenCoordinator.swift`

- [ ] **Step 1: 写 coordinator**

```swift
import Foundation

/// AppDelegate（application(_:open:)）→ SwiftUI ContentView 的单向桥。
/// 沙盒「打开方式」/ Dock 拖放传入的图片 URL 暂存此处，ContentView 观察 pendingOpen
/// 变化后消费（设回 nil）。单例 mirror AboutWindowController.shared pattern。
final class ExternalOpenCoordinator: ObservableObject {
    static let shared = ExternalOpenCoordinator()

    /// 待处理的外部打开图片 URL 集合。ContentView 消费后清回 nil。
    @Published var pendingOpen: [URL]?

    private init() {}
}
```

- [ ] **Step 2: 编译验证**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`（PBXFileSystemSynchronizedRootGroup 自动纳入新 .swift）

- [ ] **Step 3: Commit**

```bash
git add Glance/ExternalOpen/ExternalOpenCoordinator.swift
git commit -m "feat(OpenWith): ExternalOpenCoordinator 单例桥（AppDelegate→SwiftUI）"
```

## Task 1.2: AppDelegate 转正 + 注入 coordinator

**Files:**
- Modify: `Glance/GlanceApp.swift`

- [ ] **Step 1: 注入 coordinator 到 environment**

在 `ContentView()` 的 environmentObject 链末尾加一行（现有链在 GlanceApp body `WindowGroup` 内）：

```swift
            ContentView()
                .environmentObject(bookmarkManager)
                .environmentObject(folderStore)
                .environmentObject(appState)
                .environmentObject(indexStoreHolder)
                .environmentObject(ExternalOpenCoordinator.shared)
                .onAppear {
                    folderStore.loadSavedFolders()
                }
```

- [ ] **Step 2: AppDelegate.application(_:open:) 去 spike alert，转正写 coordinator**

把 spike 的 `application(_:open:)`（含 NSAlert 实测块）整段替换为：

```swift
    // 从 Finder「打开方式」/ Dock 拖放 / 拖图到窗口接收图片文件。
    // 过滤出图片 URL 后写入 coordinator，由 ContentView 观察消费驱动 QuickViewer。
    func application(_ application: NSApplication, open urls: [URL]) {
        let images = urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        }
        guard !images.isEmpty else { return }
        ExternalOpenCoordinator.shared.pendingOpen = images
    }
```

并在文件顶部 import 区加（`import AppKit` 已由 spike 加入）：

```swift
import UniformTypeIdentifiers
```

- [ ] **Step 3: 编译验证**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Glance/GlanceApp.swift
git commit -m "feat(OpenWith): application(_:open:) 转正 — 图片过滤后写 coordinator + 注入 environment"
```

## Task 1.3: ContentView 外部打开 → QuickViewer

**Files:**
- Modify: `Glance/ContentView.swift`（enum line 24-28 / `@State` 区 line ~100-110 / QV overlay line 208-233 / dismiss 仲裁 line 238-259 / 加 handler + onChange/onAppear）

- [ ] **Step 1: QuickViewerEntry 加 .externalOpen case**

把 `private enum QuickViewerEntry`（line 24-28）改为：

```swift
private enum QuickViewerEntry {
    case grid       // 路径 1: grid 双击 cell 直接进 QV
    case preview    // 路径 2: grid → preview → 双击 → QV
    case ephemeral  // 路径 3 (M2 Slice J): EphemeralResultView 双击 cell 进 QV → 退出直接回 baseGrid，不卡在 ephemeral 无焦点态
    case externalOpen  // 路径 5 (OpenWith): Finder「打开方式」进 QV → 退出回 app 之前状态，清 externalOpenUrls
}
```

- [ ] **Step 2: 加 externalOpen 观察 + 临时 URL 状态**

在 `@State private var v2Urls: [URL] = []`（line 100）后插入：

```swift
    /// OpenWith — Finder「打开方式」临时图源。non-nil 时 QV 图源走它（不碰 folderStore.images / IndexStore）。
    @State private var externalOpenUrls: [URL]? = nil
    /// OpenWith — AppDelegate→SwiftUI 桥，观察 pendingOpen 触发外部打开。
    @ObservedObject private var externalOpen = ExternalOpenCoordinator.shared
```

- [ ] **Step 3: QV 图源加 externalOpenUrls 优先级**

把 QV overlay 的 `images:` 参数（line 210）改为：

```swift
                    images: externalOpenUrls ?? (smartFolderStore.selected != nil ? v2Urls : folderStore.images),
```

- [ ] **Step 4: dismiss 仲裁加 .externalOpen case**

在 `onChange(of: quickViewerIndex)` 的 switch（line 240-259）的 `.ephemeral` case 后、`.none` case 前插入：

```swift
            case .externalOpen:
                // 路径 5 (OpenWith)：清临时图源退回 app 之前状态；selectedImageIndex 清 nil
                // 防 baseGrid 反弹（QV 方向键写过），focus 回 grid（无内容时无害）
                externalOpenUrls = nil
                folderStore.selectedImageIndex = nil
                focusTarget = .grid
```

- [ ] **Step 5: 加 handleExternalOpen + onChange/onAppear 触发**

在 body 的 `.animation(DS.Anim.normal, value: quickViewerIndex)`（line 235）之后、`.onChange(of: quickViewerIndex)`（line 238）之前插入触发链：

```swift
        .onChange(of: externalOpen.pendingOpen) { _, newValue in
            if let urls = newValue { handleExternalOpen(urls) }
        }
        .onAppear {
            // 冷启动兜底：app 启动时 application(_:open:) 可能已写 pendingOpen，
            // 但 ContentView 还没 mount → onChange 漏触发，onAppear 补一次消费。
            if let urls = externalOpen.pendingOpen { handleExternalOpen(urls) }
        }
```

并在 ContentView 内（任意 private 方法区，建议放 inspectorURL computed 之后）加 handler：

```swift
    /// OpenWith — 外部打开图片：临时图源驱动 QuickViewer，不持久化、不进 IndexStore。
    private func handleExternalOpen(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        externalOpenUrls = urls
        quickViewerEntry = .externalOpen
        quickViewerIndex = 0
        externalOpen.pendingOpen = nil  // 消费掉，防重复触发
    }
```

- [ ] **Step 6: 编译验证**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`，0 warning

- [ ] **Step 7: Commit**

```bash
git add Glance/ContentView.swift
git commit -m "feat(OpenWith): ContentView 外部打开 → 临时图源驱动 QuickViewer + 关闭仲裁退回原状态"
```

## Task 1.4: Slice 1 收尾验证

- [ ] **Step 1: 三段 verify**

Run: `./scripts/verify.sh`
Expected: `=== summary: 12 passed, 0 failed ===`

- [ ] **Step 2: 追加 PENDING 人工测试项**

向 `specs/PENDING-USER-ACTIONS.md` 新建 `### OpenWith Slice 1` H3 段，追加：
- 全新文件夹的图，Finder 右键「打开方式」→ Glance 不再灰、能选 → 选中后直接进 QuickViewer 全屏看这张
- Finder 多选 3 张图「打开方式 → Glance」→ 进 QV 看第一张，filmstrip/方向键能翻这 3 张（不含同文件夹其它图）
- QV 里 ESC/关闭 → 退回 app 之前状态（冷启动→空 baseGrid；已开着→之前浏览的文件夹），sidebar 没多出文件夹
- 拖一张图到 Dock 的 Glance 图标 → 同样进 QV 看图

- [ ] **Step 3: 文档同步 + commit**

按 CLAUDE.md 文档同步规则：`CLAUDE.md` 文件结构加 `Glance/ExternalOpen/` + `Glance/Info.plist`；`specs/Roadmap.md` 已完成表或 Bug Fix 段加 OpenWith Slice 1 行；`specs/OpenWith.md` 状态更新。逐文件 `git add` + commit（spike 转正的 Info.plist + pbxproj 一并提交）。

---

# Slice 2 — 浏览所在文件夹

> 在 Slice 1 基础上增量可 ship：QuickViewer 看外部图时，一键「浏览所在文件夹」（按需授权父目录）等同添加文件夹。

## Task 2.1: QuickViewerOverlay 加「浏览所在文件夹」入口

**Files:**
- Modify: `Glance/QuickViewer/QuickViewerOverlay.swift`（init line 30-45 + TopBar 区）

- [ ] **Step 1: init 加 onBrowseFolder 回调**

把 `QuickViewerOverlay` 的属性区（line 24 `let onCommandF` 后）加：

```swift
    /// OpenWith Slice 2 — 用户点「浏览所在文件夹」按钮触发，caller 传入当前图 URL。
    /// nil → 不渲染按钮（非外部打开场景 caller 不提供）。
    let onBrowseFolder: ((URL) -> Void)?
```

init 参数列表（line 30-38）末尾 `onCommandF: (() -> Void)? = nil` 后加 `onBrowseFolder: ((URL) -> Void)? = nil`，init body（line 44 后）加 `self.onBrowseFolder = onBrowseFolder`：

```swift
    init(
        images: [URL],
        startIndex: Int,
        onDismiss: @escaping () -> Void,
        onIndexChange: @escaping (Int) -> Void,
        onFindSimilar: ((URL) -> Void)? = nil,
        currentSupportsFeaturePrint: Bool = true,
        onCommandF: (() -> Void)? = nil,
        onBrowseFolder: ((URL) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: QuickViewerViewModel(images: images, startIndex: startIndex))
        self.onDismiss = onDismiss
        self.onIndexChange = onIndexChange
        self.onFindSimilar = onFindSimilar
        self.currentSupportsFeaturePrint = currentSupportsFeaturePrint
        self.onCommandF = onCommandF
        self.onBrowseFolder = onBrowseFolder
    }
```

- [ ] **Step 2: TopBar 渲染按钮（仅 onBrowseFolder 非 nil 时）**

在 QuickViewerOverlay 现有顶部工具栏区找到「找类似」按钮（`onFindSimilar` 渲染处，grep `onFindSimilar` 在 body 的使用点），mirror 其 `if let` 渲染模式，在其旁加：

```swift
                if let onBrowseFolder, let current = viewModel.images[safe: viewModel.currentIndex] {
                    Button {
                        onBrowseFolder(current)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                    .help("浏览所在文件夹")
                }
```

> 注：`viewModel.images` / `viewModel.currentIndex` 是否可访问、`[safe:]` 下标是否存在，实施时 grep `QuickViewerViewModel` 确认；若无 `[safe:]` 则用 `viewModel.currentIndex < viewModel.images.count` guard 取 `viewModel.images[viewModel.currentIndex]`。按钮的具体 DS 样式 mirror 同区「找类似」按钮，不引入新硬编码。

- [ ] **Step 3: 编译验证**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Glance/QuickViewer/QuickViewerOverlay.swift
git commit -m "feat(OpenWith): QuickViewer 加「浏览所在文件夹」入口按钮"
```

## Task 2.2: ContentView handleBrowseFolder（按需授权 + addFolder）

**Files:**
- Modify: `Glance/ContentView.swift`（QV overlay 传 onBrowseFolder + 加 handler）

- [ ] **Step 1: QV overlay 传 onBrowseFolder**

在 QV overlay 调用（line 209-231）的 `onCommandF: { openSearch() }` 后加：

```swift
                    onBrowseFolder: { url in handleBrowseFolder(url) },
```

- [ ] **Step 2: 加 handleBrowseFolder**

在 ContentView 加 handler（mirror handleExternalOpen 旁）：

```swift
    /// OpenWith Slice 2 — 浏览外部打开图的所在文件夹。
    /// 父文件夹已添加 → 直接选中浏览；未添加 → NSOpenPanel 预定位父目录授权后 addFolder。
    private func handleBrowseFolder(_ imageURL: URL) {
        let parent = imageURL.deletingLastPathComponent()

        // 已添加过（父目录是某 root 或在某 root 子树下）→ 直接选中，关 QV 退回浏览
        let alreadyManaged = folderStore.rootFolders.contains { root in
            parent == root.url || parent.path.hasPrefix(root.url.path + "/")
        }
        if alreadyManaged {
            folderStore.selectFolder(parent)
            externalOpenUrls = nil
            quickViewerEntry = nil
            quickViewerIndex = nil
            return
        }

        // 未添加 → NSOpenPanel 预定位父目录，用户选中即授权（沙盒铁律：单文件打开不含父目录权限）
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = parent
        panel.prompt = "浏览此文件夹"
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        folderStore.addFolder(from: chosen)  // 持久化 bookmark + discoverTree + selectFolder
        externalOpenUrls = nil
        quickViewerEntry = nil
        quickViewerIndex = nil
    }
```

并确认 ContentView 顶部已 `import AppKit`（NSOpenPanel）。若无则加 `import AppKit`。

- [ ] **Step 3: 编译验证**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`，0 warning

- [ ] **Step 4: Commit**

```bash
git add Glance/ContentView.swift
git commit -m "feat(OpenWith): handleBrowseFolder — 父目录已加直接浏览 / 未加 NSOpenPanel 授权后 addFolder"
```

## Task 2.3: Slice 2 收尾验证

- [ ] **Step 1: 三段 verify**

Run: `./scripts/verify.sh`
Expected: `=== summary: 12 passed, 0 failed ===`

- [ ] **Step 2: 追加 PENDING 人工测试项**

向 `specs/PENDING-USER-ACTIONS.md` 新建 `### OpenWith Slice 2` H3 段，追加：
- 打开**全新文件夹**的图 → QV 里点「浏览所在文件夹」（folder 图标）→ 弹「选择文件夹」对话框预定位到父目录 → 选中后 sidebar 加入该文件夹 + grid 显示整个文件夹缩略图 + 定位到刚才那张图，重启 app 该文件夹仍在
- 打开**已添加过文件夹**里的图 → 点「浏览所在文件夹」→ 不弹对话框，直接关 QV 跳到该文件夹 grid
- 浏览所在文件夹对话框点「取消」→ 留在 QV 看图，sidebar 无变化

- [ ] **Step 3: 文档同步 + commit + push（/go 收尾）**

走 `/go`：文档同步（`specs/Roadmap.md` + `specs/OpenWith.md` 状态 → 完成）+ PENDING + commit + push（pre-push codex review）+ 一段话汇报。

---

## Self-Review（writing-plans 自查）

**Spec coverage**（对 `specs/OpenWith.md` 逐条）：
- 单图打开进 QV → Task 1.3 ✓ / 多图 filmstrip → Task 1.3 图源用 externalOpenUrls 全集 ✓
- 浏览所在文件夹入口 → Task 2.1 ✓ / 按需授权 addFolder → Task 2.2 ✓ / 父目录已加省一步 → Task 2.2 alreadyManaged 分支 ✓
- 关 QV 退回原状态 → Task 1.3 Step 4 .externalOpen 仲裁 ✓
- 文档类型声明 → spike 已做，Task 1.4 Step 3 转正提交 ✓
- Dock 拖放 → Task 1.2 application(_:open:) 覆盖 ✓
- 不抢默认（LSHandlerRank=Alternate）→ Info.plist 已含 ✓

**Placeholder scan**：Task 2.1 Step 2 的 `viewModel.images[safe:]` 标注了"实施时 grep 确认 + fallback"——非空想 placeholder，是诚实的 code-reality-check 待办（QuickViewerViewModel 内部 API 实施时验证）。其余 step 均有完整代码。

**Type consistency**：`externalOpenUrls: [URL]?` / `ExternalOpenCoordinator.pendingOpen: [URL]?` / `QuickViewerEntry.externalOpen` / `handleExternalOpen(_:)` / `handleBrowseFolder(_:)` / `onBrowseFolder: ((URL) -> Void)?` 跨 task 命名一致 ✓

---

## Slice 1 完成详细（commit `<本次>`，ship 待）

Slice 1（外部打开看单图）+ 实测发现并修复的 4 个 bug 一起实现。**Slice 2（浏览所在文件夹）尚未做。**

| Task | 内容 | 状态 |
|------|------|------|
| 1.1 | 新建 `Glance/ExternalOpen/ExternalOpenCoordinator.swift`（单例 ObservableObject + `@Published pendingOpen`，`import Foundation` + `import Combine`——plan 漏 Combine，`@Published` 需要） | ✅ |
| 1.2 | `GlanceApp.swift`：spike NSAlert 转正成 `application(_:open:)` 过滤图片→写 coordinator；`import UniformTypeIdentifiers`；注入 environment | ✅ |
| 1.3 | `ContentView.swift` 6 处：QuickViewerEntry.externalOpen / externalOpenUrls + @ObservedObject externalOpen / QV images 源加 externalOpenUrls 优先 / dismiss 仲裁 .externalOpen 分支 / onChange(pendingOpen) / 冷启动兜底**合并进现有 .onAppear**（未建第二个） | ✅ |
| 1.4 | spike 的 Info.plist + pbxproj（INFOPLIST_FILE ×2 + 新增 PBXFileSystemSynchronizedBuildFileExceptionSet 把 Info.plist 从 Copy Bundle Resources 排除消 warning）转正提交 + verify + 文档同步 | ✅ |

### 实测发现并修复的 bug（user PENDING 验证逐一通过）

| # | 现象 | 根因 | 修复 |
|---|------|------|------|
| 1 | 多图「打开方式」spawn 多个空白窗口（Mission Control 见 3 窗）+ 抢 key | `WindowGroup` + `CFBundleDocumentTypes` 被 macOS 当可开文档 app，按每文件 spawn WindowGroup 实例 | `WindowGroup` → 单实例 `Window("一眼", id: "main")` |
| 2 | 外部打开进 QV 后 ESC 关不掉，须先点图 | QV `.onAppear { isFocused = true }` 时承载窗口还非 key（NSApp.activate 异步/冷启动），@FocusState 赋值被静默丢弃 | `AppState.isWindowKey` + WindowAccessor `windowDidBecomeKey/ResignKey` + 装 delegate 时 `isKeyWindow` 播种；QV onAppear 仅 key 时 assert + `.onChange(isWindowKey)` 补 assert（codex:rescue 方案 c）；application(open:) 加 `NSApp.activate(ignoringOtherApps:)` |
| 3 | 智能文件夹进 QV 首次悬停工具栏 tooltip 串成随机文件名 | V2 `SmartFolderImageCell` 显式 `.help(relativePath)` 的 tracking area 在 QV overlay 盖上后仍存活串扰（V1 cell 无显式 .help 故不串）；先试 QV 顶部 Text `.help("")` 无效（改错目标） | `ContentView` mainContent 加 `.allowsHitTesting(quickViewerIndex == nil)`，QV 期底层 grid tooltip tracking 失活（codex:rescue 二诊定位） |
| 4 | smart folder cell tooltip 只显文件名看不出来自哪个文件夹 | `.help(image.relativePath)` 根目录层图退化成纯文件名 | 改显完整路径：cell 复用 loadThumb 已 resolve 的 `fileURL.path` 存 @State，`.help(fullPath ?? relativePath)` |

附带：修了 M3 既有 `ParsedSearch` / `SearchSizeUnit` 的 actor-isolation warning（项目 default main-actor isolation 下纯值类型未标 `nonisolated`，runSearch detached task 访问 `parsed.isEmpty` 触发；标 `nonisolated` 修复）。

### 偏离 plan
- `ExternalOpenCoordinator` 补 `import Combine`（plan 只写 Foundation）。
- plan 行号因文件增长全失效，按符号名内容匹配实施。
- 冷启动兜底合并进 ContentView 现有 `.onAppear`（plan 写新建一个）。

### 已知遗留（不在本 commit）
- **侧边栏移除文件夹后智能文件夹仍残留其缩略图、点开一直 loading**：独立 bug，下一摊处理（方案 1 索引对账 + 防 wipe + 方案 3 加载失败占位）。
