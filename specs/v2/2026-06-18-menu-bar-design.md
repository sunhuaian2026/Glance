# Glance V2 macOS 菜单栏增补 — Design

> **文件**: `specs/v2/2026-06-18-menu-bar-design.md`
> **作者**: 主 agent (`superpowers:brainstorming` skill) + 孙红军 (decision authority)
> **状态**: draft → codex review → 军哥拍板 → 走 `superpowers:writing-plans` → 实施
> **类型**: 独立子系统 (非里程碑, 不塞 M 序号)
> **关联**: 紧跟「主窗 detail 工具栏查找按钮 followup」(commit `2db5372`) 之后, 同一议题二阶段
> **关联术语字典**: `CONTEXT.md` A 段 (英文术语标 ✅) / C 段 (中英文边界) / D 段 (三层方法论)

---

## 0. 概述

为 Glance 主窗 macOS 菜单栏增补常用动作入口。

**当前现状**: `GlanceApp.swift` 只挂了一个 `CommandGroup(replacing: .appInfo) { AboutMenuButton() }` 把「关于一眼」塞 Apple 菜单下, 其它系统默认菜单 (文件 / 编辑 / 显示 / 窗口 / 帮助) 全为空壳, app 自定义的 12 项快捷键全部未在菜单栏暴露。

**本子系统目标**: 把这 12 项快捷键 + 2 个新动作 (添加文件夹根 / reopen 图库主窗) 按 macOS 标准范式分类挂到菜单栏, 让鼠标用户和不熟键盘的新用户能从菜单发现 + 触发, 同时不破坏快速看图器内现有 `.onKeyPress` 直接接管行为。

**非目标 (避 scope 蠕变)**:

- ❌ 不为主窗增添新动作 (复制 grid 选中 cell 的图 / 主窗直接旋转 等) — 单独 design
- ❌ 不重写快速看图器内已有 `.onKeyPress` 实现, 现有裸 F / L / R / Delete / 方向键全部保留
- ❌ 不引入新的工具栏改动 (主窗 detail 工具栏查找按钮已在 commit `2db5372` ship)
- ❌ 不做菜单项国际化 (中文菜单文本 hardcoded, 跟项目其它 UI 一致)

---

## 1. app 当前 12 项快捷键完整清单 (现状, 不变更)

| 快捷键 | 行为 | 现状生效域 |
|---|---|---|
| ⌘F | 打开查找 overlay | 主窗 + 快速看图器 (QV 内分支 `onCommandF`) |
| ⌘I | 切 Inspector | 主窗 toolbar button (现有) |
| F | 切全屏 | 仅快速看图器内 |
| L / R | 旋转左/右 | 仅快速看图器内 |
| ⌘C | 复制图片 | 仅快速看图器内 |
| ⌘⌥C | 复制路径 | 仅快速看图器内 |
| ⌘⇧R | 在 Finder 中显示 | 仅快速看图器内 |
| Delete / ⌘⌫ | 移到废纸篓 | 仅快速看图器内 |
| ⌘0 / 0 | 适合窗口 / 1:1 实际大小 | 仅快速看图器内 |
| ⌘= / ⌘- | 放大 / 缩小 | 仅快速看图器内 |
| ← / → | 切图 | 仅快速看图器内 |
| ESC / Space | 关快速看图器 | 仅快速看图器内 |

---

## 2. 决策段

### D-mb-1 菜单分类范式 = 标准三菜单 (编辑 / 显示 / 图像)

**决策**: 把 12 项快捷键 + 2 个新动作分到三个菜单, **不全堆「编辑」一个菜单**。

**军哥原话**: 「编辑菜单把我们常用的一些快捷键例如 F 是全屏这些加进去」。brainstorming 拍板按 macOS 标准范式分类, 非字面理解原话。

**菜单分类规则**:
- **编辑** (Edit) — 数据操作: 查找 / 复制图 / 复制路径
- **显示** (View) — 视图状态: 全屏 / 信息切换 / 缩放系列
- **图像** (Image) — 当前图操作: 旋转 / 翻转 / 在 Finder 中显示 / 移到废纸篓

**为什么不堆「编辑」**: macOS 用户根深蒂固在「显示」菜单找全屏 / 缩放, 在「图像」菜单找旋转 / 翻转 (mirror Preview.app / Photos.app 范式)。全堆「编辑」语义混乱, 菜单长度也失控 (15 项一长条)。

**Tradeoff 已知**: 三菜单负担略高于一菜单, 但 V3 / 未来扩展时有处安放, 长期一致性优于短期发现性。

**关联**: D-mb-2 / D-mb-4 / D-mb-5

---

### D-mb-2 全屏快捷键策略 = 双轨

**决策**: 菜单栏「进入全屏」keyEquivalent = `⌘^F` (macOS 标准), 快速看图器内裸 `F` 保留不变。

**背景**: 现状快速看图器内 `.onKeyPress(.init("f"))` 切全屏。macOS 系统标准全屏快捷键是 `⌘^F` (Cmd+Ctrl+F)。

**双轨理由**:
- 菜单栏挂 `⌘^F` → macOS 范式用户查菜单时一眼看到熟悉快捷键
- 快速看图器内裸 `F` 保留 → 军哥本人现有肌肉记忆不破坏, 单键比 ⌘^F 快
- 主窗按 `⌘^F` 也响应 → 主窗自己也能进系统全屏 (macOS 标准 NSWindow 全屏)
- 主窗**不响应**裸 `F` → 避免 TextField 输入时撞键风险

**实现路径**:
- 菜单项 `Button { toggleFullScreen() } .keyboardShortcut("f", modifiers: [.command, .control])` 全局生效
- 快速看图器内 `.onKeyPress(.init("f"))` 不动, 因 first responder 优先级会先 catch (QV NSHostingView 是 key window first responder)
- 实际两套独立 hot path, 不互相干扰

**Tradeoff 已知**: 一致性洁癖角度不 pure, 但兼顾军哥习惯 + macOS 范式是最实用解。

**关联**: D-mb-3 (keyboardShortcut 策略整体)

---

### D-mb-3 keyboardShortcut 挂载策略 = 保守 (⌘ 组合挂全局, 裸字母不挂菜单)

**决策**: 菜单项的 `.keyboardShortcut` 挂载分两类:

| 类型 | 例 | 是否挂 menu keyboardShortcut | 响应路径 |
|---|---|---|---|
| ⌘ 组合 (单/多修饰键) | ⌘F, ⌘^F, ⌘I, ⌘C, ⌘⌥C, ⌘⇧R, ⌘0, ⌘=, ⌘-, ⌘O | **挂** 全局 keyboardShortcut | 主窗状态时 SwiftUI commands 接 → 调 action; 快速看图器在场时 QV `.onKeyPress` 优先 (first responder 优于 menu equivalent in SwiftUI/AppKit) |
| 裸字母 / Delete / 方向键 | F, L, R, 0 (不带 ⌘), Delete, ←, → | **不挂** keyboardShortcut, **菜单文本手工拼快捷键 hint** (例「旋转左 (L)」) | 仅快速看图器 `.onKeyPress` 接 (现状不变); 鼠标点菜单触发 action |

**为什么裸字母不挂菜单**:
1. **撞键风险**: macOS NSMenu 的 keyEquivalent 在 NSWindow.sendEvent 早期 dispatch, **先于** first responder keyDown。SwiftUI Commands 的全局 keyboardShortcut 行为类似。挂裸字母会撞 TextField 输入 (虽然 NSText.performKeyEquivalent 一般 return NO, 但 SwiftUI NSHostingView 行为不可 100% 保证)
2. **状态隔离**: 裸字母的语义只在快速看图器内有意义 (旋转 / 删除 / 全屏)。主窗状态下挂全局没意义反而易撞
3. **现状保留**: 快速看图器内裸字母通过 `.onKeyPress` 直接接管的实现已 stable, 不引入新依赖

**Tradeoff 已知**: 用户在菜单看到「旋转左 (L)」可能期望 app 全局按 L 都能旋转, 实际只在快速看图器内响应。需要用户理解「快捷键 hint = 快速看图器内可用」, 但这是 Glance 的合理产品模型 (旋转/翻转只在看图器内有视觉)。菜单项 disable 状态时快捷键 hint 视觉灰显, 也是合理的 visual cue。

**关联**: D-mb-4 (disable 状态机)

---

### D-mb-4 菜单项 disable 策略 = 简单 binding (不建大状态机)

**决策**: 菜单项的 `.disabled()` 绑两个简单源, **不新建专职 ObservableObject 状态机**:

| 菜单项 | disable 条件 |
|---|---|
| 查找 ⌘F | 永远 enable (主窗 openSearch / QV onCommandF 都能响应) |
| 全屏 ⌘^F | 永远 enable (主窗 / QV 都可全屏) |
| 显示/隐藏信息 ⌘I | `folderStore.selectedImageIndex == nil` (复用现有主窗 toolbar 按钮逻辑) |
| 旋转左 / 旋转右 / 水平翻转 / 垂直翻转 | `!MainQuickViewerWindowController.shared.isShowing` (QV 不活就 disable) |
| 适合窗口 ⌘0 / 实际大小 / 放大 ⌘= / 缩小 ⌘- | 同上 (QV 不活就 disable) |
| 复制图片 ⌘C / 复制路径 ⌘⌥C / 在 Finder 中显示 ⌘⇧R | 同上 (QV 不活就 disable) |
| 移到废纸篓 ⌫ | 同上 + 当前根 schemaVersion >= 2 (V1 老 bookmark 不让删, mirror 快速看图器内 handleTrashCurrent guard) |
| 添加文件夹根 ⌘O | 永远 enable (调 NSOpenPanel) |
| 图库主窗 (窗口菜单) | `!MainWindowController.shared.hasWindow` (主窗在就隐藏菜单项, 不在就 enable; mirror AppDelegate.applicationShouldHandleReopen 逻辑) |

**为什么不建专职状态机**:
- 候选状态机方案 (新建 `MenuBarState: ObservableObject` 持 `isQuickViewerActive` / `hasCurrentImage` / `canDelete` 多 flag): 需要 ContentView / MainQuickViewerWindowController / QuickViewerViewModel 三处写状态, **耦合面广** + drift 风险
- 简单 binding: `MainQuickViewerWindowController.shared.isShowing` 现有单例直接读, `folderStore.selectedImageIndex` 现有 @Published 直接读
- 项目复杂度优先级: 菜单栏 disable 是低风险特性, 不值得为它建一套独立状态层

**实现要点**: `MainQuickViewerWindowController.shared` 当前是否暴露 `@Published var isShowing`? 待 plan 阶段 reality check (本 design 不假设, 列入「实施前确认项」)。

**Tradeoff 已知**: 简单 binding 跨 controller 耦合, 但 controller 已是单例; 等需求增长再升级到状态机。

**关联**: D-mb-3 / D-mb-7

---

### D-mb-5 范围 = 保守起步 (一次性挂全 17 个菜单项)

**决策**: 一次性把全部菜单项挂上, **不分批挂**。

**菜单项总数 = 17 项, 分布**:
- 现有快捷键里**适合挂菜单的 13 项**: ⌘F (查找) / ⌘I (信息) / ⌘^F (全屏, 菜单挂 ⌘^F 而非 QV 裸 F, 见 D-mb-2) / L (旋转左) / R (旋转右) / ⌘C (复制图) / ⌘⌥C (复制路径) / ⌘⇧R (Finder 显示) / ⌘⌫ (移废纸篓, 不挂裸 ⌫ 见 D-mb-3) / ⌘0 (适合窗口) / 0 (实际大小, 不挂 keyboardShortcut 见 D-mb-3) / ⌘= (放大) / ⌘- (缩小)
- 现有快捷键里**不挂菜单的 4 项**: ← / → (切图, 是 QV 内导航不进菜单) / ESC / Space (关 QV, 现状保留)
- **新增动作 (无现有快捷键, 仅 contextMenu) 2 项**: 水平翻转 / 垂直翻转
- **全新动作 + 新快捷键 2 项**: 添加文件夹根 ⌘O / 图库主窗 (无快捷键)

**为什么一次到位**:
- 菜单栏挂载是结构性改动, 分批挂会出现「菜单缺项 → 后续补」的中间态, 用户感知差
- 12 项全挂的改动量集中在 `GlanceApp.swift` 一个文件 (SwiftUI `.commands` ViewBuilder), 不外溢
- disable 策略 (D-mb-4) 已经覆盖「主窗状态下大部分动作 disable」, 一次挂全也不会噪音

**新增 2 项动作**:

1. **添加文件夹根 ⌘O** (文件菜单)
   - mirror 主窗侧边栏现有「+」按钮 + Finder 拖拽路径, 第三个入口
   - 调 `NSOpenPanel` 选目录 → `bookmarkManager.addBookmark(for:)` → `folderStore.loadSavedFolders()` (mirror 既有 addFolders 函数路径)
   - 用 `⌘O` 是 macOS 标准「打开」快捷键, 符合用户期望
2. **图库主窗 (窗口菜单)**
   - 关窗驻留模式 (D-OW15) 下用户关了主窗想召回时通过菜单 reopen
   - 调 `MainWindowController.shared.show(...)` (mirror `AppDelegate.applicationShouldHandleReopen` 路径)
   - 主窗已在场时菜单项隐藏 (`!hasWindow` 判断)

**Tradeoff 已知**: 一次挂 14 项 (12 + 2) 改动比分批大, 但 SwiftUI `.commands` 是声明式集中改动, 风险低于分布式改动。

**关联**: D-mb-1 / D-mb-4

---

### D-mb-6 实施途径 = SwiftUI `.commands` CommandGroup

**决策**: 通过 SwiftUI `Scene.commands(...)` + `CommandGroup(...)` / `CommandMenu(...)` 挂菜单, **不自建 NSMenu**。

**Mirror 现状**: `GlanceApp.swift` 现有 `.commands { CommandGroup(replacing: .appInfo) { AboutMenuButton() } }` 范式。本子系统继续沿用。

**CommandGroup 选用**:

| 菜单 | API | 备注 |
|---|---|---|
| 文件 (File) | `CommandGroup(after: .newItem) { ... }` | 在系统「新建」附近插入「添加文件夹根 ⌘O」 |
| 编辑 (Edit) | `CommandGroup(after: .pasteboard) { ... }` 或 `CommandGroup(replacing: .textEditing)` | 查找 / 复制图 / 复制路径 (paste board 段附近) |
| 显示 (View) | `CommandMenu("显示") { ... }` 或 `CommandGroup(replacing: .sidebar) { ... }` | 全屏 / 信息切换 / 缩放系列 |
| 图像 (Image) | `CommandMenu("图像") { ... }` | 全新顶级菜单 (macOS 默认无), 旋转 / 翻转 / Finder / 废纸篓 |
| 窗口 (Window) | `CommandGroup(after: .windowList) { ... }` | 「图库主窗」reopen 入口 (在系统窗口列表之后) |

**Commands 内 View 状态观察**:
- `CommandGroup` / `CommandMenu` 接受任意 `View` 作为 content
- 自定义 struct 形态 view (持 `@ObservedObject` 引用 `MainQuickViewerWindowController.shared` 等单例) 可在 commands 内 instantiate
- 不需要 `.environmentObject()` 路径 (Scene-level 注入复杂, 单例 + observed object 更简单)

**为什么不自建 NSMenu**:
- 自建需要 `NSApp.mainMenu = ...` + 自己管 NSMenuItem 生命周期 + dynamic enable/disable 写 `NSMenuItemValidation`
- 跟项目现有 SwiftUI 架构断裂, 维护成本高
- SwiftUI `.commands` 范式已经够用, 复杂度 fit 项目规模

**Tradeoff 已知**: SwiftUI Commands 在 macOS 14 部分 API 有限制 (例如不能动态修改菜单结构, 但本子系统是静态结构, 不受影响)。disabled state 动态绑定通过 view 内 @ObservedObject 实现可行。

**关联**: D-mb-4 (状态观察机制)

---

### D-mb-7 菜单文本快捷键 hint 风格 = 手工拼字符串

**决策**: 不挂 keyboardShortcut 的菜单项, **菜单文本内手工拼快捷键 hint**, 风格 mirror 项目现有工具栏 tooltip。

**风格规范**:
- 旋转左: `「旋转左 (L)」`
- 旋转右: `「旋转右 (R)」`
- 水平翻转: `「水平翻转」` (无快捷键, 无 hint)
- 垂直翻转: `「垂直翻转」` (无快捷键, 无 hint)
- 移到废纸篓: `「移到废纸篓 (⌫)」` (Delete 用 ⌫ 符号, mirror contextMenu)
- 适合窗口 (无 ⌘): `「适合窗口 (⌘0)」` (此项挂 keyboardShortcut, hint 是 SwiftUI 自动渲染, 但 Label 文本也含 ⌘0 字样保持视觉一致)

**为什么不依赖 SwiftUI Label 自动渲染**:
- 挂 `.keyboardShortcut` 的菜单项 SwiftUI 自动右侧渲染快捷键 hint (✓)
- 不挂 keyboardShortcut 的菜单项 SwiftUI 不渲染 hint, 需要手工拼到 Label 文本
- 项目现有工具栏 tooltip 风格 (`「适合 (⌘0)」`) 已先例, 一致性高

**关联**: D-mb-3

---

### D-mb-8 动态文案策略 = 切换状态项有, 其余不切

**决策**: 菜单项的文案动态切换仅限两项, 其它静态:

| 菜单项 | 静态文案 | 动态文案 |
|---|---|---|
| 全屏 | — | 主窗/QV 全屏中: 「退出全屏 (⌘^F)」; 否则: 「进入全屏 (⌘^F)」 |
| 信息 (Inspector) | — | Inspector 展开: 「隐藏信息 (⌘I)」; 否则: 「显示信息 (⌘I)」 |
| 旋转左 | 「旋转左 (L)」 | — (无状态切换) |
| 旋转右 | 「旋转右 (R)」 | — |
| 水平翻转 | 「水平翻转」 | — |
| 垂直翻转 | 「垂直翻转」 | — |
| 复制图片 | 「复制图片」(系统 ⌘C 自动 hint) | — |
| 复制路径 | 「复制路径」(系统 ⌘⌥C 自动 hint) | — |
| 在 Finder 中显示 | 「在 Finder 中显示」(系统 ⌘⇧R 自动 hint) | — |
| 移到废纸篓 | 「移到废纸篓 (⌫)」 | — |
| 适合窗口 | 「适合窗口」(系统 ⌘0 自动 hint) | — |
| 实际大小 | 「实际大小 (0)」 | — (不挂 keyboardShortcut, 手工 hint) |
| 放大 / 缩小 | 「放大」/「缩小」(系统 ⌘= / ⌘- 自动 hint) | — |
| 查找 | 「查找…」(系统 ⌘F 自动 hint) | — |
| 添加文件夹根 | 「添加文件夹根…」(系统 ⌘O 自动 hint) | — |
| 图库主窗 (窗口菜单) | 「图库主窗」 | — |

**为什么动态文案只限 2 项**:
- 全屏 / Inspector 是双态可切换 (UI 状态机), 动态文案给用户当前态反馈
- 其它项是单向触发 (旋转/复制/删除 都是 one-shot), 无对应反向操作, 不需要动态文案
- 减少 SwiftUI Commands ViewBuilder 内的 @ObservedObject 数量 (复杂度可控)

**全屏状态源 (双窗口处理)**:
项目有两个独立全屏状态: 主窗 `AppDelegate.appState.isFullScreen` 和快速看图器 `MainQuickViewerWindowController.shared.viewerAppState.isFullScreen`。菜单文案规则:

```
isAnyFullScreen = appState.isFullScreen || viewerAppState.isFullScreen
菜单文案 = isAnyFullScreen ? "退出全屏 (⌘^F)" : "进入全屏 (⌘^F)"
```

action 调用: 看当前 key window 是谁:
- 主窗是 key → 调 `appState.toggleFullScreen()` (走主窗 NSWindow 系统全屏)
- 快速看图器是 key → 调 `viewerAppState.toggleFullScreen()` (走 QV 4 态状态机, 见 `MainQuickViewerWindowController` Slice2 设计)
- 都不是 key (理论上不应该, 但兜底) → no-op

**Tradeoff 已知**: 「移到废纸篓」无「从废纸篓还原」反向项 — 因 QV 内单张撤销已经在右下角 toast (`TrashUndoBanner` 模式), 主窗 banner 也有, 菜单栏不重复。

**关联**: D-mb-4

---

## 3. 完整菜单结构 (最终方案)

```
Apple 菜单
├ 关于一眼                       (现有)
├ ─────
└ 退出一眼                ⌘Q     (系统默认)

文件 (File)
├ 添加文件夹根…           ⌘O     ← 新增 (D-mb-5)
├ ─────
└ 关闭                    ⌘W     (系统默认)

编辑 (Edit)
├ (系统默认: 撤销 / 重做 / 剪切 / 复制 / 粘贴) [置顶, 系统注入]
├ ─────
├ 查找…                   ⌘F     ← 新增 (D-mb-1)
├ ─────
├ 复制图片                ⌘C     ← 新增 [disable: !QV.isShowing]
└ 复制路径                ⌘⌥C    ← 新增 [disable: !QV.isShowing]

显示 (View)
├ 显示信息 / 隐藏信息     ⌘I     ← 新增 (动态文案 D-mb-8) [disable: !folderStore.selectedImageIndex]
├ ─────
├ 适合窗口                ⌘0     ← 新增 [disable: !QV.isShowing]
├ 实际大小 (0)                   ← 新增 (D-mb-7 手工 hint) [disable: !QV.isShowing]
├ 放大                    ⌘=     ← 新增 [disable: !QV.isShowing]
├ 缩小                    ⌘-     ← 新增 [disable: !QV.isShowing]
├ ─────
└ 进入全屏 / 退出全屏     ⌘^F    ← 新增 (动态文案 D-mb-2 D-mb-8)

图像 (Image) ← 全新顶级菜单 (D-mb-1)
├ 旋转左 (L)                     ← 新增 (D-mb-7 手工 hint) [disable: !QV.isShowing]
├ 旋转右 (R)                     ← 新增 [disable: !QV.isShowing]
├ ─────
├ 水平翻转                       ← 新增 [disable: !QV.isShowing]
├ 垂直翻转                       ← 新增 [disable: !QV.isShowing]
├ ─────
├ 在 Finder 中显示       ⌘⇧R    ← 新增 [disable: !QV.isShowing]
├ ─────
└ 移到废纸篓 (⌫)                 ← 新增 (D-mb-7 手工 hint) [disable: !QV.isShowing OR schemaVersion<2]

窗口 (Window)
├ (系统默认: 最小化 / 缩放 / 全屏切换) [置顶, 系统注入]
├ ─────
└ 图库主窗                       ← 新增 (D-mb-5) [hide when MainWindowController.shared.hasWindow]

帮助 (Help)
└ (系统默认, 无新增)
```

**菜单分隔符使用规则**: 仅在语义不同的子组之间用分隔符 (如「全屏」与「缩放系列」之间), 同组之间 (如旋转左/右) 不分隔。

---

## 4. 实施任务概览 (高层, 不替 plan)

> 详细 task 拆分留给 `superpowers:writing-plans` skill。下面是高层 task 框架, 用于 codex review 时讨论实施可行性。

预估改动文件:

| 文件 | 改动 |
|---|---|
| `Glance/GlanceApp.swift` | 主体改动: `.commands` ViewBuilder 内挂 5 个菜单 CommandGroup/CommandMenu, 每个内含 N 个 Button + .keyboardShortcut + .disabled binding。预计 +150 行 |
| `Glance/QuickViewer/MainQuickViewerWindowController.swift` | 加 `@Published var isShowing: Bool` (如未暴露), 在 show()/close() 中切换。预计 +5 行 |
| `Glance/MainWindow/MainWindowController.swift` | 已有 `hasWindow` (CLAUDE.md 描述确认), 可直接用。无改动 |
| 新建 `Glance/MenuBar/MenuBarCommands.swift` (可选) | 把 GlanceApp.body.commands 内 5 个 CommandGroup 拆出来到独立文件 (提升可读性, 单文件 200 行内) |
| 新建 `Glance/MenuBar/MenuBarActions.swift` (可选) | 集中菜单 action 函数 (调 MainQVController / openSearch / addFolder 等)。预计 +60 行 |
| `Glance/DesignSystem.swift` | 不改动 (菜单无视觉常量) |
| `specs/Roadmap.md` / `CLAUDE.md` / `specs/PENDING-USER-ACTIONS.md` | 文档同步 (任务收尾) |

预估任务节奏:

1. **任务 A**: 状态暴露 (`MainQuickViewerWindowController.isShowing` @Published) + 单元 reality check (action 函数现有 API)
2. **任务 B**: 文件菜单「添加文件夹根 ⌘O」+ 编辑菜单 (查找 / 复制图 / 复制路径)
3. **任务 C**: 显示菜单 (信息切换 / 缩放系列 / 全屏)
4. **任务 D**: 图像菜单 (旋转 / 翻转 / Finder / 废纸篓)
5. **任务 E**: 窗口菜单 (图库主窗 reopen)
6. **任务 F**: 任务收尾 (verify / 文档同步 / PENDING / commit / push)

每任务都满足 vertical slice 三条 (端到端可跑 / 用户可感知 / 独立可 ship)。

---

## 5. 风险表 (R-mb-*)

| ID | 风险描述 | 缓解 |
|---|---|---|
| R-mb-1 | SwiftUI `.commands` 内 View 用 `@ObservedObject` 观察 `MainQuickViewerWindowController.shared.isShowing` 时, SwiftUI 不一定接收变更通知 (Scene-level state 不像 View-level 一致) | plan 阶段 spike 验证: 写 minimal 测试 commands 内 button .disabled() binding 是否随 publisher 更新 |
| R-mb-2 | macOS 系统注入的「文件→关闭」「编辑→剪切/复制/粘贴」「窗口→全屏」等默认菜单项可能跟自定义项冲突 | 用 `CommandGroup(after: ...)` / `CommandGroup(replacing: ...)` 显式定位, 不混入系统组 |
| R-mb-3 | NSMenu 的 `⌘C` keyEquivalent 跟系统「复制」冲突, 用户在主窗 grid 选中 cell 按 ⌘C 期望「复制 grid 选中」 (虽然现在不支持), 菜单挂 `⌘C` 到「复制图片」可能拦截 | 「复制图片」menu item disable when !QV.isShowing → ⌘C 不被菜单接 → 系统「复制」默认 fall back; QV 内 ⌘C 由 QV `.onKeyPress` 接 (现状) |
| R-mb-4 | `⌘^F` 全屏快捷键跟 macOS 系统全屏 (绿色 traffic light) 是否冲突 | macOS 系统全屏的 menu equivalent 默认是 `⌃⌘F`, 跟我们挂的 `⌘^F` 是同一个键, **会冲突**。需要 plan 阶段确认: (a) 用 `CommandGroup(replacing: .toolbar)` 替换系统 toolbar 组 (但 toolbar 不是全屏); (b) 用 `CommandGroup(replacing: .fullscreen)` 如果 macOS 14 暴露此 API; (c) 落到 `CommandMenu("显示")` 独立挂, 让两套 ⌘^F 都响应 (都是切全屏, 不冲突仅重复) |
| R-mb-5 | `.environmentObject()` 路径在 Scene + Commands 跨 boundary 是否正常工作 | 避免依赖 environment, 改用 `MainQuickViewerWindowController.shared` 单例直接持; 这是项目现有范式 |
| R-mb-6 | 菜单项 disable state 因 `@Published var isShowing` 状态更新延迟一帧, 用户能看到「短暂可点 → 立刻 disable」闪烁 | 一帧延迟在 macOS 菜单语境下肉眼不可感; 真有问题 plan 阶段加 `objectWillChange.send()` 显式触发 |
| R-mb-7 | 「图库主窗」reopen 时 BookmarkManager / FolderStore / IndexStoreHolder 实例是否一致 | AppDelegate 持单例, 调 `MainWindowController.shared.show(bookmarkManager: appDelegate.bookmarkManager, ...)`, 跟现有 `showMainWindow` 路径一致 |
| R-mb-8 | NSOpenPanel 在 `.commands` 内 Button action 中调用, AppKit 模态窗是否影响菜单生命周期 | NSOpenPanel.runModal 是 modal session, 不影响菜单。mirror 现有 `BookmarkMigrationCoordinator.pickRoots` 路径 |
| R-mb-9 | 「移到废纸篓 ⌫」menu item keyEquivalent 用裸 `⌫` 还是 ⌘⌫? 现状 QV 内两个都触发 | 菜单挂 keyboardShortcut 仅 `⌘⌫` (⌘ 组合, 全局安全), 裸 `⌫` 仅在 QV 内 `.onKeyPress(.delete)` 接 (mirror D-mb-3 规则: 裸字母不挂菜单) |
| R-mb-10 | 「适合窗口 ⌘0」与 SwiftUI 系统默认菜单「Actual Size ⌘0」冲突 (Preview.app 默认 ⌘0 是 1:1, ⌘+ 是 fit window? 或反过来) | 跟项目现有约定一致: ⌘0 = 适合窗口, 裸 0 = 实际大小 1:1 (D-mb-7); 跟 macOS 系统 toolbar 命令组冲突时显式 CommandGroup(after: ...) |

---

## 6. 实施前确认项 (Plan 阶段 Reality Check)

writing-plans skill 实施前必须 grep 实际代码确认 (避免「写 implementation plan 引用已有代码前必须 Read 实际文件」教训):

- [ ] `MainQuickViewerWindowController.shared.isShowing` 是否已暴露为 `@Published`, 若否需补
- [ ] `MainWindowController.shared.hasWindow` 实际签名 (Bool / @Published Bool / async)
- [ ] `bookmarkManager.addBookmark(for:)` 实际签名 (sync / async / throws)
- [ ] `folderStore.loadSavedFolders()` 实际签名 (是否需要 await)
- [ ] `openSearch()` 函数是否已经在 ContentView 暴露 internal / private (commands 内能否直接调)
- [ ] R-mb-4: macOS 14 SwiftUI 是否有 `CommandGroup(replacing: .fullscreen)` (或等价)
- [ ] AppDelegate 持的 `appState` 是否能被 GlanceApp.body 直接持 reference (initializer 注入)
- [ ] 项目部署目标 macOS 14 下 `CommandGroup` 所有用到的 placement (`.newItem`, `.pasteboard`, `.sidebar`, `.windowList`) 是否都可用

---

## 7. 开放问题 (留给 codex review / 军哥)

1. **菜单顶级名称中文化**: macOS 标准的 File/Edit/View/Window/Help 在 zh-Hans locale 自动渲染为「文件/编辑/显示/窗口/帮助」(系统注入)。新建 `CommandMenu("图像")` 是自定义顶级, 必须用中文 hardcoded。需要英文 locale 时该如何? 当前项目只 zh-Hans + en 两个 locale, 但 InfoPlist.strings 已经做了 app 名 i18n。菜单 i18n 是否需要这次做?
   - **当前提议**: 不做 i18n, 全 hardcoded 中文。理由: 减少复杂度, 单语用户为主。
2. **「关闭」菜单项的语义**: 主窗 ⌘W = 关图库主窗 (走 D-OW15 关窗驻留); 快速看图器 ⌘W (现状无) = 关 QV? 还是 ESC/Space 已经够用不需要菜单?
   - **当前提议**: 不加 ⌘W 关 QV, 保留 ESC/Space + 红色 traffic light close
3. **菜单顺序**: 文件 / 编辑 / 显示 / 图像 / 窗口 — 「图像」插在「显示」和「窗口」之间是 macOS Photos.app 范式。是否符合军哥审美?
4. **「适合窗口 ⌘0」与「实际大小 0」** menu 行同时存在, 但裸 `0` 不挂 keyboardShortcut (D-mb-3 规则), 菜单显示「实际大小 (0)」手工 hint 是否怪? 用户从菜单点能用, 但快捷键提示是「0」(无修饰) 不像标准 menu equivalent 风格
   - **当前提议**: 接受怪感, 保持现状 QV 内裸 0 = 1:1; 替代方案是把裸 0 也升级为 ⌘^0 或 ⌘0 后改 fit window 用别的键
5. **菜单挂载后, 快速看图器内裸字母按键事件流是否会变?** 现状裸字母通过 `.onKeyPress` 在 QV NSHostingView focused 时接管, 菜单挂载 `⌘ 组合` keyboardShortcut 应不影响裸字母; 但需要 plan 阶段 reality check 一遍 SwiftUI Commands 全 key down 流向

---

## 8. 实施完成后 PENDING 真机肉眼验项预估

> 详细 list 留给实施任务收尾时写 PENDING-USER-ACTIONS.md。预估覆盖范围:

- 5 菜单可见性 + 项数量对照
- 14 项菜单可点击执行 (12 已有快捷键 + 2 新增)
- ⌘ 组合快捷键全局触发 (主窗状态 + QV 状态)
- 裸字母仅 QV 内响应 (现状不变, 回归测试)
- 动态文案切换 (全屏 / 信息) 真机看
- disable state 正确 (主窗状态下大部分图像菜单灰)
- NSOpenPanel 打开/取消行为
- 「图库主窗」reopen 关窗驻留场景

预估 ~25 项, 跟既有快速看图器增强 19 项 + 更多菜单 4 项 + 查找按钮 4 项 合并验。

---

## 9. 关联

- **前置**: 主窗 detail 工具栏查找按钮 followup (`2db5372`)
- **同源**: 快速看图器增强独立子系统 (`8525e18`..`66ab9fa` ship)
- **下游**: 等本 design + codex review + 军哥拍板后, 调 `superpowers:writing-plans` 产出 implementation plan
- **术语字典**: 「菜单栏」「快捷键」「工具栏」「快速看图器」「侧边栏」「缩略图」均按 CONTEXT.md 规范使用
