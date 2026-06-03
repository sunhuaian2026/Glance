# OpenWith 轻量看图窗重构（方向 2）— 设计

> 状态：设计完成（2026-06-03 brainstorming 落地），待 writing-plans 出 task 级 plan。
> 关系：**取代** `specs/OpenWith.md` 里"外部打开复用图库主窗口 + QV overlay"的旧模型；Info.plist 文档类型声明、`application(_:open:)` 入口保留。
> 缘起：旧模型（单 `Window` scene 复用主窗口 + AppDelegate 消费 open 事件）在 warm 场景有两个 macOS 顽疾——(1) app 自杀（已用 shouldTerminate=false 临时挡）(2) 窗口不自动置顶（5 种激活 API 真机全败，见 Roadmap 待修复 + `project_openwith_warm_activation_macos_limitation` memory）。根因是"app 自己消费 open 事件 + 复用单 Window scene 瞬态"在跟系统对着干。本方向改成 Preview/Quick Look 式轻量语义，**自建独立看图窗**绕开顽疾。

## 目标行为模型

| 场景 | 打开时 | 看图窗 ESC 关闭后 |
|------|--------|-------------------|
| **冷启动**（Glance 未运行）→ Finder「打开方式」 | 只显**独立看图窗**（全屏看这张），**不显**图库主界面 | **Glance 整个退出**（Quick Look 式"看完即走"） |
| **warm**（Glance 已开、正在用图库主界面）→ Finder「打开方式」 | 看图窗**独立弹出并置顶**，图库主界面**原样不动** | 关看图窗，**图库主界面还在**，app 不退 |
| 正常点 Dock 打开 Glance（无文件） | 显图库主界面（不变） | — |

术语：**图库主界面** = SwiftUI `Window` scene 那个 sidebar + 缩略图浏览主窗口；**看图窗** = 全屏 QuickViewer。

核心语义：**从 Finder 打开方式看单图 = 一次性轻量看图，不牵出图库主界面**；已在用 Glance 时开图不打扰正在用的主界面。

## 架构

### 新增 `Glance/ExternalOpen/ExternalViewerWindowController.swift`
纯 AppKit 单例，**复刻 `Glance/About/AboutWindowController.swift` 已验证的模式**（自建 `NSWindow` + `NSHostingView`，`makeKeyAndOrderFront` + `NSApp.activate(ignoringOtherApps:)`——自建窗能可靠置顶，不受 SwiftUI 单 Window scene 顽疾影响）。

职责：
- `show(urls: [URL])`：首次 `createWindow`；设置看图窗图源 = urls；`makeKeyAndOrderFront` + activate 置顶。
- 持有**自己的轻量 `AppState` 实例**（`appState.window` = 看图窗本身）→ QuickViewer 的 F 全屏 / traffic light / 焦点都作用在看图窗，不碰图库窗。
- 窗口内容 = `QuickViewerOverlay(...)` + `WindowAccessor(appState: 看图窗 AppState)` 背景。
- 沙盒：`show` 时对每个 url `startAccessingSecurityScopedResource()`，持有到窗口关闭，关闭时 `stopAccessing`。
- `isReleasedWhenClosed = false`（mirror About），复用 window 实例。

### `AppDelegate.application(_:open:)`（`GlanceApp.swift`）
改为：过滤图片 URL 后**直接** `ExternalViewerWindowController.shared.show(urls: images)`（不再写 `ExternalOpenCoordinator.pendingOpen`）。

### 看图窗内容（精简 QuickViewer）
复用 `QuickViewerOverlay`，但传 `onFindSimilar=nil` / `onCommandF=nil` / 无 `onBrowseFolder`（纯看图）。保留缩放/方向键切图/F 全屏/ESC/胶片条。多图 = 一个看图窗 + 胶片条显选中集合。`onDismiss` → 关看图窗（+ 冷启动场景退出 app，见生命周期）。

### 生命周期（cold / warm / 退出）
1. **看图窗是自建 AppKit 窗、不复用图库窗** → 无"复用单 Window 的瞬态 close/reopen" → 崩溃根源消失 → **`applicationShouldTerminateAfterLastWindowClosed` 恢复默认 `true`**（去掉旧 workaround），生命周期回归"关掉最后一个窗就退出"。
2. **冷启动抑制图库窗**：图库 `Window` scene 启动会自动建窗。检测到"本次为打开文件而冷启动" → **关掉自动建的图库窗**，只留看图窗 → 看图窗 ESC 关 → 最后一个窗没了 → app 自然退出。
3. **warm**：`application(open:)` 在已 `finishedLaunching` 时触发 → 不动图库窗，只 show 看图窗 → ESC 关看图窗 → 图库窗还在 → 不退。

**兜底（后备方案，若冷启动检测不可靠）**：看图窗自己定退出——`show()` 时记录"此刻有没有用户在用的图库窗"；ESC 关闭时若没有 → `NSApp.terminate`，有 → 只关窗。不依赖启动时序，更稳。

## 增删清单

**新增**：`ExternalViewerWindowController.swift`。

**删除**（回滚旧模型 Slice 1/2 在 ContentView 的机器）：
- `ContentView`：`externalOpenUrls` / `handleExternalOpen` / `handleBrowseFolder` / `QuickViewerEntry.externalOpen` case / `.onChange(externalOpen.pendingOpen)` / onAppear 外部打开兜底 / 整套激活机器（`scheduleActivation` / `waitForAppActivation` / `externalOpenActivationRequest` / `externalOpenActivationTask` / `.onChange(windowIdentity)` / `.onChange(isWindowKey)`）
- `QuickViewerOverlay`：`onBrowseFolder` 属性 + init 参数 + 底部「浏览所在文件夹」按钮（Slice 2 按钮回滚）
- `Glance/ExternalOpen/ExternalOpenCoordinator.swift`：整文件删除（桥不再需要）
- `DS.ExternalOpen`：激活超时常量不再用，删
- QV overlay 在 ContentView 是否仍需保留 `.externalOpen` 入口：否，QV overlay 只剩 grid/preview/ephemeral 三入口

**保留**：`Info.plist` 文档类型声明 + pbxproj `INFOPLIST_FILE` + exception set（进 Open With 必需）；`AppState.windowIdentity/attachWindow/detachWindow`（看图窗的 WindowAccessor 复用，且图库窗也用）；`AppState.isWindowKey`（QV 焦点）。

**改**：`GlanceApp.swift` `application(open:)` 改调 controller；`applicationShouldTerminateAfterLastWindowClosed` 删掉（恢复默认 true）；加冷启动检测 + 抑制图库窗逻辑。

## 风险

- **⚠️ 冷启动检测 + 抑制图库窗是最 tricky 的部分**：依赖 macOS 启动时序（`application(open:)` 与 `applicationDidFinishLaunching` 先后在不同情况会变）。**开发 Mac mini 无 GUI 会话，置顶/窗口显隐类 GUI 行为 CC 无法自验**，需用户真机迭代。兜底方案（看图窗自定退出）降低此风险。
- **置顶**：自建 NSWindow 理论上能可靠置顶（AboutWindowController 已证），但仍需用户真机确认 warm open 看图窗确实跳前台。
- **多图集合导航**：需真机确认胶片条/方向键在独立看图窗里正常。

## 决策记录

- **D-OW5 外部打开 = 轻量独立看图窗（Preview/Quick Look 式），非复用图库主窗口**。Why：旧模型复用单 Window scene + 消费 open 事件跟系统对着干，导致 warm 崩溃 + 置顶顽疾；自建独立窗顺着系统、置顶可控、语义更符合"快速看一张图"。How：ExternalViewerWindowController（mirror AboutWindowController）。
- **D-OW6 冷启动看图 ESC = app 退出（看完即走）；warm 不退（图库在用）**。Why：用户拍板——从 Finder 打开方式看单图是一次性行为，不该牵出图库主界面。
- **D-OW7 看图窗砍掉找类似/搜索/浏览所在文件夹，纯看图**。Why：轻量语义；这些是图库功能，想用去图库主界面。**回滚 Slice 2「浏览所在文件夹」按钮**（`84a1f5b`）。
- **D-OW8 shouldTerminate 恢复默认 true**。Why：新模型不复用图库窗 → 无瞬态 close → 旧 workaround（=false）不再需要，回归自然窗口计数退出语义。
