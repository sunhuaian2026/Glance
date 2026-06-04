# OpenWith 轻量看图窗重构（方向 2）— 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: 用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐 task 实施。Steps 用 `- [ ]` checkbox 跟踪。
> 设计源：`specs/2026-06-03-openwith-lightweight-viewer-design.md`（D-OW5~D-OW11）。本项目**无 XCTest target → 跳 TDD**（CLAUDE.md 例外）；每 task 验收 = `make build` BUILD SUCCEEDED 0 error/0 warning + 收尾走 `/go` 三段 verify + PENDING 真机清单。
> **GUI 行为 CC 在 Mac mini 验不了**（置顶/前台/key window/全屏），全部进 PENDING 真机清单由用户验。
> **本版已折入二轮 codex plan-review 的 2 个 P1 + 5 个 P2**（见文末"codex review 折入记录"）。

**Goal:** 外部打开（Finder「打开方式」/ Dock 拖放）改成自建独立看图窗（Preview/Quick Look 式），先在 **warm 场景**跑通并验证"自建 NSWindow 置顶 + QuickViewer 搬进独立窗"这个方向 2 的核心赌注。

**Architecture:** `AppDelegate.application(_:open:)` 过滤图片 URL 后直接 `ExternalViewerWindowController.shared.show(urls:terminateOnClose:)`。控制器是 `@MainActor` 纯 AppKit 单例，自建 `NSWindow + NSHostingController(QuickViewerOverlay.environmentObject(viewerAppState).id(session.id))`，**自己当 `NSWindowDelegate`**（不接 `WindowAccessor`，避免 delegate 冲突），持有 `ViewerSession`（security-scope token + `terminateOnClose`）。窗口关闭（ESC/⌘W/红灯/`windowWillClose`）统一走一个 close path：reset `isFullScreen/isWindowKey` → end session（stop scope）→ `terminateOnClose` 决定 `NSApp.terminate` 还是只关窗。

**Tech Stack:** AppKit（`NSWindow` / `NSHostingController` / `NSWindowDelegate` / `NSApp.activate`）+ SwiftUI（复用 `QuickViewerOverlay`）+ 沙盒 Security Scoped Resource + UniformTypeIdentifiers。

**起点：** working tree 干净，旧 OpenWith 模型（`ExternalOpenCoordinator.pendingOpen` → `ContentView` 消费）已 ship 在 `v2/dev`。

**Slice 1 硬边界（codex，不可越界）：**
- **保留**主 SwiftUI `Window("一眼")` scene；**保留** `applicationShouldTerminateAfterLastWindowClosed = false`。
- **暂不删** `ContentView` 的 externalOpen 机器 / `ExternalOpenCoordinator.swift` / QV overlay 的 `onBrowseFolder` 按钮 / `DS.ExternalOpen`——改 `application(_:open:)` 不再写 `pendingOpen` 后旧消费路径自然休眠，跑通真机验过后在 **Slice 2** 删。
- **Slice 1 `terminateOnClose` 恒传 `false`**（warm-only 验证）。冷启动此刻仍会被主 scene 拉起图库窗 + 看图窗叠加，ESC 只关看图窗、app 不退——**这是预期的过渡态，不是 bug，Slice 1 不解决冷启动**，Slice 2 收 lifecycle 才做"看完即走"。
- **看图窗不显 traffic light / 不测红灯关闭**（codex P2#6，用户拍板"删红灯"）：QV `onAppear` 已 `hideTrafficLights()`，看图窗是 Preview 式 chrome-less 全黑，关闭只走 QV 内置控件 + ESC + ⌘W。

---

## 文件结构

| 文件 | 职责 | 动作 |
|------|------|------|
| `Glance/QuickViewer/QuickViewerViewModel.swift` | 加 `deinit` 取消在途 `imageLoadTask` + prefetch（修复 teardown 漏取消，二次打开换图源前置依赖） | 改（Slice 1, Task 1） |
| `Glance/ExternalOpen/ViewerSession.swift` | 一次看图会话：`@MainActor`，security-scope token 持有 + `terminateOnClose` flag + start/end 配平 | 新建（Slice 1, Task 2） |
| `Glance/ExternalOpen/ExternalViewerWindowController.swift` | `@MainActor` 纯 AppKit 单例：自建 NSWindow + NSHostingController + 自任 NSWindowDelegate + 统一 close path + 二次打开换图源 + deferred 置顶 reassert | 新建（Slice 1, Task 3） |
| `Glance/GlanceApp.swift` | `application(_:open:)` 改调控制器（不再写 `pendingOpen`） | 改（Slice 1, Task 4） |
| `Glance/FullScreen/AppState.swift` | 看图窗复用 `AppState` 类（新建实例，非改文件） | 复用，不改 |
| `Glance/QuickViewer/QuickViewerOverlay.swift` | 复用，不改（已自带 colorScheme/focus/hideTrafficLights） | 复用，不改 |

> 注：`AppState.init()` 会写全局 `NSApp.appearance`；看图窗另建 `AppState()` 实例会二次触发（读同一 UserDefaults pref，幂等无害）。长期应拆 `WindowState`（D-OW11 tech debt），Slice 1 接受现状。

---

# Slice 1 — 自建看图窗，warm 跑通 + 验置顶

**端到端可感知：** Glance 已开着用图库时，Finder 选图片「打开方式 → 一眼」→ 独立看图窗弹出置顶看图，图库主窗原样不动；ESC/⌘W 关看图窗，图库还在、app 不退；再次打开另一张图复用同窗显新图。

---

### Task 1: QuickViewerViewModel 加 deinit —— teardown 取消在途加载（二次打开前置）

**Files:**
- Modify: `Glance/QuickViewer/QuickViewerViewModel.swift:255-259`（`clearPrefetchCache()` 之后追加 `deinit`）

**Why:** 二次打开换图源靠 `.id(session.id)` 让旧 `@StateObject QuickViewerViewModel` teardown。当前 VM 无 `deinit`，`imageLoadTask` 只在下次 `loadCurrentImage()` 开头 cancel（见 `:209`），teardown 时在途 task 不取消。加 `deinit` 取消是正确的 teardown 卫生（减少 teardown 后还更新 UI/缓存的风险，顺带修 grid/preview 复用 VM 的潜在 task leak）。**注意：这不是 scope 竞态的安全边界**——`imageLoadTask` 内层套了 `Task.detached{loadFullNSImage}` 同步读盘，协作式 cancel 挡不住已进入的读（codex re-review P1#2）。scope 生命周期的安全性由控制器的 `retiredSessions`（关窗才统一 end）兜底，不依赖本 deinit。

- [ ] **Step 1: 在 `clearPrefetchCache()` 方法后、类右括号前追加 deinit**

```swift
    func clearPrefetchCache() {
        prefetchTasks.values.forEach { $0.cancel() }
        prefetchTasks.removeAll()
        prefetchCache.removeAll()
    }

    deinit {
        imageLoadTask?.cancel()
        prefetchTasks.values.forEach { $0.cancel() }
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `make build`
Expected: BUILD SUCCEEDED — 0 errors, 0 warnings

---

### Task 2: ViewerSession — security-scope 会话

**Files:**
- Create: `Glance/ExternalOpen/ViewerSession.swift`

- [ ] **Step 1: 写 ViewerSession**

```swift
//
//  ViewerSession.swift
//  Glance
//
//  一次"看图"会话：持有本次 urls 对应的 security-scoped resource token，
//  并记录关闭时是否要终止 app（冷启动看完即走 = true / warm = false）。
//  二次 show 时旧 session 的 end() 由控制器延后到旧 rootView teardown 之后再调，
//  配平 start/stop 且避开与旧加载 task 的竞态。仅被控制器（main actor）调用。
//

import Foundation

@MainActor
final class ViewerSession {
    let id = UUID()
    let urls: [URL]
    /// 看图窗关闭后是否终止整个 app。冷启动 open = true（看完即走）；warm = false（只关窗）。
    let terminateOnClose: Bool

    /// 实际 start 成功、需要在 end 时 stop 的 URL（start 返回 false 的不记，避免不配平 stop）。
    private var accessedURLs: [URL] = []
    private var started = false

    init(urls: [URL], terminateOnClose: Bool) {
        self.urls = urls
        self.terminateOnClose = terminateOnClose
    }

    /// 幂等：重复调只第一次生效。
    func start() {
        guard !started else { return }
        started = true
        for url in urls where url.startAccessingSecurityScopedResource() {
            accessedURLs.append(url)
        }
    }

    /// 幂等：stop 所有 start 成功的 URL，清空。重复调无副作用。
    func end() {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessedURLs.removeAll()
        started = false
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `make build`
Expected: BUILD SUCCEEDED — 0 errors, 0 warnings（新文件经 PBXFileSystemSynchronizedRootGroup 自动入编译）

---

### Task 3: ExternalViewerWindowController — 自建看图窗 + 自任 delegate

**Files:**
- Create: `Glance/ExternalOpen/ExternalViewerWindowController.swift`

复刻 `AboutWindowController` 的"自建 NSWindow + NSHostingView 可靠置顶"骨架（见 `Glance/About/AboutWindowController.swift`），但：(a) rootView 每次 show 换 `.id(session.id)` 强制 `QuickViewerOverlay` 重建 `@StateObject QuickViewerViewModel`（否则单例窗复用显旧图，codex P1#5）；(b) 控制器自任 `NSWindowDelegate` 复刻 `WindowAccessor.Coordinator` 的 fullscreen/key 跟踪 + 统一 close path（不接 `WindowAccessor`，避免 delegate 被抢，codex P1#3）；(c) 注入 `viewerAppState`（`QuickViewerOverlay` 强依赖 `@EnvironmentObject AppState`，缺则崩，codex P1#4）；(d) **close path 无条件 reset `isFullScreen`**（全屏中 ⌘W/红灯关窗后残留 true 会让下次 ESC 变成退全屏，codex P1#1）；(e) **create window 后先 `attachWindow` 再 set rootView**（QV onAppear 焦点链时序，codex P2#4）；(f) **deferred 置顶 reassert**（主 scene 仍在，warm open 可能后手抢 key，codex P2#5）。

- [ ] **Step 1: 写控制器**

```swift
//
//  ExternalViewerWindowController.swift
//  Glance
//
//  外部打开（Finder「打开方式」/ Dock 拖放）的独立看图窗（Preview/Quick Look 式）。
//  纯 AppKit 单例：自建 NSWindow + NSHostingController(QuickViewerOverlay)，自任
//  NSWindowDelegate（不接 WindowAccessor，避免 delegate 被抢）。持有 ViewerSession
//  管理 security-scope + terminateOnClose。窗口关闭统一走 windowWillClose path。
//

import AppKit
import SwiftUI

@MainActor
final class ExternalViewerWindowController: NSObject {
    static let shared = ExternalViewerWindowController()

    private var window: NSWindow?
    private var hosting: NSHostingController<AnyView>?
    /// 看图窗专属 AppState（F 全屏 / traffic light / 焦点都作用在看图窗，不碰图库窗）。
    private let viewerAppState = AppState()
    private var session: ViewerSession?
    /// 二次 show 退役的旧 session。**不在二次 show 时 end**——旧 VM 的嵌套 `Task.detached{loadFullNSImage}`
    /// 是同步读盘、协作式 cancel 挡不住，过早 stop scope 与之竞态（codex re-review P1#2）。改为累积到
    /// windowWillClose 统一 end：短期 scope 重叠无害（sandbox 允许同进程多 scoped resource），可证安全。
    /// 代价：一次 warm 会话内反复开图，scope 保留到关窗才释放——Slice 1 只测几张~几十张（PENDING 14）可接受。
    private var retiredSessions: [ViewerSession] = []

    private override init() { super.init() }

    /// 打开/复用看图窗显示 urls。terminateOnClose：Slice 1 恒 false（warm-only）。
    func show(urls: [URL], terminateOnClose: Bool) {
        guard !urls.isEmpty else { return }

        // 二次打开：旧 session 退役但不 end（见 retiredSessions 注释），新 session start 新 scope。
        if let current = session {
            retiredSessions.append(current)
        }
        let newSession = ViewerSession(urls: urls, terminateOnClose: terminateOnClose)
        newSession.start()
        session = newSession

        if window == nil {
            createWindow()
        }
        guard let win = window else { return }

        // 先 attach（播种 window 指针，让 QV onAppear 时 viewerAppState.window 非 nil），再换 rootView。
        viewerAppState.attachWindow(win)
        // 换 rootView：.id(session.id) 强制 QuickViewerOverlay 重建 viewModel 显新图源。
        hosting?.rootView = makeRootView(session: newSession)

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // deferred 置顶 reassert：主 SwiftUI scene 仍在场，warm open 时它可能在本帧后手 order/key 抢走置顶。
        // 下一 main-actor hop 再 assert 一次。guard session.id 仍 current + 窗口仍 visible，避免在窗口已关闭
        // （isReleasedWhenClosed=false → self.window 仍非 nil）或已被更新的 show 取代时把旧窗拉前台（codex re-review P2）。
        let currentID = newSession.id
        Task { @MainActor [weak self] in
            guard let self, let win = self.window,
                  self.session?.id == currentID, win.isVisible else { return }
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func makeRootView(session: ViewerSession) -> AnyView {
        AnyView(
            QuickViewerOverlay(
                images: session.urls,
                startIndex: 0,
                onDismiss: { [weak self] in self?.closeWindow() },
                onIndexChange: { _ in },          // 看图窗不同步任何图库选中
                onFindSimilar: nil,               // 纯看图，砍找类似（D-OW7）
                currentSupportsFeaturePrint: false,
                onCommandF: nil,                  // 纯看图，砍搜索（D-OW7）
                onBrowseFolder: nil               // 纯看图，砍浏览所在文件夹（D-OW7）
            )
            .environmentObject(viewerAppState)
            .id(session.id)
        )
    }

    private func createWindow() {
        let host = NSHostingController(rootView: AnyView(EmptyView()))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: DS.ExternalViewer.defaultWindowWidth,
                                height: DS.ExternalViewer.defaultWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.contentViewController = host
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false  // 关闭后保留实例，下次 show 复用同一 window
        win.collectionBehavior.insert(.fullScreenPrimary)  // 允许 F 进原生全屏
        win.center()
        win.delegate = self
        self.window = win
        self.hosting = host
    }

    /// onDismiss / 外部主动关窗入口。触发 window.close() → windowWillClose 走统一 close path。
    private func closeWindow() {
        window?.close()
    }
}

// MARK: - NSWindowDelegate（复刻 WindowAccessor.Coordinator 的 fullscreen/key 跟踪 + 统一 close path）

extension ExternalViewerWindowController: NSWindowDelegate {
    func windowDidEnterFullScreen(_ notification: Notification) {
        viewerAppState.isFullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        viewerAppState.isFullScreen = false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        viewerAppState.attachWindow(win)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let win = notification.object as? NSWindow,
              win === viewerAppState.window else { return }
        viewerAppState.isWindowKey = false
    }

    /// 统一 close path：ESC（onDismiss→closeWindow）/ ⌘W / 红灯 / 系统关闭都汇到这。
    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        // 无条件 reset：全屏中 ⌘W/红灯关窗后若残留 isFullScreen=true，下次打开第一下 ESC
        // 会被 QV 当成"退全屏"而非关窗（codex P1#1）。detach 已清 isWindowKey，这里补 isFullScreen。
        viewerAppState.isFullScreen = false
        viewerAppState.detachWindow(win)
        let terminate = session?.terminateOnClose ?? false
        // 统一在关窗时 end 当前 + 所有退役 session（stop 全部 security-scope，幂等）。
        session?.end()
        retiredSessions.forEach { $0.end() }
        retiredSessions.removeAll()
        session = nil
        if terminate {
            NSApp.terminate(nil)
        }
        // terminate=false：isReleasedWhenClosed=false，window 实例保留待下次 show 复用。
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `make build`
Expected: BUILD SUCCEEDED — 0 errors, 0 warnings

---

### Task 4: 接 AppDelegate — open 事件路由到看图窗

**Files:**
- Modify: `Glance/GlanceApp.swift:83-93`（`application(_:open:)`）

- [ ] **Step 1: 改 application(_:open:) 调控制器**

把"过滤后写 `ExternalOpenCoordinator.shared.pendingOpen`"改成"直接 show 看图窗"。**Slice 1 恒传 `terminateOnClose: false`**（warm-only）。`AppDelegate.accessedURLs` / `applicationWillTerminate` 的 stop 暂留（旧 coordinator 路径休眠后它不再被写入，无害；Slice 2 清理）。`applicationShouldTerminateAfterLastWindowClosed` 保持 `false` 不动。

替换 `application(_:open:)` 方法体为：

```swift
    // 从 Finder「打开方式」/ Dock 拖放接收图片文件 → 过滤图片 URL → 直接打开独立看图窗
    // （方向 2：ExternalViewerWindowController 自建 NSWindow，置顶可控，不复用图库主窗）。
    // Slice 1 恒传 terminateOnClose:false（warm-only 验证）；冷启动"看完即走"在 Slice 2 收 lifecycle 后接。
    func application(_ application: NSApplication, open urls: [URL]) {
        let images = urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        }
        guard !images.isEmpty else { return }
        ExternalViewerWindowController.shared.show(urls: images, terminateOnClose: false)
    }
```

- [ ] **Step 2: 验证编译**

Run: `make build`
Expected: BUILD SUCCEEDED — 0 errors, 0 warnings
检查点：`ExternalOpenCoordinator.shared.pendingOpen` 现在没有写入方了 → `ContentView` 的 `.onChange(externalOpen.pendingOpen)` 自然不再触发（旧路径休眠，代码暂留）。

- [ ] **Step 3: Slice 1 收尾（/go）**

跑 `/go`：三段 verify（grep 文档同步 + `make build` + 单测 skip）→ 文档同步（Roadmap OpenWith 段 + CLAUDE.md 文件结构加 `ViewerSession.swift` / `ExternalViewerWindowController.swift` + design 文档 Slice 1 完成详细 + QuickViewerViewModel deinit 进 Bug Fix/变更记录）→ 追加 PENDING 真机清单（见下）→ 逐文件 `git add` → commit + push（触发 pre-push codex）。

```bash
git add Glance/QuickViewer/QuickViewerViewModel.swift \
        Glance/ExternalOpen/ViewerSession.swift \
        Glance/ExternalOpen/ExternalViewerWindowController.swift \
        Glance/GlanceApp.swift \
        specs/2026-06-03-openwith-lightweight-viewer-design.md \
        specs/2026-06-03-openwith-lightweight-viewer-plan.md \
        specs/Roadmap.md CLAUDE.md specs/PENDING-USER-ACTIONS.md CONTEXT.md
git commit -m "feat(OpenWith): Slice 1 自建独立看图窗（warm，方向2）"
```

---

## Slice 1 PENDING 真机清单（CC 在 Mac mini 验不了，用户真机逐条验）

warm 场景（先正常打开 Glance、加几个文件夹、停在图库主界面）：
1. Finder 选一张图 →「打开方式 → 一眼」→ 独立看图窗**弹出并置顶到前台**，图库主窗原样在后面没动。
2. 看图窗里方向键 / 胶片条 / 上下张按钮能切图（多文件打开时）。
3. 按 ESC（非全屏）→ 看图窗关闭，图库主窗还在，**app 不退**。
4. 按 ⌘W → 同 ESC，看图窗关、app 不退。
5. 看图窗开着时，再去 Finder「打开方式」开**另一张**图 → **复用同一看图窗、显示新图**（不是显旧图、不是开第二个窗）。**连续换 5 张**确认每次都显当前图——这是 smoke test，scope 同步 I/O 竞态本就低概率，过不代表 P1#2 绝对无竞态（真正安全来自 retiredSessions 关窗才 end，不过早 stop）。
6. 按 F 进原生全屏 → 再按 ESC **先退全屏**（QV 语义）→ 再按 ESC 才关窗。
7. **全屏态下直接 ⌘W 关窗** → 再开一张图 → 第一下 ESC **就关窗**（不是退全屏）——验 P1#1 close path reset isFullScreen。
8. 一次选**多张**图「打开方式」→ 看图窗显第一张 + 胶片条显全部，能切。
9. Dock 图标上**拖多个**图片文件 → 同多文件打开。
10. app 切到后台时收 Finder open → 看图窗能抢到前台（deferred reassert 应已加固）。
11. 多显示器：看图窗出现在合理屏幕（主屏或鼠标所在屏）。
12. 反复开关看图窗 10 次后，活动监视器看 Glance 内存无明显泄漏（security-scope 配平 + VM deinit）。

边界 / 过渡态（**预期行为，非 bug**）：
13. 冷启动（Glance 没开）「打开方式」→ 此刻会**同时**显图库主窗 + 看图窗叠加，ESC 只关看图窗、app 不退。Slice 2 才改成"只显看图窗、看完即走"。
14. ⚠️ **大量文件**（几百上千张一次打开）暂不在 Slice 1 验收范围——`ViewerSession` 一次 start 全部 URL 可能撞 sandbox scope 资源上限（codex P2#7），后续若需支持改"按当前图 + 邻近预取按需 scope"。先只测几张~几十张。

---

# Slice 2 — 收回 lifecycle，拿"冷启动看完即走"（待 Slice 1 真机验过再细化）

> **不在本次 plan 展开 task 级细节**——Slice 1 是方向 2 核心赌注（自建窗置顶 + QuickViewer 搬迁），真机验过、确认无坑后，再回来按下列 scope 走 writing-plans 补 Slice 2 的 task。提前细化等于在没验证的赌注上压工作量。

Slice 2 scope（来自 design D-OW9/D-OW10）：
- 新增 `MainWindowController`：把图库主窗从 SwiftUI `Window` scene 收回自建 `NSWindow + NSHostingController(ContentView)`（注入现 GlanceApp 那套 environmentObject）。
- `GlanceApp`：移除真实 `Window("一眼")` scene，只留 `Settings`/`.commands` 类非主窗 scene（验 `.commands` 的 About 菜单仍正常）。
- `AppDelegate` 决定首窗：`applicationDidFinishLaunching` / reopen 时若**非**为 open 文件启动 → `MainWindowController.show()`；为 open 文件 → 只建看图窗，`terminateOnClose: true`。冷/warm 判断用**自持 `MainWindowController` 状态**，禁止扫 `NSApp.windows`（D-OW10）。
- 删除旧模型残留：`ContentView` externalOpen 机器（逐项确认三入口焦点/selectedImageIndex 行为）+ QV overlay `onBrowseFolder` 按钮 + `ExternalOpenCoordinator.swift`（删文件前再报告用户）+ `DS.ExternalOpen` + `AppDelegate.accessedURLs`/`applicationWillTerminate` 残留。
- `applicationShouldTerminateAfterLastWindowClosed`：退出语义改自持窗口计数 + `ViewerSession.terminateOnClose`。

---

## Self-Review（plan 写完自查）

1. **Spec 覆盖**：design Slice 1 边界全部落 task —— ✅ 自建窗(T3)/ViewerSession scope(T2)/open 路由(T4)/保留主 scene+shouldTerminate=false(T4 注)/terminateOnClose 恒 false(T4)/不删旧码(边界声明)/置顶限 warm(PENDING 13)。codex 一轮四实现债：environmentObject 注入(T3 makeRootView)/二次打开换图源(T3 .id(session.id) + T1 deinit)/scope 配平(T2 + T3 close path)/delegate 不被抢(T3 自任 delegate) —— ✅ 全覆盖。
2. **Placeholder 扫描**：无 TBD / 无"加适当错误处理" —— 每段给完整 Swift 代码 —— ✅。
3. **类型一致性**：`ViewerSession(urls:terminateOnClose:)` / `.start()` / `.end()` / `.id` / `.terminateOnClose`（T2）与 T3 调用一致；`show(urls:terminateOnClose:)`（T3）与 T4 调用一致；`QuickViewerOverlay(images:startIndex:onDismiss:onIndexChange:onFindSimilar:currentSupportsFeaturePrint:onCommandF:onBrowseFolder:)` 对齐真实 init 签名（已 Read `QuickViewerOverlay.swift:33-50`）；`AppState.attachWindow/detachWindow/isFullScreen/isWindowKey/window`、`QuickViewerViewModel.imageLoadTask/prefetchTasks/clearPrefetchCache` 对齐真实源码 —— ✅。
4. **真实 API 核对（Code reality check）**：`NSHostingController.rootView` 可写换 rootView —— ✅；`win.contentViewController = host` —— ✅；`isReleasedWhenClosed=false` 复用 window —— ✅（mirror About）；`UTType(filenameExtension:)` —— ✅（沿用原 `application(open:)` 写法）；VM 无 deinit 已确认（Read `QuickViewerViewModel.swift:255-260`）→ T1 补 —— ✅；项目 `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`（codex 查 pbxproj:286）→ 新类型显式 `@MainActor` —— ✅。

---

## codex review 折入记录（2026-06-03 二轮 plan-review）

| 等级 | codex 发现 | 折入位置 |
|------|-----------|---------|
| P1#1 | close path 没 reset `isFullScreen`，全屏中 ⌘W/红灯关窗后残留 → 下次 ESC 变退全屏 | T3 `windowWillClose` 无条件 `isFullScreen=false` + PENDING 7 |
| P1#2（一轮） | 二次 show 先 `end()` 旧 scope，旧 `imageLoadTask` 还在读旧 URL 竞态 | 一轮试修：VM `deinit` + 延 runloop end → **二轮 re-review 判定仍不安全** |
| P1#2（二轮 re-review） | `DispatchQueue.main.async` 不保证排在旧 VM teardown 后；`imageLoadTask` 内层 `Task.detached` 同步读盘 cancel 挡不住 | 改：T3 `retiredSessions` 累积旧 session，**关窗（windowWillClose）才统一 end**，不在二次 show 过早 stop；VM `deinit` 保留但仅作 teardown 卫生（措辞已改）+ PENDING 5 降级为 smoke test |
| P2（二轮）deferred reassert | `isReleasedWhenClosed=false` → 窗口关后 `self.window` 仍非 nil，async 可能把已关窗口再拉前台 | T3 reassert 改 `Task { @MainActor in }` + guard `session.id==currentID && win.isVisible` |
| P2（二轮）GCD vs actor | 类型已 `@MainActor`，混 `DispatchQueue.main.async` 可能隔离 warning | deferred reassert 改用 `Task { @MainActor in }`（旧 session end 已不再用 async） |

---

## Slice 1 完成详细（commit `7a32dff`）

| Task | 文件 | 落地 |
|------|------|------|
| T1 | `QuickViewerViewModel.swift` | 加 `deinit { imageLoadTask?.cancel(); prefetchTasks.values.forEach{$0.cancel()} }`（teardown 卫生，非 scope 安全边界） |
| T2 | `ViewerSession.swift`（新建） | `@MainActor` 会话：start 仅记 `startAccessingSecurityScopedResource()` 返回 true 的 URL，end 幂等 stop；持 `terminateOnClose` |
| T3 | `ExternalViewerWindowController.swift`（新建） | `@MainActor` 单例：自建 NSWindow + `NSHostingController<AnyView>` + 自任 NSWindowDelegate；`show` 先 `attachWindow` 再换 `.id(session.id)` rootView，`Task{@MainActor}` deferred reassert（guard session.id+isVisible）；旧 session 进 `retiredSessions` 关窗统一 end；`windowWillClose` reset `isFullScreen`/detach + 按 `terminateOnClose` terminate/只关窗 |
| T4 | `GlanceApp.swift` | `application(_:open:)` 改调 `ExternalViewerWindowController.shared.show(urls:terminateOnClose:false)`，不再写 `pendingOpen`；旧 coordinator 路径休眠 |

**验收**：`make build` BUILD SUCCEEDED 0 error/0 code warning（verify.sh 12 passed/0 failed）。三轮 codex review 收敛（design→plan→re-review→Go）全部折入。GUI 行为（warm 置顶/连换图/全屏⌘W后ESC/多文件/Dock多拖/后台抢前台/多屏/内存）见 PENDING-USER-ACTIONS，**待用户真机验**。Slice 2（收 lifecycle 拿冷启动看完即走 + 删旧 coordinator 等残留）待 Slice 1 真机验过再走 writing-plans。
| P2#3 | 项目 default main-actor isolation，新类型该显式 `@MainActor` | T2 `@MainActor ViewerSession` + T3 `@MainActor ExternalViewerWindowController` |
| P2#4 | attach 时序：应 create window 后先 attach 再 set rootView/show | T3 `show()` 先 `attachWindow(win)` 再换 rootView |
| P2#5 | warm 置顶验证不干净，主 scene 可能后手抢 key，应加 deferred reassert | T3 `show()` 末尾 `DispatchQueue.main.async` 再 assert 一次 |
| P2#6 | 红灯关闭与 QV 复用冲突（attach 时序不稳 traffic light 可能时隐时现） | 用户拍板删红灯：Slice 1 硬边界声明"不显 traffic light/不测红灯"，PENDING 移除红灯项 |
| P2#7 | `ViewerSession` 一次 start 所有 URL 对大批量不克制 | PENDING 14 限定 Slice 1 不测大量文件 |
| P2（确认非风险） | `AnyView`+`NSHostingController<AnyView>.rootView`+`.id` 方案站得住 | 保留原方案 |

---

## Slice 1 真机验证 + bug fix（2026-06-04，commit `a3e4ae0`）

真机验出 2 bug + 1 调整，修复后核心达成：

| 现象 | 根因 | 修复 |
|------|------|------|
| 看图窗只显 1×1 像素、看不到图（cold/warm 都中，表现为"主界面闪一下→无 QV→app 僵尸态点 Dock 无反应"） | `createWindow` 用 `contentViewController = NSHostingController`，AppKit 忽略传入 contentRect、改用 hosting `fittingSize` 定窗口尺寸；初始 rootView `EmptyView` fitting=0 → 窗口压成 1×1；换 QuickViewerOverlay（弹性布局 fitting 仍 0）后窗口已定死不再长大 | 改 `contentView = NSHostingView<AnyView>`（mirror `AboutWindowController` 已验证骨架，contentView 不反向驱动窗口尺寸）+ `host.autoresizingMask=[.width,.height]` 跟随 resize/全屏。**上方 T3/P2 里写的 NSHostingController 方案正是 1×1 根源——纠正记录在此** |
| 看图窗首开键盘须先点鼠标（ESC/F/方向键不响应） | `isWindowKey` 在 QuickViewerOverlay mount **之前**就被 `windowDidBecomeKey→attachWindow` 翻 true → `.onChange(of:isWindowKey)` 补救永不触发；仅剩 onAppear 那次 `isFocused=true` 被刚 mount 帧的 focus 系统静默丢弃 | `requestKeyboardFocusIfWindowIsKey()` 设 `isFocused=true` 后 `Task{@MainActor}+await Task.yield()` 让出一个 runloop 周期再补一次（async/await，非 callback——pre-push codex 拒 `DispatchQueue.main.async`，commit `fdadc92`；跨过未 ready 帧；幂等，主窗无副作用）。共享组件 QuickViewerOverlay 改动 |
| 红绿灯交通灯显示冗余且丑（QV 自带 X 按钮已可关窗） | 中途为"让红灯显示"加的 `managesHostTrafficLights` 参数方向反了 | revert 参数，看图窗回到 `onAppear hideTrafficLights`（QV 永不 disappear→永久隐藏），靠 QV X 按钮关窗 |

**真机验过（warm）**：✅ 置顶成功（方向2 核心赌注成立，V1 顽疾在自建独立窗下解决）/ 多图翻页 / 连换图不显旧图 / focus 自动 / ESC·⌘W·X 关窗后图库主窗在、app 不退。

**已知未解（归 Slice 2，同根：SwiftUI `Window` scene 仍在）**：cold 启动双窗（图库主窗+看图窗）；warm 看完关图后图库主窗被 odoc 瞬态 close 不自动回来（须点 Dock）。Slice2 移除 Window scene + AppDelegate 自建主窗（D-OW9/10）一并根治。

**诊断手段教训**：NSLog 经 macOS 统一日志被按隐私策略 redact 成 `<private>`，外部 `log show`/Console grep 不到 → 改写沙盒文件 trace（`~/Library/Containers/<bundleid>/Data/`）绕开脱敏定位。诊断埋点已全部清理。
