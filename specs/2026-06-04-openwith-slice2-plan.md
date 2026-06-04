# OpenWith 方向2 Slice 2 实施计划 — 收回 lifecycle，拿冷启动看完即走

> **For agentic workers:** REQUIRED SUB-SKILL: 用 superpowers:subagent-driven-development 或 executing-plans 逐 task 实施。Steps 用 checkbox（`- [ ]`）跟踪。本项目无 XCTest target，按 CLAUDE.md 跳 TDD，验收等价 = `make build` 0 error/0 warning + `specs/PENDING-USER-ACTIONS.md` 真机清单。
>
> 承接 `specs/2026-06-03-openwith-lightweight-viewer-{design,plan}.md`（Slice 1 已 ship + 真机验过 warm 置顶/显图/focus）。决策源 design D-OW9/10/11 + 本文档新增 D-OW12~15。

**Goal:** 移除 SwiftUI `Window("一眼")` scene，把图库主窗创建权收回 AppDelegate（自建 `MainWindowController`），让 odoc 进来时 SwiftUI 不再瞬态 close 主窗 —— 一并根治 cold 双窗 + warm 关图后主窗丢失，并拿到冷启动"看完即走"。

**Architecture:** AppDelegate 升级为窗口/对象生命周期的唯一所有者：持有原 `GlanceApp @StateObject` 的 4 个 ObservableObject（BookmarkManager/FolderStore/AppState/IndexStoreHolder），按"是否为打开文件而启动"自持状态决定首窗（cold open→只建看图窗 terminateOnClose=true；普通 launch/reopen→`MainWindowController` 建图库主窗）。`MainWindowController` mirror `AboutWindowController` 骨架自建 NSWindow + NSHostingView(ContentView)。SwiftUI `App` body 只留 `Settings` scene 挂 `.commands`（About 菜单）。删除 Slice 1 暂留的 `ExternalOpenCoordinator` 旧桥 + ContentView externalOpen 残留机器 + QV onBrowseFolder + DS.ExternalOpen。

**Tech Stack:** SwiftUI + AppKit hybrid；`@NSApplicationDelegateAdaptor`；`NSWindow`/`NSHostingView`；macOS 14+ deploy target；project default actor isolation = MainActor。

---

## ⚠️ Slice 2 关键设计决策（design 未完全敲定，**codex review 重点评这 4 条**）

### D-OW12 — 对象 ownership 从 `GlanceApp @StateObject` 迁到 `AppDelegate`
**现状**（`GlanceApp.swift:14-26`）：`@StateObject` 持有 4 个对象，`init()` 里 `BookmarkManager()` → `FolderStore(bookmarkManager:)` → `IndexStoreHolder()`，`AppState()` 默认。ContentView 在 `Window` scene 内拿 5 个 `.environmentObject`。
**问题**：移除 `Window` scene 后 ContentView 不再在 SwiftUI scene 渲染、改在 `MainWindowController` 的 `NSHostingView` 里，`@StateObject` 失去承载 scene。
**决策**：4 个对象 ownership 移到 `AppDelegate`（普通 strong properties，`applicationDidFinishLaunching` 前 lazy 构造，AppDelegate 单例生命周期 = app 生命周期，存活保证等价 @StateObject）。`MainWindowController.show()` 与 SwiftUI `Settings` scene 都从 `appDelegate` 拿同一批引用注入。
**风险**：`@NSApplicationDelegateAdaptor` 暴露的 `appDelegate` 在 SwiftUI `Settings` scene body 里访问其 `@Published`-持有对象，SwiftUI 观察链是否正常（AppDelegate 不是 ObservableObject，但它持有的对象是）。**注入给 NSHostingView 的 ContentView 用 `.environmentObject` 是标准的、必正常**；Settings scene 做成无依赖最小化（`EmptySettingsView` 不碰这些对象）规避此疑虑。
**实现细节（codex P2-2/P2-3）**：AppDelegate 类整体标 `@MainActor`（`FolderStore`/`IndexStoreHolder` 是 `@MainActor`，stored property 在 AppDelegate 隔离一致才不触 Swift actor 隔离检查）；`override init()` 只构造 `BookmarkManager`/`FolderStore`（读 UserDefaults/bookmark 数据，**不碰 live NSWindow/NSApp UI**），时机比 `GlanceApp.init()` 略早但等价安全（AppDelegate 在 NSApplication 初始化后才实例化）。`AppState.init()` 现调 `applyAppearance()`（设 `NSApp.appearance`）——AppDelegate.init 时 NSApp 已存在，安全，但加注释提醒勿往这些 init 塞依赖 live window 的逻辑。

### D-OW13 — 菜单栏 host：`App` body 只留 `Settings` scene 挂 `.commands`（**最高风险**）
**现状**：`.commands { CommandGroup(replacing: .appInfo) { AboutMenuButton() } }` 挂在 `Window` scene 上（`GlanceApp.swift:45-52`）；`AboutMenuButton` 只调 `AboutWindowController.shared.show()`（纯 AppKit，不依赖 scene）。
**决策**：`App` body 改为单个 `Settings { EmptySettingsView() }` scene + `.commands` 挂其上。理由：SwiftUI `App` body 必须 ≥1 Scene；`Settings` 是非主窗 scene（冷启动不建窗、不进 Window 菜单），满足 design D-OW9"只留 Settings/.commands 类非主窗 scene"且否决占位 Window scene。About 菜单是 app-level command（`.appInfo`），不依赖 focused window，预期正常。
**风险（codex + 真机必验）**：
- ⚠️ macOS 14 下移除所有 `WindowGroup`/`Window` 后，标准菜单栏（App/Edit/Window/Help）是否仍由 SwiftUI 生成、`.commands` 注入是否生效 —— **不确定，必须真机验「关于一眼」菜单项可点 + ⌘Q 退出可用**。
- `Settings` scene 引入 ⌘, 弹设置窗：Glance 当前无设置内容 → `EmptySettingsView` 放最小占位（一行说明文字），不做新功能（YAGNI）。
- "Window" 菜单不再管理自建窗（自建 NSWindow 不进 SwiftUI Window scene 列表）→ 可接受（Glance 不依赖 Window 菜单的标准项）。
**降级备选（若真机验 .commands 失效）**：AppDelegate 用纯 AppKit `NSMenu` 重建菜单栏（About + ⌘Q），归 **Slice 2b** 独立处理，不在本 plan 范围 —— 本 plan 先赌 Settings scene 方案，codex 若判定大概率失效则提前转 Slice 2b。

### D-OW14 — cold/warm 判断 + 首窗决策（自持状态，禁扫 NSApp.windows）
**机制**（Slice 1 诊断日志实证的时序：cold open 时 `application(open:)` 在 `applicationDidFinishLaunching` **之前**触发，`hasFinishedLaunching=false`）：
- AppDelegate 两个标志：`hasFinishedLaunching: Bool`、`launchedForFileOpen: Bool`。
- `application(_:open:)`：cold（`!hasFinishedLaunching`）→ `launchedForFileOpen = true` + show 看图窗 `terminateOnClose: true`；warm（`hasFinishedLaunching`）→ show 看图窗 `terminateOnClose: false`（不动主窗）。
- `applicationDidFinishLaunching`：`hasFinishedLaunching = true`；`if !launchedForFileOpen { MainWindowController.shared.show(...) }`。
- `applicationShouldHandleReopen`（点 Dock）：`if !MainWindowController.shared.hasWindow { MainWindowController.shared.show(...) }; return true`。
**符合 D-OW10**：cold/warm 完全由 AppDelegate 自持标志判断，不扫 `NSApp.windows`。

### D-OW15 — 退出语义：`applicationShouldTerminateAfterLastWindowClosed` = `false`（关窗驻留，真机后从 true 修正）
> **⚠️ 真机修正（2026-06-04，用户拍板「关窗驻留」）**：原拟回 `true`（关窗即退），真机验后改 **`false`（关窗驻留，像 Photos/Preview/访达）**——图库 app 关图库主窗应驻留 dock、点 Dock reopen、⌘Q 才退，避免重看要冷启动。**cold 看完即走不受影响**（由看图窗 `terminateOnClose=true` 主动 `NSApp.terminate` 控制，与 last-window 语义独立）；warm 关看图窗/主窗都驻留、⌘Q 退。Window scene 已移除，`false` 不再有 Slice1 瞬态自杀风险。下方原"回 true"论证保留作决策演进记录。
**design D-OW8 历史**：Slice 1 因主 `Window` scene 还在、odoc 触发瞬态 close→0 窗自杀，强制 `=false`。
**决策（Slice 2 更新）**：移除 `Window` scene 后**瞬态 close 不再发生**（自建 NSWindow 不响应 odoc），可回 macOS 标准 `=true`。语义自洽：
- cold open：看图窗 `terminateOnClose=true` → 关窗时 `ViewerSession` 已 `NSApp.terminate`（看完即走，主动退，不靠 last-window）。
- warm：图库主窗 + 看图窗并存；关看图窗后主窗仍在（≥1 窗）→ 不触发 last-window-closed；关图库主窗后若无看图窗 → 0 窗 → `=true` 标准退出（合理）。
- 普通启动：仅图库主窗，关它 → 退出 app（标准 macOS 单窗 app 行为）。
**风险**：需真机验 warm 下"关看图窗主窗在不退 / 关主窗看图窗在不退 / 全关才退"。**若回 true 仍有边角自杀**，降级为 AppDelegate 自持窗口计数（`MainWindowController.hasWindow || ExternalViewerWindowController.hasVisibleWindow` 才允许 terminate）—— 作为 Task 4 内的兜底分支预留。
**About/Settings 窗边角（codex P1-3）**：About 窗（`AboutWindowController`，`NSWindow` titled）/ Settings 窗可见时关图库主窗 → 仍有可见 NSWindow → 不 terminate，符合标准 last-window 语义，**声明可接受**（About 开着时不该退 app）。即只有所有窗（主窗 + 看图窗 + About + Settings）全关才 terminate，符合直觉。

### D-OW16 — 图库主窗 delegate 单一归属：MainWindowController 自任，移除 ContentView WindowAccessor（解 codex P1-1/P1-2）
**问题（codex P1-1，plan 初稿漏掉的最大地雷）**：`MainWindowController` 自建窗会设 `win.delegate = self`，但 ContentView 内 `WindowAccessor(appState:)`（`ContentView.swift:466`）的 `makeNSView` 也执行 `window.delegate = context.coordinator` —— 两者争抢同一 `NSWindow.delegate`、互相覆盖。后果：`MainWindowController.windowWillClose` 不触发（`hasWindow` 失效、reopen 断裂），或 `AppState` 的 attach/fullscreen/key 跟踪丢失。
**决策**：图库主窗 delegate **单一归属 MainWindowController**（自任 `NSWindowDelegate`，接管 `attachWindow`/`detachWindow`/`windowDidEnter/ExitFullScreen`/`windowDidBecome/ResignKey`/`windowWillClose` 全部驱动 `appState`，见 Task 1 代码）；**移除 ContentView 的 `WindowAccessor(appState:)`**（Task 3，配合 Window scene 移除一起改）。这正是 Slice 1 `ExternalViewerWindowController` 已真机验证的模式（看图窗自任 delegate、不接 WindowAccessor）。
**牵连**：`WindowAccessor.swift`（`Glance/FullScreen/WindowAccessor.swift`）移除 ContentView 这唯一使用者后全项目无引用 → 可删（Task 3 删前报告）。`AppState.attachWindow/detachWindow/isWindowKey/isFullScreen` API 不变，只是改由 controller 调而非 WindowAccessor。

---

## File Structure

| 文件 | 动作 | 责任 |
|------|------|------|
| `Glance/MainWindow/MainWindowController.swift` | **新建** | `@MainActor` 单例，自建图库主窗 NSWindow + NSHostingView(ContentView+4注入)，`show(...)` 建/复用，`hasWindow` 供 AppDelegate 查 |
| `Glance/GlanceApp.swift` | 改 | 删 `@StateObject` 4 对象；body 改 `Settings` scene 挂 `.commands`；AppDelegate 升级为对象 owner + lifecycle 决策 |
| `Glance/ContentView.swift` | 改 | 删 externalOpen 残留机器（D-OW9 增删清单）；QV `images:` 源去掉 `externalOpenUrls ??`；删 `.environmentObject(ExternalOpenCoordinator)` 依赖 |
| `Glance/ExternalOpen/ExternalOpenCoordinator.swift` | **删除** | 旧桥整文件删（删前 git 已报告，本 plan 执行时再确认一次） |
| `Glance/DesignSystem.swift` | 改 | 删 `DS.ExternalOpen` enum（仅 `waitForAppActivation` 用，随之删） |
| `Glance/QuickViewer/QuickViewerOverlay.swift` | 改 | 删 `onBrowseFolder` 属性/init 参/底部按钮（D-OW7 纯看图） |

> **删文件提示**：`ExternalOpenCoordinator.swift` 删除 = 物理删一个 .swift。CLAUDE.md「禁止删除文件需先报告」—— design 增删清单已在设计阶段同意，Task 6 执行删除前在对话里再报告一次等用户确认。PBXFileSystemSynchronizedRootGroup 删文件自动移出编译，不动 pbxproj。

---

## Tasks

> **总原则**：Slice 2 是一个原子架构切换，内部 task 有依赖顺序。**实施顺序按下方 Task 1→7**。**build 节奏（codex P2-3，不是"每 task 都绿"）**：Task 1 可单独 build 过（MainWindowController 未被调用）；**Task 2+3 必须同一次编辑、同一次 build**（删 `@StateObject` 与改 body 强耦合，分开必红——Task 2 的"允许红"指它不可单独 build，须与 Task 3 合并）；Task 4 后 app 才能真正启动、跑菜单门控 + 真机验收；Task 5/6 各自 build 过。**不要在已知红的中间态（Task 2 单独）停下**。这不违反 vertical slice —— Slice 2 整体满足"端到端可跑（启动/外部打开/退出全工作）+ 用户可感知（cold 看完即走、warm 主窗不丢）+ 独立可 ship"，内部 task 只是实施步骤。

### Task 1: 新建 `MainWindowController`（自建图库主窗）

**Files:**
- Create: `Glance/MainWindow/MainWindowController.swift`

- [ ] **Step 1: 写 MainWindowController**

mirror `AboutWindowController` 骨架，但承载 ContentView + 4 注入 + 可 resize/全屏。注入对象由调用方（AppDelegate）传入，避免 controller 自己持有 ownership（ownership 在 AppDelegate，D-OW12）。

```swift
//
//  MainWindowController.swift
//  Glance
//
//  图库主窗（ContentView）的自建 NSWindow 管理。方向2 Slice2：把主窗创建权从 SwiftUI
//  Window scene 收回 AppDelegate（D-OW9），odoc 进来时 SwiftUI 不再瞬态 close 主窗，
//  根治 cold 双窗 + warm 关图主窗丢失。mirror AboutWindowController 骨架。
//

import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject {
    static let shared = MainWindowController()

    private var window: NSWindow?
    /// delegate 回调驱动图库 appState（attach/fullscreen/key）。ownership 在 AppDelegate，
    /// 此处弱引用避免循环（AppDelegate 持 appState 整个 app 生命周期，回调时必非 nil）。
    private weak var appState: AppState?

    /// AppDelegate 查"图库主窗是否已建且在场"决定首窗/reopen（D-OW14，禁扫 NSApp.windows）。
    var hasWindow: Bool { window != nil }

    private override init() { super.init() }

    /// 建/复用图库主窗。注入集由 AppDelegate 传入（ownership 在 AppDelegate，D-OW12）。
    func show(
        bookmarkManager: BookmarkManager,
        folderStore: FolderStore,
        appState: AppState,
        indexStoreHolder: IndexStoreHolder
    ) {
        self.appState = appState
        if window == nil {
            createWindow(
                bookmarkManager: bookmarkManager,
                folderStore: folderStore,
                appState: appState,
                indexStoreHolder: indexStoreHolder
            )
            folderStore.loadSavedFolders()  // 原 ContentView .onAppear 的加载迁来（scene 没了，显式调）
        }
        guard let win = window else { return }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appState.attachWindow(win)  // 兜底再 attach（幂等：同 win 第二次只刷新 isWindowKey，不重换 windowIdentity，codex P2-1）
    }

    private func createWindow(
        bookmarkManager: BookmarkManager,
        folderStore: FolderStore,
        appState: AppState,
        indexStoreHolder: IndexStoreHolder
    ) {
        // ContentView 在 Task 3 已移除内部 WindowAccessor（delegate 单一归属 D-OW16）；
        // 本 controller 自任 NSWindowDelegate 接管 attach/fullscreen/key/close 驱动 appState。
        let root = ContentView()
            .environmentObject(bookmarkManager)
            .environmentObject(folderStore)
            .environmentObject(appState)
            .environmentObject(indexStoreHolder)
        let host = NSHostingView(rootView: AnyView(root))
        host.autoresizingMask = [.width, .height]
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: DS.ExternalViewer.defaultWindowWidth,
                                height: DS.ExternalViewer.defaultWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.contentView = host
        win.title = "一眼"
        win.isReleasedWhenClosed = false  // 防 windowWillClose 期间访问已释放 window；windowWillClose 置 window=nil → 下次 show 重建新实例（非复用同窗，codex P2-2）
        win.collectionBehavior.insert(.fullScreenPrimary)
        win.center()
        win.delegate = self            // 单一 delegate 归属（D-OW16，P1-1）
        self.window = win
        appState.attachWindow(win)     // 主动 attach 播种 window 指针（替代原 WindowAccessor 的 attach）
    }
}

// MARK: - NSWindowDelegate（mirror Slice 1 ExternalViewerWindowController：接管 attach/fullscreen/key/close）
extension MainWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        appState?.attachWindow(win)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win === appState?.window else { return }
        appState?.isWindowKey = false
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        appState?.isFullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        appState?.isFullScreen = false
    }

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        // 主窗关闭：reset isFullScreen + detach + 清 window 引用（hasWindow 翻 false，reopen 重建）。
        // 退出由 applicationShouldTerminateAfterLastWindowClosed 决定（D-OW15）。
        appState?.isFullScreen = false
        appState?.detachWindow(win)
        window = nil
    }
}
```

> **D-OW16 解 P1-1/P1-2**：MainWindowController 自任 delegate 接管全部 AppState 挂接，ContentView 移除 WindowAccessor（Task 3）→ delegate 单一归属，不再与 WindowAccessor 争抢。这正是 Slice 1 ExternalViewerWindowController 已验证的模式（自任 delegate 复刻 fullscreen/key 跟踪）。`folderStore.loadSavedFolders()` 用 `if window == nil` 守避免 reopen 重复加载。

- [ ] **Step 2: `make build` 验证编译**

Run: `make build`
Expected: BUILD SUCCEEDED, 0 error, 0 warning（此时 MainWindowController 未被调用，仅确认类型/注入签名编译通过）。

- [ ] **Step 3: Commit**

```bash
git add Glance/MainWindow/MainWindowController.swift
git commit -m "feat(OpenWith): 新增 MainWindowController 自建图库主窗（Slice2 Task1）"
```

---

### Task 2: AppDelegate 升级为对象 owner + 构造迁移（D-OW12）

**Files:**
- Modify: `Glance/GlanceApp.swift`（AppDelegate 类，行 64-92）

- [ ] **Step 1: AppDelegate 持有 4 对象 + 构造**

把 `GlanceApp.init()`（行 21-26）的对象构造迁到 AppDelegate。AppDelegate 用 `lazy` 或在 `applicationDidFinishLaunching` 前构造 —— 选 stored property + `applicationDidFinishLaunching` 早期构造（确保单次、顺序正确）。

```swift
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // 对象 ownership（原 GlanceApp @StateObject 迁来，D-OW12）。
    let bookmarkManager: BookmarkManager
    let folderStore: FolderStore
    let appState = AppState()
    let indexStoreHolder = IndexStoreHolder()

    // D-OW14 lifecycle 状态机
    private var hasFinishedLaunching = false
    private var launchedForFileOpen = false

    // security-scope 兜底（原有）
    var accessedURLs: [URL] = []

    override init() {
        let bm = BookmarkManager()
        self.bookmarkManager = bm
        self.folderStore = FolderStore(bookmarkManager: bm)
        super.init()
    }

    // application(open:) / didFinishLaunching / shouldHandleReopen / shouldTerminate 在 Task 4 实现
}
```

> ⚠️ **codex 评估点**：AppDelegate `override init()` 构造 ObservableObject 是否过早（早于 NSApplication 完全 ready）？BookmarkManager/FolderStore 构造只读 UserDefaults/bookmark 数据、不碰 UI，应安全（与原 GlanceApp.init 时机等价）。

- [ ] **Step 2: `make build`**

Run: `make build`
Expected: 编译可能因 GlanceApp body 仍引用 `@StateObject`（下一步删）而报错 —— **本 step 允许红**，Task 2/3 一起改完 GlanceApp 才绿。或先合并 Task 2+3 实施再 build。

> **实施提示**：Task 2 和 Task 3 改同一文件 `GlanceApp.swift`、强耦合（删 @StateObject 必须同时改 body），**建议合并为一次编辑后再 build**。分列只为讲清两件事（对象迁移 vs scene 改造）。

---

### Task 3: GlanceApp 移除 Window scene + Settings scene 挂 commands + 移除 WindowAccessor（D-OW13/D-OW16）

**Files:**
- Modify: `Glance/GlanceApp.swift`（`struct GlanceApp` body 行 13-54）
- Create: `Glance/MainWindow/EmptySettingsView.swift`（Settings scene 占位内容）
- Modify: `Glance/ContentView.swift`（移除 `WindowAccessor(appState:)` 行 466，D-OW16）
- Delete: `Glance/FullScreen/WindowAccessor.swift`（移除唯一使用者后全项目无引用）

- [ ] **Step 1: 写 EmptySettingsView 占位**

```swift
//
//  EmptySettingsView.swift
//  Glance
//
//  Settings scene 占位。方向2 Slice2：App body 移除 Window scene 后需保留 ≥1 个非主窗
//  scene 挂 .commands（About 菜单），选 Settings。Glance 暂无设置项故最小占位（YAGNI）。
//

import SwiftUI

struct EmptySettingsView: View {
    var body: some View {
        Text("Glance · 一眼")
            .font(.headline)
            .frame(width: 360, height: 120)
    }
}
```

- [ ] **Step 2: 改 GlanceApp body**

```swift
@main
struct GlanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 方向2 Slice2：移除 Window("一眼") 主窗 scene，图库主窗改由 AppDelegate +
        // MainWindowController 自建（D-OW9）。App body 只留 Settings 非主窗 scene 挂
        // .commands（About 菜单）。冷启动首窗 / reopen 全走 AppDelegate（D-OW14）。
        Settings {
            EmptySettingsView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuButton()
            }
        }
    }
}
```

> 删除原 `@StateObject` 4 行（行 14-17）+ `init()`（行 21-26）+ 整个 `Window(...)` scene（行 33-44）。`AboutMenuButton`（行 56-62）保留不动。

- [ ] **Step 3: 移除 ContentView 的 WindowAccessor + 删 WindowAccessor.swift（D-OW16）**

ContentView 行 466 `WindowAccessor(appState: appState)` 整行删（它挂在某个 `.background(...)` 或视图层里，删时确认不破坏周边布局——实施者打开实际确认挂载形式）。删后图库主窗的 NSWindow 挂接由 `MainWindowController` 自任 delegate 接管（Task 1 已实现）。

确认全项目无其它 `WindowAccessor` 引用（Explore 已确认仅 ContentView:466）：
```bash
rg "WindowAccessor" Glance/   # 期望：仅 WindowAccessor.swift 自身定义，无其它引用
```
确认后删文件（**删前在对话报告，CLAUDE.md 规则**）：
```bash
git rm Glance/FullScreen/WindowAccessor.swift
```

- [ ] **Step 4: `make build`**

Run: `make build`
Expected: BUILD SUCCEEDED, 0 error/0 warning。此时 app 能编译，但启动后**还不会建任何主窗**（AppDelegate lifecycle 在 Task 4）—— 仅确认 scene 改造 + WindowAccessor 移除编译通过。

> ⚠️ **D-OW13 菜单硬门控（codex P2-1/P2-5，真机验，不过则停）**：**执行时机 = Task 4 lifecycle 完成、app 能真正启动建窗之后**（Task 3 编译后 app 还不建任何窗、无法验菜单，故门控放在 Task 4 build 之后执行；此处记录是因为它验的是本 task 的 scene 改造）。届时**真机第一件事验菜单栏**——「一眼」菜单有「关于一眼」可点弹 About、⌘Q 能退、Edit/Window/Help 标准菜单在、⌘, 弹 Settings 占位窗。**任一不成立 = Settings-only scene 方案不保菜单 → 立即停，转纯 AppKit NSMenu 方案（Slice 2b），不继续删 Task 5/6**。这是整个 Slice 2 的前提门控。

- [ ] **Step 5: Commit**

```bash
git add Glance/GlanceApp.swift Glance/MainWindow/EmptySettingsView.swift Glance/ContentView.swift
git rm Glance/FullScreen/WindowAccessor.swift
git commit -m "refactor(OpenWith): App 移除 Window scene 改 Settings + AppDelegate 持对象 + 移除 WindowAccessor（Slice2 Task2-3）"
```

---

### Task 4: AppDelegate lifecycle —— 首窗决策 + cold/warm + reopen + 退出（D-OW14/15）

**Files:**
- Modify: `Glance/GlanceApp.swift`（AppDelegate 类）

- [ ] **Step 1: 实现 lifecycle 方法**

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        hasFinishedLaunching = true
        // 不是为打开文件而启动 → 建图库主窗（普通 launch）。是 → 只看图窗（cold 看完即走）。
        if !launchedForFileOpen {
            showMainWindow()
        }
    }

    // 点 Dock 图标 / reopen：无图库主窗则重建（D-OW14）。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !MainWindowController.shared.hasWindow {
            showMainWindow()
        }
        return true
    }

    // 退出语义回标准 true（D-OW15）：Window scene 已移除，瞬态 close 不再发生。
    // cold 看图窗自己 terminateOnClose=true 主动退；warm/普通最后一窗关 → 标准退出。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // Finder「打开方式」/ Dock 拖放（D-OW14 cold/warm 分流）。
    func application(_ application: NSApplication, open urls: [URL]) {
        let images = urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        }
        guard !images.isEmpty else { return }
        // cold（启动前收到 open）：标记 + terminateOnClose=true（看完即走）。
        // warm（已 finishedLaunching）：terminateOnClose=false（只关看图窗，主窗不动）。
        if !hasFinishedLaunching {
            launchedForFileOpen = true
        }
        ExternalViewerWindowController.shared.show(
            urls: images,
            terminateOnClose: !hasFinishedLaunching
        )
    }

    private func showMainWindow() {
        MainWindowController.shared.show(
            bookmarkManager: bookmarkManager,
            folderStore: folderStore,
            appState: appState,
            indexStoreHolder: indexStoreHolder
        )
    }
```

> ⚠️ **codex 评估点**：(1) cold open 时序——`application(open:)` 确实先于 `applicationDidFinishLaunching`？Slice 1 诊断日志（A2/B2）实证 cold 时 `application(open:) hasFinishedLaunching=false` 在前、`applicationDidFinishLaunching` 在后，**已验证成立**。(2) `terminateOnClose: !hasFinishedLaunching` —— cold=true/warm=false，等价 D-OW14。(3) D-OW15 回 true 的边角：warm 时若用户先关主窗（看图窗还开着）→ 主窗 `windowWillClose` 置 `window=nil` 但看图窗在（≥1 窗）→ 不触发 last-window → 不退，正确；最后关看图窗 → `ViewerSession.end` + 0 窗 → terminate，正确。**若真机发现 warm 关主窗瞬间误退，降级自持计数兜底**（见 D-OW15）。(4) **多文件冷启动（codex P2-4）**：`application(open:)` 收 URL 数组，多文件一次只调一次、`show(urls:)` 全传 viewer，正确；近乎同时的**多次** open 调用（极少见）后一次覆盖前一次 session（旧 session 进 `retiredSessions` 关窗统一 end，Slice 1 已处理，不泄漏 scope，可接受）。(5) **不支持的 URL 冷启动（codex P2-5）**：Finder 发非图片 URL → `images.isEmpty` → `application(open:)` 早 return、`launchedForFileOpen` 保持 false → `applicationDidFinishLaunching` 正常建图库主窗，行为合理（已列入 Task 7 验收矩阵）。

- [ ] **Step 2: `make build`**

Run: `make build`
Expected: BUILD SUCCEEDED, 0 error/0 warning（`UniformTypeIdentifiers` import 已在文件顶部，原 application(open:) 就用）。

- [ ] **Step 3: Commit**

```bash
git add Glance/GlanceApp.swift
git commit -m "feat(OpenWith): AppDelegate 接管首窗决策+cold/warm+退出语义（Slice2 Task4）"
```

---

### Task 5: 删 ContentView externalOpen 残留机器 + 简化 QV images 源

**Files:**
- Modify: `Glance/ContentView.swift`

- [ ] **Step 1: 删除符号（精确行号 by Explore）**

删除以下（删后逐项确认不破坏 grid/preview/ephemeral 三入口焦点 + selectedImageIndex 行为，codex P2）：

| 删除 | 行号 |
|------|------|
| `@State externalOpenUrls` | 104 |
| `@ObservedObject externalOpen = ExternalOpenCoordinator.shared` | 106 |
| `@State externalOpenActivationRequest` | 108 |
| `@State externalOpenActivationTask` | 110 |
| `handleExternalOpen()` 函数 | 142-152 |
| `scheduleActivation()` 函数 | 160-180 |
| `waitForAppActivation()` 函数 | 184-201 |
| `finalizeActivation()` 函数 | 203-207 |
| `handleBrowseFolder()` 函数 | 213-233 |
| `QuickViewerEntry` 的 `.externalOpen` case | 29 |
| `.onChange(of: externalOpen.pendingOpen)` | 347-349 |
| `.onChange(of: appState.windowIdentity)` | 352-355 |
| `.onChange(of: appState.isWindowKey)` | 356-359 |
| `.onChange(of: quickViewerIndex)` 内 `.externalOpen` 分支 | 379-384 |
| `.onAppear` 内 pendingOpen 兜底行 | 436 |

- [ ] **Step 2: QV `images:` 源去掉 externalOpenUrls 三元（行 318）**

改：
```swift
// 原: images: externalOpenUrls ?? (smartFolderStore.selected != nil ? v2Urls : folderStore.images),
images: smartFolderStore.selected != nil ? v2Urls : folderStore.images,
```

`onBrowseFolder` 参数（行 340）整行删除（QV 那侧的 onBrowseFolder 在 Task 6 删）。

> ⚠️ **codex 评估点**：`QuickViewerEntry` 删 `.externalOpen` case 后，`quickViewerEntry` 还剩哪些 case、`.onChange(of: quickViewerIndex)` 的 switch 是否仍 exhaustive、grid/preview/ephemeral 三入口焦点恢复路径是否完整保留（externalOpen 曾参与 selected index 清理 + focusTarget 恢复，删它后这些清理对其它 entry 仍正确）。**实施者必须打开 ContentView 实际读 `.onChange(of: quickViewerIndex)` 全部分支 + QuickViewerEntry 全部 case，确认删除后逻辑完整** —— 不可只按行号删。`.onAppear`（行 432-437）删 pendingOpen 那行后保留 `folderStore.loadSavedFolders()` 等其它逻辑（注意：Task 1 已把 loadSavedFolders 迁到 MainWindowController；此处若重复需去重 —— 实施者确认 ContentView.onAppear 还剩什么）。

- [ ] **Step 3: symbol 搜索强制验全清（codex P2-7，替代纯行号删除）**

行号删除风险高（ContentView 长、逻辑交织）。删完跑 symbol 搜索确认无残留：
```bash
rg "externalOpenUrls|externalOpenActivation|ExternalOpenCoordinator|handleExternalOpen|scheduleActivation|waitForAppActivation|finalizeActivation|handleBrowseFolder|QuickViewerEntry\.externalOpen|pendingOpen" Glance/ContentView.swift
```
期望：**无输出**（全清）。有残留 → 回去删干净。**另：实施者必须打开 ContentView 实际读 `.onChange(of: quickViewerIndex)` 的完整 switch + `QuickViewerEntry` 全部 case，确认删 `.externalOpen` 分支/case 后 switch 仍 exhaustive、grid/preview/ephemeral 三入口的 selectedImageIndex 清理 + focusTarget 恢复对其它 entry 仍正确**——不可只按行号机械删。

- [ ] **Step 4: `make build`**

Run: `make build`
Expected: BUILD SUCCEEDED, 0 error/0 warning。编译器兜底抓任何漏删引用。

- [ ] **Step 5: Commit**

```bash
git add Glance/ContentView.swift
git commit -m "refactor(OpenWith): 删 ContentView externalOpen 残留机器（Slice2 Task5）"
```

---

### Task 6: 删 ExternalOpenCoordinator + DS.ExternalOpen + QV onBrowseFolder

**Files:**
- Delete: `Glance/ExternalOpen/ExternalOpenCoordinator.swift`
- Modify: `Glance/DesignSystem.swift`（删 `DS.ExternalOpen` enum，行 178-184）
- Modify: `Glance/QuickViewer/QuickViewerOverlay.swift`（删 onBrowseFolder：属性 27 / init 参 41 / init 赋值 49 / 渲染块 314-320）

- [ ] **Step 1: 报告并删除 `ExternalOpenCoordinator.swift`**

CLAUDE.md「删文件先报告」—— 执行前在对话确认。删除：
```bash
git rm Glance/ExternalOpen/ExternalOpenCoordinator.swift
```
（此时全仓应已无引用：GlanceApp 的 `.environmentObject(ExternalOpenCoordinator.shared)` 在 Task 3 删 Window scene 时随之消失；ContentView 的 `@ObservedObject` 在 Task 5 删。）

- [ ] **Step 2: 删 `DS.ExternalOpen`**（DesignSystem.swift:178-184）

整个 `enum ExternalOpen { ... }` 删除（唯一使用者 `waitForAppActivation` 已在 Task 5 删）。

- [ ] **Step 3: 删 QV `onBrowseFolder`**

- 属性（行 27）`let onBrowseFolder: ((URL) -> Void)?` 删
- init 参数（行 41）`onBrowseFolder: ((URL) -> Void)? = nil` 删
- init 赋值（行 49）`self.onBrowseFolder = onBrowseFolder` 删
- 底部按钮渲染块（行 314-320 `if let onBrowseFolder { ... }`）删

> 注意：Task 5 已删 ContentView 那侧传 `onBrowseFolder:` 实参（行 340），故 QV init 去掉该参数后所有 caller 一致（ContentView QV 调用 + ExternalViewerWindowController.makeRootView 都不再传）。**确认 `ExternalViewerWindowController.makeRootView` 当前没传 onBrowseFolder**（Slice 1 已是 `onBrowseFolder: nil` —— Explore 确认 ExternalViewer 那侧本就传 nil；删参数后该行也要去掉）。

- [ ] **Step 4: symbol 搜索强制验全清（codex P2-7）+ `make build`**

```bash
rg "ExternalOpenCoordinator|DS\.ExternalOpen|ExternalOpen\b|onBrowseFolder" Glance/
```
期望：无残留（`ExternalOpenCoordinator.swift` 已删、`DS.ExternalOpen` 已删、QV `onBrowseFolder` 已删、ContentView 实参已在 Task 5 删）。然后：

Run: `make build`
Expected: BUILD SUCCEEDED, 0 error/0 warning。编译器兜底抓任何漏删引用。

- [ ] **Step 5: Commit**

```bash
git add Glance/DesignSystem.swift Glance/QuickViewer/QuickViewerOverlay.swift
git commit -m "refactor(OpenWith): 删 ExternalOpenCoordinator/DS.ExternalOpen/QV onBrowseFolder（Slice2 Task6）"
```

---

### Task 7: 文档同步 + 真机验收清单 + /go 收尾

- [ ] **Step 1: 文档同步**（CLAUDE.md 强制规则）
  - `CLAUDE.md` 文件结构：加 `MainWindow/MainWindowController.swift` + `EmptySettingsView.swift`；删 `ExternalOpenCoordinator.swift` 条目；GlanceApp 描述改"Settings scene + AppDelegate 自建主窗"；标注 ExternalOpenCoordinator 已删。
  - `specs/Roadmap.md`：待修复段"cold 双窗 + warm 关图主窗丢失"标 Slice2 已解决；关键架构决策加 D-OW12~15；已完成表加 Slice2 行。
  - `specs/2026-06-03-openwith-lightweight-viewer-design.md`：Slice 2 段标"已实施"，回写 D-OW12~15 与 design 原 outline 的差异（菜单 Settings scene / 退出回 true）。
  - 本 plan 末尾加"Slice 2 完成详细"表。

- [ ] **Step 2: 追加 PENDING 真机清单**（`specs/PENDING-USER-ACTIONS.md`，CC 验不了 GUI/lifecycle）

```markdown
### OpenWith 方向2 Slice2 — lifecycle 接管（真机验）

- [ ] **菜单栏存活（D-OW13 最高风险）**：app 启动后菜单栏「一眼」菜单有「关于一眼」可点弹 About；⌘Q 能退出；⌘, 弹 Settings 占位窗
- [ ] **冷启动看完即走**：Glance 没开 → Finder 打开方式开图 → **只弹看图窗、无图库主窗**；ESC/⌘W/X 关窗 → **整个 app 退出**
- [ ] **普通启动建主窗**：双击 Dock 图标/app → 弹图库主窗（ContentView 正常，sidebar+grid 都在）
- [ ] **warm 主窗不丢（核心修复）**：先开 Glance 用图库 → Finder 打开方式开图 → 看图窗弹出、图库主窗原样在 → 关看图窗 → **图库主窗还在、app 不退**（不再需点 Dock）
- [ ] **warm 置顶回归**：warm 开看图窗仍置顶到前台（Slice1 能力不退化）
- [ ] **reopen 重建**：关掉图库主窗（app 不退，若还有看图窗）→ 点 Dock 图标 → 图库主窗重新出现
- [ ] **退出语义（D-OW15）**：仅图库主窗时关它 → app 退出；warm 关主窗留看图窗 → 不退；最后关看图窗 → 退
- [ ] **About/Settings 开着时关主窗（codex P2-6）**：打开「关于一眼」或 ⌘, Settings 后关图库主窗 → app **不退**（仍有可见窗，标准 last-window 语义）；全关才退
- [ ] **⌘Q 直退（codex P2-8）**：看图窗/主窗开着时直接 ⌘Q → app 退出、无残留进程（security-scope 随进程退出释放，ViewerSession 未先 end 不是问题）
- [ ] **WindowAccessor/全屏回归**：图库主窗 F 进全屏正常、traffic light 行为正常、QV 焦点正常（自建窗下 WindowAccessor attach 未坏）
- [ ] **folderStore 加载**：启动后已保存文件夹正常加载（loadSavedFolders 迁到 MainWindowController 后未丢/未重复）
- [ ] **不支持 URL 冷启动（codex P2-5）**：app 没开 → Finder 用 Glance 打开非图片文件（如 .txt 改名 / 拖非图到 Dock）→ 应正常建图库主窗（不弹看图窗、不崩、不僵尸态）
```

- [ ] **Step 3: `/go` 五步收尾**（verify 三段 + 文档同步 + PENDING + commit/push + 汇报）。pre-push codex review 把关。

---

## Self-Review

**1. Spec 覆盖**（对照 design Slice 2 增删清单 line 83-101）：
- ✅ 移除 `Window("一眼")` scene → Task 3
- ✅ 新增 `MainWindowController` 承载 ContentView → Task 1
- ✅ AppDelegate 决定首窗（cold viewer-only / 普通 main）→ Task 4
- ✅ viewer 带 terminateOnClose（cold=true/warm=false）→ Task 4（`!hasFinishedLaunching`）
- ✅ 删 ContentView externalOpen 机器 → Task 5
- ✅ 删 QV onBrowseFolder 按钮 → Task 6
- ✅ 删 `ExternalOpenCoordinator.swift` → Task 6
- ✅ 删 `DS.ExternalOpen` → Task 6
- ✅ `applicationShouldTerminateAfterLastWindowClosed` 改退出语义 → Task 4（D-OW15 回 true + 兜底）
- ✅ **delegate 单一归属（codex P1-1 新增）**→ MainWindowController 自任 NSWindowDelegate 接管 AppState 挂接 + 移除 ContentView WindowAccessor → Task 1+3（D-OW16）

**2. Placeholder 扫描**：无 TBD/TODO；每个 code step 给真实代码；高风险点标注的是"codex 评估 + 真机验"而非"实现细节待填"。唯一"实施者需打开文件确认"的是 Task 5 的 `.onChange(of: quickViewerIndex)` switch exhaustive 性 —— 这是**删除操作的安全确认**（不是脑补占位），因 Explore 未逐行 dump 该 switch 全部分支。

**3. 类型一致性**：`MainWindowController.show(bookmarkManager:folderStore:appState:indexStoreHolder:)` 签名在 Task 1 定义、Task 4 `showMainWindow()` 调用一致；`hasWindow` Task 1 定义、Task 4 reopen 用一致；`ExternalViewerWindowController.show(urls:terminateOnClose:)` 沿用 Slice 1 既有签名（Explore 确认）。

**4. codex review 折入（2026-06-04 第一轮）**：P1-1 delegate 双持地雷 → D-OW16（MainWindowController 自任 delegate + 移除 WindowAccessor，Task 1+3）；P1-2 AppState 挂接 → 同 D-OW16；P1-3 About/Settings 边角 → D-OW15 声明可接受；P2-1 菜单升级真机硬门控（Task 3 Step 4 后停-or-go）；P2-2/P2-3 AppDelegate @MainActor + init 注释（D-OW12）；P2-4/P2-5 多次 open/不支持 URL（Task 4 + 验收矩阵）；P2-6 delegate 合并进 Task 1/3；P2-7 rg symbol 搜索删除（Task 5/6）。

**5. 剩余最大不确定**：D-OW13 菜单 host —— codex verdict 是「GO 但需真机验证」，故 Task 3 Step 4 后菜单硬门控为停-or-go 关卡，不过则转纯 AppKit NSMenu（Slice 2b）。这是 CC 在 Mac mini 验不了、必须真机的点。
