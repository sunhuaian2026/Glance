# Glance V2 macOS 菜单栏增补 — Design (v2 reshape)

> **文件**: `specs/v2/2026-06-18-menu-bar-design.md`
> **作者**: 主 agent (`superpowers:brainstorming` skill) + 孙红军 (decision authority) + codex (read-only review)
> **状态**: v2 draft → codex 复审 → 军哥拍板 → 走 `superpowers:writing-plans` → 实施
> **类型**: 独立子系统 (非里程碑, 不塞 M 序号)
> **关联**: 紧跟「主窗 detail 工具栏查找按钮 followup」(commit `2db5372`) 之后, 同一议题二阶段
> **关联术语字典**: `CONTEXT.md` A 段 / C 段 / D 段

---

## 0. 版本变更说明 (v1 → v2 reshape)

**v1 commit `5441f57`** 被 codex review 给 **RESHAPE** verdict (非 APPROVE-WITH-FIXES), 3 个 P0 + 4 个 P1 + 3 个 P2:

| codex 问题 | 命中点 | v2 修法 |
|---|---|---|
| P0-1 ⌃⌘F 没有 SwiftUI CommandGroupPlacement.fullscreen slot 可替换 | D-mb-2 全屏快捷键 | **v2**: 第一批不加全屏菜单项; 全屏 ownership 留第二批 design 决定 |
| P0-2 design 引用多处假符号 (`isShowing`/`viewerAppState`/`openSearch`/`addBookmark`) | D-mb-4 / D-mb-6 / D-mb-8 | **v2**: 全用真实符号 (`isPresenting` / 暴露 facade / `FolderStore.addFolder()`); 新增 D-mb-9 facade pattern 段 |
| P0-3 ⌘ 组合两边都挂 = 菜单先 catch QV 永不 fire (NSMenu.performKeyEquivalent 优先于 first responder) | D-mb-3 keyboardShortcut 策略 | **v2 = 方向 Y**: 菜单**不挂任何 keyboardShortcut**, 全靠点击 + 菜单文本字符串显示快捷键 hint (例 `「复制图片  (⌘C)」`), 所有 ⌘ 组合在 QV `.onKeyPress` 现状不变 |
| P1-1 SwiftUI Commands @ObservedObject 行为未验证 | D-mb-4 disable 状态机 | **v2**: 改用 AppDelegate 持的 ObservableObject + Commands 内 view 显式 @ObservedObject; plan 阶段 spike 验证 |
| P1-2 双窗口全屏 OR 状态太粗 (漏过渡态) | D-mb-8 全屏文案 | **v2**: 第一批不加全屏菜单项, 此条暂搁置 |
| P1-3 scope 偏大需拆 | D-mb-5 范围 | **v2**: 拆两批 — 第一批 16 项无争议菜单, 第二批全屏 + 共享快捷键路由 (单独 design v3) |
| P1-4 Section 6 reality check 清单不够 | Section 6 | **v2**: 已通过 reality check (本 design 列入 §1 真实 API 表) |
| P2-1 a11y 手拼字符串 VoiceOver 当标题正文读 | D-mb-7 hint 风格 | **v2**: 接受 trade-off — VoiceOver 读出快捷键字串 (例「复制图片 Command C」) 比无 hint 强; 项目优先级 a11y 排后 |
| P2-2 i18n 应明说先只做 zh-Hans | 跨决策 | **v2**: §11 加明说: 全 hardcoded zh-Hans, 后续 en locale 时单独 design |
| P2-3 SwiftUI commands hot reload 易误判 | Section 6 | **v2**: §10 实施清单加一条 |

**军哥拍板**: 方向 Y (codex P0-3 修法选项中军哥拍最保守路径) + 拆两批 (codex P1-3 推荐)。

---

## 1. 真实 API 表 (reality check 通过项, 从 v1 fix 来)

> codex P0-2 + 主 agent reality check (commit `5441f57` 后 grep) 共同确认:

| design v1 引用 (假) | 真实 API | 来源文件 |
|---|---|---|
| ~~`MainQuickViewerWindowController.shared.isShowing`~~ | `MainQuickViewerWindowController.shared.isPresenting` (`@Published private(set) var isPresenting: Bool`) | `Glance/QuickViewer/MainQuickViewerWindowController.swift:47` |
| ~~`MainQuickViewerWindowController.shared.viewerAppState` 直接读~~ | `viewerAppState` 是 `private let`, 外部不可访问。需暴露 facade (D-mb-9) | 同上 :55 |
| ~~`ContentView.openSearch()`~~ | `private func openSearch()`, 外部不可调用。需暴露 facade | `Glance/ContentView.swift:894` |
| ~~`bookmarkManager.addBookmark(for:)`~~ | `BookmarkManager.saveBookmark(for:) throws` (底层); UI 入口走 `FolderStore.addFolder()` (无参版已封装 NSOpenPanel + autoSelect) | `Glance/BookmarkManager.swift:44` / `Glance/FolderBrowser/FolderStore.swift:149` |
| `MainWindowController.shared.hasWindow` | 真实存在 ✓ (codex OK) | `Glance/MainWindow/MainWindowController.swift` |
| `AppState.isFullScreen` + `toggleFullScreen()` | 真实存在 ✓ (codex OK) | `Glance/FullScreen/AppState.swift` |
| CommandGroupPlacement `.newItem`/`.pasteboard`/`.sidebar`/`.windowList` | 真实存在 ✓ (codex OK, macOS 14 SwiftUI SDK) | SwiftUI standard |

QV 当前 `.onKeyPress` 共享快捷键完整分布 (现状, v2 不动):
- `.escape` / `.space` — 关 QV
- `.leftArrow` / `.rightArrow` — 切图
- `0` / `=` / `-` — handler 内部 `event.modifiers.contains(.command)` 分支检查 (⌘0 / ⌘= / ⌘-)
- `f` — handler 内 `.command` 分支调 onCommandF; 否则全屏 `toggleFullScreen()`
- `l` — 旋转左
- `r` — handler 内 `.command + .shift` 分支调 Finder; 否则旋转右
- `c` — handler 内 `.command` 分支调复制图; `.command + .option` 分支调复制路径
- `.delete` / `.deleteForward` — 移废纸篓

**关键事实**: 这些 ⌘ 组合都不是 SwiftUI `.keyboardShortcut`, 是 `.onKeyPress` handler 内手动检查 modifier。菜单不挂 keyboardShortcut → 菜单不抢 QV `.onKeyPress` → 现状零破坏。

---

## 2. 概述 (v2)

为 Glance 主窗 macOS 菜单栏增补常用动作入口。

**当前现状**: `GlanceApp.swift` 只挂了一个 `CommandGroup(replacing: .appInfo) { AboutMenuButton() }` 把「关于一眼」塞 Apple 菜单下, 其它系统默认菜单 (文件 / 编辑 / 显示 / 窗口 / 帮助) 全为空壳, app 自定义快捷键全部未在菜单栏暴露。

**v2 目标 (第一批)**: 把 16 项**无争议菜单项**挂菜单栏, **不挂任何 keyboardShortcut**, 仅鼠标点击 + 菜单文本字符串显示快捷键 hint。所有现有 QV `.onKeyPress` 路径零改动。

**v2 非目标 (避 scope 蠕变, 第一批不做)**:
- ❌ 全屏菜单项 (D-mb-2 fullscreen ownership 留第二批 design v3)
- ❌ 共享快捷键升级到方向 X (Commands 接管 — 留 design v3)
- ❌ 重写 QV 共享快捷键路径
- ❌ 给主窗加新动作 (复制 grid 选中 cell / 主窗直接旋转 等)
- ❌ 菜单项国际化 (中文菜单文本 hardcoded zh-Hans)

---

## 3. 决策段 (v2)

### D-mb-1 菜单分类范式 = 标准三菜单 (编辑 / 显示 / 图像) [军哥拍板, 不变]

**决策**: 把第一批 16 项菜单项分到三个菜单 (+ 文件 + 窗口 共 5 顶级), **不全堆「编辑」一个菜单**。

军哥原话「编辑菜单加 F 全屏」是概括说法, 标准 macOS 范式按语义分类:
- **编辑** (Edit) — 数据操作: 查找 / 复制图 / 复制路径
- **显示** (View) — 视图状态: 信息切换 / 缩放系列 (全屏第二批)
- **图像** (Image) — 当前图操作: 旋转 / 翻转 / 在 Finder 中显示 / 移到废纸篓

**关联**: D-mb-5 / D-mb-10

---

### D-mb-2 全屏菜单项 = **第一批不加**, 留第二批 design v3 [v2 简化]

**决策**: 第一批菜单栏**不加任何全屏菜单项**。全屏交回 macOS 系统注入 (窗口菜单系统默认有「全屏切换」, 快捷键 ⌃⌘F 系统自带)。

**v1 → v2 变更**: v1 设计在显示菜单加「进入全屏 ⌘^F」+ 双轨 (菜单 ⌘^F + QV 裸 F)。codex P0-1 指出 SwiftUI `CommandGroupPlacement` 在 macOS 14 SDK **没有 `.fullscreen` slot 可替换**, 自挂 ⌃⌘F 会跟系统注入冲突。v2 接受 codex 修法: 全屏交回系统。

**第二批 design v3 要回答**:
- 是否需要在菜单栏显式露出「进入全屏」入口 (鼠标用户从菜单点)?
- QV 内裸 F 是否保留?
- 主窗 ⌃⌘F 系统全屏跟 QV 内裸 F 的双窗口语义是否需要统一?
- 这些决策牵涉双窗口全屏状态机 (codex P1-2 漏过渡态), 单独 design 处理。

**关联**: D-mb-10 (拆批边界)

---

### D-mb-3 keyboardShortcut 策略 = **方向 Y** (菜单全不挂, 文本字符串 hint) [军哥拍板]

**决策**: 第一批菜单项的 `.keyboardShortcut` 挂载策略:

- ❌ **菜单项不挂任何 `.keyboardShortcut`** (无论 ⌘ 组合还是裸字母)
- ✅ **菜单文本里手工拼快捷键 hint 字符串** (例 `「复制图片  (⌘C)」` / `「旋转左  (L)」` / `「移到废纸篓  (⌫)」`)
- ✅ **所有快捷键响应路径不变** — QV 内的 ⌘ 组合 / 裸字母全部通过 QV `.onKeyPress` handler (现状); 主窗 ⌘F 通过 ContentView body 末尾 `.onKeyPress` (现状); 主窗 ⌘I 通过 toolbar button `.keyboardShortcut` (现状)

**为什么方向 Y (codex P0-3 修法)**:
- ⌘ 组合两边挂 = 菜单先 catch QV `.onKeyPress` 永不 fire (NSMenu.performKeyEquivalent 在 AppKit dispatch 路径优先于 first responder)
- QV 内现有 `.onKeyPress` modifier 分支 (例 `c` 内分支 .command + .option) 实现 stable, 不破坏
- 菜单作鼠标用户备用入口 + 快捷键发现性载体, 不当 hot key 总闸
- **改动最小**: 只动 `GlanceApp.swift` 加 .commands, 不动 QV 一行

**用户感知**:
- ⌘C 在 QV 内: 通过 .onKeyPress 复制 ✓ (现状)
- ⌘C 在主窗: 系统默认 NSMenu「编辑→复制」(空 action) 或不响应 (主窗本来就没复制图概念, 可接受)
- 菜单点「复制图片  (⌘C)」: 鼠标用户照点 (调 QV facade 触发 — QV 必须 isPresenting)
- 用户看菜单文本里的 (⌘C) hint: 学到 QV 内可用此快捷键, 自然形成认知

**关联**: D-mb-4 / D-mb-7 / D-mb-9

---

### D-mb-4 菜单项 disable 策略 = 简单 binding (用真实符号) [P0-2 修]

**决策**: 菜单项的 `.disabled()` 绑两个真实源:

| 菜单项 | disable 条件 (用真实符号) |
|---|---|
| 查找…  (⌘F) | 永远 enable (调 facade openSearch 即可, 主窗状态有效) |
| 显示/隐藏信息  (⌘I) | `folderStore.selectedImageIndex == nil` (复用 ContentView toolbar 按钮逻辑) |
| 旋转左 / 旋转右 / 水平翻转 / 垂直翻转 | `!MainQuickViewerWindowController.shared.isPresenting` ← **真实符号 (非 isShowing)** |
| 适合窗口 / 实际大小 / 放大 / 缩小 | 同上 (`!isPresenting`) |
| 复制图片 / 复制路径 / 在 Finder 中显示 | 同上 |
| 移到废纸篓 | `!isPresenting` (V1 老 bookmark 拦截由 QV facade trash 函数内部 schema gate, 菜单不二次检查) |
| 添加文件夹根… | 永远 enable (调 facade addFolder 即可) |
| 图库主窗 (窗口菜单) | hide when `MainWindowController.shared.hasWindow == true`; 永远不 disable (要么显, 要么隐) |

**为什么不建专职状态机**:
- v1 提议 `MenuBarState: ObservableObject` 多 flag (codex P1-1 警告未验证): v2 沿用简单方案, 接受未来若需要再升级 (YAGNI)
- 简单 binding: `MainQuickViewerWindowController.shared` 是 ObservableObject 单例, Commands 内 view `@ObservedObject` 直接观察 `.isPresenting` @Published

**实施前 spike (P1-1 风险缓解)**: plan 阶段 任务 A 先 spike 验证 SwiftUI .commands 内 view 用 @ObservedObject 观察 controller.shared 单例时, .disabled binding 是否随 publisher 更新。reality check 是 plan 第一步, 失败则升级到 AppDelegate 持的 MenuBarState ObservableObject 中转层。

**关联**: D-mb-3 / D-mb-9

---

### D-mb-5 第一批范围 = 16 项无争议菜单 [军哥拍板, 拆两批]

**决策**: 第一批挂 16 项菜单, 第二批留 1+ 项 (见 D-mb-10):

**第一批菜单项总数 = 16 项**:
- 编辑菜单: 查找… (1) + 复制图片 (1) + 复制路径 (1) = **3 项**
- 显示菜单: 信息切换 (1) + 适合窗口 (1) + 实际大小 (1) + 放大 (1) + 缩小 (1) = **5 项**
- 图像菜单: 旋转左 (1) + 旋转右 (1) + 水平翻转 (1) + 垂直翻转 (1) + 在 Finder 中显示 (1) + 移到废纸篓 (1) = **6 项**
- 文件菜单: 添加文件夹根… (1) = **1 项**
- 窗口菜单: 图库主窗 (1) = **1 项**

**为什么拆两批 (codex P1-3 推荐)**:
- 第一批 = 16 项**全方向 Y**, 零快捷键冲突, scope 集中 (单文件 `GlanceApp.swift` + facade 暴露 + 状态 spike)
- 第二批 = 全屏 + 共享快捷键路由 (有争议, 需新 brainstorming 单独 design v3)
- 分批 ship 让用户先用上 80% 价值, 第二批等深思熟虑

**关联**: D-mb-10

---

### D-mb-6 实施途径 = SwiftUI `.commands` CommandGroup + ViewModel facade [P0-2 修]

**决策**: 沿用 SwiftUI `Scene.commands(...)` + `CommandGroup(...)` / `CommandMenu(...)` 范式 (mirror `AboutMenuButton`)。新增 **action facade 层** 暴露 ContentView / MainQuickViewerWindowController / QuickViewerViewModel 等私有 API 给 commands 调用。

**Mirror 现状**: `GlanceApp.swift` 现有 `.commands { CommandGroup(replacing: .appInfo) { AboutMenuButton() } }` 范式。本子系统继续沿用。

**CommandGroup 选用** (v1 + P1 调整):

| 菜单 | API | 备注 |
|---|---|---|
| 文件 (File) | `CommandGroup(after: .newItem) { ... }` | 在系统「新建」附近插入「添加文件夹根…」 |
| 编辑 (Edit) | `CommandGroup(after: .pasteboard) { ... }` | 查找 / 复制图 / 复制路径 (paste board 段附近) |
| 显示 (View) | `CommandGroup(after: .sidebar) { ... }` 或 `CommandMenu("显示") { ... }` | 信息切换 / 缩放系列 (`replacing: .sidebar` 会改 sidebar 菜单内容, 改用 `after`) |
| 图像 (Image) | `CommandMenu("图像") { ... }` | 全新顶级菜单, 旋转 / 翻转 / Finder / 废纸篓 |
| 窗口 (Window) | `CommandGroup(after: .windowList) { ... }` | 「图库主窗」reopen 入口 |

**Commands 内 View 状态观察**:
- `CommandGroup` / `CommandMenu` 接受任意 `View` 作为 content
- 把 commands 内容拆成独立 struct view (持 `@ObservedObject` 引用 `MainQuickViewerWindowController.shared` 等单例)
- AppDelegate 已持单例 (`folderStore` / `appState` / `bookmarkManager` / `indexStoreHolder` 等), 在 GlanceApp.body 把 AppDelegate 引用通过 init 传入 commands view

**P1-1 风险**: 单例 @ObservedObject 在 SwiftUI commands 内未验证, plan 阶段任务 A spike 第一步。

**关联**: D-mb-4 / D-mb-9

---

### D-mb-7 菜单文本快捷键 hint 风格 = **所有项手工拼字符串** [P0-3 + P2-1 修]

**决策**: 第一批菜单项**全部**用手工拼字符串显示快捷键 hint, **不依赖 SwiftUI 自动渲染** (因 D-mb-3 不挂任何 keyboardShortcut):

**风格规范**:
- 有快捷键: 「<动作>  (<快捷键>)」 — 例 `「查找…  (⌘F)」` / `「复制图片  (⌘C)」` / `「旋转左  (L)」` / `「移到废纸篓  (⌫)」` (两个空格分隔动作和 hint 块)
- 无快捷键: 「<动作>」 — 例 `「水平翻转」` / `「图库主窗」` / `「添加文件夹根…」`

**Symbol 规范**:
- ⌘ Command / ⌃ Control / ⌥ Option / ⇧ Shift — Unicode 标准符号 (mirror QV contextMenu 已用)
- ⌫ Delete (向左 backspace 符号)
- L / R / 0 / = / − 裸字母直接显示

**为什么手工拼**:
- D-mb-3 不挂 keyboardShortcut → SwiftUI 不会自动渲染 hint → 必须手工拼到 Label 文本
- 项目现有工具栏 tooltip 风格 (`「适合 (⌘0)」` 工具栏) 已先例, 一致性高
- mirror QV `contextMenu` 「复制图片 (⌘C)」「移到废纸篓 (⌫)」 等已落地风格

**a11y trade-off (codex P2-1)**:
- VoiceOver 会把字符串当标题正文读出: 例「复制图片 Command C」(读出 ⌘ 符号语义为 "Command")
- 比无 hint 强 (用户至少知道快捷键存在); 项目 a11y 排后, 接受
- 第二批 design v3 (方向 X 升级时) 用 SwiftUI 自动 hint 渲染才能根治 a11y

**关联**: D-mb-3

---

### D-mb-8 动态文案策略 = 第一批仅信息切换, 全屏第二批 [v1 简化]

**决策**: 第一批菜单项动态文案仅限**一项** (信息切换), 全屏第二批 design v3 处理:

| 菜单项 | 静态文案 | 动态文案 |
|---|---|---|
| 显示信息 / 隐藏信息 | — | `showInspector == true` 时: `「隐藏信息  (⌘I)」`; 否则: `「显示信息  (⌘I)」` |
| 旋转左 | `「旋转左  (L)」` | — |
| 旋转右 | `「旋转右  (R)」` | — |
| 水平翻转 | `「水平翻转」` | — |
| 垂直翻转 | `「垂直翻转」` | — |
| 复制图片 | `「复制图片  (⌘C)」` | — |
| 复制路径 | `「复制路径  (⌘⌥C)」` | — |
| 在 Finder 中显示 | `「在 Finder 中显示  (⌘⇧R)」` | — |
| 移到废纸篓 | `「移到废纸篓  (⌫)」` | — |
| 适合窗口 | `「适合窗口  (⌘0)」` | — |
| 实际大小 | `「实际大小  (0)」` | — |
| 放大 | `「放大  (⌘=)」` | — |
| 缩小 | `「缩小  (⌘−)」` | — |
| 查找… | `「查找…  (⌘F)」` | — |
| 添加文件夹根… | `「添加文件夹根…」` | — |
| 图库主窗 | `「图库主窗」` | — |

**信息状态源**: `showInspector` 是 ContentView 的 `@State`。Commands 内 view 需要观察该状态 — 通过 facade 暴露 (D-mb-9) 把 `showInspector` 提升到 AppState 或独立 InspectorState ObservableObject, 让 ContentView 和 commands view 共享。

**为什么动态文案只限 1 项**:
- 信息切换是双态可切换, 动态文案给用户当前态反馈
- 其它项是单向触发 (旋转/复制/删除 都是 one-shot), 无对应反向操作, 不需要动态文案
- 全屏切换涉及双窗口状态机, 留第二批 design v3 一并处理 (P1-2 风险)

---

### D-mb-9 公开 Facade Pattern [新增, P0-2 修]

**决策**: 第一批新建 2 个公开 facade, 把 Commands 调用的私有 API 暴露:

#### 9.1 ContentView 入口暴露

`ContentView.swift` 当前 `openSearch()` 是 `private func`。Commands 调不到。

**修法选项 (军哥拍 / plan 阶段定)**:
- (a) 把 `openSearch` 改 `internal` (默认 access level), Commands 内 view 通过 @EnvironmentObject 或 closure 持 ContentView 引用调用
- (b) 把 `openSearch` 的核心逻辑提取到 AppDelegate / 独立 SearchOverlayState (ObservableObject), Commands 直接调
- (c) GlanceApp.body 持 closure 引用 ContentView 的 openSearch (init-time 注册到 AppDelegate)

**推荐**: **(b) 提取到 AppDelegate** — 跟现有架构对齐 (AppDelegate 已持 4 单例), Commands 直接通过 `AppDelegate.shared.searchOverlayState.open()` 触发。Inspector 状态 (`showInspector`) 同步提升, 不再是 ContentView @State。

#### 9.2 MainQuickViewerWindowController 入口暴露

QV controller 当前 `viewerAppState` 是 `private let`, 共享动作函数 (`viewModel.rotateLeft` / `copyImageToPasteboard` 等) 在 QuickViewerOverlay 内, 不暴露给外部。

**修法**: MainQuickViewerWindowController 加 **action facade methods**:

```swift
@MainActor extension MainQuickViewerWindowController {
    // 旋转/翻转
    func performRotateLeft() { /* 调当前 QV viewModel.rotateLeft() */ }
    func performRotateRight() { ... }
    func performToggleFlipH() { ... }
    func performToggleFlipV() { ... }
    // 复制
    func performCopyImage() { ... }
    func performCopyPath() { ... }
    // 显示
    func performRevealInFinder() { ... }
    // 删除
    func performTrashCurrent() async { ... }  // 走 QuickViewerTrashCoordinator
    // 缩放
    func performResetToFit() { ... }
    func performResetToOneToOne() { ... }
    func performZoomIn() { ... }
    func performZoomOut() { ... }
}
```

每个 method 内部:
1. `guard isPresenting else { return }` (兜底)
2. 调对应 QuickViewerViewModel / 内部 helper 函数 (复用现有 QuickViewerOverlay 已有的 action 函数实现)

**Note**: facade methods 复用 QuickViewerOverlay 已有 action (`copyImageToPasteboard` / `copyCurrentPath` / `revealInFinder` / `handleTrashCurrent`) 的实现, 把核心逻辑下沉到 controller 或 ViewModel, Overlay 改成调 facade。这样 contextMenu / 「更多」menu / 工具栏菜单 / app 菜单栏 4 个入口都调同一 facade, 单点维护。

#### 9.3 FolderStore 入口

**复用现有 `FolderStore.addFolder()` (无参版, 已封装 NSOpenPanel + saveBookmark + 树加载 + autoSelect)** — codex OK 段确认。Commands 直接调 `appDelegate.folderStore.addFolder()`, 不重拼 NSOpenPanel 流程。

#### 9.4 MainWindowController 入口

`MainWindowController.shared.show(bookmarkManager:folderStore:appState:indexStoreHolder:)` 已 internal, Commands 内 view 通过 AppDelegate 拿 4 单例 reference 调用 (mirror AppDelegate.showMainWindow)。

`MainWindowController.shared.hasWindow` 用作 `.disabled` binding / 菜单项 hide 条件。

**关联**: D-mb-4 / D-mb-6

---

### D-mb-10 第一批 / 第二批边界 [新增, P1-3 拆批]

**决策**: 本 design 仅覆盖第一批 (16 项无争议菜单)。第二批写入独立 design v3 (issue 时间: 第一批 ship 后, 用户实际反馈 + 全屏方向决策时机)。

**第一批 (本 design)**:
- ✅ 16 项菜单 (文件 1 / 编辑 3 / 显示 5 / 图像 6 / 窗口 1)
- ✅ 公开 Facade Pattern (D-mb-9)
- ✅ 简单 binding disable (D-mb-4)
- ✅ 信息切换动态文案 (D-mb-8)

**第二批 (design v3 待写)**:
- 全屏菜单项 (D-mb-2)
- 共享快捷键路由方向决策: 永久方向 Y vs 升级方向 X
- 全屏双窗口状态机 (codex P1-2)
- ⌘W 关 QV 菜单项 (开放问题)

第二批触发条件: 第一批 ship 后用户真机用 1-2 周, 反馈「菜单挂了但快捷键还是要去 QV 里用」是否影响体验。

---

## 4. 第一批完整菜单结构 (最终方案 v2)

```
Apple 菜单
├ 关于一眼                           (现有)
├ ─────
└ 退出一眼                ⌘Q         (系统默认)

文件 (File)
├ (系统默认无新增, .newItem 空)
├ 添加文件夹根…                       ← 第一批新增 [永远 enable]
├ ─────
└ 关闭                    ⌘W         (系统默认)

编辑 (Edit)
├ (系统默认: 撤销 / 重做 / 剪切 / 复制 / 粘贴) [置顶, 系统注入]
├ ─────
├ 查找…  (⌘F)                        ← 第一批新增 [永远 enable]
├ ─────
├ 复制图片  (⌘C)                     ← 第一批新增 [disable: !isPresenting]
└ 复制路径  (⌘⌥C)                    ← 第一批新增 [disable: !isPresenting]

显示 (View)
├ 显示信息 / 隐藏信息  (⌘I)           ← 第一批新增 (动态文案 D-mb-8) [disable: !folderStore.selectedImageIndex]
├ ─────
├ 适合窗口  (⌘0)                     ← 第一批新增 [disable: !isPresenting]
├ 实际大小  (0)                      ← 第一批新增 [disable: !isPresenting]
├ 放大  (⌘=)                        ← 第一批新增 [disable: !isPresenting]
└ 缩小  (⌘−)                        ← 第一批新增 [disable: !isPresenting]
[全屏菜单项第二批 design v3 处理, 第一批不加]

图像 (Image) ← 全新顶级菜单 (D-mb-1)
├ 旋转左  (L)                        ← 第一批新增 [disable: !isPresenting]
├ 旋转右  (R)                        ← 第一批新增 [disable: !isPresenting]
├ ─────
├ 水平翻转                            ← 第一批新增 [disable: !isPresenting]
├ 垂直翻转                            ← 第一批新增 [disable: !isPresenting]
├ ─────
├ 在 Finder 中显示  (⌘⇧R)            ← 第一批新增 [disable: !isPresenting]
├ ─────
└ 移到废纸篓  (⌫)                    ← 第一批新增 [disable: !isPresenting]

窗口 (Window)
├ (系统默认: 最小化 / 缩放 / 全屏切换) [置顶, 系统注入]
├ ─────
└ 图库主窗                            ← 第一批新增 [hide when hasWindow]

帮助 (Help)
└ (系统默认, 无新增)
```

**菜单分隔符规则**: 仅在语义不同的子组之间用分隔符 (例「查找」与「复制」之间), 同组之间 (旋转左/右) 不分隔。

---

## 5. 实施任务概览 (高层, 不替 plan)

> 详细 task 拆分留给 `superpowers:writing-plans` skill。下面是高层框架, codex 复审用。

**预估改动文件**:

| 文件 | 改动 |
|---|---|
| `Glance/MenuBar/SearchOverlayState.swift` (新建) | 抽出 search overlay 状态机 (D-mb-9.1 (b) 修法), 替换 ContentView `@State` 私有持有 |
| `Glance/MenuBar/InspectorState.swift` (新建, 可选) | 抽出 inspector showInspector 状态 (D-mb-8 + D-mb-9.1) |
| `Glance/QuickViewer/MainQuickViewerWindowController+Actions.swift` (新建) | facade extension (D-mb-9.2), 11 个 perform* methods |
| `Glance/GlanceApp.swift` | 主改动: AppDelegate 加 SearchOverlayState / InspectorState 单例; `.commands` ViewBuilder 内挂 5 个菜单 CommandGroup/CommandMenu, 每个内含 N 个 Button + .disabled binding。预计 +200 行 |
| `Glance/MenuBar/MenuBarCommands.swift` (新建, 可选) | 把 GlanceApp.body.commands 内 5 个 CommandGroup 拆出来独立文件 (单文件 < 250 行) |
| `Glance/ContentView.swift` | 修改: `openSearch` 改走 SearchOverlayState; `showInspector` 改走 InspectorState; `openSearch` 函数访问级别确认; toolbar 既有 ⌘I 按钮可改走 InspectorState binding |
| `Glance/QuickViewer/QuickViewerOverlay.swift` | 局部改: 现有 action 函数 (`copyImageToPasteboard` / `copyCurrentPath` / `revealInFinder` / `handleTrashCurrent`) 抽出核心逻辑到 facade extension, Overlay 改调 facade。预计 ±30 行 |
| `Glance/MainWindow/MainWindowController.swift` | 不改动 (已有 hasWindow, codex OK) |
| `Glance/QuickViewer/MainQuickViewerWindowController.swift` | 不改动主体 (isPresenting 已 @Published) |
| `specs/Roadmap.md` / `CLAUDE.md` / `specs/PENDING-USER-ACTIONS.md` | 文档同步 (任务收尾) |

**预估第一批任务节奏 (vertical slice 拆分)**:

1. **任务 A**: spike + facade 框架 — SearchOverlayState / InspectorState ObservableObject + AppDelegate 持单例 + 验证 SwiftUI commands 内 @ObservedObject 触发 .disabled (P1-1 risk)
2. **任务 B**: 文件菜单「添加文件夹根…」 + 窗口菜单「图库主窗」(最简单, 单独动作)
3. **任务 C**: 编辑菜单 3 项 (查找 / 复制图 / 复制路径) — 需 QV facade 部分
4. **任务 D**: 图像菜单 6 项 (旋转 / 翻转 / Finder / 废纸篓)
5. **任务 E**: 显示菜单 5 项 (信息切换 + 缩放系列) — 信息切换需 InspectorState 完成接线
6. **任务 F**: 任务收尾 (verify / 文档同步 / PENDING / commit / push)

每任务都满足 vertical slice 三条 (端到端可跑 / 用户可感知 / 独立可 ship)。

---

## 6. 风险表 (R-mb-* v2)

| ID | 风险描述 | v2 缓解 |
|---|---|---|
| R-mb-1 (修) | SwiftUI `.commands` 内 View 用 @ObservedObject 观察 ObservableObject 单例时 .disabled binding 是否随 publisher 更新 | plan 任务 A 第一步 spike 验证; 失败则升级 AppDelegate 持 MenuBarState ObservableObject 中转 |
| R-mb-2 | 系统注入的「编辑→剪切/复制/粘贴」「窗口→全屏」可能跟自定义项冲突 | 用 `CommandGroup(after: ...)` 显式定位, 不混入系统组 |
| R-mb-3 (修) | ⌘C 等 keyEquivalent 跟系统冲突 | **v2 = 方向 Y 全 解决**: 菜单不挂任何 keyboardShortcut, 系统「编辑→复制」⌘C 不受影响; QV 内 ⌘C 由 QV `.onKeyPress` 现状接 |
| ~~R-mb-4 (删)~~ | ~~⌘^F 全屏 keyEquivalent 系统冲突~~ | **v2**: 第一批不加全屏菜单项, 风险消除; 第二批 design v3 重新评估 |
| R-mb-5 (修) | `.environmentObject` 跨 Scene + Commands 边界 | v2: 不依赖 environment, 改用 AppDelegate 持单例 + closure init 注入 commands view (D-mb-9.1 (b)) |
| R-mb-6 | 菜单项 disable 延迟一帧 | 一帧延迟肉眼不可感; spike 验证 |
| R-mb-7 | 「图库主窗」reopen 时 4 单例一致性 | AppDelegate 持单例, 直接拿 reference (mirror `showMainWindow`) |
| R-mb-8 | NSOpenPanel 在 commands action 中调用模态问题 | NSOpenPanel.runModal 是 modal session, 不影响菜单 (mirror `BookmarkMigrationCoordinator.pickRoots`); 复用 `FolderStore.addFolder()` 已封装 (codex OK 确认) |
| R-mb-9 (修) | 移废纸篓键位 | **v2**: 不挂 keyEquivalent, 菜单文本「(⌫)」hint; ⌫ 在 QV 内 .onKeyPress(.delete) 现状接 |
| R-mb-10 (修) | ⌘0 / 0 系统冲突 | **v2**: 不挂 keyEquivalent, 文本「(⌘0)」/「(0)」hint; ⌘0/0 在 QV 内现状接 |
| R-mb-11 (新, P1-1) | facade 单例 + Commands view 观察方案未验证 | plan 任务 A spike 第一步, 失败升级 |
| R-mb-12 (新, P2-3) | SwiftUI .commands 改完后菜单结构开发期 hot reload 可能不刷新 | 实施 checklist 加一条: 改完菜单结构必须重启 app 验证, 不信 Xcode preview hot reload |
| R-mb-13 (新, D-mb-9.1) | SearchOverlayState 抽出可能影响 ContentView 既有 ⌘F 路径 | 任务 A 抽出时保留 ContentView body 末尾 `.onKeyPress(.init("f"))` 现状作 fallback; SearchOverlayState 是状态机, ContentView 仍持有触发器 |
| R-mb-14 (新, D-mb-9.2) | facade 抽出 QV action 时, Overlay 与 facade 调用顺序 / argument 边界 | plan 任务 A spike 第二步 — 抽 1 个 action (例 copyImageToPasteboard) 验证 contextMenu / 工具栏「更多」menu 都还能正常工作 |

---

## 7. 实施前确认项 (Plan 阶段 Reality Check, v2 补全)

writing-plans skill 实施前必须 grep 实际代码确认 (v1 Section 6 + codex P1-4 补全):

- [x] `MainQuickViewerWindowController.shared.isPresenting` `@Published private(set) var` ← **§1 已确认 ✓**
- [x] `MainWindowController.shared.hasWindow` ← **codex OK 段已确认 ✓**
- [x] `BookmarkManager.saveBookmark(for:) throws` (底层) + `FolderStore.addFolder()` UI 入口 ← **§1 已确认 ✓**
- [x] `ContentView.openSearch()` 是 `private func` ← **§1 已确认 ✓ → 必须暴露 D-mb-9.1**
- [x] `viewerAppState` 是 `private let` ← **§1 已确认 ✓ → 必须 facade D-mb-9.2**
- [x] QV `.onKeyPress` 共享快捷键分布 (⌘ 组合在 handler 内 modifier 分支检查) ← **§1 已确认 ✓**
- [x] `CommandGroupPlacement` `.newItem` / `.pasteboard` / `.sidebar` / `.windowList` 在 macOS 14 SDK 存在 ← **codex OK 段已确认 ✓**
- [ ] **新**: plan 任务 A spike 验证 — SwiftUI commands 内 view 用 @ObservedObject 观察 controller.shared 单例 `.isPresenting` 是否触发 .disabled 重渲染 (R-mb-1 / R-mb-11)
- [ ] **新**: plan 任务 A spike 验证 — facade extension 抽 1 个 action (例 copyImageToPasteboard) 后, contextMenu / 工具栏「更多」menu 是否仍正常工作 (R-mb-14)
- [ ] **新**: plan 阶段确认 — `CommandGroup(after: .sidebar)` 在 macOS 14 显示菜单是否生成自定义菜单顶部追加而不替换系统 sidebar 子菜单
- [ ] **新**: plan 阶段确认 — `CommandMenu("图像")` 是否能在显示和窗口菜单之间插入 (macOS 14 顶级菜单排序行为)
- [ ] **新**: AppDelegate 是否需要新建 `SearchOverlayState` / `InspectorState` 单例, 还是可以直接在 GlanceApp.body 用 `@StateObject` 持 (Scene-level @StateObject 是否生效)

---

## 8. 开放问题 (留给 codex 复审 / 军哥)

1. **D-mb-9.1 修法选择**: ContentView.openSearch 暴露走 (a) internal / (b) AppDelegate 单例 / (c) closure 注入? v2 推荐 (b), 军哥 codex 复审时可 challenge
2. **D-mb-9.2 facade 实现位置**: extension MainQuickViewerWindowController vs 独立 QuickViewerActions struct? v2 推荐 extension (mirror Swift 标准)
3. **D-mb-7 a11y 字符串**: VoiceOver 读「Command C」体验是否完全可接受, 还是 plan 阶段考虑 SwiftUI .accessibilityLabel 覆盖?
4. **D-mb-10 第二批触发**: 用户反馈周期 1-2 周 vs 第一批 ship 后立即评估? 项目优先级 (V2.3 release / M5 找相似清理 等) 是否优先于第二批菜单?
5. **菜单顺序**: 文件 / 编辑 / 显示 / 图像 / 窗口 — 「图像」插在显示和窗口之间是 Photos.app 范式。如军哥审美偏好「编辑/显示/工具/图像/窗口」或其它顺序, 现在改还来得及

---

## 9. 第一批完成后 PENDING 真机肉眼验项预估

> 详细 list 留给实施任务收尾时写 PENDING-USER-ACTIONS.md。预估覆盖范围:

**菜单可见性 (5 顶级 + 16 项)**:
- 5 顶级菜单 (文件 / 编辑 / 显示 / 图像 / 窗口) 都有自定义项
- 16 项菜单项可见, 文本 hint 字符串风格一致

**点击行为 (主窗状态)**:
- 编辑→查找… 点 = 弹搜索 overlay (跟 ⌘F 一样)
- 文件→添加文件夹根… 点 = NSOpenPanel (跟侧边栏 + 按钮一样)
- 窗口→图库主窗 点 = 关窗驻留态下 reopen 主窗
- 显示→显示信息 点 = 切 Inspector (跟工具栏 ⓘ 一样)
- 其它菜单项 (复制 / 旋转 / 翻转 / Finder / 废纸篓 / 缩放) 在主窗状态全 disable (灰)

**点击行为 (快速看图器在场)**:
- 图像→旋转左 点 = QV 内当前图旋转 90° (跟按 L 一样)
- 图像→水平翻转 点 = QV 内当前图水平翻 (跟 contextMenu 一样)
- 图像→在 Finder 中显示 点 = 弹 Finder 高亮当前图
- 图像→移到废纸篓 点 = 走 trash flow (跟按 Delete 一样)
- 编辑→复制图片 点 = 复制 NSPasteboard
- 显示→适合窗口 点 = QV resetToFit

**键盘行为回归 (零破坏)**:
- 按 ⌘F (主窗): 弹搜索 overlay (现状不变)
- 按 ⌘C (QV 内): 复制图片 (现状不变)
- 按 L (QV 内): 旋转左 (现状不变)
- 按 ⌫ (QV 内): 移废纸篓 (现状不变)
- 按 ⌘C (主窗): 系统默认行为 (不响应或系统「编辑→复制」)

**动态文案 (D-mb-8)**:
- Inspector 打开/关闭时菜单文案切换「隐藏信息」/「显示信息」

**disable state (D-mb-4)**:
- 主窗状态下旋转/翻转/复制/Finder/废纸篓/缩放 全部灰
- 主窗未选图时「显示信息」灰
- QV 在场 + 当前图加载成功时菜单项全 enable
- 主窗已显示时窗口→图库主窗 隐藏 (hide, 非 disable)

**a11y**:
- VoiceOver 读出菜单项文案 + 快捷键 hint (例「复制图片 Command C」)

预估第一批 ~20 项, 跟既有快速看图器增强 19 项 + 更多菜单 4 项 + 查找按钮 4 项 = 总 47 项军哥本机验。

---

## 10. 实施 checklist (v2 新增, P2-3)

plan 实施时硬约束:
- [ ] 改完 `.commands` 结构必须**重启 app 验证**, 不信 Xcode preview hot reload (macOS .commands 改动 hot reload 不刷新)
- [ ] 验证菜单顶级数量 + 菜单项数量 + 分隔符位置 (5 顶级 / 16 项 / 7 个分隔符)
- [ ] 验证 disable binding 是否实时响应 (打开 QV → 菜单项全 enable / 关 QV → 菜单项全 disable)
- [ ] 验证 NSOpenPanel 弹出后 app 菜单栏交互正常
- [ ] 验证 facade 单点 — copy 等动作 4 个入口 (contextMenu / 工具栏「更多」menu / 菜单栏 / 快捷键) 行为一致

---

## 11. i18n (v2 新增, P2-2)

**第一批不做 i18n**: 全部菜单文本 hardcoded zh-Hans。理由:
- 项目主用户单语 (zh-Hans)
- 自定义顶级菜单「图像」/「显示」hardcoded 中文 (区别于系统注入的 zh-Hans locale 翻译)
- 后续若英文 locale 需要, 单独 design (跟 `InfoPlist.strings` 已有 app 名 i18n 模式对齐)

**hint 字符串符号兼容**: ⌘ ⌃ ⌥ ⇧ ⌫ 是 Unicode, 跨 locale 无翻译需求。

---

## 12. 关联

- **前置 v1**: design v1 commit `5441f57` (codex review 后 RESHAPE)
- **同期**: 主窗 detail 工具栏查找按钮 followup (`2db5372`)
- **同源**: 快速看图器增强独立子系统 (`8525e18`..`66ab9fa` ship)
- **下游**: 第一批 design + codex 复审 + 军哥拍板后, 调 `superpowers:writing-plans` 产出 implementation plan; 第一批 ship 后第二批走独立 design v3
- **术语字典**: 「菜单栏」「快捷键」「工具栏」「快速看图器」「侧边栏」「缩略图」均按 CONTEXT.md 规范使用
