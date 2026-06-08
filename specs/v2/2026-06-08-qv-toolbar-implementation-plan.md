# QV toolbar regression 修复实施 Plan — 方案 2 独立无装饰 QV 窗

> **执行方式**：subagent-driven-development（一 task 一 subagent，task 间 review）。步骤用 `- [ ]` 跟踪。
> **设计源**：`specs/v2/2026-06-08-qv-toolbar-design.md`（D-QVT1~7）。
> **版本**：v2（已过两轮 codex review：design review + plan review，本稿吸收 plan review 全部 P0/P1/P2）。

**Goal**：主窗 QV/全屏看图时 titlebar 完全纯净（同外部看图窗），grid/sidebar 状态与 QV 既有交互全不退化。

**Architecture**：主窗 QV 从 `ContentView` 内 `.overlay { QuickViewerOverlay }` 改为新单例 `MainQuickViewerWindowController` 管理的 top-level 同框无装饰 NSWindow（复用 `ExternalViewerWindowController` 已验证纯净模式）。主窗 ContentView 视图树保持挂载 → 状态天然保留。

**Tech Stack**：SwiftUI + AppKit（NSWindow/NSWindowDelegate）+ NSHostingView。macOS 14+。

---

## ⚠️ 项目特化约定（读 CLAUDE.md）

1. **跳 TDD**：无 XCTest target。每 task 验收 = `./scripts/verify.sh`（grep 规则 + `xcodebuild build` 零 error 零新 warning + 单测占位）+ 真机验项追加 `specs/PENDING-USER-ACTIONS.md`（Mac mini 无 GUI，窗口/全屏/focus 只能军哥真机验）。
2. **重灾区给契约不给死代码**：窗口/focus/全屏反复翻车区（3 轮死结）。本 plan 给**接口契约 + 改动清单 + 状态规格 + 真机验门控**，新文件给完整骨架，但全屏/时序不预写未验证死代码。subagent 每 task 读现状 + 按契约实现 + 真机验驱动。

## 🔑 统一机制（plan review 后确立，贯穿全 plan）

**QVDismissalReason** — QV 所有关闭路径带 reason，统一在主窗 become-key 后由 `onDismiss(reason:entry:)` 一次回调分派。一举解决：close completion / dismissal reason / ⌘F·找类似跨窗次序 / focus 时序。
```swift
enum QVDismissalReason {
    case normal            // ESC / 关闭按钮 / ⌘W / images 变化外部关 → 按 entry 路由焦点
    case findSimilar(URL)  // QV 内点找类似 → 关 QV 后主窗 handleFindSimilar(url)
    case commandF          // QV 内 ⌘F → 关 QV 后主窗 openSearch()
}
```

**MainQuickViewerWindowController 公开契约**（Task 1.1 一次定全，后续 slice 复用）：
```swift
@MainActor
final class MainQuickViewerWindowController: NSObject, ObservableObject {
    static let shared = MainQuickViewerWindowController()

    @Published private(set) var isPresenting: Bool = false   // 替代 quickViewerIndex 哨兵

    /// 打开/复用 QV 窗。currentSupportsFeaturePrint 是固定 Bool（进 QV 时算，mirror 现状
    /// ContentView:253，QV 内不随 index 更新 — 保持现状，不引入闭包，YAGNI）。
    func show(images: [URL], startIndex: Int, entry: QuickViewerEntry,
              mainWindow: NSWindow,
              currentSupportsFeaturePrint: Bool,
              onIndexChange: @escaping (Int) -> Void,
              onDismiss: @escaping (QVDismissalReason, QuickViewerEntry) -> Void)

    /// 统一关闭。reason 透传给 onDismiss（在主窗 become-key 后触发）。幂等
    /// （controller close / 主窗 close / 快捷键可同时命中）。
    func close(reason: QVDismissalReason)
}
```
> controller 内部把 QuickViewerOverlay 的 `onFindSimilar`/`onCommandF`/`onDismiss` 全转成 `close(reason:)`：
> `onFindSimilar = { close(reason: .findSimilar($0)) }` / `onCommandF = { close(reason: .commandF) }` / `onDismiss = { close(reason: .normal) }`。
> QuickViewerOverlay init **不改**（已有这些参数）。

---

## File Structure

| 文件 | 动作 | 责任 |
|---|---|---|
| `Glance/QuickViewer/MainQuickViewerWindowController.swift` | **新建** | 单例，top-level 同框无装饰窗 + viewerAppState + 全屏状态机 + 父窗协调 + dismissal reason 分派 |
| `Glance/MainWindow/MainWindowController.swift` | 改 | 新增 one-shot「after-next-become-key」回调注册 API（focus 4 步地基，plan review P1） |
| `Glance/ContentView.swift` | 改 | 4 入口改调 controller / 移除 overlay+`:295`+动画 / quickViewerIndex 全量 16 处迁移（含 `:691` findSimilar、`:734-736` openSearch）/ 拆 isPresenting / handleQVDismiss(reason:entry:) |
| `Glance/QuickViewer/QuickViewerOverlay.swift` | Slice 2 微调 | 全屏输入（F）改经 controller 注入路由，不直接 `appState.toggleFullScreen()`（plan review P1）。Slice 1 不动 |

---

# Slice 1 — 最小可用纯净看图（windowedCover 态）

> ✅ **实施完成 + 真机验 9 项全过（2026-06-08，commit `ebd88bf`~`4cb1323`）**。下方 task 步骤为执行记录，全部已落地。

**Ship 价值**：4 入口进 QV titlebar 完全纯净，退出回原位 focus 正确，找类似/⌘F 不退化。全屏鲁棒留 Slice 2。**独立可 ship**。

### Task 1.1：契约骨架（QuickViewerEntry internal + QVDismissalReason + controller 公开面 + become-key API）

**Files**：Create `Glance/QuickViewer/MainQuickViewerWindowController.swift`；Modify `Glance/ContentView.swift`（QuickViewerEntry）、`Glance/MainWindow/MainWindowController.swift`

- [ ] **Step 1**：`ContentView.swift:25` 的 `private enum QuickViewerEntry` 去 private 提文件级 internal。grep 确认 `.grid/.preview/.ephemeral` 引用不破。
- [ ] **Step 2**：定义 `enum QVDismissalReason`（见上）于 controller 文件。
- [ ] **Step 3**：建 controller 骨架（mirror ExternalViewerWindowController createWindow：NSHostingView 当 contentView / `titleVisibility=.hidden` / `titlebarAppearsTransparent=true` / `isReleasedWhenClosed=false` / `.fullScreenPrimary` / 自任 delegate）+ 专属 `viewerAppState = AppState()` + `@Published isPresenting`。**砍** ViewerSession/scope/terminateOnClose/retiredSessions。`show`/`close` 留签名 + 空实现。
- [ ] **Step 4**：`MainWindowController` 加 one-shot become-key API（plan review P1，focus 4 步地基）：
  ```swift
  // 注册一个「主窗下次 become key 后执行一次」的回调（可带 expected window 校验）。
  func runAfterNextBecomeKey(_ block: @escaping () -> Void)
  ```
  `windowDidBecomeKey` 内：先 `appState.attachWindow(win)`（现状），再 drain 匹配回调（建议 `Task { @MainActor in await Task.yield(); block() }`）。
- [ ] **Step 5**：verify 编译。
- [ ] **Step 6**：commit `feat(QV): controller 契约骨架 + QVDismissalReason + MainWindowController become-key API`

### Task 1.2：controller show/close + 同框 frame + focus 4 步时序（windowedCover）

**Files**：Modify `Glance/QuickViewer/MainQuickViewerWindowController.swift`

- [ ] **Step 1**：`show(...)`：存 onIndexChange/onDismiss/entry/mainWindow 引用；`hosting.rootView = QuickViewerOverlay(images:startIndex:onDismiss:{close(.normal)}, onIndexChange:存的, onFindSimilar:{close(.findSimilar($0))}, currentSupportsFeaturePrint:传入, onCommandF:{close(.commandF)}).environmentObject(viewerAppState).id(每次 show 换 UUID)`；`viewerAppState.attachWindow(win)`；`win.setFrame(mainWindow.frame, display:true)`（同框）；`makeKeyAndOrderFront`+`NSApp.activate`；`isPresenting=true`。
- [ ] **Step 2**：`close(reason:)`（**幂等**：已在关闭中则忽略）：记 reason+entry → `window?.close()`。
- [ ] **Step 3**：`windowWillClose` delegate（**focus 4 步，D-QVT7**）：
  1. （prepareDismiss 已在 close 时做非焦点清理）`viewerAppState.isFullScreen=false` + `viewerAppState.detachWindow` + `isPresenting=false`；
  2. 捕获 reason+entry 到局部（**在清 closure 前**，plan review 警告 6）；
  3. `MainWindowController.shared.runAfterNextBecomeKey { onDismiss(reason, entry) }`；
  4. `mainWindow.makeKeyAndOrderFront(nil)` + activate；
  5. 清存的 closure（防持过期 ContentView）。
  **不在此处设 focusTarget**（主 hosting 尚未 key，SwiftUI 丢弃）。
- [ ] **Step 4**：同框跟随最小集：监听 mainWindow `didMove`/`didResize` → `win.setFrame(main.frame, display:true)`（完整集留 Slice 2）。
- [ ] **Step 5**：verify 编译。
- [ ] **Step 6**：commit `feat(QV): show/close + 同框 frame + dismissal focus 4 步时序`

### Task 1.3：ContentView 原子迁移（4 入口 + 移除 overlay + quickViewerIndex 全量 16 处）

> **plan review P0：本 task 必须一次完成、一次编译通过、一次 commit。** 中间不留半迁移态（quickViewerIndex 删除后 :691/:734 等会断编译）。

**Files**：Modify `Glance/ContentView.swift`

- [ ] **Step 1**：观察 controller：`@ObservedObject private var qvController = MainQuickViewerWindowController.shared`。
- [ ] **Step 2**：写 `presentQuickViewer(images:startIndex:entry:)` helper：取 `appState.window` 主窗 → `qvController.show(images:startIndex:entry:mainWindow:currentSupportsFeaturePrint: currentSupportsFeaturePrint(at:startIndex), onIndexChange:{ folderStore.selectedImageIndex = $0 }, onDismiss: handleQVDismiss)`。
- [ ] **Step 3**：写 `handleQVDismiss(reason:entry:)`（主窗已 become-key 后触发）：
  - `.normal` → 原 `:262` switch（.grid→清 selectedImageIndex+focusTarget=.grid / .preview→focusTarget=.preview / .ephemeral→清 selectedImageIndex+focusTarget=.ephemeral / 兜底→currentEphemeral != nil ? .ephemeral : .grid）
  - `.findSimilar(let url)` → `handleFindSimilar(sourceUrl: url)`（其内部设 ephemeral+焦点）
  - `.commandF` → `openSearch()`
- [ ] **Step 4**：改 4 入口为 `presentQuickViewer(...)`：`:399` ephemeral（images=req.urls）/ `:494` SmartFolder（images=computeV2Urls()）/ `:508` ImageGrid（images=folderStore.images）/ `:530` preview onQuickView（images 按 :234 规则）。
- [ ] **Step 5**：移除 `.overlay{ quickViewerIndex... }`（:231-258）+ `.animation(value:quickViewerIndex)`（:259）+ `.toolbar(...windowToolbar)`（:295）。**保留** `:300 .toolbarBackground(.hidden)`（plan review 确认）。
- [ ] **Step 6**：quickViewerIndex 全量 16 处迁移（plan review grep 清单，逐处）：删 `:122` state、`:124` quickViewerEntry state；`:185` allowsHitTesting→`!qvController.isPresenting`；`:262` onChange 块删（路由迁 handleQVDismiss）；`:313` preview-close guard→`!qvController.isPresenting`；`:320-321` images 变化→`qvController.close(reason:.normal)`；`:519/:521` previewOverlay 条件→`!qvController.isPresenting`；**`:691` handleFindSimilar 关 QV→删（findSimilar 现在走 dismissal reason，handleFindSimilar 由 onDismiss 触发，不自关）**；**`:734-736` openSearch 关 QV→删（⌘F 走 dismissal reason）**。
- [ ] **Step 7**：verify 编译 + `grep -n quickViewerIndex Glance/ContentView.swift` 零残留 + `grep -n quickViewerEntry` 零残留。
- [ ] **Step 8**：commit `refactor(QV): ContentView 原子迁移到 controller（4 入口+移除 overlay+quickViewerIndex 全清）`

### Slice 1 验收 + 真机验
- [ ] verify 三段全绿。
- [ ] 追加 `specs/PENDING-USER-ACTIONS.md`（Slice 1，含 plan review 补的项）：
  1. 4 入口（V1 grid/SmartFolder grid/preview/ephemeral）进 QV：**titlebar 完全纯净**，截图对比外部看图窗。
  2. QV 内方向键 → 退出后 grid highlight 跟随。
  3. QV 内找类似 → 关 QV 回 ephemeral grid 结果。
  4. QV 内 ⌘F → 关 QV + 主窗搜索框**真正拿到键盘焦点**（能打字，非只见 overlay）。
  5. 退出 QV：grid 缩略图无重载闪 / 滚动位置 / sidebar 展开态 / 列宽不变。
  6. **每条关闭路径**（ESC / Space / 关闭按钮 / ⌘W / 红绿灯）后主窗实际获得 key+front + entry focus 正确。
  7. 关 QV 后重开（callback + viewerAppState 重置正确）；已开着时再次双击不叠窗。
  8. QV 窗同框盖主窗 + 拖动主窗 QV 跟随。

---

# Slice 2 — 全屏 4 态状态机（D-QVT6）

> ✅ **实施完成（2026-06-08，commit `5d47b3c`~`01f60b9`），待真机验**（含 review 防御修复 I-1/I-3/M-1 + close transitioning guard + 主窗 willClose/miniaturize force close 防悬挂）。下方 task 步骤为执行记录，全部已落地。Task2.2+2.3 合并实施。

**Ship 价值**：全屏看图纯净 + 正确 ESC + 主窗已全屏下进 QV 正常。**独立可 ship**。

### Task 2.1：QV 全屏输入经 controller 拦截（状态机前提，plan review P1）

**Files**：Modify `Glance/QuickViewer/QuickViewerOverlay.swift` + controller

- [ ] **Step 1**：QuickViewerOverlay 现直接调 `appState.toggleFullScreen()`（grep :174/:309 等）+ 读 `appState.isFullScreen`（:407）。改为经 controller 注入的 closure（如 `onToggleFullScreen: () -> Void`，默认透传 viewerAppState.toggleFullScreen 保持 ExternalViewer 等其它调用方不变）→ controller 接管，按状态机决定 toggle QV 窗还是主窗。
- [ ] **Step 2**：verify 编译（确认 ExternalViewerWindowController 等其它 QuickViewerOverlay 调用方不破）。
- [ ] **Step 3**：commit `refactor(QV): 全屏输入经 controller 路由（不直接调 AppState）`

### Task 2.2：presentation 4 态状态机 + fullScreenAuxiliary 继承

**Files**：Modify controller

- [ ] **Step 1**：`enum Presentation { case windowedCover, qvNativeFullScreen, inheritedMainFullScreen, transitioning }`。show 时按 `mainWindow.styleMask.contains(.fullScreen)` 判初始：主窗已全屏→`inheritedMainFullScreen`（QV collectionBehavior `.fullScreenAuxiliary`，orderFront 到主窗全屏 Space 上层，**不 toggleFullScreen**）；否则 `windowedCover`（`.fullScreenPrimary`）。
- [ ] **Step 2**：QV delegate `windowDidEnterFullScreen`/`windowDidExitFullScreen` 驱动 viewerAppState.isFullScreen + presentation 转移（不只镜像 delegate）。
- [ ] **Step 3**：`transitioning` 拦截重复 F/show/close。
- [ ] **Step 4**：verify 编译。
- [ ] **Step 5**：commit `feat(QV): 全屏 4 态状态机 + fullScreenAuxiliary 继承主窗全屏`

### Task 2.3：F + 首/次 ESC 全屏交互 + frame 跟随补全

**Files**：Modify controller

- [ ] **Step 1**：windowedCover F → QV toggleFullScreen 进 qvNativeFullScreen；qvNativeFullScreen F/ESC → 退回 windowedCover。
- [ ] **Step 2**：inheritedMainFullScreen 首 F/首 ESC → `mainWindow.toggleFullScreen(nil)`；主窗 `windowDidExitFullScreen` → QV 切 `.fullScreenPrimary`+frame 对齐主窗恢复尺寸+进 windowedCover；次 ESC → close(.normal)。**保留「首 ESC 退全屏、次 ESC 关 QV」**。
- [ ] **Step 3**：frame 跟随补全：`didChangeScreen`/miniaturize/deminiaturize/close（Slice 1 已接 didMove/didResize）。主窗 close/miniaturize → controller.close(.normal)。
- [ ] **Step 4**：verify 编译。
- [ ] **Step 5**：commit `feat(QV): F + 首次 ESC 全屏交互 + frame 跟随补全`

### Slice 2 验收 + 真机验
- [ ] verify 三段全绿。
- [ ] 追加 PENDING（Slice 2，plan review 补全各输入路径）：
  1. windowedCover F→QV 全屏纯净；再 F/ESC 退回同框。
  2. 主窗先全屏→双击进 QV：QV 在同一全屏 Space 上层（无新建黑屏 Space）。
  3. inheritedMainFullScreen 首 ESC 退主窗全屏（QV 回同框）、次 ESC 关 QV。
  4. **全屏各独立输入路径**：toolbar F 按钮 / 键盘 F / ESC / Space / 红绿灯（各走不同代码）。
  5. 过渡中途收到 close / 过渡失败 / 狂按不崩不残留半态。
  6. deminiaturize + 多屏 screen-change frame 正常。
  7. inheritedMainFullScreen 下 toolbar 图标 + viewerAppState.isFullScreen 正确。

---

# Slice 3 — 边界硬化（design 第 7 节）

**Ship 价值**：各边界场景不崩。**独立可 ship**。

### Task 3.1：findSimilar task 生命周期 + invalid input 策略

**Files**：Modify controller + `ContentView.handleFindSimilar`

- [ ] **Step 1**：`handleFindSimilar` 的 async Task 存引用；controller.close 或主窗关时取消在途 task（避免关 QV 后仍设 ephemeral）。
- [ ] **Step 2**：show 前 guard：空 images / 越界 startIndex → **明确策略**（clamp 或拒绝 + 不开窗），断言而非"碰巧不 crash"。
- [ ] **Step 3**：verify 编译。
- [ ] **Step 4**：commit `fix(QV): findSimilar task 取消 + invalid input 策略`

### Task 3.2：生命周期边界 + 窗口细节

**Files**：Modify controller

- [ ] **Step 1**：生命周期边界（design 第 7 节，逐条）：主窗关闭/最小化/隐藏 → close；app deactivation/reactivation / Space 切换 / app termination 行为定义；重复 show 复用窗换 rootView **同时刷新 callbacks**（防快照过期）；外部看图窗与主窗 QV 并存（两单例独立，viewerAppState 不串）。
- [ ] **Step 2**：窗口细节枚举（design:106）：shadow / level / collectionBehavior / 窗口切换(tab 关闭) / restoration / accessibility。
- [ ] **Step 3**：verify 编译。
- [ ] **Step 4**：commit `fix(QV): 生命周期边界 + 窗口细节硬化`

### Slice 3 验收 + 真机验
- [ ] verify 三段全绿。
- [ ] 追加 PENDING（Slice 3 + **真值表逐格**：entry{grid/preview/ephemeral} × 全屏{是/否} × 退出{ESC/F/关闭按钮/⌘W/主窗关}）：
  1. QV 内找类似未完成时关 QV → task 取消，不残留误设 ephemeral。
  2. 空文件夹/越界：按策略 clamp 或不开窗，不崩。
  3. close-then-reopen / 搜索跳转 / repeated show 后旧快照/result 正确丢弃。
  4. QV 开着关主窗/最小化主窗/隐藏 app/切 Space：QV 正确收起。
  5. 外部 Finder 看图窗 + 主窗 QV 同时开：互不干扰。
  6. 真值表每格行为符合预期。

---

## Self-Review（plan vs design + plan review 覆盖）

- **D-QVT2~7 全覆盖**；**plan review P0**：findSimilar:691 + openSearch:734-736 已纳入 Task 1.3 Step 6（Slice 1 迁移）✅；Task 1.3 原子化（一次编译一次 commit）✅
- **plan review P1**：MainWindowController become-key API（Task 1.1 Step 4，files 含 MainWindowController.swift）✅；契约一次定全含 QVDismissalReason 解决 close completion/dismissal/⌘F 次序 ✅；currentSupportsFeaturePrint 改回固定 Bool ✅；QV 全屏输入经 controller（Task 2.1）✅；prepareDismiss/捕获 reason 在清 closure 前（Task 1.2 Step 3）✅
- **plan review P2**：各 slice 真机验补全（关闭路径×获 key / 全屏各输入 / 边界）✅
- **vertical slice 自检**：Slice 1=看图纯净（立即可感知）/ Slice 2=全屏正确 / Slice 3=边界鲁棒，各端到端可 ship，非横切 ✅
- **placeholder 扫描**：全屏/时序处「契约+真机验驱动」是重灾区项目特化，非 TODO 占位 ✅
