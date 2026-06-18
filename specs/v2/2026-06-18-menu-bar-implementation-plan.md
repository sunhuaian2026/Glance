# Glance V2 macOS 菜单栏增补 第一批 implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan 任务-by-任务. Steps use checkbox (`- [ ]`) syntax for tracking.

> **design 反链**: [`specs/v2/2026-06-18-menu-bar-design.md`](2026-06-18-menu-bar-design.md) (v2.1, commit `a6a216b`)
> **状态**: plan draft 待 codex review → 军哥拍板 → 实施
> **术语**: 见 `CONTEXT.md`「术语字典」D 段(独立子系统不塞 M 序号, 用「任务 A/B/C/D/E/F」)
> **配对**: 本 plan 落 `specs/v2/2026-06-18-menu-bar-implementation-plan.md`
> **scope**: **仅第一批 16 项无争议菜单** (全屏 + 共享快捷键路由方向决策留第二批 design v3)

---

**Goal:** 为 Glance 主窗 macOS 菜单栏挂 16 项常用动作入口(文件 1 / 编辑 3 / 显示 5 / 图像 6 / 窗口 1), 让鼠标用户和不熟键盘的新用户能从菜单栏发现 + 触发, 同时**零破坏**快速看图器内现有 `.onKeyPress` 共享快捷键路径。

**Architecture:** SwiftUI `Scene.commands` + `CommandGroup` / `CommandMenu` 范式(mirror 现有 `AboutMenuButton`); 新建 2 个 ObservableObject (`SearchOverlayState` trigger event 模式 + `InspectorState` 双向 sync) 桥接 ContentView 私有 @State 给菜单 view; 新建 `MainQuickViewerWindowController` closure registry 模式(controller 持 `[QuickViewerCommand: () -> Void]` 注册表, Overlay onAppear 注册 / onDisappear 清空)桥接 ViewModel 给菜单 view, **不动 ViewModel ownership**; **零 `.keyboardShortcut` 挂载**(方向 Y), 所有快捷键 hint 用菜单文本手工拼字符串「(⌘C)」 / 「(L)」 / 「(⌫)」。

**Tech Stack:** SwiftUI(macOS 14+) `Scene.commands` / `CommandGroup` / `CommandMenu` / `@ObservableObject` / `.onReceive` + AppKit(`NSOpenPanel` 通过 `FolderStore.addFolder()` 现有封装复用)

**最小真实改动集**:

| 改动类型 | 文件 | 改动概要 |
|---|---|---|
| **新建** | `Glance/MenuBar/SearchOverlayState.swift` | ObservableObject, `@Published private(set) var triggerToken: UUID` + `requestOpen()`(D-mb-9.1 trigger event 模式) |
| **新建** | `Glance/MenuBar/InspectorState.swift` | ObservableObject, `@Published var isShown: Bool`(D-mb-8 信息切换动态文案 + D-mb-9.1 双向 sync) |
| **新建** | `Glance/MenuBar/MenuBarCommands.swift` | 5 个 commands view struct(`FileMenuCommands` / `EditMenuCommands` / `ViewMenuCommands` / `ImageMenuCommands` / `WindowMenuCommands`), 每个持必要 `@ObservedObject` + Button label 手工拼快捷键 hint |
| **新建** | `Glance/QuickViewer/MainQuickViewerWindowController+Commands.swift` | extension: `enum QuickViewerCommand` + 4 个 `@Published` registry + `register/clear/performCommand/performTrash`(D-mb-9.2 closure registry 模式) |
| **必改** | `Glance/GlanceApp.swift` | AppDelegate 加 SearchOverlayState + InspectorState 单例; `.commands` 挂 5 个 CommandGroup/CommandMenu |
| **必改** | `Glance/ContentView.swift` | `openSearch` 不动 (保持 private); 加 `.onReceive(searchOverlayState.$triggerToken.dropFirst())` listener; `showInspector` @State 改双向 sync 到 InspectorState |
| **必改** | `Glance/QuickViewer/QuickViewerOverlay.swift` | `onAppear` 调 controller.registerCommandHandlers; `onDisappear` 调 controller.clearCommandHandlers |
| **文档同步** | `specs/Roadmap.md` / `CLAUDE.md` / `specs/PENDING-USER-ACTIONS.md` | 任务 F 收尾时同步 |

**不改动文件**(显式):
- `Glance/QuickViewer/QuickViewerViewModel.swift` — 零改动(closure registry 不动 ownership)

**额外必改文件** (self-review 修):
- `Glance/QuickViewer/MainQuickViewerWindowController.swift` — 主文件加 3 个 stored properties (`commandHandlers` / `trashHandler` / `hasImageProvider`), 因为 Swift extension 不能加 stored properties; 行为方法在 +Commands.swift extension 里。
- `Glance/FullScreen/AppState.swift` — 全屏菜单项第二批
- `Glance/MainWindow/MainWindowController.swift` — `hasWindow` 已暴露, 直接复用
- `Glance/BookmarkManager.swift` / `Glance/FolderBrowser/FolderStore.swift` — `FolderStore.addFolder()` 复用现有封装(NSOpenPanel + saveBookmark + 树加载 + autoSelect 全在内)
- `Glance/DesignSystem.swift` — 菜单无视觉常量

---

## 任务全表

| 任务 | 一句话 | 文件触及数 | 估时 | 依赖 | 用户独立感知 |
|---|---|---|---|---|---|
| **任务 A** ⚠️ | 前置 spike + facade 框架(SearchOverlayState/InspectorState 双桥 + closure registry) | 4 新建 + 3 改 | 0.5-1 天 | 无 | **不单独 ship** — 跟任务 B 合并提交 |
| **任务 B** | 文件菜单「添加文件夹根…」+ 窗口菜单「图库主窗」(跟任务 A 合并) | +1 新建(MenuBarCommands) + 1 改(GlanceApp) | 0.5 天 | A | 菜单栏文件 / 窗口下新增可点击项, 点添加根弹 NSOpenPanel / 关窗驻留下点图库主窗 reopen |
| **任务 C** | 编辑菜单 3 项(查找 / 复制图 / 复制路径) | 2 改(MenuBarCommands + GlanceApp) | 0.5 天 | A + B | 编辑菜单新 3 项, 点击触发对应动作; 主窗状态复制项 disable |
| **任务 D** | 图像菜单 6 项(旋转 L/R + 翻转 H/V + Finder + 废纸篓) | 2 改(MenuBarCommands + GlanceApp) | 0.5-1 天 | A + B | 新增「图像」顶级菜单, 6 项快速看图器在场时 enable / 主窗状态全 disable |
| **任务 E** | 显示菜单 5 项(信息切换 + 缩放系列 4 项) | 2 改(MenuBarCommands + GlanceApp) | 0.5 天 | A + B | 显示菜单新 5 项, 信息切换动态文案; 缩放快速看图器在场时 enable |
| **任务 F** | 任务收尾(verify / Roadmap / CLAUDE.md / PENDING / commit / push) | 3 文档 | 0.25 天 | A-E 全 | 文档同步 + PENDING 20 项军哥本机肉眼验 |

**总估时**: 3-4 天。**实施顺序硬约束**: **A+B 合并 → C → D → E → F 严格串行**, 不并行。理由:
- A+B 合并是「第一个用户可感知 ship 点」, 必须先建框架再上菜单项
- C/D/E 都改 `MenuBarCommands.swift` 同文件, 并行 subagent 会 merge 冲突 + 三步改邻近行
- F 收尾必须等 A-E 全 ship 完才能跑

---

## 总体时序

```
任务 A (spike + facade 框架) ─┐
                              ├─→ 合并 ship → 任务 C (编辑) → 任务 D (图像) → 任务 E (显示) → 任务 F (收尾)
任务 B (文件 + 窗口菜单)     ─┘
```

- 任务 A 是 spike 不单独 ship — codex v2 P2-2 反馈, 跟任务 B 合并: 验证 SwiftUI commands 内 @ObservedObject 真触发 .disabled (R-mb-1 / R-mb-11) + closure registry 跟 Overlay lifecycle 协调 (R-mb-14) + commands 内 view 用 controller.shared 单例真能响应
- 任务 B 是最简单菜单项(文件添加根 + 窗口主窗 reopen), 验证 commands view 装配可行 + 菜单出现在正确位置
- C/D/E 在 framework 已稳的基础上, 把剩余 14 项菜单挂上
- F 是文档同步 + push, 把 PENDING 真机肉眼验项交给军哥

---

## 风险与对策

| ID | 风险 | 对策 | 触发任务 |
|---|---|---|---|
| **R-mb-1 / R-mb-11** | SwiftUI commands 内 view 用 `@ObservedObject` 观察 `MainQuickViewerWindowController.shared` 单例 `.isPresenting` 是否触发 `.disabled` 重渲染 | 任务 A.8 spike 验证 — 写最小 commands 内 view + 1 个 button 绑 disabled, 实测开关 QV 看 disabled state 切换 | A |
| **R-mb-12** | SwiftUI `.commands` 改完后菜单结构 hot reload 可能不刷新 | **任务 F.1 verify checklist 加一条「重启 app 看菜单结构」**, 不信 Xcode preview hot reload(macOS .commands 改动 hot reload 限制) | F |
| **R-mb-13** | SearchOverlayState 抽出后 ContentView 既有 ⌘F `.onKeyPress` 路径回归风险 | 任务 A.4 加 `.onReceive` listener 时**不动**现有 `.onKeyPress` 一行; 验证主窗 ⌘F 仍弹 search overlay | A |
| **R-mb-14** | facade closure registry 跟 Overlay onAppear/onDisappear lifecycle 协调不当导致 stale closure 或 crash | 任务 A.7 严格按 `onAppear 注册 / onDisappear 清空` 模式; 任务 A.8 spike 抽 1 个 VM 依赖项(`rotateLeft`)验证 closure 捕获 viewModel 跟 NSWindow lifecycle 正确 dispose | A |
| **R-mb-2** | 系统注入的「编辑→剪切/复制/粘贴」「窗口→全屏」可能跟自定义项视觉冲突 | 用 `CommandGroup(after: ...)` 显式定位, 不混入系统组(B/C/D/E 各 CommandGroup placement 明示) | B/C/D/E |
| **R-mb-3** | NSMenu 文本「复制图片  (⌘C)」字面跟系统「编辑→复制 ⌘C」混淆 | 方向 Y 全不挂 keyEquivalent, 用户实际按 ⌘C 在 QV 内仍走 `.onKeyPress`; 主窗按 ⌘C 走系统默认(无 app action)。**已 design 明示「已知设计选择, 非 bug」** | C/D |
| **新风险 R-mb-15** | `CommandGroup(after: .sidebar)` 在 macOS 14 显示菜单实际渲染位置未验 | 任务 E.5 build + run 实测; 不对则改用 `CommandMenu("显示")` 或 `(replacing: .sidebar)` 备选 | E |
| **新风险 R-mb-16** | `CommandMenu("图像")` 顶级菜单插入位置(显示和窗口之间)需 build + run 实测确认 | 任务 D.5 build + run 实测 | D |
| **新风险 R-mb-17** | Overlay 用同一闭包捕获 `viewModel` 多次注册可能引发循环引用 | 闭包是 `() -> Void` 捕获弱引用 `viewModel`(SwiftUI @StateObject 自动管理), Overlay onDisappear 清空 controller.registeredCommandHandlers; 任务 A.7 加内存压力 spike(开关 QV 5 次看进程内存稳定) | A |

---

## 任务 A — 前置 spike + facade 框架(跟任务 B 合并 ship)

**Files:**
- Create: `Glance/MenuBar/SearchOverlayState.swift`
- Create: `Glance/MenuBar/InspectorState.swift`
- Create: `Glance/QuickViewer/MainQuickViewerWindowController+Commands.swift`
- Create: `Glance/MenuBar/MenuBarCommands.swift` (空骨架, 任务 B-E 填充)
- Modify: `Glance/GlanceApp.swift` (AppDelegate 加 2 单例 + .commands 挂 1 个临时 spike CommandGroup)
- Modify: `Glance/ContentView.swift` (加 `.onReceive(searchOverlayState.$triggerToken.dropFirst())` listener + showInspector 双向 sync)
- Modify: `Glance/QuickViewer/QuickViewerOverlay.swift` (onAppear/onDisappear 调 register/clear)

### 步骤拆分

- [ ] **A.1: 新建 `SearchOverlayState.swift` (trigger event 模式)**

文件 `Glance/MenuBar/SearchOverlayState.swift`:

```swift
//
//  SearchOverlayState.swift
//  Glance
//
//  D-mb-9.1 — Search overlay trigger event 模式
//  仅持 trigger token, ContentView 仍是 sole state owner.
//

import SwiftUI

@MainActor
final class SearchOverlayState: ObservableObject {
    /// 每次 requestOpen() 换新 UUID, ContentView 通过 .onReceive 监听变更触发原 openSearch().
    @Published private(set) var triggerToken: UUID = UUID()

    /// 菜单栏「查找…」点击入口.
    func requestOpen() {
        triggerToken = UUID()
    }
}
```

- [ ] **A.2: 新建 `InspectorState.swift` (双向 sync)**

文件 `Glance/MenuBar/InspectorState.swift`:

```swift
//
//  InspectorState.swift
//  Glance
//
//  D-mb-8 + D-mb-9.1 — Inspector 状态共享(ContentView showInspector 双向 sync).
//  菜单栏「显示信息 / 隐藏信息」动态文案读这里.
//

import SwiftUI

@MainActor
final class InspectorState: ObservableObject {
    @Published var isShown: Bool = false
}
```

- [ ] **A.3: 必改主文件 stored properties + register/clear methods (codex plan P0 修); 新建 +Commands.swift extension 放 enum + performCommand/performTrash (只读)**

**codex plan P0 修法**: Swift `private(set)` 在跨文件 extension 内不可 set。改方案 — `register/clear` 写状态的方法放**主文件** (跟 stored properties 同文件), `+Commands.swift` extension 只放 enum + 只读 facade methods。

**步骤 1**: 必改 `Glance/QuickViewer/MainQuickViewerWindowController.swift` 在既有 `@Published private(set) var isPresenting` 之后 (line 47 附近) 加 3 stored properties + 2 写入 method:

```swift
// 在 line 47 之后加:

// MARK: - D-mb-9.2 菜单栏 closure registry

@Published private(set) var commandHandlers: [QuickViewerCommand: () -> Void] = [:]
private(set) var trashHandler: (() async -> Void)? = nil
private(set) var hasImageProvider: () -> Bool = { false }

func registerCommandHandlers(
    handlers: [QuickViewerCommand: () -> Void],
    trash: @escaping () async -> Void,
    hasImage: @escaping () -> Bool
) {
    self.commandHandlers = handlers
    self.trashHandler = trash
    self.hasImageProvider = hasImage
    // commandHandlers 是 @Published 自动 send; trashHandler/hasImageProvider 不是,
    // 显式 send 确保 hasCurrentImage computed property 的 view binding 同步更新.
    objectWillChange.send()
}

func clearCommandHandlers() {
    self.commandHandlers = [:]
    self.trashHandler = nil
    self.hasImageProvider = { false }
    objectWillChange.send()
}
```

**步骤 2**: 新建 enum + 只读 facade `Glance/QuickViewer/MainQuickViewerWindowController+Commands.swift`:

```swift
//
//  MainQuickViewerWindowController+Commands.swift
//  Glance
//
//  D-mb-9.2 — 快速看图器命令 closure registry (只读 facade 段, 写入在主文件).
//

import SwiftUI

enum QuickViewerCommand: Hashable {
    case rotateLeft, rotateRight
    case toggleFlipH, toggleFlipV
    case copyImage, copyPath
    case revealInFinder
    case resetToFit, resetToOneToOne
    case zoomIn, zoomOut
}

@MainActor
extension MainQuickViewerWindowController {
    /// 菜单栏 commands 触发入口(同步动作).
    func performCommand(_ cmd: QuickViewerCommand) {
        guard isPresenting, let handler = commandHandlers[cmd] else { return }
        handler()
    }

    /// 菜单栏 commands 触发入口(异步动作, 仅 trash).
    func performTrash() async {
        guard isPresenting, let handler = trashHandler else { return }
        await handler()
    }

    /// commands view 用作 .disabled binding 第三层(快速看图器在场 + 有图).
    var hasCurrentImage: Bool {
        guard isPresenting else { return false }
        return hasImageProvider()
    }
}
```

**为什么拆分**: extension 文件只读 stored properties 不需要 setter access, `private(set)` 限制不冲突; 写入逻辑在主文件保留 strict access control。

- [ ] **A.4: 新建 `MenuBarCommands.swift` 空骨架**

文件 `Glance/MenuBar/MenuBarCommands.swift`:

```swift
//
//  MenuBarCommands.swift
//  Glance
//
//  D-mb-1 / D-mb-6 — 5 个菜单 commands view struct.
//  任务 B-E 逐个填充内容.
//

import SwiftUI

/// 文件菜单(任务 B).
struct FileMenuCommands: View {
    @ObservedObject var folderStore: FolderStore

    var body: some View {
        Button("添加文件夹根…") {
            folderStore.addFolder()
        }
    }
}

/// 编辑菜单(任务 C 填充).
struct EditMenuCommands: View {
    @ObservedObject var searchOverlayState: SearchOverlayState
    @ObservedObject var qvController: MainQuickViewerWindowController

    var body: some View {
        EmptyView()  // 任务 C 填充
    }
}

/// 显示菜单(任务 E 填充).
struct ViewMenuCommands: View {
    @ObservedObject var inspectorState: InspectorState
    @ObservedObject var qvController: MainQuickViewerWindowController
    @ObservedObject var folderStore: FolderStore

    var body: some View {
        EmptyView()  // 任务 E 填充
    }
}

/// 图像菜单(任务 D 填充).
struct ImageMenuCommands: View {
    @ObservedObject var qvController: MainQuickViewerWindowController

    var body: some View {
        EmptyView()  // 任务 D 填充
    }
}

/// 窗口菜单(任务 B).
struct WindowMenuCommands: View {
    let bookmarkManager: BookmarkManager
    let folderStore: FolderStore
    let appState: AppState
    let indexStoreHolder: IndexStoreHolder
    let searchOverlayState: SearchOverlayState
    let inspectorState: InspectorState
    @ObservedObject var mainWindowController: MainWindowController

    var body: some View {
        if !mainWindowController.hasWindow {
            Button("图库主窗") {
                MainWindowController.shared.show(
                    bookmarkManager: bookmarkManager,
                    folderStore: folderStore,
                    appState: appState,
                    indexStoreHolder: indexStoreHolder,
                    searchOverlayState: searchOverlayState,
                    inspectorState: inspectorState
                )
            }
        }
    }
}
```

**A.4.1 必改 MainWindowController.swift conform ObservableObject (codex plan P0 修)**:

修改 `Glance/MainWindow/MainWindowController.swift`:

```swift
// 既有声明类似: @MainActor final class MainWindowController { ... }
// 改成 conform ObservableObject:
@MainActor final class MainWindowController: ObservableObject {
    static let shared = MainWindowController()

    // 既有 hasWindow 改成 @Published 让 commands view .disabled/.if 重渲染:
    @Published private(set) var hasWindow: Bool = false

    // 既有 show()/close() 等方法在切换 NSWindow 时已经设 hasWindow, 不动逻辑.
    // ... 既有 body 不变 ...
}
```

**为什么 hasWindow 改 @Published**: 窗口菜单「图库主窗」用 `mainWindowController.hasWindow` 做 `if !... { Button }` 条件渲染 (D-mb-4 hide when hasWindow); 不 @Published 则窗口开关时菜单不刷新, 用户必须重启菜单才看到 reopen 项。

**Note A.4.2**: 任务 A.4 这步先不挂 EditMenu / ViewMenu / ImageMenu 到 GlanceApp.commands, 任务 C/D/E 填充后才挂。

- [ ] **A.5: GlanceApp.swift 加 2 单例 + 临时 spike CommandGroup**

修改 `Glance/GlanceApp.swift` AppDelegate class 加 2 个属性:

```swift
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let bookmarkManager: BookmarkManager
    let folderStore: FolderStore
    let appState = AppState()
    let indexStoreHolder = IndexStoreHolder()

    // D-mb-9 新增 2 单例(菜单栏增补 第一批)
    let searchOverlayState = SearchOverlayState()
    let inspectorState = InspectorState()

    // ... 既有 lifecycle methods 不变 ...
}
```

GlanceApp body 加临时 spike CommandGroup(任务 A.8 用, 任务 B 替换为真实菜单):

```swift
@main
struct GlanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptySettingsView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuButton()
            }
            // 任务 A.8 spike — 验证 SwiftUI commands 内 @ObservedObject 触发 .disabled
            // 任务 B/C/D/E 实现真菜单后此 CommandGroup 删除
            CommandGroup(after: .windowList) {
                SpikeProbeCommands(qvController: MainQuickViewerWindowController.shared)
            }
        }
    }
}

/// 任务 A.8 spike probe — 验证 commands 内 @ObservedObject 真触发 .disabled.
private struct SpikeProbeCommands: View {
    @ObservedObject var qvController: MainQuickViewerWindowController

    var body: some View {
        Button("[SPIKE] 旋转左 (L) — 仅 spike 用") {
            qvController.performCommand(.rotateLeft)
        }
        .disabled(!qvController.isPresenting)
    }
}
```

- [ ] **A.6: ContentView.swift 加 SearchOverlayState listener + InspectorState 双向 sync**

修改 `Glance/ContentView.swift`:

**注入路径 (codex plan P0 修)**: 不用 force unwrap `NSApp.delegate as! AppDelegate` (违反 CLAUDE.md「禁止 force unwrap」全局规则)。改用既有 environmentObject 注入链 mirror M4 模式 — `MainWindowController.swift` 在 `show(...)` 时已经把 4 单例 (bookmarkManager/folderStore/appState/indexStoreHolder) 通过 NSHostingView rootView 的 `.environmentObject()` 注入到 ContentView; 同模式扩展 注入 2 个新单例。

**步骤 1**: 修改 `Glance/MainWindow/MainWindowController.swift` 的 `show(...)` 方法, 新增 2 参数:

```swift
// 既有签名:
// func show(bookmarkManager:, folderStore:, appState:, indexStoreHolder:)
// 新签名 (加 searchOverlayState + inspectorState):
func show(
    bookmarkManager: BookmarkManager,
    folderStore: FolderStore,
    appState: AppState,
    indexStoreHolder: IndexStoreHolder,
    searchOverlayState: SearchOverlayState,
    inspectorState: InspectorState
) {
    // ... 既有逻辑 ...
    // rootView 注入链加 2 个新 environmentObject:
    let rootView = ContentView()
        .environmentObject(bookmarkManager)
        .environmentObject(folderStore)
        .environmentObject(appState)
        .environmentObject(indexStoreHolder)
        .environmentObject(searchOverlayState)
        .environmentObject(inspectorState)
    // ...
}
```

**步骤 2**: AppDelegate.showMainWindow 调用更新 (`Glance/GlanceApp.swift`):

```swift
private func showMainWindow() {
    MainWindowController.shared.show(
        bookmarkManager: bookmarkManager,
        folderStore: folderStore,
        appState: appState,
        indexStoreHolder: indexStoreHolder,
        searchOverlayState: searchOverlayState,
        inspectorState: inspectorState
    )
}
```

**步骤 3**: 修改 `Glance/ContentView.swift` 加 2 个 @EnvironmentObject 声明:

```swift
struct ContentView: View {
    // ... 既有 @EnvironmentObject / @StateObject / @State 全保留 ...

    @EnvironmentObject var searchOverlayState: SearchOverlayState
    @EnvironmentObject var inspectorState: InspectorState

    var body: some View {
        // ... 既有 body 内容不变 ...
        .onReceive(searchOverlayState.$triggerToken.dropFirst()) { _ in
            // dropFirst 跳过初始 UUID, 仅响应 requestOpen() 触发的换新.
            openSearch()
        }
        .onChange(of: showInspector) { _, newValue in
            // ContentView showInspector 改 → InspectorState.isShown 同步; guard 避免循环.
            if inspectorState.isShown != newValue {
                inspectorState.isShown = newValue
            }
        }
        .onChange(of: inspectorState.isShown) { _, newValue in
            // InspectorState.isShown 改(菜单栏触发) → showInspector 同步; guard 避免循环.
            if showInspector != newValue {
                showInspector = newValue
            }
        }
        // ... 既有 .onKeyPress 等不动 ...
    }
}
```

**为什么不用 NSApp.delegate force unwrap**: CLAUDE.md 全局禁 force unwrap; environmentObject 注入链是项目现有标准 (mirror M4 任务 2 收尾 step A.5 BookmarkMigrationCoordinator 模式); 跨 scope (Scene-level vs window-level) 通过 NSHostingView 注入路径稳定。

- [ ] **A.7: QuickViewerOverlay.swift 加 onAppear 注册 / onDisappear 清空 closure registry**

修改 `Glance/QuickViewer/QuickViewerOverlay.swift` 在现有 `.onAppear` block 末尾加注册, `.onDisappear` block 末尾加清空:

```swift
// 在 line 193 附近(既有 .onAppear) 加 closure registry 注册:
.onAppear {
    viewModel.applyViewportSize(geo.size)
    requestKeyboardFocusIfWindowIsKey()
    showControlsTemporarily()
    loadCurrentMetadata()
    // D-mb-9.2 — 注册 closure registry 给 app 菜单栏调用.
    MainQuickViewerWindowController.shared.registerCommandHandlers(
        handlers: [
            .rotateLeft: { viewModel.rotateLeft() },
            .rotateRight: { viewModel.rotateRight() },
            .toggleFlipH: { viewModel.toggleFlipH() },
            .toggleFlipV: { viewModel.toggleFlipV() },
            .copyImage: { copyImageToPasteboard() },
            .copyPath: { copyCurrentPath() },
            .revealInFinder: { revealInFinder() },
            .resetToFit: { viewModel.resetToFit() },
            .resetToOneToOne: { viewModel.resetToOneToOne() },
            .zoomIn: { viewModel.zoomIn() },
            .zoomOut: { viewModel.zoomOut() }
        ],
        trash: { await handleTrashCurrent() },
        hasImage: { viewModel.currentNSImage != nil }
    )
}
.onChange(of: geo.size) { _, newSize in
    viewModel.applyViewportSize(newSize)
}
// ... 其余 .onChange / .onKeyPress 不动 ...
```

在 line 224 附近(既有 `.onDisappear`) 加清空:

```swift
.onDisappear {
    hideTask?.cancel()
    appState.showTrafficLights()
    viewModel.clearPrefetchCache()
    // D-mb-9.2 — 清空 closure registry, 防 stale closure 引用已 disappear 的 viewModel.
    MainQuickViewerWindowController.shared.clearCommandHandlers()
}
```

**A.7.1 registry 清理时机覆盖范围 (codex plan P1 修)**:

`.onDisappear` 是 SwiftUI 主路径, 覆盖正常关 QV (ESC / Space / 关闭按钮) 场景。还有 3 个边缘路径需要 controller 主动调 `clearCommandHandlers()`:

| 边缘路径 | 代码触发点 | 是否已覆盖 |
|---|---|---|
| `MainQuickViewerWindowController.close(reason:)` 主动关 | controller `close()` 路径末尾 | 任务 A.7.1 step 1 显式加 `clearCommandHandlers()` 兜底 |
| controller `windowWillClose` notification | controller 自身 NSWindowDelegate | 同上, 已有 lifecycle hook 加 `clearCommandHandlers()` |
| app `applicationWillTerminate` 异常退出 | AppDelegate.applicationWillTerminate | 不需手动清, 进程退出 registry 自然释放 |

**任务 A.7.1 step 1**: 修改 `MainQuickViewerWindowController.swift` `close(...)` 方法或 `windowWillClose` handler 末尾加:

```swift
// close() 或 windowWillClose 路径末尾, 在 isPresenting = false 之后:
clearCommandHandlers()
```

**任务 A.7.1 step 2**: registry 持有的闭包 strong-capture viewModel, 但 viewModel 是 Overlay 的 `@StateObject` (Overlay 是 owner), Overlay disappear 触发 onDisappear → clearCommandHandlers → registry 释放闭包 → viewModel 引用计数减 → 同步 SwiftUI 释放 viewModel。无循环引用 (controller → 闭包 → viewModel, viewModel 不持 controller 反向)。

**Note**: registry 清理不是「即时释放保证」, 但延迟时长 ≤ Overlay disappear 后下一帧 (SwiftUI lifecycle 标准, 用户感知不到)。

- [ ] **A.8: 跑 spike — `make build` + 真机肉眼验证 spike probe button**

跑 `make build`:

```bash
make build 2>&1 | tail -30
```

期望: BUILD SUCCEEDED, 0 errors, 0 code warnings。

军哥本机肉眼验证 (PENDING 1 项, 任务 A.8 收尾时收集):
- 启动 app → 窗口菜单顶部出现「[SPIKE] 旋转左 (L) — 仅 spike 用」菜单项 → **点击灰显**(disabled, 因为快速看图器不在场)
- 双击任一图进快速看图器 → 菜单项**变 enable** → 点击 = 快速看图器内图旋转 90°
- 关快速看图器 → 菜单项**重新变 disable**

验证通过 → R-mb-1 / R-mb-11 / R-mb-14 全过 → 任务 B-E 继续

**A.8 失败 fallback 步骤明确 (codex plan P1 修)**:

如 spike 失败 (菜单项 .disabled binding 不随 isPresenting 切换), 按下面步骤升级:

**Fallback 步骤 1 — 新建 `Glance/MenuBar/MenuBarState.swift`**:

```swift
//
//  MenuBarState.swift
//  Glance
//
//  Fallback — 若 SwiftUI commands view 直接观察 controller.shared @ObservedObject 不响应,
//  改用 AppDelegate 持 MenuBarState ObservableObject 作中转层.
//

import SwiftUI
import Combine

@MainActor
final class MenuBarState: ObservableObject {
    @Published var isQuickViewerPresenting: Bool = false
    @Published var hasCurrentImage: Bool = false
    @Published var hasMainWindow: Bool = false

    private var cancellables = Set<AnyCancellable>()

    func bind(
        qvController: MainQuickViewerWindowController,
        mainController: MainWindowController
    ) {
        qvController.$isPresenting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isQuickViewerPresenting = $0 }
            .store(in: &cancellables)
        qvController.$commandHandlers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.hasCurrentImage = qvController.hasCurrentImage }
            .store(in: &cancellables)
        mainController.$hasWindow
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.hasMainWindow = $0 }
            .store(in: &cancellables)
    }
}
```

**Fallback 步骤 2 — AppDelegate 持单例 + bind 调用**:

```swift
// AppDelegate 加:
let menuBarState = MenuBarState()

// applicationDidFinishLaunching 内调:
menuBarState.bind(
    qvController: MainQuickViewerWindowController.shared,
    mainController: MainWindowController.shared
)
```

**Fallback 步骤 3 — 各 commands view 改用 menuBarState**:

```swift
// 例 ImageMenuCommands 改:
struct ImageMenuCommands: View {
    @ObservedObject var menuBarState: MenuBarState
    let onCommand: (QuickViewerCommand) -> Void

    var body: some View {
        Button("旋转左  (L)") { onCommand(.rotateLeft) }
            .disabled(!menuBarState.isQuickViewerPresenting)
        // ... 其它项 ...
    }
}
```

**Fallback 步骤 4 — GlanceApp 注入 menuBarState + onCommand closure**:

```swift
CommandMenu("图像") {
    ImageMenuCommands(
        menuBarState: appDelegate.menuBarState,
        onCommand: { MainQuickViewerWindowController.shared.performCommand($0) }
    )
}
```

后续任务 C/D/E 全部按 fallback 同模式: 各 commands view 直接 @ObservedObject menuBarState, 不再持 qvController 引用。

- [ ] **A.9: commit 任务 A 框架(不 push, 等任务 B 一起)**

```bash
git add Glance/MenuBar/SearchOverlayState.swift \
        Glance/MenuBar/InspectorState.swift \
        Glance/QuickViewer/MainQuickViewerWindowController+Commands.swift \
        Glance/MenuBar/MenuBarCommands.swift \
        Glance/GlanceApp.swift \
        Glance/ContentView.swift \
        Glance/QuickViewer/QuickViewerOverlay.swift

git commit -m "$(cat <<'EOF'
feat(菜单栏增补-A): facade 框架 + spike probe (SearchOverlayState / InspectorState / 命令 closure registry)

任务 A 前置 spike + 框架:
- 新建 SearchOverlayState (trigger event 模式 D-mb-9.1)
- 新建 InspectorState (双向 sync D-mb-9.1)
- 新建 MainQuickViewerWindowController+Commands.swift extension (closure registry D-mb-9.2)
- 新建 MenuBarCommands.swift 5 个 commands view 空骨架 (B-E 填充)
- GlanceApp AppDelegate 加 2 单例 + 临时 SpikeProbeCommands (任务 B 替换)
- ContentView 加 .onReceive(searchOverlayState.$triggerToken.dropFirst()) listener + InspectorState 双向 sync (不动既有 .onKeyPress)
- Overlay onAppear 注册 11 closure + trash + hasImage; onDisappear 清空

spike PENDING 1 项 (军哥本机验):
- 窗口菜单「[SPIKE] 旋转左 (L)」disable/enable 随快速看图器开关切换

不单独 ship — 任务 B 合并后一起 push。
EOF
)"
```

---

## 任务 B — 文件菜单 + 窗口菜单(跟任务 A 合并 ship)

**Files:**
- Modify: `Glance/MenuBar/MenuBarCommands.swift` (FileMenuCommands / WindowMenuCommands 已在 A.4 加, B 验证内容)
- Modify: `Glance/GlanceApp.swift` (删 SpikeProbeCommands + 挂真实 FileMenuCommands + WindowMenuCommands)

### 步骤拆分

- [ ] **B.1: GlanceApp.body 替换 spike + 挂文件菜单 + 窗口菜单**

修改 `Glance/GlanceApp.swift` body:

```swift
var body: some Scene {
    Settings {
        EmptySettingsView()
    }
    .commands {
        CommandGroup(replacing: .appInfo) {
            AboutMenuButton()
        }
        // 任务 B — 文件菜单「添加文件夹根…」
        CommandGroup(after: .newItem) {
            FileMenuCommands(folderStore: appDelegate.folderStore)
        }
        // 任务 B — 窗口菜单「图库主窗」
        CommandGroup(after: .windowList) {
            WindowMenuCommands(
                bookmarkManager: appDelegate.bookmarkManager,
                folderStore: appDelegate.folderStore,
                appState: appDelegate.appState,
                indexStoreHolder: appDelegate.indexStoreHolder,
                mainWindowController: MainWindowController.shared
            )
        }
    }
}
```

- [ ] **B.2: verify build**

跑 `make build`:

```bash
make build 2>&1 | tail -10
```

期望: BUILD SUCCEEDED, 0 errors, 0 code warnings。

- [ ] **B.3: 真机 spike (PENDING 任务 B 1 项)**

军哥本机验:
- 启动 app → 文件菜单看到「添加文件夹根…」→ 点击弹 NSOpenPanel → 选目录 → 侧边栏出现新文件夹根
- 主窗 ⌘W 关窗驻留 → 窗口菜单看「图库主窗」→ 点击 → 主窗 reopen

- [ ] **B.4: commit + push (合并任务 A)**

```bash
git add Glance/GlanceApp.swift

git commit -m "$(cat <<'EOF'
feat(菜单栏增补-B): 文件菜单「添加文件夹根…」+ 窗口菜单「图库主窗」reopen

任务 B 跟任务 A 合并 ship (codex v2 P2-2 任务 A 不单独 ship).

改动:
- GlanceApp.body.commands 删 SpikeProbeCommands (任务 A.8 spike)
- 挂 CommandGroup(after: .newItem) { FileMenuCommands } — 添加文件夹根 → FolderStore.addFolder()
- 挂 CommandGroup(after: .windowList) { WindowMenuCommands } — 图库主窗 reopen, hide when hasWindow

PENDING 2 项 (军哥本机验):
- 文件菜单 添加文件夹根… NSOpenPanel → 选目录 → 侧边栏新根
- 主窗关窗驻留态下 窗口菜单 → 图库主窗 → reopen 主窗
EOF
)"

git push 2>&1 | tail -3
```

---

## 任务 C — 编辑菜单 3 项(查找 / 复制图 / 复制路径)

**Files:**
- Modify: `Glance/MenuBar/MenuBarCommands.swift` (填充 EditMenuCommands)
- Modify: `Glance/GlanceApp.swift` (挂 EditMenuCommands)

### 步骤拆分

- [ ] **C.1: 填充 EditMenuCommands**

修改 `Glance/MenuBar/MenuBarCommands.swift` 的 `EditMenuCommands`:

```swift
struct EditMenuCommands: View {
    @ObservedObject var searchOverlayState: SearchOverlayState
    @ObservedObject var qvController: MainQuickViewerWindowController

    var body: some View {
        Group {
            // D-mb-3 / D-mb-7 — 手工拼快捷键 hint, 零 .keyboardShortcut (方向 Y)
            Button("查找…  (⌘F)") {
                searchOverlayState.requestOpen()
            }

            Divider()

            Button("复制图片  (⌘C)") {
                qvController.performCommand(.copyImage)
            }
            .disabled(!qvController.hasCurrentImage)

            Button("复制路径  (⌘⌥C)") {
                qvController.performCommand(.copyPath)
            }
            .disabled(!qvController.isPresenting)
        }
    }
}
```

**注意**: 复制图片用 `hasCurrentImage` (要求图加载成功, mirror QV contextMenu `.disabled(viewModel.currentNSImage == nil)`); 复制路径用 `isPresenting` (有 URL 就行, 图可能正加载中)。

- [ ] **C.2: GlanceApp.body 挂 EditMenuCommands**

修改 `Glance/GlanceApp.swift` body, 在 `.commands` 块内既有 CommandGroup 后加:

```swift
// 任务 C — 编辑菜单 3 项
CommandGroup(after: .pasteboard) {
    EditMenuCommands(
        searchOverlayState: appDelegate.searchOverlayState,
        qvController: MainQuickViewerWindowController.shared
    )
}
```

- [ ] **C.3: verify build**

```bash
make build 2>&1 | tail -10
```

期望: BUILD SUCCEEDED, 0 errors, 0 code warnings。

- [ ] **C.4: commit + push**

```bash
git add Glance/MenuBar/MenuBarCommands.swift Glance/GlanceApp.swift

git commit -m "$(cat <<'EOF'
feat(菜单栏增补-C): 编辑菜单 3 项 (查找 / 复制图 / 复制路径)

改动:
- MenuBarCommands.swift 填充 EditMenuCommands
  - 「查找…  (⌘F)」永远 enable → searchOverlayState.requestOpen()
  - 「复制图片  (⌘C)」disable when !hasCurrentImage → qvController.performCommand(.copyImage)
  - 「复制路径  (⌘⌥C)」disable when !isPresenting → qvController.performCommand(.copyPath)
- GlanceApp 挂 CommandGroup(after: .pasteboard) { EditMenuCommands }

零 .keyboardShortcut 挂载 (方向 Y D-mb-3), 文本字符串「(⌘C)」/「(⌘⌥C)」hint.

PENDING 4 项 (军哥本机验):
- 编辑菜单看 查找/复制图/复制路径 3 项
- 主窗状态下 复制图/复制路径 灰
- 双击进快速看图器后 复制图/复制路径 enable
- 主窗按 ⌘F 弹 search overlay; 菜单点查找等效
EOF
)"

git push 2>&1 | tail -3
```

---

## 任务 D — 图像菜单 6 项(旋转 L/R + 翻转 H/V + Finder + 废纸篓)

**Files:**
- Modify: `Glance/MenuBar/MenuBarCommands.swift` (填充 ImageMenuCommands)
- Modify: `Glance/GlanceApp.swift` (挂 CommandMenu("图像"))

### 步骤拆分

- [ ] **D.1: 填充 ImageMenuCommands**

修改 `Glance/MenuBar/MenuBarCommands.swift` 的 `ImageMenuCommands`:

```swift
struct ImageMenuCommands: View {
    @ObservedObject var qvController: MainQuickViewerWindowController

    var body: some View {
        Group {
            // 旋转
            Button("旋转左  (L)") {
                qvController.performCommand(.rotateLeft)
            }
            .disabled(!qvController.isPresenting)

            Button("旋转右  (R)") {
                qvController.performCommand(.rotateRight)
            }
            .disabled(!qvController.isPresenting)

            Divider()

            // 翻转 (无快捷键)
            Button("水平翻转") {
                qvController.performCommand(.toggleFlipH)
            }
            .disabled(!qvController.isPresenting)

            Button("垂直翻转") {
                qvController.performCommand(.toggleFlipV)
            }
            .disabled(!qvController.isPresenting)

            Divider()

            // Finder 显示
            Button("在 Finder 中显示  (⌘⇧R)") {
                qvController.performCommand(.revealInFinder)
            }
            .disabled(!qvController.isPresenting)

            Divider()

            // 移到废纸篓 (async)
            Button("移到废纸篓  (⌫)") {
                Task { await qvController.performTrash() }
            }
            .disabled(!qvController.isPresenting)
        }
    }
}
```

**注意**: 所有项用 `!isPresenting` 简单 disable(快速看图器不在就 disable), 不二次检查 `hasCurrentImage` 因为旋转/翻转在图加载中也合理(只动 viewModel state, 不需要 image data)。

- [ ] **D.2: GlanceApp.body 挂 ImageMenuCommands 全新顶级 CommandMenu**

修改 `Glance/GlanceApp.swift` body, 在 `.commands` 块内继续加:

```swift
// 任务 D — 图像菜单 6 项 (全新顶级菜单)
CommandMenu("图像") {
    ImageMenuCommands(qvController: MainQuickViewerWindowController.shared)
}
```

- [ ] **D.3: verify build**

```bash
make build 2>&1 | tail -10
```

期望: BUILD SUCCEEDED, 0 errors, 0 code warnings。

- [ ] **D.4: 真机验证「图像」菜单位置 (R-mb-16)**

军哥本机验:
- 启动 app → 顶部菜单栏新出现「图像」菜单
- 位置 = 显示和窗口之间 (CommandMenu macOS 14 顶级菜单默认追加, 实际位置真机看)
- 如果位置不对(例如出现在帮助之前), R-mb-16 触发, 接受 macOS 14 默认位置不强求

- [ ] **D.5: commit + push**

```bash
git add Glance/MenuBar/MenuBarCommands.swift Glance/GlanceApp.swift

git commit -m "$(cat <<'EOF'
feat(菜单栏增补-D): 图像菜单 6 项 (旋转 L/R + 翻转 H/V + Finder + 废纸篓)

改动:
- MenuBarCommands.swift 填充 ImageMenuCommands
  - 「旋转左  (L)」/「旋转右  (R)」disable when !isPresenting → performCommand(.rotateLeft/.rotateRight)
  - 「水平翻转」/「垂直翻转」disable when !isPresenting (无快捷键)
  - 「在 Finder 中显示  (⌘⇧R)」disable when !isPresenting
  - 「移到废纸篓  (⌫)」disable when !isPresenting → async Task { performTrash() }
- GlanceApp 挂 CommandMenu("图像") { ImageMenuCommands } 全新顶级菜单

零 .keyboardShortcut 挂载, 文本字符串 hint.

PENDING 5 项 (军哥本机验):
- 顶部菜单栏新出现「图像」菜单 (位置: 显示和窗口之间)
- 主窗状态下 6 项全 disable (灰)
- 双击进快速看图器后 6 项全 enable
- 点旋转左 = 图旋转 90° (跟按 L 一样)
- 点移到废纸篓 = 走 trash flow (跟按 Delete 一样, 弹撤销 toast)
EOF
)"

git push 2>&1 | tail -3
```

---

## 任务 E — 显示菜单 5 项(信息切换 + 缩放系列 4 项)

**Files:**
- Modify: `Glance/MenuBar/MenuBarCommands.swift` (填充 ViewMenuCommands)
- Modify: `Glance/GlanceApp.swift` (挂 ViewMenuCommands)

### 步骤拆分

- [ ] **E.1: 填充 ViewMenuCommands**

修改 `Glance/MenuBar/MenuBarCommands.swift` 的 `ViewMenuCommands`:

```swift
struct ViewMenuCommands: View {
    @ObservedObject var inspectorState: InspectorState
    @ObservedObject var qvController: MainQuickViewerWindowController
    @ObservedObject var folderStore: FolderStore

    var body: some View {
        Group {
            // D-mb-8 — 动态文案: 信息切换
            Button(inspectorState.isShown ? "隐藏信息  (⌘I)" : "显示信息  (⌘I)") {
                inspectorState.isShown.toggle()
            }
            .disabled(folderStore.selectedImageIndex == nil)

            Divider()

            // 缩放系列 (快速看图器在场时 enable)
            Button("适合窗口  (⌘0)") {
                qvController.performCommand(.resetToFit)
            }
            .disabled(!qvController.isPresenting)

            Button("实际大小  (0)") {
                qvController.performCommand(.resetToOneToOne)
            }
            .disabled(!qvController.isPresenting)

            Button("放大  (⌘=)") {
                qvController.performCommand(.zoomIn)
            }
            .disabled(!qvController.isPresenting)

            Button("缩小  (⌘−)") {
                qvController.performCommand(.zoomOut)
            }
            .disabled(!qvController.isPresenting)
        }
    }
}
```

**注意**: 缩小用 `⌘−` 全角破折号(U+2212 Minus Sign), 跟 QV 工具栏 / contextMenu 既有 `「缩小 (⌘-)」` 半角对齐? — 检查项目既有约定 (任务 E.3 verify check)。

- [ ] **E.2: GlanceApp.body 挂 ViewMenuCommands**

修改 `Glance/GlanceApp.swift` body, 在 `.commands` 块内继续加:

```swift
// 任务 E — 显示菜单 5 项
CommandGroup(after: .sidebar) {
    ViewMenuCommands(
        inspectorState: appDelegate.inspectorState,
        qvController: MainQuickViewerWindowController.shared,
        folderStore: appDelegate.folderStore
    )
}
```

**注意 R-mb-15**: `CommandGroup(after: .sidebar)` 在 macOS 14 显示菜单实际位置未验。任务 E.4 真机验; 不对则改用 `CommandMenu("显示")` 替代。

- [ ] **E.3: 项目术语字典 - / − 一致性检查**

```bash
grep -n "缩小" Glance/QuickViewer/QuickViewerOverlay.swift Glance/DesignSystem.swift
```

如果项目既有用半角 `-`, 任务 E.1 改回 `「缩小  (⌘-)」`(全角不一致); 如果用全角 `−`, 保持。

- [ ] **E.4: verify build**

```bash
make build 2>&1 | tail -10
```

期望: BUILD SUCCEEDED, 0 errors, 0 code warnings。

- [ ] **E.5: 真机验证 (R-mb-15 + R-mb-12)**

军哥本机验:
- 启动 app → 显示菜单看 5 项 (信息切换 + 适合/1:1/放大/缩小)
- 显示菜单位置 = 系统 sidebar 子菜单之后 (R-mb-15 验证)
- 双击进快速看图器 → 切 Inspector → 菜单文案切换「隐藏信息」/「显示信息」(D-mb-8 动态文案)
- 改完 .commands 必须**重启 app** (R-mb-12 hot reload 警示)

- [ ] **E.6: commit + push**

```bash
git add Glance/MenuBar/MenuBarCommands.swift Glance/GlanceApp.swift

git commit -m "$(cat <<'EOF'
feat(菜单栏增补-E): 显示菜单 5 项 (信息切换 + 缩放系列)

改动:
- MenuBarCommands.swift 填充 ViewMenuCommands
  - 「显示信息 / 隐藏信息  (⌘I)」动态文案 (D-mb-8) — 绑 InspectorState.isShown.toggle()
  - 「适合窗口  (⌘0)」/「实际大小  (0)」disable when !isPresenting
  - 「放大  (⌘=)」/「缩小  (⌘-)」disable when !isPresenting
- GlanceApp 挂 CommandGroup(after: .sidebar) { ViewMenuCommands }

零 .keyboardShortcut 挂载, 文本字符串 hint.
信息切换动态文案双向 sync: ContentView showInspector ⇄ InspectorState.isShown.

PENDING 4 项 (军哥本机验):
- 显示菜单看 5 项 (位置 = sidebar 系统子菜单之后)
- 主窗未选图时 显示信息 灰
- 双击进快速看图器 + 切 Inspector → 文案切换
- 主窗状态下 缩放 4 项 全 disable
EOF
)"

git push 2>&1 | tail -3
```

---

## 任务 F — 任务收尾(verify / 文档同步 / PENDING / commit / push)

**Files:**
- Modify: `specs/Roadmap.md` (Bug Fix 段加 row)
- Modify: `CLAUDE.md` (文件结构加 Glance/MenuBar/*.swift)
- Modify: `specs/PENDING-USER-ACTIONS.md` (加菜单栏 section)

### 步骤拆分

- [ ] **F.1: 跑 verify 三段**

```bash
./scripts/verify.sh 2>&1 | tail -30
```

期望: 14 passed, 0 failed。

**R-mb-12 检查**: 改完 .commands 必须重启 app 验证菜单结构生效(不信 Xcode preview hot reload)。

- [ ] **F.2: Roadmap.md 加 row**

按既有 Bug Fix 段格式 (mirror commit `66ab9fa` 快速看图器增强 row):

修改 `specs/Roadmap.md` 在 Bug Fix 段开头插入:

```markdown
| 菜单栏增补 第一批（本次, 2026-06-18 ship 7 commit）| **独立子系统 ship 第一批 16 项菜单**: 把 16 项常用动作挂主窗 macOS 菜单栏 (文件 1 / 编辑 3 / 显示 5 / 图像 6 / 窗口 1), 方向 Y 零 .keyboardShortcut 挂载 (D-mb-3, 共享快捷键现状全保留), 全用菜单文本字符串「(⌘C)」/「(L)」/「(⌫)」hint。design v2.1 commit `a6a216b` (codex v1 RESHAPE → v2 APPROVE-WITH-FIXES → v2.1 收紧, 共 3 轮 codex review + 军哥拍方向 Y + 拆两批)。改动: 新建 4 文件 (SearchOverlayState / InspectorState / MenuBarCommands / MainQuickViewerWindowController+Commands) + 改 3 文件 (GlanceApp / ContentView / QuickViewerOverlay); 不动 viewModel ownership (closure registry 模式 D-mb-9.2); 不动既有 ⌘F .onKeyPress 路径 (trigger event 模式 D-mb-9.1)。verify.sh 三段全过 (0 error 0 warning), 0 self-fix 单轮过。PENDING 20 项军哥本机肉眼验。全屏菜单 + 共享快捷键路由方向决策 留第二批 design v3。|
```

- [ ] **F.3: CLAUDE.md 文件结构加 Glance/MenuBar/**

修改 `CLAUDE.md` 在文件结构段, 找 `Glance/MainWindow/` 描述后加:

```markdown
    ├── MenuBar/                  ← 2026-06-18 菜单栏增补 第一批 (D-mb-* 决策, 方向 Y)
    │   ├── SearchOverlayState.swift          ← trigger event 模式 (@Published triggerToken UUID), ContentView 仍 sole state owner, .onReceive listener 调原 openSearch (D-mb-9.1)
    │   ├── InspectorState.swift              ← 双向 sync (@Published isShown Bool), ContentView showInspector ⇄ InspectorState (D-mb-9.1)
    │   └── MenuBarCommands.swift             ← 5 commands view struct (FileMenuCommands / EditMenuCommands / ViewMenuCommands / ImageMenuCommands / WindowMenuCommands), 16 项菜单零 .keyboardShortcut + 文本字符串 hint (D-mb-3 / D-mb-7)
```

修改 `CLAUDE.md` 在 `Glance/QuickViewer/` 描述末尾加:

```markdown
    │   └── MainQuickViewerWindowController+Commands.swift ← 2026-06-18 菜单栏增补 D-mb-9.2 closure registry 模式; enum QuickViewerCommand + register/clear/performCommand/performTrash; 不动 viewModel ownership; Overlay onAppear/onDisappear 自管 lifecycle
```

- [ ] **F.4: PENDING-USER-ACTIONS.md 加菜单栏 section**

修改 `specs/PENDING-USER-ACTIONS.md`, 在末尾追加:

```markdown
---

### V2 菜单栏增补 第一批 — 文件/编辑/显示/图像/窗口 16 项 + 框架(2026-06-18 ship 待真机验)

> 第一批 ship `<HEAD-sha>` (任务 A+B 合并 + C + D + E + F 共 6 commit, 7 commit 含 F 文档 commit)。verify.sh 三段全过(14/14, build 0 error 0 warning), subagent-driven 0 self-fix 单轮过。codex v1 RESHAPE → v2 APPROVE-WITH-FIXES → v2.1 收紧 3 轮 codex review; 方向 Y 零 .keyboardShortcut, 文本字符串 hint (D-mb-3 / D-mb-7); 第二批全屏 + 共享快捷键路由方向决策 留 design v3。

军哥本机肉眼验项:

**任务 A 框架 spike (1 项)**:
- [ ] (2026-06-18) **closure registry + commands @ObservedObject disable binding**: 启动 app → 窗口菜单看「图库主窗」disable/enable 随 hasWindow 切换 (此项任务 B 完成时实际等价于 R-mb-1 验证)

**任务 B 文件 + 窗口菜单 (2 项)**:
- [ ] (2026-06-18) **文件菜单 添加文件夹根…**: 文件菜单看见「添加文件夹根…」→ 点击弹 NSOpenPanel → 选目录 → 侧边栏出现新文件夹根
- [ ] (2026-06-18) **窗口菜单 图库主窗 reopen**: ⌘W 关主窗驻留 → 窗口菜单看「图库主窗」(主窗在时此项 hide) → 点击 reopen 主窗 + 数据状态恢复

**任务 C 编辑菜单 (4 项)**:
- [ ] (2026-06-18) **编辑菜单 3 项可见**: 编辑菜单看「查找…  (⌘F)」/「复制图片  (⌘C)」/「复制路径  (⌘⌥C)」(快捷键 hint 字符串拼在文本里)
- [ ] (2026-06-18) **主窗状态 复制项 disable**: 主窗状态下复制图/复制路径 灰显; 查找永远 enable
- [ ] (2026-06-18) **快速看图器在场 复制项 enable**: 双击进快速看图器 → 编辑菜单复制图/复制路径 enable → 点击 = 复制到 NSPasteboard (Slack/Finder/备忘录粘贴有图)
- [ ] (2026-06-18) **查找菜单 = ⌘F 等效**: 点编辑菜单查找… = 主窗弹 search overlay (跟按 ⌘F 一样); 按 ⌘F 仍弹 (现状不变, 不双触发)

**任务 D 图像菜单 (5 项)**:
- [ ] (2026-06-18) **图像菜单 6 项可见**: 顶部菜单栏出现「图像」顶级菜单 (位置 = 显示和窗口之间, R-mb-16 验证)
- [ ] (2026-06-18) **主窗状态 6 项全 disable**: 主窗状态下旋转/翻转/Finder/废纸篓 全灰
- [ ] (2026-06-18) **快速看图器在场 6 项全 enable**: 双击进快速看图器 → 6 项全 enable
- [ ] (2026-06-18) **菜单各项执行**: 点旋转左 = 图旋转 90° (跟 L 一样); 点 Finder = 弹 Finder 反白; 点移到废纸篓 = 走 trash flow + 弹撤销 toast
- [ ] (2026-06-18) **快捷键 hint 字符串**: 菜单文本里看到「(L)」/「(R)」/「(⌘⇧R)」/「(⌫)」字符串

**任务 E 显示菜单 (4 项)**:
- [ ] (2026-06-18) **显示菜单 5 项可见**: 显示菜单看「显示信息  (⌘I)」+ 缩放 4 项 (适合/1:1/放大/缩小, R-mb-15 验证位置 = sidebar 系统子菜单之后)
- [ ] (2026-06-18) **主窗未选图 信息项 disable**: 主窗状态下未选图时显示信息 灰
- [ ] (2026-06-18) **Inspector 切换动态文案**: 双击进快速看图器 + 切 Inspector → 显示菜单文案切「显示信息 / 隐藏信息」(D-mb-8 动态)
- [ ] (2026-06-18) **缩放系列 disable + enable**: 主窗状态缩放 4 项 全 disable; 快速看图器在场全 enable; 点适合窗口 = QV 适合 (跟按 ⌘0 一样)

**通用 (4 项)**:
- [ ] (2026-06-18) **菜单结构 5 顶级 + 16 项**: 5 顶级菜单 (文件/编辑/显示/图像/窗口) + 16 项菜单, 数量对照表正确
- [ ] (2026-06-18) **零键盘干扰**: app 内按 L 仍只在快速看图器内旋转, 主窗按 L 无反应 (现状不变); 按 ⌘C 仍只在快速看图器内复制图, 主窗按 ⌘C 无反应 (D-mb-3 方向 Y 已知设计选择)
- [ ] (2026-06-18) **改 .commands 必须重启验证 (R-mb-12)**: 真机改菜单结构后 Xcode preview hot reload 不刷新, 必须实际 cmd+Q 重启 app
- [ ] (2026-06-18) **a11y VoiceOver**: VoiceOver 读菜单项 + 快捷键 hint (例「复制图片 Command C」), 体验可接受 (D-mb-7 trade-off)

⚠️ 第二批 (全屏菜单 + 共享快捷键路由方向决策) 留 design v3, 本次第一批 ship 后用户反馈 1-2 周再决定。
```

- [ ] **F.5: 跑 verify 三段 (R-mb-12 包括)**

```bash
./scripts/verify.sh 2>&1 | tail -30
```

期望: 14 passed, 0 failed。

- [ ] **F.6: CLAUDE.md 关键架构决策段补行 (codex plan P1 修)**

按 CLAUDE.md「文档同步强制规则」表的「架构或交互逻辑变化」类型, 必须更新「关键架构决策」段 (项目走 `specs/Roadmap.md` 「关键架构决策」段, 无独立 docs/adr/)。

修改 `specs/Roadmap.md` 在「关键架构决策」段尾追加:

```markdown
- **D-mb-9 (2026-06-18)**: 菜单栏增补 第一批采用 trigger event + closure registry 双 facade 模式 — SearchOverlayState 只持 `@Published triggerToken UUID` (ContentView 仍是 search overlay sole state owner); MainQuickViewerWindowController 加 `commandHandlers` registry + Overlay onAppear 注册/onDisappear 清空 (不动 viewModel ownership)。**核心权衡**: 不全提升 state 到全局层 (避 V2 M3 chips / M4 五态互斥大面积重构), 仅暴露 trigger + closure 桥接面给菜单栏。**Why 这是关键决策**: 后续菜单/工具栏入口扩展都应沿此模式, 不开新桥接路径; 第二批 design v3 全屏菜单 + 共享快捷键路由方向决策若选方向 X (Commands 接管), 需要重新评估此模式扩展性。
```

- [ ] **F.7: commit + push**

```bash
git add specs/Roadmap.md CLAUDE.md specs/PENDING-USER-ACTIONS.md

git commit -m "$(cat <<'EOF'
docs(菜单栏增补): 第一批 ship 文档同步 + PENDING 20 项军哥本机肉眼验 [docs-only]

任务 A+B+C+D+E 共 6 commit ship 完, 任务 F 收尾文档同步:
- Roadmap.md Bug Fix 段加 row (16 项菜单 + 方向 Y 零 .keyboardShortcut + closure registry)
- Roadmap.md 关键架构决策段加 D-mb-9 行 (trigger event + closure registry 双 facade 模式)
- CLAUDE.md 文件结构加 Glance/MenuBar/3 新文件 + Glance/QuickViewer/+Commands.swift extension
- PENDING-USER-ACTIONS.md 加菜单栏 section 20 项军哥本机肉眼验

⚠️ 第二批 (全屏菜单 + 共享快捷键路由方向决策) 留 design v3, 本次第一批 ship 后用户反馈 1-2 周再决定。
EOF
)"

git push 2>&1 | tail -3
```

- [ ] **F.8: 一段话汇报军哥**

例:
> **BUILD SUCCEEDED — 0 errors, 0 code warnings** (版本 `<commit>-d.<MMDD-HHMM>`, HEAD = `<sha>`)
>
> 菜单栏增补第一批 ship 完。改动: 新建 4 文件 + 改 3 文件; 方向 Y 零 .keyboardShortcut, 文本字符串 hint; closure registry 不动 viewModel ownership; 7 commit 单轮 0 self-fix 全过。
>
> PENDING 20 项军哥本机肉眼验, 任务 A 框架 spike 1 项 + 任务 B 文件/窗口 2 项 + 任务 C 编辑 4 项 + 任务 D 图像 5 项 + 任务 E 显示 4 项 + 通用 4 项。
>
> 总 PENDING 进度: <现有总数> + 20 = <新总数> 项。
>
> 第二批全屏 + 共享快捷键路由方向决策留 design v3。

---

## 任务 X 完成详细 (实施时填)

实施时每个任务完成后在这里追加详细记录, mirror 既有 plan「Slice X 完成详细」表风格。

### 任务 A 完成详细 (TBD)

| 步骤 | commit | 备注 |
|---|---|---|
| A.1 SearchOverlayState | `<sha>` | |
| ... | | |

### 任务 B 完成详细 (TBD)

### 任务 C 完成详细 (TBD)

### 任务 D 完成详细 (TBD)

### 任务 E 完成详细 (TBD)

### 任务 F 完成详细 (TBD)

---

## 关联

- **前置 design**: [`specs/v2/2026-06-18-menu-bar-design.md`](2026-06-18-menu-bar-design.md) (v2.1, commit `a6a216b`)
- **前置 followup**: 主窗 detail 工具栏查找按钮 (`2db5372`)
- **同源**: 快速看图器增强独立子系统 (`8525e18`..`66ab9fa`)
- **下游**: 第一批 ship 后第二批 design v3 (全屏菜单 + 共享快捷键路由方向决策)
- **术语字典**: 「菜单栏」「快捷键」「工具栏」「快速看图器」「侧边栏」按 CONTEXT.md 规范使用
