# QV/全屏 toolbar regression 修复设计 — 方案 2：独立无装饰 QV 窗

- 日期：2026-06-08
- 状态：设计中（已过 codex review 收敛开放点，待军哥拍板）
- 关联：`specs/Roadmap.md`「## 待修复 Bug」QV toolbar 行（3 轮死结回滚记录，干净态 `a2a8fd4` / 记档 `5587429`）
- 前置：OpenWith 方向2 Slice2（`519bd74`~`58e98fd`，主窗改 `MainWindowController` 自建 NSWindow，本 regression 引入点）

> 注：本文行号基于 HEAD `5587429`，plan/实施阶段须重新 grep 确认（codex review 已指出初稿行号过期，本稿已修正为当前行号）。

---

## 1. 背景与问题

QV（双击进全窗看图）/ 全屏看图时主窗顶部 toolbar 露着（`+` / 系统分栏 / ⓘ信息 / 外观切换 / 缩略图 slider / 排序），看图不纯净。期望：**完全纯净**（像外部看图窗那样全黑无 titlebar 装饰）。军哥已拍板要这一档，不接受系统分栏按钮残留。

## 2. 根因（已确认，勿重复诊断）

主窗 = `MainWindowController` 自建 `NSWindow` + `contentView = NSHostingView(ContentView)`。`NSHostingView` 当 contentView 时 `sceneBridgingOptions` 默认 `.all`，SwiftUI 把 `ContentView` 的 `.toolbar{}` / `.navigationTitle` 持续复写回 `NSWindow.toolbar` / `title`，AppKit 单设隐藏被下一帧 bridge 覆盖。死结（已排除）：单设无效 / toggle bridging 丢列布局 / Task.yield reassert 闪。
**对照事实**：`ExternalViewerWindowController` 纯净，因其 contentView 是纯 `NSHostingView(QuickViewerOverlay)`，无 `.toolbar`，`titleVisibility=.hidden` 生效，无复写源。

## 3. 目标 / 非目标

**目标**：QV / 全屏看图 titlebar 完全纯净（无自定义按钮、无系统分栏、无标题），同外部看图窗。grid 模式 toolbar、grid/sidebar 子树状态、QV 既有交互（方向键 highlight 跟随 / 找类似 / ⌘F / entry 路由 / 全屏首 ESC 退全屏次 ESC 关）全部不退化。
**非目标**：不改 grid 模式 6 按钮外观/交互；不动 NavigationSplitView/sidebar/grid 架构；不动 security-scope；TrafficLightHide 另案；不顺手重构。

## 4. 方案选择 [决策 D-QVT1]

brainstorming 探出 4 候选，过 codex:rescue 评估：

| 方案 | 纯净可靠 | 状态保留 | 工作量 | 主风险 |
|---|---|---|---|---|
| 1 ContentView.body 条件切换根视图 | 中高 | **差** | 中 | grid/分栏/sidebar 状态重置（与现有刻意保留 ImageGridView 不重载缩略图的设计冲突，列宽无 binding 可救） |
| **2 独立无装饰 QV 窗（选定）** | **高** | **高** | 中 | 焦点/窗口生命周期 + 全屏跨 Space |
| 3 全 AppKit NSToolbar 重写 | 高 | 高 | **极高** | 永久 toolbar 基础设施维护负担 |
| 4 同窗 host swap | 潜在高 | 潜在高 | 中高 | 赌未文档化的 contentView 重附加 @State 保留，赌输退化成方案 1 |

**选方案 2 理由**：唯一一个项目里已有完整实现 + 人工验证过纯净的模式（`ExternalViewerWindowController`），风险边界最清晰、可复用。codex 指出方案 2 的跨窗"race"实为高估——回调都是主线程 closure，跨 NSWindow 不引入并发；要处理的是窗口生命周期次序（有验证样本）。

## 5. 架构设计

### 5.1 总览
主窗 QV 从「ContentView 内 `.overlay { QuickViewerOverlay }`」改为「新 controller 管理一个盖住主窗的独立无装饰 NSWindow，内放 `NSHostingView(QuickViewerOverlay)`」。**网格 / 导航子树保持挂载**（仅 QV overlay 相关 modifier 消失）→ grid 缩略图 @State / 滚动位置 / sidebar 展开态 / NavigationSplitView 列宽天然保留。这是方案 2 优于方案 1 的根本。

### 5.2 新建 controller [D-QVT2]
新文件 `Glance/QuickViewer/MainQuickViewerWindowController.swift`（名暂定，plan 敲定）。**ownership：单例（mirror ExternalViewerWindowController.shared）**，由 ContentView 通过环境/回调驱动，**绝不在 `ContentView.body` 内创建**（codex 强调）。

复用 ExternalViewer 的**窗口骨架**：无装饰窗（`titleVisibility=.hidden` + `titlebarAppearsTransparent=true`）+ `NSHostingView` 当 contentView（非 contentViewController，避 1×1 陷阱）+ 自任 NSWindowDelegate + 专属 `viewerAppState`（QV 窗全屏/key/traffic light 作用在 QV 窗）。
**砍掉**：`ViewerSession`/security-scope/`terminateOnClose`/`retiredSessions`（主窗的图已在 scope 内，`v2Urls` 已 resolve）。
**新加（ExternalViewer 没有、不能直接复用的部分，codex 点名）**：父主窗协调（frame 跟随 + 全屏 Space）、entry/focus 路由回主窗、QV 窗全屏状态机、async 操作代际 guard（operation UUID）。

### 5.3 触发 + 退出改造
**4 个进 QV 入口**（codex 修正，原稿漏写为 3 处）：
- `:404` ephemeral grid 双击（entry=.ephemeral）
- `:500` / `:511` grid 双击（entry=.grid）
- `:532` preview onQuickView（entry=.preview）

改造：进入不再设 `quickViewerIndex` overlay，改调 `controller.show(images:startIndex:entry:callbacks:)`。退出：controller 关窗 → `onDismiss` 回调 ContentView，把现在 `:262 onChange(quickViewerIndex)` 的 entry→focusTarget 路由迁过来。
**同时移除** `:295 .toolbar(quickViewerIndex != nil ? .hidden : .visible, for:.windowToolbar)`（原 regression 失效点，codex 点名遗漏）+ `:232-259` overlay 构建/动画。

QV 窗有独立 key window + 独立 @FocusState（QuickViewerOverlay 本就独立持本地 @FocusState，`ContentView:12` 证实不参与父仲裁）→ focus 隔离更干净。

### 5.4 状态拆分 [D-QVT3]
`quickViewerIndex` 现身兼两职。拆分：
- **当前 index** → QV 窗 / controller 管，**但 ContentView 仍需 `onIndexChange` 回调**回写 `folderStore.selectedImageIndex`（同步 grid highlight + 退出后预览，codex 强调仅 controller 持有不够）。
- **「QV 是否在场」哨兵** → ContentView 保留 `isQuickViewerPresenting: Bool`（controller 维护、ContentView 观察）。

**quickViewerIndex 全量依赖（codex grep，原稿 185/521/734 严重不全）——plan 须逐处处理（移除/迁移/替换）**：
`:122`(声明) `:185`(allowsHitTesting) `:232 :238 :259 :262`(overlay 构建/dismiss/动画/退出路由) `:295`(toolbar 隐藏) `:311 :312 :313`(preview-close 焦点 guard) `:320 :321`(folder/image 变化强制 dismiss QV) `:404 :500 :511 :532`(4 入口) `:519 :521`(阻止 preview 渲染) `:691`(async Find Similar 关 QV) `:732 :734 :736`(openSearch 判断/退 QV)。

images 来源沿用 `:234`：`(currentEphemeral != nil || smartFolderStore.selected != nil) ? v2Urls : folderStore.images`，show 时算好传入（快照）。

### 5.5 跨窗交互次序 [D-QVT4]（codex：是次序不是 race）
- **⌘F**：QV 窗内 `onCommandF` → **等 controller close 完成**（completion 回调，在主窗 `windowDidBecomeKey` 后）→ openSearch。同 turn 同时关窗+请求 search 焦点有风险（QV 可能仍持 key，`.search` 焦点丢）。
- **找类似**（codex 修正我的事实错误）：现状 = `handleFindSimilar` 算结果 → 设 `currentEphemeral` → **关 QV 回 ephemeral grid**（非"重 show QV 换源"）。方案 2 保持此行为：`onFindSimilar` → 主窗算 ephemeral + 关 QV 窗 → 回主窗 ephemeral grid。**加 operation/session UUID**：async 结果晚到时，仅当发起的 QV session 仍 current 且未关/未切搜索才生效，否则丢弃；关 QV 时取消在途任务。

## 6. 开放点 — codex review 已收敛

### 6.1 窗口呈现方式 [D-QVT5 → 定为 top-level]
**top-level 同框盖**（codex 推翻原稿倾向的 child window）。理由：`addChildWindow` 文档+实测**不保证**进入父窗全屏 Space；top-level 可显式用 `.fullScreenAuxiliary`（Apple 明确定义同 Space 显示）。全屏正确性 > 省 frame observer。
实现：监听主窗 `didMove`/`didResize`/`didChangeScreen`/miniaturize/deminiaturize/close，同步 `qv.setFrame(main.frame, display:true)` + 保持置上；关闭 shadow + 窗口切换（tab）。

### 6.2 全屏语义 [D-QVT6] — controller 显式状态机（codex 方案）
四态：
- `windowedCover`：QV top-level 同框 + `.fullScreenPrimary`；F 切 QV native 全屏。
- `qvNativeFullScreen`：QV 拥有全屏 Space，主窗不变。
- `inheritedMainFullScreen`：主窗已全屏；QV 以 `.fullScreenAuxiliary` 在该 Space 上层展示。**不对 QV 调 `toggleFullScreen`**（会新建 Space）。
- `transitioning`：过渡期拒绝重复 F/show/close。

`inheritedMainFullScreen` 下首 F/首 ESC → `main.toggleFullScreen(nil)`；`main.windowDidExitFullScreen` 时 QV 切 `.fullScreenPrimary`、frame 对齐主窗恢复尺寸、进 `windowedCover`；次 ESC 关 QV（**保留现有"首 ESC 退全屏、次 ESC 关 QV"预期**）。
∴ QV controller 需自己的 presentation state，`viewerAppState.isFullScreen` 不能只镜像 delegate。

### 6.3 关 QV 窗 focus 时序 [D-QVT7] — codex 4 步
1. 幂等 `prepareDismiss`：QV 还盖着时清 presentation state + 做非焦点路由，防 preview/grid 闪现。
2. `windowWillClose`：detach QV 状态、移 observer、清 callback/session。
3. 下一 main-actor turn：`main.makeKeyAndOrderFront(nil)` + activate app。
4. `MainWindowController.windowDidBecomeKey` 后再 yield 一次，再按 entry 设 `focusTarget`。
**不要**在 QV `windowWillClose` 里设 `focusTarget`（主 hosting 尚未 key，SwiftUI 静默丢弃焦点请求）。

## 7. 边界与错误处理（codex Q7，plan 须逐条覆盖）
- QV 开着时：主窗关闭 / 最小化 / 隐藏 / 切 Space/屏幕 / app 终止。
- 重复 show / 空图片数组 / 越界 startIndex。
- 全屏过渡失败回调 / 过渡期间的 close 请求（transitioning 态拦截）。
- 快照期间文件夹排序 / 图源变更（show 传快照，变更后行为定义）。
- async Find Similar 取消 + 过期结果拒绝（operation UUID）。
- controller callback cleanup，避免持过期 ContentView / 环境对象。
- 窗口细节：shadow / level / collectionBehavior / 窗口切换(tab) / restoration / 无障碍。
- 外部看图窗（ExternalViewerWindowController）与主窗 QV 同时存在。
- **真值表**：entry 类型（grid/preview/ephemeral）× 主窗全屏状态 × 退出机制（ESC / F / 关闭按钮 / ⌘W / 主窗关闭）—— plan 阶段补全。

## 8. 验收标准
1. 4 入口（grid/preview/ephemeral×2）进 QV：titlebar 完全纯净（无自定义按钮 + 无系统分栏 + 无标题），同外部看图窗。
2. QV 内方向键切图：退出后 grid highlight 跟随当前图（不变）。
3. QV 内找类似：关 QV 回 ephemeral grid 结果（不变）；⌘F：退 QV 开主窗 search（不变）。
4. 退出 QV：grid 缩略图无重载、滚动位置/sidebar 展开态/列宽不变（方案 2 核心收益）。
5. 全屏：windowedCover 下 F 进 QV 全屏；主窗已全屏进 QV 走 inheritedMainFullScreen；首 ESC 退全屏次 ESC 关 QV。
6. 编译零 error 零新 warning；`/go` 三段 verify 过。

## 9. 真机验清单（Mac mini 无 GUI 验不了，写入 PENDING-USER-ACTIONS.md）
- titlebar 纯净度截图对比外部看图窗。
- top-level 同框盖：盖住效果 + 跟随主窗 move/resize/换屏/最小化。
- 全屏 4 态：windowedCover F 进全屏 / 主窗已全屏进 QV（fullScreenAuxiliary 同 Space）/ 首 ESC 退全屏次 ESC 关 / 过渡期重复按键。
- 关 QV 后主窗回前台 + 4 入口 focus + highlight 正确。
- 找类似 / ⌘F 跨窗次序无丢焦点。
- async 找类似过期结果不误弹 QV。
- 外部看图窗与主窗 QV 同时存在。
- 真值表逐格验。
