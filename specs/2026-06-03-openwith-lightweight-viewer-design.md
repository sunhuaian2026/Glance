# OpenWith 轻量看图窗重构（方向 2）— 设计

> 状态：设计完成（2026-06-03 brainstorming 落地，2026-06-03 二轮 codex design review 收敛），待 writing-plans 出 task 级 plan。
> 关系：**取代** `specs/OpenWith.md` 里"外部打开复用图库主窗口 + QV overlay"的旧模型；Info.plist 文档类型声明、`application(_:open:)` 入口保留。
> 缘起：旧模型（单 `Window` scene 复用主窗口 + AppDelegate 消费 open 事件）在 warm 场景有两个 macOS 顽疾——(1) app 自杀（已用 shouldTerminate=false 临时挡）(2) 窗口不自动置顶（5 种激活 API 真机全败，见 Roadmap 待修复 + `project_openwith_warm_activation_macos_limitation` memory）。根因是"app 自己消费 open 事件 + 复用单 Window scene 瞬态"在跟系统对着干。本方向改成 Preview/Quick Look 式轻量语义，**自建独立看图窗**绕开顽疾。
>
> **二轮 review 关键修正**（codex，对照真实源码）：要严格做到"冷启动只建看图窗、ESC 退 app"（Preview 语义），SwiftUI 没有原生捷径（`handlesExternalEvents` / `openWindow` / `DocumentGroup` / `defaultLaunchBehavior` 都排除，理由见下）。**唯一干净路是把真实窗口创建权从 SwiftUI `Window` scene 收回 AppDelegate**：主窗也改自建 `MainWindowController`，看图窗自建 `ExternalViewerWindowController`，cold/warm 判断用自持 controller 状态（**禁止扫 `NSApp.windows`**）。"不可见占位 `Window` scene"是坑（仍是 scene → 幽灵主窗），不采用。

## 目标行为模型（Preview / Quick Look 式）

| 场景 | 打开时 | 看图窗 ESC/⌘W 关闭后 |
|------|--------|-------------------|
| **冷启动**（Glance 未运行）→ Finder「打开方式」 | 只建并显**独立看图窗**（全屏看这张），**不建**图库主窗 | **Glance 整个退出**（"看完即走"） |
| **warm**（Glance 已开、正在用图库主窗）→ Finder「打开方式」 | 看图窗**独立弹出并置顶**，图库主窗**原样不动** | 关看图窗，**图库主窗还在**，app 不退 |
| 正常点 Dock 打开 Glance（无文件）/ reopen | 显图库主窗（`MainWindowController` 建） | — |

术语：**图库主窗** = 承载 `ContentView`（sidebar + 缩略图浏览）的主窗口；**看图窗** = 全屏 QuickViewer 独立窗。**冷/warm = 本次进程是否"为打开文件而启动"**——由 AppDelegate 自己掌握，不靠扫窗口列表猜。

核心语义：**从 Finder 打开方式看单图 = 一次性轻量看图，不牵出图库主窗**；已在用 Glance 时开图不打扰正在用的主窗。

## 为什么没有 SwiftUI 原生捷径（codex 排除项）

要"冷启动按是否由文件启动决定首窗建谁"，下列 SwiftUI 路径都不成立：

- `handlesExternalEvents`：URL / user activity 的 scene 路由，不是 Finder「打开方式」文件 open-document 的可靠替代。
- `openWindow`：太晚——只能从已运行的 SwiftUI environment 打开窗，拦不住冷启动 primary scene 先建。
- `Window` vs `WindowGroup`：只改单/多窗口语义，不能"按是否由文件启动"条件决定首窗。
- `DocumentGroup`：最接近"打开文件生成文档窗"，但会把 app 改成文档 app 模型（还要图库主窗 / 非编辑图片文档 / 多文件合一 viewer / warm 不打扰 / 条件退出），是另一套 lifecycle，不是低风险捷径。
- `defaultLaunchBehavior`：较新 SwiftUI API，macOS 14 不可依赖；且只控 scene 默认 launch 行为，不等价完整 open-document 路由。

结论：真实窗口创建权必须离开无条件的 `Window("一眼")` scene。

## 架构

### 新增 `Glance/ExternalOpen/ExternalViewerWindowController.swift`（看图窗）
纯 AppKit 单例。**复刻 `Glance/About/AboutWindowController.swift` 的"自建 `NSWindow` + `NSHostingView` 可靠置顶"骨架，但不照搬其一次性 rootView**——看图窗要响应"二次打开换图源"，需要 session model。

职责：
- `show(urls: [URL], terminateOnClose: Bool)`：首次 `createWindow`；建/替换 `ViewerSession`（见下）；`makeKeyAndOrderFront` + `NSApp.activate(ignoringOtherApps:)` 置顶。
- 持有**自己的轻量 viewer `AppState` 实例**（`appState.window` = 看图窗本身）→ QuickViewer 的 F 全屏 / traffic light / 焦点都作用在看图窗，不碰图库窗。
- 窗口内容 = `QuickViewerOverlay(...)`，**必须显式 `.environmentObject(viewerAppState)`**（QuickViewerOverlay 强依赖 `@EnvironmentObject AppState`，缺注入直接运行时崩溃），传 `onFindSimilar=nil` / `onCommandF=nil` / 无 `onBrowseFolder`（纯看图）。
- **二次打开换图源**：rootView 不能是一次性的。每次 `show` 替换 hosting rootView，或给内容加 `.id(session.id)` 强制重建，或把图源提升为 viewer 持有的 observable model 让 `QuickViewerViewModel` 重建。（否则单例 window + `@StateObject QuickViewerViewModel` 在 init 时按首批 urls 建一次，二次打开显旧图。）
- `isReleasedWhenClosed = false`（mirror About），复用 window 实例。

### 新增 `ViewerSession`（看图窗的一次会话）
封装"一次看图"的生命周期，解掉 security-scope 配平 + 退出语义：
- 持有本次 urls + 对每个 url 的 `startAccessingSecurityScopedResource()` token。
- `terminateOnClose: Bool`：冷启动 open = `true`（看完退 app）；warm = `false`（只关窗）。
- 二次 `show`：**先 end 旧 session（stop 所有 scope），再 start 新 session**——避免重入/泄漏/start 返回 false 未处理。
- 窗口关闭（ESC / ⌘W / 红灯 / `windowWillClose` 任一路径）走**同一个 close path**：end session（stop scope）→ 若 `terminateOnClose` 则 `NSApp.terminate`，否则只关窗。

### 新增 `MainWindowController`（图库主窗，Slice 2 引入）
把图库主窗从 SwiftUI `Window` scene 收回自建：
- `show()`：建/复用 `NSWindow + NSHostingController(ContentView)`，注入 `BookmarkManager / FolderStore / 图库 AppState / IndexStoreHolder / ExternalOpenCoordinator`（沿用现 GlanceApp 注入集）。
- AppDelegate 持有它，**冷/warm 判断 = "我建过 main 窗了吗"**（自持状态），不扫 `NSApp.windows`（混入 About/看图窗/隐藏最小化窗/系统 panel，不可靠）。

### `GlanceApp.swift` / `AppDelegate`
- 不再声明 `Window("一眼", id:"main")` 作为真实主窗（Slice 2）。SwiftUI `App` 只保留 `Settings` / `.commands` 这类**非主窗 scene**（app-level 命令如 About 仍可用；依赖 focused-scene 的 SwiftUI commands 会变脆，当前主要是 About，自建无碍）。
- `application(_:open:)`：过滤图片 URL 后**直接** `ExternalViewerWindowController.shared.show(urls:, terminateOnClose: <冷启动?>)`（不再写 `ExternalOpenCoordinator.pendingOpen`）。
- `applicationDidFinishLaunching` / reopen：若**不是**为 open 文件而启动 → `MainWindowController.show()`；是 → 不建主窗（Slice 2）。

## 生命周期模型（cold / warm / 退出）

- **冷启动 open**：进程为打开文件而起 → AppDelegate **只** show 看图窗（`terminateOnClose=true`），不建 main 窗 → ESC/⌘W 关 → close path 见 `terminateOnClose=true` → `NSApp.terminate`。看完即走。
- **warm open**：进程已 `finishedLaunching` 且 main 窗已由用户在用 → show 看图窗（`terminateOnClose=false`），不动 main 窗 → ESC 关看图窗 → 只关窗，main 窗在，app 不退。
- **正常 launch / reopen（无文件）**：`MainWindowController.show()` → 自然窗口语义。
- **退出语义**：Slice 2 收完 lifecycle 后，由自建窗 + 自持状态决定，不再依赖 SwiftUI primary scene 的 last-window 行为。

> ⚠️ **`applicationShouldTerminateAfterLastWindowClosed` 分阶段处理**：原 D-OW8 想直接恢复默认 `true`——**撤销**。Slice 1（主 scene 还在）必须保持 `=false`（否则单 Window scene 仍可能瞬态 close 到 0 窗自杀，codex P1#2）；退出语义改由 `ViewerSession.terminateOnClose` + Slice 2 的自持窗口计数显式控制。

## 实施切片（vertical slice，风险前置）

### Slice 1 — 自建看图窗，先用在 warm，验置顶 + 清实现债（不碰 lifecycle）
范围：建 `ExternalViewerWindowController` + `ViewerSession` + viewer `AppState`；`application(_:open:)` 改直接 show 看图窗。
**硬边界（codex）**：
- **保留**主 SwiftUI `Window` scene；**保留** `applicationShouldTerminateAfterLastWindowClosed = false`；**暂不删** ContentView 的 externalOpen 机器和 QV overlay 的 `.externalOpen` 入口（新路径跑通、真机验过再删旧桥/按钮）。
- 置顶验证**只限 warm 场景**——只要 `Window("一眼")` 还在，冷启动主窗仍会被 SwiftUI 拉起，Slice 1 **证明不了冷启动**，不得宣称 cold 已解决。
- Slice 1 仍可能撞单 `Window` scene 的 transient close/reopen 抢 key；解法不是放弃，而是保持 `=false` + viewer 最后 order front + 把验证限定 warm。
实现债（Slice 1 一并解掉，codex 上一轮 P1）：environmentObject 注入 / 二次打开换图源 / ViewerSession 持有 scope 配平 / `WindowAccessor` 不抢 controller 的 close delegate（用 notification / delegate 多路复用 / 把 window state 接进 controller）/ ESC·⌘W·红灯·windowWillClose 统一 close path。
**Slice 1 验收（真机，CC 在 Mac mini 验不了 GUI）**：warm 下 app 前台/后台/主窗最小化/主窗隐藏；多文件一次打开；看图窗已开时再次 Finder open（不显旧图）；F 全屏后 ESC/⌘W/红灯关闭；Dock 拖多个文件；security scope 无泄漏。

### Slice 2 — 收回 lifecycle，拿"冷启动看完即走"
范围：移除真实 `Window("一眼")` scene；新增 `MainWindowController` 承载 `ContentView`；AppDelegate 决定首窗（冷启动 open 只建 viewer、普通 launch/reopen 建 main）；viewer 带 `terminateOnClose`（cold=true / warm=false）；删 ContentView externalOpen 机器 + QV overlay onBrowseFolder 按钮 + `ExternalOpenCoordinator.swift` + `DS.ExternalOpen`；`applicationShouldTerminateAfterLastWindowClosed` 退出语义改自持窗口计数。
> 兜底升级：原"扫 `NSApp.windows` 判断有无图库窗" → **撤销**。改用 `MainWindowController` 自持状态 + `ViewerSession.terminateOnClose`，cold/warm 完全可控。

### Slice 3（条件触发）— 只有混合形态在菜单/reopen/Settings 撞硬墙才切完整 AppKit lifecycle
不提前切；迁移面大（菜单 / settings / commands / app init 全重接），成本不值得先付。

## 增删清单

**新增**：`ExternalViewerWindowController.swift` + `ViewerSession`（Slice 1）；`MainWindowController`（Slice 2）。

**删除**（Slice 2，回滚旧模型 Slice 1/2 在 ContentView 的机器；删文件已在设计阶段同意，实施时删 `ExternalOpenCoordinator.swift` 前再报告一次）：
- `ContentView`：`externalOpenUrls` / `handleExternalOpen` / `handleBrowseFolder` / `QuickViewerEntry.externalOpen` case / `.onChange(externalOpen.pendingOpen)` / onAppear 外部打开兜底 / 整套激活机器（`scheduleActivation` / `waitForAppActivation` / `externalOpenActivationRequest` / `externalOpenActivationTask` / `.onChange(windowIdentity)` / `.onChange(isWindowKey)`）。删除时**逐项确认** grid/preview/ephemeral 三入口仍保持当前焦点 + selectedImageIndex 行为（codex P2：externalOpen 还参与 QV provenance / selected index 清理 / focusTarget 恢复 / toolbar 隐藏，不是单纯入口桥）。
- `QuickViewerOverlay`：`onBrowseFolder` 属性 + init 参数 + 底部「浏览所在文件夹」按钮（Slice 2 按钮回滚 `84a1f5b`）。
- `Glance/ExternalOpen/ExternalOpenCoordinator.swift`：整文件删除。
- `DS.ExternalOpen`：激活超时常量不再用，删。

**保留**：`Info.plist` 文档类型声明 + pbxproj `INFOPLIST_FILE` + exception set（进 Open With 必需）；`AppState.windowIdentity/attachWindow/detachWindow`（看图窗 + 图库窗 WindowAccessor 复用）；`AppState.isWindowKey`（QV 焦点）。

**改**：`GlanceApp.swift` `application(open:)` 改调 controller（Slice 1）；Slice 2 移除 `Window` scene、加 `MainWindowController`、退出语义改自持。

## 风险

- **⚠️ GUI 行为 CC 在 Mac mini（常无 GUI 会话）验不了**：置顶/前台/key window/窗口显隐/冷启动时序全靠用户真机迭代。两片拆解把最大不确定性（自建窗置顶 + QuickViewer 搬迁）压在 Slice 1，赌注前置。
- **置顶**：自建 NSWindow 理论能可靠置顶，但 About 只证了"app 已激活后从菜单开小窗"，**没证** warm 后台 app 收 Finder open 抢前台 / Spaces / 全屏窗 / Dock 拖入 / 多显示器——Slice 1 真机验。
- **`.commands` 菜单在 Slice 2 去主 scene 后是否仍正常**：app-level 命令大概率可用，依赖 focused-scene 的会脆；当前主要是 About，风险低但需验。
- **多图集合导航**：胶片条 / 方向键在独立看图窗里正常 → Slice 1 真机验。

## 决策记录

- **D-OW5 外部打开 = 轻量独立看图窗（Preview/Quick Look 式），非复用图库主窗口**。Why：旧模型复用单 Window scene + 消费 open 事件跟系统对着干，导致 warm 崩溃 + 置顶顽疾；自建独立窗顺着系统、置顶可控、语义更符合"快速看一张图"。How：`ExternalViewerWindowController`（mirror About 骨架，但带 session model）。
- **D-OW6 冷启动看图 ESC = app 退出（看完即走）；warm 不退（图库在用）**。Why：用户拍板——从 Finder 打开方式看单图是一次性行为，不该牵出图库主窗。这是 Preview 语义的核心，决定了必须走 D-OW9。
- **D-OW7 看图窗砍掉找类似/搜索/浏览所在文件夹，纯看图**。Why：轻量语义；这些是图库功能，想用去图库主窗。**回滚 Slice 2「浏览所在文件夹」按钮**（`84a1f5b`）。
- **D-OW8 ~~shouldTerminate 恢复默认 true~~ → 撤销，改分阶段**。Why：codex P1#2——只要 SwiftUI 主 `Window` scene 还在（Slice 1），恢复 true 会被单 Window scene 瞬态 close 触发自杀。改为：Slice 1 保持 `=false`；退出语义由 `ViewerSession.terminateOnClose` + Slice 2 自持窗口计数控制。
- **D-OW9 真实窗口创建权从 SwiftUI `Window` scene 收回 AppDelegate；主窗也改自建 `MainWindowController`**。Why：Preview 式冷启动需"按是否由文件启动决定首窗建谁"，SwiftUI 无原生捷径（见"为什么没有 SwiftUI 原生捷径"），事后 `.close()` 主窗不可靠（闪/抢 key/触发 terminate）。**否决"不可见占位 Window scene"**（仍是 scene → 参与恢复/Window 菜单/last-window → 幽灵主窗）。How：App 只留 Settings/.commands 类非主窗 scene，main + viewer 都由 controller 自建。
- **D-OW10 cold/warm 判断用自持 controller 状态，禁止扫 `NSApp.windows`**。Why：`NSApp.windows` 混入 About/看图窗/隐藏最小化主窗/系统 panel，`isVisible`/`canBecomeMain` 无法表达"用户正在用图库"，冷启动主窗已建会误判 warm、warm 主窗最小化会误判 cold 把 app 退掉。How：AppDelegate 自持 `MainWindowController` 状态 + `ViewerSession.terminateOnClose`。
- **D-OW11 `ExternalViewerWindowController` 不照搬 About 一次性 rootView，需 `ViewerSession`**。Why：单例 window 复用 + `@StateObject QuickViewerViewModel` 按首批 urls init 一次 → 二次打开显旧图（核心场景）；security scope 也要随会话 start/stop 配平。How：每次 show 替换 rootView / `.id(session.id)` / 提升图源为 observable；ViewerSession 持有 scope token + terminateOnClose，二次 show 先 end 旧 session。
