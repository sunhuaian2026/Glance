# Glance（原 ISeeImageViewer）Roadmap

## 总体目标

打造一款 macOS 原生风格、界面精致的本地看图 app（Glance · 一眼）。

**初心（2026-06-09 军哥澄清，纠正之前"纯看图器"理解偏差）**：图片散在不同盘 / 文件夹，可能有相似 / 重复但用户不知道——Glance 帮你**找出哪些图相似 / 重复 → 清理 → 省硬盘空间**。看图 / 浏览是**辅助手段**（清理前确认删哪张），不是终极目的。

**一句话定位**：比 Eagle 更轻、免费的「**找重复 / 相似图、清理省硬盘空间**」工具。Eagle 付费 + 重管理锁库，Glance 免费 + 不抢库 + 轻。

**核心红线（决定加不加功能，新 session / 迷路时先读这两条）**：
1. **不抢库**：图永远在用户原文件夹，Glance 只是浏览器；卸载后用户的图 / 文件夹结构 / 组织方式一点不变（对比 Eagle 靠锁库吃留存）。智能文件夹永远是 rule-based 查询结果，绝不存 app 自有的图组织数据（见关键架构决策 V2 D1）。
2. **克制 + 回归初心**：新功能进来前先问「这服务『找重复 / 清理省空间』初心，还是又往『看图浏览』堆？」。⚠️ **当前已知偏差**：精力堆在了看图浏览侧（智能文件夹 / 全局搜索 / QuickViewer / 全屏 / QV toolbar），而初心的核心闭环「**主动扫出重复 / 相似 → 一览 → 批量删除省空间**」反而没闭环（**删除功能压根没做**）——见下方待开发 M4 + memory `glance_mission_gap_m4`。注意：类似图查找 / 去重是**初心核心**（不是浏览功能），智能文件夹 / 搜索才是浏览辅助。不抢库红线仍不破（标签 / 收藏夹 / 评分 / 导入一律砍）。

---

## 当前进度（2026-05-09）

**V2.0 GA ship 完成（2026-05-09）— V2 M1 全部 Slice 累积 deliverable 齐**

- **V2.0 GA**（2026-05-09 ship + tag `v2.0`）：V2 M1 全部 9 个 deliverable Slice（A/B/C/D/E/F/G/H/I）累积 ship
- **V2 M1 Slice A（V2.0-beta1）**：IndexStore (sqlite3) + 单 folder scan + "全部最近" 智能文件夹 + Sidebar IA 改造 + cross-folder grid 完整对齐 V1
- **V2 M1 Slice B（V2.0-beta2）**：时间分段 chip sticky header + 第 2 内置 SF「本周新增」+ 键盘 (sectionIdx, row, col) 导航算法
- **V2 M1 Slice D（V2.0-beta3）**：hide toggle 右键菜单（稀疏 explicit walk SQL）+ Inspector 来源 path 段 + "在 Finder 中显示"按钮
- **V2 M1 Slice G（V2.0-beta4）**：删 root 清理（FK CASCADE）+ FSEvents 增量监听（每 root 一 stream，ItemCreated/Removed/Modified/Renamed 实时同步）
- **V2 M1 Slice H（V2.0-beta5）**：内容去重 SHA256 + cheap-first 粗筛 + Inspector 副本段 + orphan duplicate 自动 promote
- **V2 M1 Slice I（V2.0 GA）**：首次索引进度 chip + 错误处理 banner + 取消 + 进度持久化 + SmartFolderStore enum-state 重构
- **V2 M2 Slice J（V2.1-beta1）**：后台 Vision feature print 索引 + QV 找类似按钮 + EphemeralResultView 端到端
- **V2 M2 Slice K（V2.1 GA）**：Vision revision 启动期迁移 + 瞬时失败 retry policy + 错误 banner 文案润色（性能验收 deferred）
- **V2 M3 Slice L（V2.2-beta1）**：3 个新内置 SmartFolder（上个月 / 截图 / 大图）+ Calendar 自然月边界 token
- **V1 v1.0**：已公开发布（GitHub Release + DMG + 仓库 public，2026-05-08 commit `0c9f699`）
- 工程化基建：`/go` 五步 / `verify.sh` 三段 oracle / `build/Glance.app` 自动 sync `~/sync/` / pre-push codex hook / build 版本号注入 + BuildInfo sidecar
- 下一步主线：V2 M3 Slice M（⌘F 搜索 → V2.2 GA）
- **V2 M4 任务 2 状态（2026-06-17）**：步骤 1 spike 三轮跑通,根因定位 V1 bookmark read-only scope（spike `Glance/_SpikeTask2CrossRoot.swift` 已 `git rm` 弃）。codex review 第五轮拍 A 方向（清旧 + schemaVersion 哨兵 + M4 删除入口首次触发清重选）已折入 design 4.5.4 + 8.2 (e) 解锁条件 + 风险 2 段实证 + plan 步骤 1.6 + 2.0.5；entitlement read-write 已同步 pbxproj + Glance.entitlements（codex 抓的两份事实漂移已修）。**任务 2 状态切「卷类型矩阵 + bookmark 迁移 design 已收敛, 待 plan 实施步骤 2.0.5 + 步骤 3-5 触发流 + 真机本地跑剩余卷类型 (b)(c)(d)」**。

---

## 已完成模块

| 模块 | Spec | 最后 Commit | 说明 |
|------|------|-------------|------|
| BookmarkManager | BookmarkManager.md | d88baa0 | Security Scoped Bookmark 持久化 |
| FolderStore | FolderStore.md | d88baa0 | 状态管理，含 imageCountByFolder |
| FolderSidebarView | FolderBrowserView.md | 0abde01 | 右键菜单、badge、文件夹列表 |
| ImageGridView | FolderBrowserView.md | 0abde01 | 160px 缩略图、文件名、双击进入 |
| ImageViewerView | ImageViewerView.md | 0abde01 | 自动隐藏控件、Filmstrip |
| DesignSystem | UI.md | 9230bc7 | DS.* 所有 UI 常量，全代码已对齐 |
| UIRefresh（Phase 1） | UIRefresh.md | 0abde01 | 三栏布局、Inspector 面板、过渡动画 |
| QuickViewer | QuickViewer.md | 9018877 | 沉浸式全窗口查看器，缩放/平移/导航，替代 ImageViewerView |
| KeyboardShortcuts | KeyboardShortcuts.md | 8885893 | 网格方向键导航、Space 进入查看器、缩放快捷键 |
| SortFilter | SortFilter.md | a2d1fc2 | 6 种排序，UserDefaults 持久化，Toolbar Menu |
| Inspector | Inspector.md | faf77ac | EXIF 元信息面板，相机/拍摄参数/GPS |
| FullScreen | AppState.md | 0abcae6 | NSWindow.toggleFullScreen，F 键切换，NSWindowDelegate 监听 |
| Liquid Glass UI | UI.md | 9a0cfde | DS.Anim / 新色系 / 毛玻璃控件 / 光晕 / 浮动气泡 Toolbar |
| 树形侧边栏 | FolderBrowserView.md | e8aec40 | FolderNode + discoverTree，List(children:) 展开/折叠 |
| AppearanceMode | AppState.md | b4363e7 | 深/浅/系统三档外观切换，UserDefaults 持久化 |
| ThumbnailSizeSlider | ThumbnailSizeSlider.md | 85ca376 | Toolbar 滑块调整缩略图尺寸（80~280pt），UserDefaults 持久化 |
| Prefetch | Prefetch.md | 849b4ae | QuickViewer ±1 图片预加载缓存，切换零延迟，CGImage 缓存 ±2 窗口 |
| AppIcon | — | fb6231c | Claude Design (Anthropic Labs) 出的 The Eye Mark · Cool Violet 方向：紫主底 + 青绿瞳孔光晕 + 白细描边，呼应 "I See" / 「一眼」双关 + 项目 DS.Color 紫青配色。master `assets/icon-1024.png` 透明背景方形画布；10 个 macOS 标准尺寸（16/32/128/256/512 各 1x+2x）由 sips 派生到 `Assets.xcassets/AppIcon.appiconset/`，Contents.json 配齐 filename 引用，xcodebuild 自动打包成 AppIcon.icns 进 .app/Contents/Resources |
| Rename | — | 8e6de41 | 应用全面重命名 ISeeImageViewer → **Glance · 一眼**（2026-04-27），三阶段 commit：6a7f870 phase 1 / 8e6de41 phase 2（主） / f46f8cd phase 3。phase 1 (6a7f870)：Bundle ID `uupt.ISeeImageViewer` → `com.sunhongjun.glance`，双语 Display Name 走 Apple i18n（zh-Hans 显示「一眼」/ en 显示「Glance」，via lproj/InfoPlist.strings）。phase 2 (8e6de41)：target / 源目录 / xcodeproj / App struct（`ISeeImageViewerApp` → `GlanceApp`）/ entitlements / Makefile / verify.sh / pre-push hook / 13 个干净 .swift header 全部统一。phase 3 (f46f8cd)：文档 + auto-memory + 全局 sunerpang CLAUDE.md 同步 [docs-only]。**未改**：项目根目录磁盘路径（保 auto-memory 路径连续）、GitHub 仓库名（择日单独操作）、git 历史 commit message（真实历史保留）、`docs/archive/*.md`（历史快照）、`Glance/ContentView.swift` & `Glance/FolderBrowser/ImageGridView.swift` 的旧 header（用户未提交 debug 代码占位中）。Bookmark / UserDefaults 因 Bundle ID 变更失效（已与用户确认重测可接受）|
| BuildVersionInfo | — | 38adfd4 | build 版本号注入 + BuildInfo.txt sidecar，取代不可靠 mtime 当跨机判断真值。Makefile + verify.sh 两条 build 路径同步通过 `xcodebuild ... CURRENT_PROJECT_VERSION="<commit>[-d].<MMDD-HHMM>"` 写入 Info.plist `CFBundleVersion`；同时输出 `Glance.app.BuildInfo.txt` sidecar（commit / dirty / version / commit_time / commit_msg / built_at / host 七字段）。-d 后缀标记 working tree 有未 commit 改动避免误读 |
| AboutPanel | — | 8f927d1 | 完整收口于 6f56072（toast/复制配套）。自定义"关于一眼"窗口（替换标准 NSAboutPanel）。原因：标准面板 NSHumanReadableCopyright 字段不可点击，无法挂复制 handler。新建 `Glance/About/AboutView.swift`：AppIcon 96px / 名称 / 动态版本号 / 两行可点击 contact（`© 2026 孙红军 · 16414766@qq.com` / `小红书 382336617`），点击复制全文到剪贴板 + 1.5s toast。GlanceApp 加 `CommandGroup(replacing: .appInfo)` + `Window("about")` scene。Text + onTapGesture 替代 Button 避免 macOS focus ring 残留（09c418c 修），补 `.accessibilityAddTraits(.isButton)` 保 a11y。DS.About 段（windowWidth/appIconSize/toastMaxWidth/toastDurationSeconds）+ DS.Color.secondaryText alias 到 SwiftUI .secondary |

---

## Bug Fix 记录

| Commit | 说明 |
|--------|------|
| QV toolbar 方案2 S1+S2 `ebd88bf`~`a4520c5` | **QV/全屏 toolbar regression（方案2 独立看图窗）**：方向2 Slice2 后主窗 NSHostingView 让 SwiftUI 持续复写 `.toolbar{}` 回 titlebar、看图不纯净。修：QV 从 ContentView `.overlay` 迁 `MainQuickViewerWindowController` 独立无装饰窗。**Slice1 windowedCover**（`ebd88bf`~`4cb1323`，9 项真机验过 2026-06-08）+ **Slice2 全屏**（`5d47b3c`~`a4520c5`，3 态状态机 + enteredFromMainFullScreen flag；inheritedMain 主窗全屏进 QV 走 codex 候选2 = QV 自己原生全屏新 Space；候选1 borderless+fullScreenAuxiliary 满屏覆盖踩 3 坑弃用；6 项 windowedCover/qvNative/最小化/全屏退出焦点/换屏 真机验过 2026-06-15 + inheritedMain 真机验过 2026-06-09）。**整 QV toolbar regression 修复至此完整收口**。详见关键架构决策第 11 条 + `specs/v2/2026-06-08-qv-toolbar-*`。Slice3（边界硬化）未启动 = backlog；小图全屏放大 = 独立 backlog 待重做（见 PENDING）。 |
| （本次）| M3 chips Slice N 真机验暴露 + 根因修复（军哥拍板焦点归还方向）：选完 chip 关 popover 后焦点没回搜索框 → 回车无反应（TextField 失焦收不到 `.onKeyPress(.return)`）+ 用户只能点 X 关闭但 X=放弃搜索 → 清空 `searchFilterState` 回默认 grid（筛选丢失）。根因=SwiftUI `@FocusState` 值不变不重新聚焦（关 popover 时 `focusTarget` 仍 == `.search`，物理键盘焦点没回 TextField），与上 session「⌘F 焦点不落 input」同源。修：`SearchChipBar` 透传 `@FocusState.Binding`，三 popover 各加 `.onChange(of: showXxxPopover)` dismiss 时 `returnFocusToSearch()`（先 `focusTarget=nil` 再 `Task.yield` 设 `.search` 弹一下绕过值不变不重聚焦，mirror `openSearch` 延迟单点设）。统一 chip+keyword 都走搜索框回车提交，**不加「应用」按钮**（界面克制 + 一并结 codex 此前 bypass 的焦点 P1）。**待真机验证焦点是否真回**（PENDING Slice N） |
| （本次）| M3 chips Slice N2 codex pre-push P1 — `SearchChipBar.chipButton` 硬编码 `0.12`(未选背景 opacity)/`0.5`(选中 stroke opacity)/`1`(lineWidth) + `Spacer(minLength: 0)` 违反 CLAUDE.md「UI 常量必须 DS.*」。plan N2.2 代码块本身漏网（design/plan 两轮 codex review 看的是文档，没抓到落地代码硬编码 → pre-push 看代码才抓到）。修：抽 `DS.Search.chipUnselectedOpacity/chipStrokeOpacity/chipStrokeWidth` 三常量 + `Spacer(minLength: DS.Spacing.zero)`。pre-push 反馈循环触发，是真 P1 不 bypass（feedback `feedback_codex_prepush_no_easy_bypass.md`）。**同轮另两项军哥拍板**：(1) codex 第二轮又要求 `Color.accentColor`/`.secondary`/`.clear` 系统语义色也 DS 化 → 经核**判定假阳**（项目 SmartFolderGridView/ListView 等 7+ 处同款惯例未 DS 化 + hook PROMPT 规则 7 本只 reject hex/Color(red:)，codex 自己加码）→ 改 `.githooks/pre-push` 规则 2/7 加系统语义色 EXEMPTION 2（根因修复非 bypass）；(2) P2 `SearchTimeBucket` label「本周/本月/今年」原滚动窗 `-7d/-30d/-365d` 语义不符 → 改自然边界：`startToken` 全档 Calendar 预计算 ISO（本周起始日/本月1号/今年1.1，device local），mirror「今天」午夜走 resolveRelativeTime ISO8601 分支 |
| M4 任务 1 步骤 4（本次）| **五态互斥 + handleFindSimilar 竞态**：(1) wireIfReady 竞态：用户点「重复清理」时 IndexStore 尚未就绪 → model.load() 因 "IndexStore 未装配" 卡 error 态；修：wireIfReady 末尾补 `if showDuplicateOverview { await duplicateOverviewModel.load() }`。(2) searchTask 竞态：进入总览时 in-flight searchTask 完成后写 currentEphemeral 强行踢回搜索结果；修：`.onChange(of: showDuplicateOverview)` 块内加 `searchTask?.cancel(); searchTask = nil`。(3) handleFindSimilar 竞态：找相似异步查询期间用户切到总览，async 完成后无条件写 currentEphemeral 并清 showDuplicateOverview；修：`await MainActor.run` 块首加 `guard !showDuplicateOverview else { return }`。 |
| 1234d68 | QuickViewer 顶部栏改为三个独立浮动气泡，去掉全宽背景遮挡问题 |
| 3ae95b3 | ImagePreviewView 文件名改用 `.navigationTitle`，消除与系统 toolbar 重叠 |
| fe82225 | 切换文件夹或取消图片选择时自动关闭 Inspector |
| f4a69da | 无图片选中时禁用 Inspector（ⓘ）按钮，防止空 Inspector 挤压网格布局 |
| 4162d7b | QuickViewer 打开时隐藏 window toolbar，修复侧边栏切换按钮点击无响应问题 |
| 2e32207 | DesignSystem 改用 `AdaptiveColor(ShapeStyle)`，修复 QuickViewer 浅色模式下颜色全错问题 |
| a8cc21f | FolderSidebarView 移除强制深色环境，侧边栏背景改为 `DS.Color.appBackground` 自适应 |
| ce79d8b | ImagePreviewView 所有硬编码 `.white` 改为 `Color.primary`，修复浅色模式导航箭头不可见问题 |
| e8e7c54 | FolderSidebarView 行背景加 `listRowBackground(DS.Color.appBackground)`，消除侧边栏与内容区色差 |
| 39b87f8 | QuickViewerOverlay 所有系统材质替换为明确深色半透明色，修复浅色模式图标不清晰问题 |
| aeca565 | 设置默认窗口尺寸 1280×800（首次启动生效，之后 macOS 记住用户调整值） |
| c6da6b5 | QuickViewer 工具栏：整体背景减淡至 opacity 0.28，移除按钮独立背景，突出图标 |
| 9d185fb | 侧边栏选中高亮：`listRowBackground` 改为 `accentColor.opacity(0.2)`，深浅模式下均正确显示 |
| decc675 | ImagePreviewView 缺少 `.focusable()` + `.focused()`，内嵌预览左右方向键无响应 |
| f00a584 | 进入 QuickViewer 时隐藏 Traffic Light 按钮，退出时恢复 |
| a064033 | TrafficLightHide：全屏中退出 QuickViewer 后 traffic light 不恢复；`showTrafficLights()` 的 `isFullScreen` guard 设计有误，去掉后修复 |
| a60008c | 列表页双击图片多出渲染框 + QuickViewer 关闭后错误回到预览页；双击时多余的 selectedImageIndex 赋值导致，删除后修复 |
| 45a61f1 | TrafficLightHide：hideTrafficLights() 挂在内层 ZStack.onAppear，与外层 onDisappear 不对称，移至同节点修复 |
| 6da903c | QuickViewer 全屏中 ESC/X 应退出全屏而非关闭 QuickViewer；加 isFullScreen 判断分支 |
| 6da903c | 列表页双击时单击 handler 同步触发设置 selectedImageIndex，导致 QuickViewer 关闭后落到预览页；onDoubleClick 中清除 selectedImageIndex 修复 |
| 0dd7241 | 预览页双击进入 QuickViewer 再关闭后方向键失效；QuickViewer 为 overlay 故 ImagePreviewView 从未 disappear，onAppear 不再触发；用 focusTrigger(UUID) 信号恢复焦点 |
| f5f992d | Slider 加 labelsHidden()，宽度从 88 改为 140；消除滑块下方多余 label 区域 |
| 9b2168d | 缩略图模糊：loadThumbnail 改为 size × backingScaleFactor，Retina 屏下正确分辨率 |
| 577c302 | 侧边栏选中行两侧浅色背景块：listRowBackground 选中时改 Color.clear，去掉 accentColor.opacity(0.2) 与系统选中高亮叠加。聚焦/失焦颜色差异（Accent Color vs 灰色）为 macOS 原生行为，符合系统规范，不做修改 |
| 577c302 | 返回缩略图页全部重载：mainContent 改 ZStack，ImageGridView 始终在层级里；预览模式下隐藏 Grid toolbar items |
| 5186338 | 排序菜单无响应：根本原因是 macOS SwiftUI `Menu { Button }` in ToolbarItem 的 NSMenuItem action 桥接失效；改为 `Picker(.menu)` + 独立方向切换 Button，完全绕开该路径 |
| 3c72730 | 排序后缩略图显示错误：`ForEach` 用 `id: \.element`（URL）但 VStack 上的 `.id(index)` 覆盖了视图身份为位置索引；排序后 SwiftUI 复用同位置视图，`@State thumbnail` 残留旧图；改为 `.id(url)` + `scrollTo(folderStore.images[next])` 修复 |
| 4560625 | 排序后预览图片随机错位（+n）：`applySortKey` 异步排序，Task 完成时 `ImagePreviewView.currentIndex`(@State) 仍指向旧位置；`onChange(of: images)` 按 URL 重新映射修复。标题栏显示文件夹名：ZStack 中两个 `.navigationTitle` 冲突，移除 `ImagePreviewView` 的，改由 `ImageGridView` 按 `selectedImageIndex` 动态决定 |
| 0330d6b | `applySortKey` 改为同步排序（`sortImagesSync`），彻底消除排序竞态。保留异步 `sortImages` 供 `scanImages` 使用 |
| e0c418d | 排序后缩略图索引错位（部分）：`applySortKey` 未重置 `selectedImageIndex`；ContentView 未在 images 变化时关闭 QuickViewer。修复：排序前置 `selectedImageIndex = nil`；`onChange(of: images)` 关闭 QuickViewer |
| 175e82a | 排序后预览索引错位（部分）：ImagePreviewView 的 `@State currentIndex` 在 `startIndex` 参数变化时不重置。修复：存储 `startIndex` 属性 + `onChange(of: startIndex)` 重置 `currentIndex` + `.id(idx)` 强制重建视图 |
| b67ab3c | 排序后点击缩略图预览错位（根因修复）：`ForEach(enumerated(), id: \.element)` 在 LazyVGrid 中排序后闭包捕获的 `index` 过期，点击时写入旧索引。修复：`highlightedIndex: Int?` 改为 `highlightedURL: URL?`，单击/双击/键盘导航全部从 URL 实时查找当前索引，彻底消除位置编号过期问题 |
| 68042e0 | Enhancement：Finder 文件夹拖到侧边栏等同 Add Folder。`FolderStore` 拆 `addFolder()`（panel）/ `addFolder(from:autoSelect:)`（单 URL）/ `addFolders(from:)`（批量，单个选中、多个保留原选择）；`FolderSidebarView` 加 `.dropDestination(for: URL.self)` 在 ZStack 整块接受，`isTargeted` 驱动紫色 strokeBorder 高亮；Security Scope 复用 `BookmarkManager.saveBookmark`（拖入 URL 在 sandbox 下自带授权）。非目录 URL 静默过滤，多文件夹循环 auto-select false 避免焦点跳 |
| 0e3ec10 | QuickViewer 拖拽 y 方向反了（98573e9 follow-up）：旧 `vm.panBy(deltaY: -event.deltaY)` 假设 NSEvent y↑ 跟 SwiftUI offset y↓ 取反，实测 NSEvent.mouseDragged.deltaY 是 device/screen 坐标 y↓，跟 SwiftUI offset 同向。修复：去掉 `-` 改 `event.deltaY` 直接累加；注释纠错；spec ZoomScrollView 节同步说明 |
| 98573e9 | QuickViewer 1:1 大图拖拽抖动 + 拖不动。根因：`ZoomScrollView.mouseDragged` 用 `dragStartOffset + event.deltaX * 2` 计算，再 `dragStartOffset = vm.offset - event.deltaX * 2` 重设——是 NO-OP（`dragStartOffset` 永远停在 `mouseDown` 时的值）。而 `NSEvent.mouseDragged.deltaX` 是 incremental 而非 cumulative，导致连续 dragged event 把 offset 设成 `init + 当前 event 的小 delta`，图像在小范围内跳变（抖动）+ 总走不远（拖不动）。修复：`QuickViewerViewModel` 加 `panBy(deltaX:deltaY:)` 累加 + `clampOffset()`；`ZoomScrollView.mouseDragged` 简化为 `vm.panBy(event.deltaX, -event.deltaY)`（1:1 倍率，y 反转 AppKit↔SwiftUI），删除 `dragStartOffset` 字段和 `mouseDown` 的 else 分支 |
| 4f9fb18 | QuickViewer 图片打开只占窗口 30-40% 的双 bug 修复（self-fix round 1 = 4bc3c11：fitScale 里 1.0 → DS.Viewer.nativeScale）。根因 A：`fitScale` 卡顶 `min(...,1.0)` 阻止任何上采样；根因 B（主凶）：`QuickViewerOverlay.imageLayer` 同时用 `.scaledToFit() + .scaleEffect(scale)` 双变换，`.scaledToFit` 已填满容器后 `.scaleEffect` 再乘一次 fitScale，图被双重压缩。修复：`fitScale` 改 Preview+Quick Look 混合策略（图 ≤ 窗口保 1:1 不上采样；图 > 窗口缩到 `DS.Viewer.fitPadding = 0.9` 占比留呼吸边）；`imageLayer` 改 `.frame(width: native.w * scale, height: native.h * scale)` 单一变换，`scale` 语义统一为相对原生像素的倍率。`clampOffset` / `canPan` 使用 `image.size * scale` 恰好对齐新的渲染尺寸，拖拽边界随之修复 |
| 1a517b5 | ImagePreviewView 单击预览方向键切换出现 loading 转圈：原 `loadImage()` 每次都 `nsImage = nil` + 异步 `NSImage(contentsOf:)`，磁盘 IO 期间显示 ProgressView。修复：参照 QuickViewer ±1 预加载策略，新增 `ImageViewer/ImagePreviewViewModel.swift`（`prefetchCache: [Int: CGImage]` + `prefetchAdjacent()` + ±2 evict + `clearCache()`），命中缓存直接 set image 无 spinner；`onDisappear` / `onChange(of: images)` 调 `clearCache()` 防止旧 index 错配。**严格 scope**：仅替换 `ImagePreviewView` 内部加载路径，未触动入口、双击、Esc/方向键、focus、startIndex 重映射等任何现有交互 |
| 5d98f3d | ImagePreviewViewModel 预加载半径魔法数字提取常量（codex P1）：`prefetchRadius=1` / `cacheKeepRadius=2` 提到 `static let`，`prefetchAdjacent` 改用 `(-r...r)` 范围生成，`evictCacheIfNeeded` 用 `cacheKeepRadius` 计算 `keepRange` |
| 868271d | ImagePreviewViewModel cache-hit 路径补取消旧 imageLoadTask（codex P1）：上一张磁盘读未完成时若导航到已缓存的下一张，cache-hit 直接 return 不取消旧 task，旧 task 后到会用上一张图覆盖当前显示。修复：`load()` 入口统一先 cancel `imageLoadTask`，再分支处理 cache hit/miss |
| c7a1533 | ImagePreviewViewModel "每张仍转圈"修复（1a517b5 follow-up）：prefetchAdjacent 原本只在首张磁盘读完成后才启动，用户 <1s 切下一张时 prefetch 才刚开始排队 → 移到当前张磁盘读 Task 启动前并发触发；`Task.detached priority .background → .utility` 防 macOS QoS 节流跑不赢 `.userInitiated` 的当前张读取 |
| 4855e40 | ImagePreviewView 仍每张转圈（c7a1533 仍未解决，根因修复）：根因在 `ContentView.swift:131` 的 `.id(idx)`（commit 175e82a 修排序错位时加），方向键 → `selectedImageIndex` 变 → idx 变 → SwiftUI 销毁旧 ImagePreviewView 重建新视图，`@StateObject vm` 跟视图生命周期绑定也被销毁，prefetchCache 全部丢失，每张都 cache miss。修复（方案 A）：vm 提到 ContentView 用 `@StateObject private var previewVM` 持有，ImagePreviewView 改 `@ObservedObject var vm` 接收注入，cache 跨 view 重建持续；clearCache 触发权移交 ContentView 在 `onChange(of: selectedFolder/selectedImageIndex==nil/images)` 三处统一调，删除 ImagePreviewView 的 `.onDisappear { vm.clearCache() }` 和 `onChange(of: images)` 里的 clearCache（前者会在 `.id` 触发重建时被错误调用）。`.id(idx)` 保留不动，QuickViewer 不动 |
| 463633d | c112059 收尾清理时擅自把缩略图文件名 `Text(url.lastPathComponent)` 还原成 `Text(url.deletingPathExtension().lastPathComponent)`（去扩展名）—— 违反 scope 锁死原则（用户当时让"你定"未明确回复时不应擅自落地"默认值"）。改回 `lastPathComponent` 保留扩展名：含同名不同后缀文件夹（4.jpg / 4.png）时标签可直接区分，跟 Finder Cover Flow 行为一致。文件：Glance/FolderBrowser/ImageGridView.swift |
| c112059 | LazyVGrid 缩略图首次点击错位（含 4.jpg/4.png 同名不同后缀场景）：第 7 次根因修复，前 6 次（3c72730/4560625/0330d6b/cfd5d76/4579f1e/4f5efce）解决了状态层（@State / index / sort race / URL identity），但 hit-test 层 bug 依旧——log 证实 TAP url 与 PREVIEW url 完全一致，但视觉上点的 cell 标签写"4.jpg" 而 click 抓到 4.png。codex:rescue review 定位真因：LazyVGrid 首次 materialize 时旧 gesture recognizer 被 reuse 错绑（不是异步竞争）。修复（方案：统一身份系统）：(1) `ForEach(Array(images.enumerated()), id: \.element)` → `ForEach(images, id: \.self)`，去掉 tuple 包装减少身份层次；(2) 两个 `.onTapGesture` 从内层 ThumbnailCell 上移到外层 VStack（紧跟 `.id(url)`），让 gesture host 和 visual identity 同层；(3) 加 `.contentShape(Rectangle())` 显式声明命中区域。同时清掉 ScrollView `.id("\(sortKey)-\(direction)")`（codex 提醒多层 identity marker 会重新引入歧义，且实测对本次 bug 无效）。`.task(id: url)` + `thumbnail = nil` reset 保留作 cell 复用第二道保险。**待办**：macOS 双 onTapGesture(count:1+2) 在 lazy 容器有已知 edge case，独立挂号 followup（见 PENDING-USER-ACTIONS） |
| 44ba6ee | ImageGridView 双击 cell 后 highlight 不跟随到双击的 cell：用户先单击 A（highlight=A），再双击 B 进 QuickViewer，ESC 退出后 highlight 仍停在 A，应跟随到 B。根因：`.onTapGesture(count: 2)` 双击 handler 漏设 `highlightedURL = url`（SwiftUI 对 count:1+count:2 双 gesture 行为：识别为双击时只触发 count:2，不连带 single tap，所以双击路径需独立维护 highlight 状态）。修复：在 `.onTapGesture(count: 2)` 闭包开头补 `highlightedURL = url`，与 `.onTapGesture(count: 1)` 对齐 |
| 44ba6ee | 缩略图网格上下方向键步长错乱跨行：`columnCount()` 用 `NSApp.keyWindow?.contentView?.bounds.width` 估算列数，但 keyWindow.contentView 是整窗宽（包含侧边栏和 Inspector），grid 实际只占中间一段；多算了列数 → 上下方向键 step 偏大 → 一按就跨过实际 grid 一行，看似乱跳。修复：`gridContent` 包 `GeometryReader`，用 `geo.size.width` 反映 mainContent 实际可用宽度（不含 sidebar/inspector）；新 `computeColumnCount(width:)` 公式 `floor((W - 2·padding + spacing) / (cellWidth + spacing))` 与 SwiftUI `.adaptive(minimum:)` 列数算法一致。Inspector 切换 / 窗口缩放时 GeometryReader 自动重算 |
| 5b29600 | 缩略图 grid ESC 退预览后焦点 race（Y-1 + Y-2）：单击 cell A 进 ImagePreviewView → ESC 退回 grid → 按方向键随机两种现象，Y-1 完全无响应 / Y-2 反而又弹出 A 的下一张预览（且预览出现后方向键正常切预览图）。codex:rescue review 验证根因方向：ImagePreviewView 关闭瞬间 `.transition(.asymmetric)` 退场期内 view 仍存活、仍 active focus、仍响应 onKeyPress；同时 ImageGridView `.onAppear { isFocused = true }` 只首次出现触发，grid 一直在 ZStack 底层不会重触 → 焦点处于 race 状态：grid 抢回则 Y-1（按键已派发到 nobody），preview 残留则 Y-2（onKeyPress(.rightArrow) → navigate → 重写 selectedImageIndex 让 preview 重 mount）。codex 推荐 A+B 双侧防御方案：(A) `ImageGridView` 加 `.onChange(of: folderStore.selectedImageIndex) { _, new in if new == nil { isFocused = true } }` 解 Y-1；(B) `ImagePreviewView.onKeyPress(.escape)` 闭包先 `isFocused = false` 再 `onDismiss()` 缩短 Y-2 race window。Plan C（去 transition / if-else 互斥）代价过大（视觉过渡丢失 + grid 可能 remount），不采用。长期更正交方案是父持有 FocusState enum 统一仲裁，超出本次 scope |
| 59a9d86 | Y bug round 2：grid 失焦在 QuickViewer dismiss 路径上未覆盖。新复现链：单击 cell A → preview → ESC（grid 拿焦 ✓）→ Space → QuickViewer → ESC → grid 失焦，Space / 方向键全静默。根因：5b29600 的 `onChange(of: selectedImageIndex)` 只覆盖 ImagePreviewView dismiss 路径；QuickViewer 走 `quickViewerIndex` (ContentView @State)，grid 完全不监听。codex:rescue (gpt-5.4 high effort, gpt-5.5 因 subagent 内部 hardcoded fallback 自动降级) 进一步发现 5.4-medium 漏掉的关键盲点：`ContentView.onChange(of: folderStore.images)` 也会强制 `quickViewerIndex = nil`（切换文件夹时），完全绕过 QV 的 onDismiss 回调；trigger 必须挂在 `ContentView.onChange(of: quickViewerIndex)`（quickViewerIndex 状态出口的真源头）才能覆盖所有关闭路径。修复（5.4-high 7 条）：(1) ContentView 加 `gridFocusTrigger: UUID @State`；(2) 传给 ImageGridView；(3) QV onDismiss 简化、移除原 previewFocusTrigger 路由；(4) 新增 `.onChange(of: quickViewerIndex)` 仲裁：if selectedImageIndex != nil → previewFocusTrigger = UUID() else gridFocusTrigger = UUID()；(5) ImageGridView 加 `gridFocusTrigger` 参数 + `.onChange(of: gridFocusTrigger)` 拉回 isFocused，保留 selectedImageIndex onChange 作冗余兜底；(6) QuickViewerOverlay `handleDismissOrExitFullScreen()` 非全屏分支 onDismiss() 前加 `isFocused = false`（B-side 加固，必须不可选）；(7) ImagePreviewView 抽 `dismissPreview()` helper（`isFocused = false` + onDismiss），ESC handler + 关闭按钮统一走 helper。架构信号：第 2 次同类 focus race bug，已排入 Roadmap 待开发段（FocusState enum 父持有重构） |
| 09c418c | AboutView contact 行点击后残留 macOS focus ring：用户截图显示点击"© 2026 孙红军 · 16414766@qq.com"行后该行周围出现 accent color 细描边。根因：macOS `Button` 是 focusable 元素，被点击 / Tab 移焦后 system 自动画 keyboard focus ring；`.buttonStyle(.plain)` 只去 button 背景，focus ring 是单独 overlay 不受影响。修复：Text + `.onTapGesture` + `.contentShape(Rectangle())` 替代 Button —— Text 不进入 focus chain 无 ring；补 `.accessibilityAddTraits(.isButton)` 让 screen reader 仍识别"按钮"语义不退化 a11y |
| 8f927d1 + 6f56072 | 自定义"关于一眼"窗口（替换标准 NSAboutPanel）：标准面板的 NSHumanReadableCopyright 字段不可点击，不能挂复制 handler；改用 SwiftUI 自定义 view + Window scene + CommandGroup(replacing: .appInfo) 实现两行 contact 文本（`© 2026 孙红军 · 16414766@qq.com` / `小红书 382336617`）支持点击复制全文到剪贴板 + 1.5s toast Capsule 提示。新建 `Glance/About/AboutView.swift`；GlanceApp 加 `.commands` + `Window("about")` scene；`@Environment(\.openWindow)` 打开。9bc7c0e 修 P1 magic number / DS.* 引用：加 DS.About 段（windowWidth/appIconSize/toastMaxWidth/toastDurationSeconds）+ DS.Color.secondaryText alias 到 SwiftUI .secondary；showToast 改用 Task.sleep(for: .seconds()) 绕开 nanoseconds 字面 |
| fb7f900 + 1e307ee | QuickViewer 底部 filmstrip 点击命中错位（c112059 同型 bug 在 filmstrip 路径漏修）：用户点 cell A，filmstrip 高亮 + 主图都跳到 cell B，可稳定复现，错位方向 + 位置随机。c112059 当时只覆盖 LazyVGrid（grid），filmstrip 是 LazyHStack 用了同样有问题的 pattern：`ForEach(Array(images.enumerated()), id: \.element)` + `.id(index)` 双层 identity 不一致 + closure 捕获 index 在 cell 复用时过期 → gesture recognizer 错绑。codex:rescue (gpt-5.5 high) 验证根因方向 + 5 处变更充分性，并补了两个我漏掉的：(a) `proxy.scrollTo` 2 处也用 index 要同步改 url；(b) `FilmstripCell .task` 缺 `id: url` reset/cancel guard。完整修复 mirror c112059：(1) `ForEach(images, id: \.self)`；(2) `.id(url)` 替 `.id(index)`；(3) `.contentShape(Rectangle())`；(4) onTapGesture 用 `firstIndex(of: url)` 实时查；(5) `isSelected` 用 url 比较；(6) `proxy.scrollTo` 2 处改用 url + indices.contains 守卫；(7) `FilmstripCell .task(id: url)` + `thumbnail = nil` reset + `Task.isCancelled` guard。CC 修了 codex 留下的小编译错（`var filmstrip: some View` body 加 let 后需 explicit return） |
| 2b858cf | 跟随系统外观模式不生效：用户在「跟随系统 / 强制深 / 强制浅」三选一菜单切到「跟随系统」后视图不重置，仍卡在之前强制色。根因：SwiftUI `.preferredColorScheme(nil)` 在 macOS 上**无法撤销**之前设过的 `.light/.dark` 强制值（已知 limitation） — 视图层级保留旧 colorScheme。修复：改用 AppKit 标准 API `NSApp.appearance` 直接控 NSAppearance（system → nil / light → .aqua / dark → .darkAqua），在 `AppState.appearanceMode.didSet` 调 `applyAppearance()`，init 末尾调一次保证启动模式生效。`GlanceApp.swift` 中的 `.preferredColorScheme(...)` modifier 删除。`QuickViewerOverlay.preferredColorScheme(.dark)` 不变（view 局部覆盖跟 NSApp.appearance 不冲突）|
| dcabffc | light 模式侧边栏 vs 内容区对比方向反了：内容区 `gridBackground` = #EBEBF0 比侧边栏 `appBackground` = #F2F2F7 **更暗**，跟 dark 模式（内容区 #141419 稍亮于侧边栏 #121217）方向相反，也跟 macOS 系统 app（Finder/Notes/Mail）light 模式视觉标准（侧边栏 vibrant 灰 + 内容区白）冲突。修：`DS.Color.gridBackground.light` #EBEBF0 → `Color.white`（#FFFFFF），让内容区永远是焦点。dark 模式不动 |
| e2e0d21 | 关于窗口位置不跟随主窗口居中（方案 1 失败）：挪动主窗口后打开关于面板，关于窗口出现在屏幕中心或上次记住位置，没相对当前主窗口居中。系统标准 NSAboutPanel 默认就跟随主窗口居中（免费），但 8f927d1 改用自定义 SwiftUI `Window("about")` 后失去该行为。**方案 1 (commit e2e0d21，已被 20fa509 重写)**：`AboutView.onAppear` + `DispatchQueue.main.async` + `setFrameOrigin`。**实测有 A→B 视觉跳跃**：window 已显示在默认位置 A 后下一帧才被移到 B，用户能看见跳跃。根因：SwiftUI Window scene 不暴露"显示前定位"hook |
| 20fa509 | 关于窗口位置（方案 2 真解）：改用纯 AppKit `AboutWindowController` 单例 + `NSHostingView(AboutView())` 替代 SwiftUI `Window("about")` scene。`show()` 函数顺序：① 创建/复用 NSWindow（`isReleasedWhenClosed = false`，关闭后保留实例）② `setFrameOrigin` 居中到主窗口 ③ `makeKeyAndOrderFront(nil)` —— 显示前已定位完，零跳跃。`GlanceApp.swift` 删 `Window("关于一眼", id: "about")` scene + `.windowResizability`；`AboutMenuButton` 不再 `@Environment(\.openWindow)`，改调 `AboutWindowController.shared.show()`。`AboutView.swift` 删原 onAppear 居中逻辑（不再需要） |
| 79fcfdf | F 键全屏只在 QuickViewer 中有效，grid 和 preview 模式按 F 无响应（v1.0 distribution smoke test 发现的老 spec/实现 gap，从 commit `0abcae6` FullScreen 模块初始就如此）。`AppState.md:62` spec 写"用户按 F 键"但模糊未指定 view，按字面是全局；实际只 `QuickViewerOverlay.swift:146` 挂了 `onKeyPress(.init("f"))` handler，`ImageGridView` / `ImagePreviewView` 都漏挂。**修法**：(1) `Glance/FolderBrowser/ImageGridView.swift` 加 `@EnvironmentObject var appState: AppState` + 在现有 `.onKeyPress(.space)` 旁加 `.onKeyPress(.init("f"), phases: .down) { _ in appState.toggleFullScreen(); return .handled }`；(2) `Glance/ImageViewer/ImagePreviewView.swift` 同上 inject + 加 F handler。spec 同步：`AppState.md:62` 改为"用户在 grid / preview / QuickViewer 任一界面按 F 键"明确全局。风险低：F 键不冲突现有 grid/preview 其他 onKeyPress（grid: space/方向键，preview: escape/space/方向键），`appState.toggleFullScreen()` 调用模式跟 QV 一致 |
| 02a36dc | Bug 4 扩展 — QV 方向键 / nav button / filmstrip 切图后 ESC 退出 grid highlight + preview 都不跟到 Z（用户期望对齐 Finder Quick Look + macOS Photos 标准）。**3 条路径**：(1) grid 双击 cell A → QV → 方向键 Z → ESC → grid highlight 期望 = Z；(2) grid 单击 A → preview → 双击 → QV → 方向键 Z → ESC → preview 期望 = Z；(3) 续 (2) 再 ESC → grid highlight 期望 = Z。**修法风险高的关键**：commit 6da903c 修过"双击 cell 进 QV 后退出回 grid 不进 preview"，靠 onDoubleClick 设 selectedImageIndex = nil；如果 QV 方向键直接写 selectedImageIndex 路径 1 会反向引发 6da903c 回归（退 QV 后 selectedImageIndex != nil → 进 preview）。**根因 + 修法**（codex:rescue gpt-5.5 high Approach A）：用入口来源 enum + QV index 变化回调，让 dismiss 路由按 provenance 走，不依赖 selectedImageIndex 是否 nil 当哨兵。改动：(1) `Glance/ContentView.swift` 加 `private enum QuickViewerEntry { case grid, preview }` + `@State quickViewerEntry: QuickViewerEntry?` + `onDoubleClick` 设 `.grid` + preview `onQuickView` 设 `.preview` + `.onChange(of: quickViewerIndex)` 仲裁改 switch entry 路由（.grid → 清 selectedImageIndex + gridFocusTrigger，.preview → previewFocusTrigger）+ QV `onIndexChange: { folderStore.selectedImageIndex = newIdx }` + 收紧 preview 渲染条件 `if let idx = selectedImageIndex, quickViewerIndex == nil`（codex 标盲点：.id(idx) 让 preview 在 selectedImageIndex 变化时整体重建，QV 期间不渲染避免后台 mount/loadImage）；(2) `Glance/QuickViewer/QuickViewerOverlay.swift` 加 `let onIndexChange: (Int) -> Void` 参数 + `.onChange(of: viewModel.currentIndex) { _, newValue in onIndexChange(newValue) }` 一处统一覆盖 nav button (goBack/goForward) + filmstrip tap (goTo) + 方向键三种 QV 内导航路径（codex 标的盲点 1，避免补 key handler 漏渠道） |
| <pending> | Bug 4 grid highlight 不跟 preview 方向键导航（UX gap，对齐 Finder Cover Flow / Photos.app）：用户单击 grid cell 1.png → preview → 方向键 ←→ 浏览到 5.png → ESC 退回 grid → grid 紫色高亮仍停在 1.png（应跟到 5.png）。**Roadmap 原描述不准**：原说 "175e82a 刻意解耦 currentIndex 跟外部 selectedImageIndex，方向键不写回"，**实际 ImagePreviewView.navigate(by:) L147-152 已写回 selectedImageIndex**。codex:rescue gpt-5.5 high 拍 + audit 5 个历史 bug 全无回归。**真根因**：`ImageGridView.swift:158-160` `.onChange(of: folderStore.selectedImageIndex)` 闭包**只**处理 nil 分支拉焦点，没有 non-nil 分支同步 highlightedURL。**修法**：扩展该闭包加 non-nil 分支 `else if let idx = newValue, folderStore.images.indices.contains(idx) { highlightedURL = folderStore.images[idx] }`，单文件 3 行。**风险评估**：codex 验证 5 个历史 commit 全无回归 — 175e82a (ImagePreviewView startIndex 重置 + .id(idx) 不动) / b67ab3c (URL identity 一致) / 44ba6ee (双击路径 onDoubleClick 清 nil 走旧分支不触发新逻辑) / 5b29600 + 59a9d86 (焦点 race nil 分支不变)。排序场景：applySortKey 先清 selectedImageIndex 再排，onChange(of: images) 也清 highlightedURL，新分支无机会跟到错位置。双写无害：单击 cell `.onTapGesture(count:1)` 已写 highlightedURL = url，新 onChange 闭包再写一次结果同 URL |
| 3cdb991 | 浅色模式下 QuickViewer 强制深色 ESC 退出后 dark colorScheme 渗透到底层（用户截图 `~/sync/g1.png` Path A / `~/sync/g2.png` Path B），失焦自愈。**Path A**（grid → 直接双击 cell → QV → ESC）：sidebar 变深灰，detail 列保持浅色。**Path B**（grid → 单击 → preview → 双击 → QV → ESC）：整个 app 全深色（sidebar + preview + 文件名 toolbar）。**老 bug**：用户 git checkout 086ade2 build 复现，跟当前 c0c833a `.toolbarBackground` 改动无关，浅色模式测试覆盖少所以一直没暴露。**根因**（codex:rescue gpt-5.5 high 拍）：`QuickViewerOverlay.swift:95` `.preferredColorScheme(.dark)` 是 **presentation-scoped** 偏好，写到 NSHostingView/NSWindow.contentView appearance 链 —— 不是纯本地子树 environment。QV dismiss 时 SwiftUI 撤销 colorScheme env 有滞后，底层 view 已被重绘。Path B preview 全深因为 QV 关闭瞬间 `previewFocusTrigger` 触发 ImagePreviewView 刷新，那一瞬 colorScheme env 还是 dark → AdaptiveColor 返 dark 值。**我之前推 "AdaptiveColor 重读 NSWindow.appearance" 错了**：AdaptiveColor 实际从 SwiftUI colorScheme env 读，不读 NSWindow.appearance。**修法**：单文件单行 `Glance/QuickViewer/QuickViewerOverlay.swift:95` `.preferredColorScheme(.dark)` → `.environment(\.colorScheme, .dark)`。`.environment` 是本地子树 SwiftUI environment，不动 NSHostingView/NSWindow appearance 链 —— QV dismiss 时无 presentation 偏好滞后撤销。QV 内部全用显式 SwiftUI 颜色无 AppKit material 故视觉等价。codex 标盲点：未来 QV 引入需要 AppKit dark appearance 的 NSVisualEffectView material 时方案不够，需补 AppKit 层 appearance 保存/恢复。当前无此问题 |
| c0c833a | 首次进 ImagePreviewView 顶部出现一条浅灰横向 toolbar 底色，跟下方 preview 紫黑色 (`appBackground` #121217) 明显断层（用户截图 `~/sync/f4.png` bug / `~/sync/f5.png` 正常）。**触发条件**：启动 app → 单击 cell 进 preview → f4 状态；双击进 QuickViewer → ESC 退出 → 再单击 cell 进 preview → 永久变 f5 状态（融合到 NSWindow title bar 深色，无断层）。文件名 + ⓘ Inspector + 外观切换按钮位置不变（detail 列左 / 右），只是 toolbar chrome 形态切换。失焦/聚焦不触发，排除 macOS focus state quirk。**前 1 次修法 e39fbbf 装到实机零变化**（关于面板 commit hash 已对齐）：codex:rescue 第一轮拍 AppKit `NSWindow.toolbarStyle = .unified` 走错层 — 浅灰横条不是 toolbarStyle (unified/expanded 布局枚举) 导致，是 SwiftUI window toolbar **background material 绘制层**，AppKit 改 `toolbarStyle` 跟视觉绘制完全不同层。**真根因**（codex:rescue 第二轮 gpt-5.5 high resume 同 thread 拍）：浅灰横条 = SwiftUI `NavigationSplitView` 默认绘制的 `.windowToolbar` background material；`ContentView.swift:97` `.toolbar(quickViewerIndex != nil ? .hidden : .visible, for: .windowToolbar)` 在 QV 进出时通过 SwiftUI 同一 toolbar visibility 栈 invalidate 了 background 绘制 → 永久变 fused（意外副作用 = 用户期望状态）。**修法**：(1) `Glance/ContentView.swift` 紧贴 L97 加 `.toolbarBackground(.hidden, for: .windowToolbar)`（macOS 13+ SwiftUI API，部署目标 14 满足）—— 直接控制 SwiftUI 这一绘制层，跟 QV hide/visible 走同一栈；(2) `Glance/FullScreen/WindowAccessor.swift` 回滚 e39fbbf 加的两处 `window.toolbarStyle = .unified`（已验证无效，留着会污染 codebase）|
| 086ade2 | Inspector 旁边粉色长条 + 整个 app 被一道粉色细框框住 + 失焦消失聚焦出现（同根因，初次诊断 61029fa+a27e496+01d1fca 把方向搞错为 SwiftUI Divider 没修对）：真根因是 SwiftUI `.focusable()` 默认渲染 system accent color focus ring，用户系统 accent color = 粉色。证据链：(1) 颜色匹配 accent color；(2) macOS 标准行为 window 失焦时 focus indicator 自动褪色 → 解释失焦/聚焦切换；(3) ImagePreviewView body 用 `appBackground.ignoresSafeArea()` 让 ZStack 跨 safe area，focus ring 沿实际边界画 → 解释整个 app 被细粉框框住；(4) 关 Inspector 后 ImagePreviewView 右缘到达窗口最右侧被边框盖住，开 Inspector 后右缘暴露在 mainContent / Inspector 之间 → 解释"Inspector 旁边那条最粗最显眼"。codex:rescue (gpt-5.5 high) 验证根因方向 + 修法 API + scope 充分性，标出原假设盲点（关 Inspector 不是 ring "消失" 而是被 layout 切掉）。修：3 处 `.focusable()` 后插入 `.focusEffectDisabled()`（macOS 14+ API，禁用视觉 ring 但保留 focus 调度，onKeyPress 仍工作） — `ImagePreviewView.swift:111` / `ImageGridView.swift:151` / `QuickViewerOverlay.swift:96`。FolderSidebarView 用 `List(selection:)` 不是 `.focusable()`，本次不动 |
| 61029fa | Inspector 开关时多一道粉色竖线 + 关闭后延迟消失（Bug 2/3 同根因合并修，**初次诊断方向搞错**，已被上一行真根因修法取代；本条留作历史，不再生效）。完整失败修法系列：61029fa 主 + a27e496 magic number fixup + 01d1fca docs 对齐：`ContentView.swift:35` 独立 `Divider()` 没加 `.transition`，跟 Inspector 的 `.move(.trailing)+.opacity` 不同步——开 Inspector 时 Divider 默认 `.opacity` 直接 fade in 到最终位置但 Inspector 还在窗外滑入，视觉上"提前到位"；关 Inspector 时 Inspector `.move` 滑出后 Divider fade out 残留。粉色推测为 SwiftUI Divider 内部 system separator color 在 dark 模式下叠加 vibrancy/accent 偏冷紫调，修同步问题后视觉 artifact 应大幅缓解（动画窗内才可见）。修：(1) ContentView.swift 删 L35 `Divider()`；(2) ImageInspectorView.swift body 末尾加 `.overlay(alignment: .leading) { Rectangle().fill(DS.Color.separatorColor).frame(width: DS.Inspector.separatorWidth) }`（DS.Inspector.separatorWidth = 0.5，HiDPI 下对应 1 物理像素）——边线绑定到 Inspector 视图本身，自动跟随同一 transition 同步出入，从语义上"分隔线 = Inspector 视觉边界"。配套：Roadmap L44 AboutPanel hash `8f927d1 + 6f56072` 改为 `8f927d1`，把 `6f56072` 信息挪入说明，让 verify.sh stage 1 hash 格式检查通过 |
| ab1fe89 | dark 模式底色跟 Finder 等系统 app 不合群（暗 60% + 偏冷蓝紫）— **partial fix**：删 hardcoded background 让系统 sidebar material 接管后实测**仍有渐变**（顶部 row 区域 vibrancy + 下半空白深黑色 windowBackground 覆盖）。codex:rescue 给的 NSVisualEffectView 桥方案落地后引发**关于居中回归**（具体因果链未定）+ 视觉仍不一致，已 revert。**待 v1.0.1 重新审**（可能需要 audit ZStack vs NavigationSplitView column 行为）。**当前 ab1fe89 状态**：ImagePreviewView/QuickViewer 仍用 appBackground 紫深色（设计语言保留）；FolderSidebarView 顶部紫色 RadialGradient glow 保留+ 失焦无响应（Finder/Mail/Notes 失焦后侧边栏会自动褪色，Glance 不变）。根因：(1) `appBackground/gridBackground` 用了硬编码 hex (#121217 / #141419) 替代 system semantic color；(2) 选了偏冷蓝紫（B 通道高于 R/G）；(3) FolderSidebarView 用 `.listStyle(.sidebar)` 后又用 `.background(DS.Color.appBackground)` 把 SwiftUI 自动派发的 NSVisualEffectView material `.sidebar` 完全覆盖掉，listRowBackground 未选中行又被 `appBackground` 二次覆盖。修：删 4 处 hardcoded background —— (1) `FolderSidebarView.swift:38` 删 `.background(appBackground)`；(2) `FolderSidebarView.swift` listRowBackground 简化为 `Color.clear`（清 `isSelected` 死变量）；(3) `ImageGridView.swift:146` 删 `.background(gridBackground)`；(4) `ImageGridView.swift:27` empty state `gridBackground` → `Color.clear`。让 NavigationSplitView + listStyle(.sidebar) 默认行为接管：sidebar 自动 NSVisualEffectView material `.sidebar` + state `.followsWindowActiveState`（失焦自动褪色，跟 Finder 一致），dark/light 自动切，跨 OS 版本稳定。`appBackground/gridBackground` 定义保留（QuickViewer / ImagePreviewView 仍引用，QuickViewer 强制 dark 是设计选择不动）|
| 60a2de2 | Slice B-α follow-up — 3 个用户首测 bug：(1) sticky header 在 dark mode 呈现"大块黑横条"：背景 `DS.Color.gridBackground` 不透明黑（#141419）改 `.regularMaterial` 半透明毛玻璃；字号 `.headline` → `.subheadline.weight(.semibold)`；padding 收紧（codex review Q3 验证 + Bug 1）。(2) ↑↓ 跨段乱跳（plan-time 决策 4 判断错的纠偏）：原 flat queryResult ± colCount 步长在 sectioned grid 下不对应"视觉一行"（section header 占视觉一行 + 每段 col=0 重置）；重写 `moveHighlight` 为 `(sectionIdx, rowInSection, col)` 模型 + `MoveDirection` enum：←→ 仍 flat ±1（A 方案，跨段自然连续，行为继承 V1）/ ↑↓ 段内同 col 上下 / 段边界跳邻段对应 col / col 超过目标行末 clamp / nil/stale highlightedID 显式 down→第一项 up→末项 / 第一段第一行 ↑ / 末段末行 ↓ 原地。新增 `locate(_:in:)` helper 定位 (sectionIdx, indexInSection)。(3) sticky header 区域点击穿透到下方 cell：SwiftUI `.background(Color)` 不消费 hit-test，加 `.contentShape(Rectangle()).onTapGesture {}` 显式吃 tap。架构：sections 提到 body 顶部一次算（codex Q5.1），render LazyVGrid + ↑↓ nav 共用同一快照，避免跨午夜 render/nav 双源不一致。修法走 codex:rescue 独立 review 后落地（路径 2，决策全 A）|
| c5b048a | Slice B-α follow-up #2 — sticky header"横条"视觉第三轮修法（前两次都失败）：用户两次反馈"黑横条/横条体验差"，60a2de2 用 `.regularMaterial` 半透明仍是"全宽横条"——根因不是 background 颜色/材质，是 SwiftUI LazyVGrid Section header **全宽 row 的 layout 属性本身**，改 background 永远改不掉。修法（用户提议 + codex:rescue 5 项 review 通过：Q1 行高 ✓ / Q3 material+Capsule ✓ / Q4 idiom ✓ / Q5 无 LazyVGrid 不兼容 ✓ / Q2 ⚠ pinned hit-test 待实测）：(1) 文字+padding 包进 `Capsule` 用 `.background(.regularMaterial, in: Capsule())` 形成 chip 实体；(2) row 自身去 background（透明），sticky 时 chip 之外区域 cell 直接透过显示；(3) 去掉 60a2de2 加的 `.contentShape(Rectangle()).onTapGesture {}`（透明 row 不需要 + 反而会阻止 chip 之外区域点 cell）。视觉效果：sticky 时左上角浮一个小 capsule（"今天 · 3 张"），其余 row 区域完全透明。修法 sub-scope 严格：仅 SmartFolderGridView.swift sectionHeader 函数体 + 顶部 doc comment；moveHighlight + locate + LazyVGrid pinnedViews + 所有交互逻辑不动 |
| `90fd910` + `ef08f72` | Slice B-α follow-up #3 — chip 在 light cell 上对比度不够（Round 3 sticky chip 形态本身 OK，但 `.regularMaterial` 在 light env 自适应偏白，跟 light cell 撞色边界融）：升 `.thickMaterial` + 加 1pt `Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)` 给 chip 永远可见边界。模式参考 macOS Calendar.app / Mail.app sidebar items hairline。修法 surface 极小（仅 sectionHeader 函数体 +3 行 .overlay），不走 codex:rescue（chip 形态主体 c5b048a 已过 review，本次仅 SwiftUI 标准 modifier 微调）。`ef08f72` 是 codex 抓的 magic number P1 fix（抽 DS.SectionHeader.chipBorderOpacity / chipBorderWidth） |
| 4f318b5 | Slice D.1 P1 真 bug：`upsertSubfolderHide` 的 `ON CONFLICT (parent_root_id, relative_path)` 没匹配 schema 的 *partial* unique idx `idx_folders_subpath ... WHERE parent_root_id IS NOT NULL`，SQLite 拒绝 prepare → 子目录 hide 永远不持久（右键 toggle 等于 no-op，状态不进数据库）。修：ON CONFLICT 后加 `WHERE parent_root_id IS NOT NULL` 子句对齐 partial idx 谓词。同 commit 顺手修 P2：`FolderSidebarView.rootURL(for:)` 嵌套 root 场景（/parent + /parent/child 同时管理）first prefix 匹配错路由 → 改 max(by:) 取最长前缀；Roadmap 当前进度段从 2026-05-08 Slice A 同步到 2026-05-09 Slice B ship + D.1 进行中 |
| `a478f29` | Slice G.4 P1 fix（codex 抓 Slice G ship commit `8df97af` 2 项 policy 违反，functional 无影响）：(1) `FSEventsWatcher.swift` 一文件双类型违反（FSEvent + FSEventsWatcher）→ 拆出 `FSEvent.swift` 独立文件；(2) `latency: 1.0` 魔法字面量 → 抽 `FSEventsWatcher.defaultLatency` static let 常量。**Tag 历史保留**：tag `v2.0-beta4` 仍指向 `8df97af`（含已知 policy 违反 + functional ship）；本 commit 标 `[skip-codex]` 让 push range 跳过 codex 复审（2 项 P1 已修），后续 review 流程不再被同 P1 重复阻塞 |
| `870cf80` | Slice H ship 后 codex P1 误判处理（commit `80806d4` Slice H 主体已正确实装 dedup 过滤，codex review 未追完 SmartFolderQueryBuilder.emitAtom `.dedupCanonicalOrNull` virtual field 翻译路径，误称 "fetch 不过滤 dedup"。SQL 实测在 `:memory:` DB 验证 4 case 通过：rows with `dedup_canonical=0` 被过滤掉，rows with `=1` / `IS NULL` 保留。本 commit 标 `[skip-codex]` push range 跳过复审；同 codex `effectiveHidden` 误判先例处理） |
| `3256733` | V2.0 GA V1 mode grid 不自动刷新 + 加手动刷新（用户 5 月 9 日 backlog 项落地）：用户报"打开一个 subfolder，删除或新增 grid 都没刷新"。根因：V1 mode `FolderStore.images` 是 selectFolder 时一次性 `contentsOfDirectory` 快照，不监听 FSEvents（Slice G FSEvents 仅更新 V2 IndexStore，V1 数据流独立）。修法（1+2 都做）：(1) **V1 FSEvents 自动**：FolderStore 加 `currentFolderWatcher: FSEventsWatcher?` + `folderWatcherQueue`，selectFolder 时停旧启新监听 url 子树，watcher callback 内 hasFileChange filter (isCreated/isRemoved/isModified/isRenamed) + race guard `selectedFolder == url` → 调 scanImages reload；removeFolder 时若 selected 在被删树内同步 stop watcher 防 leak；(2) **手动刷新兜底**：FolderStore 加 `refreshCurrentFolder()` public method，FolderSidebarView contextMenu 在 `node.url == selectedFolder` 时显"刷新"按钮调它（仅 selected 节点显避免歧义"刷哪个"）。覆盖 90% 自动 + 10% FSEvents 偶发漏 / 用户强制刷新场景。Surface：FolderStore.swift +25 行 + FolderSidebarView.swift +3 行 |
| `f34edb7` | V2.0 GA Slice D follow-up #2 — hide 图标扩展到 subfolder（explicit 触发）：用户首测发现 subfolder 单独 hide 时（root visible）该 subfolder 行无图标提示，状态视觉缺口。3cd463c 当时把 scope 锁死在仅 root 层，subfolder 完全没图标 → 不对症。修法：(1) IndexStore 加 `isExplicitlyHidden(rootId:, relativePath:)` API — 不走 path-walk 继承，仅查 row 自己 hide_in_smart_view 字段（root row 用 id + parent_root_id IS NULL，subfolder row 用 parent_root_id + relative_path 精确匹配）；(2) ContentView 加 `explicitlyHidden(rootURL:, nodeURL:)` 闭包传给 sidebar；(3) FolderSidebarView.folderRow 去掉 `isRoot` 限制，对所有节点用 `isExplicitlyHidden` 决定图标显示。规则：仅 row 显式 hide=1 才显图标 — root.hide=1 显（保持 3cd463c 行为）/ subfolder 单独 hide 显（修当前 bug）/ subfolder 继承 root hide 不显（避免 root hide 整树时所有 subfolder 都顶图标的视觉爆炸）。`isEffectivelyHidden` 闭包保留给 contextMenu label 用，语义不变 |
| `3cd463c` | V2.0 GA Slice D follow-up — sidebar root 层加 hide 状态图标：用户提需求"文件夹被 hide 后该有图标提醒"（hide 是隐式状态，用户切到具体 folder 仍能看到所有图，智能文件夹里却没了，没视觉提示容易困惑）。修法：`FolderSidebarView.folderRow` 在 `isRoot && isEffectivelyHidden(node.url, node.url) == true` 时跟在 folder Label 后渲染 `Image(systemName: "eye.slash")` + `.font(.caption) .foregroundStyle(.secondary)` + `.help("在智能文件夹中隐藏")` tooltip。Scope 锁死：仅 root 层，subfolder 不显（嵌套继承规则复杂 — root hide 整树 / subfolder 单独 unhide / subfolder 单独 hide — 显式规则需单独产品决策；当前 contextMenu label 仍能表达 subfolder hide 状态） |
| `5cd4387` | V2.0 GA SVG preview / QuickViewer 永卡 spinner（c88c7ae 缩略图修法 follow-up）：用户报缩略图能看了但 preview 和 QV 仍卡 spinner。根因：`ImagePreviewViewModel.load` + `QuickViewerViewModel.load` 主路径都用 `CGImageSourceCreateImageAtIndex`，跟 c88c7ae 之前的 loadThumbnail 同 ImageIO API，对 SVG (vector) return nil → spinner。修法：(1) `ImageGridView.swift` 抽 `loadFullNSImage(url:)` 顶层 helper（SVG 走 `NSImage(contentsOf:)` / 其他走 CGImageSource），preview / QV 4 处主路径 + thumbnail 路径将来都可复用；(2) `ImagePreviewViewModel.load` + `QuickViewerViewModel.load` 主路径改调 helper；(3) prefetch 路径（preview / QV 各一）对 SVG `continue` 跳过 — `prefetchCache` 类型 `[Int: CGImage]` 存不了 vector，SVG 是 KB 级 vector 文件 cache miss 时主路径直 load 不亏。`loadFullNSImage` 抽出后未来加新 codec fallback (HEIF live photo 等) 一处改即可 |
| `c88c7ae` | V2.0 GA SVG 缩略图永卡 spinner：用户拖 `ai-logo.svg` 到 Downloads，FSEvents 入库正常（chip + 段头都出），但 grid cell 一直转圈；macOS Preview / Quick Look 能正常打开 SVG。根因：`loadThumbnail` 用 `CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceCreateThumbnailFromImageAlways` 对 vector 格式 (SVG) return nil（vector 无内嵌 raster thumbnail），spinner 永卡。修法：(1) `ImageGridView.swift loadThumbnail()` 加 SVG fallback —— `.svg` 文件走 `NSImage(contentsOf:)` 让 macOS CoreSVG rasterize，按 maxPixelSize 等比缩 nsImage.size，SwiftUI 渲染时按 vector 数据重新栅格化无糊；(2) `FolderStore.swift supportedExtensions` 加 "svg"，让 V1 单 folder mode 也接受 SVG（之前只 V2 ImageMetadataReader UTType 接受，V1 / V2 不一致）。注意：ImagePreviewView / QuickViewer 大图加载用 NSImage(contentsOf:) 原生支持 SVG（macOS 11+），无需改，PENDING 加项让用户测覆盖。Surface：2 文件 ~10 行 |
| `3914a01` | V2.0 GA 智能文件夹 grid spinner 永卡（stale row 残留）：用户首测「全部最近」grid 多张图卡 spinner 永久加载不出来，文件名 `00-cover.png` / `05-card-05.png` 等；Quick Look 能正常预览文件本身。SQL 查 IndexStore：发现 stale row（id=42 path=`未命名文件夹/output/05-card-05.png`，dedup_canonical=NULL）—— 用户在 Glance 没运行时用 Finder 把图从 subfolder 移到 root 顶层，FSEvents 只在 app 运行期监听（`kFSEventStreamEventIdSinceNow`），错过这次离线移动；FolderScanner 走 INSERT OR IGNORE **只插不删**，旧 row 永久残留；DedupPass 试读不存在的 path 算 SHA256 失败 → canonical 留 NULL；SmartFolder「全部最近」`dedupCanonicalOrNull=true` 把 NULL row 也送进 grid → cell 拼 `appendingPathComponent("未命名文件夹/output/...")` → CGImageSource 返 nil → spinner 永卡。修法（架构补 FSEvents 离线缺口）：(1) `IndexedImage.swift` 加 `fetchAllRelativePaths(folderId:) -> Set<String>` + `deleteImages(folderId:, relativePaths:) -> Int` 批量 API；(2) `FolderScanner.scan` 加 cleanup pass：完整 scan（resumeFrom == nil）期间收集 seenPaths，扫完算 `stored - seen` batch delete stale row + log；resume 场景 seenPaths 不全跳过避免误删；DedupPass 在 cleanup 后由 caller (FolderStoreIndexBridge) 自动重跑修正 canonical（`triggerDedupFullPass` 已挂在 registerAndScan 末尾）；(3) 顺手补 `nonisolated DedupPass` + `nonisolated ContentHasher` 修 Swift 6 strict concurrency warning（之前 detached task 调 main actor isolated static method 报 warn，build 时实际 work 但全局规则不允许 warn）。也可由 backlog "sidebar 文件夹右键刷新"补补充手动 trigger 入口 |
| `5f1e365` | V2.0 GA 启动双 loading 闪屏 follow-up（修法 1 `3ad6f1f` 不充分）：用户装 `3ad6f1f` 后报"仍连闪两下，间隔几乎一样"。codex:rescue gpt-5.5 high audit 拍板真根因 = 多 root + 已 indexed 库重启场景，bridge `registerAndScan → triggerDedupFullPass → onIndexChanged → refreshSelected` 在每个 root 完成时连发，肉眼合并成"连闪两下"；且 `SmartFolderStore.queryResult` 在 `.loading` 状态返回空数组，让 SmartFolderGridView 走 emptyState 分支 → grid 整片消失 = 视觉闪烁的真正放大器。修法 1（删 onChange-rootFolders 内冗余 refresh）只消了一条 source，没解决 bridge 自身的多 fire 问题，方案不对症。**修法 2（codex:rescue 推荐方案 5，本 commit 落地）**：让 `.loading` 状态保留上一次 `.loaded` 的数据，grid 不清空。改动：(1) `SmartFolderState.swift` `.loading` case 加 `staleImages: [IndexedImage]` 关联值；(2) `SmartFolderStore.swift` select / refreshSelected 进入 loading 时 carry 当前 queryResult（同 SF refresh）或 `[]`（切到不同 SF），queryResult accessor 在 `.loading` 返回 staleImages，stale-write guard 适配新 pattern；(3) SmartFolderGridView 完全不动（`queryResult.isEmpty` 分支自动失效）。覆盖所有 refresh source（启动 select / FSEvents / dedup / 手动 select / hide toggle 后 refresh），未来不再为新 trigger 闪。trade-off（codex 标的）：loading 期间用户可能点到 stale cell，启动场景接受度高 |
| `3ad6f1f` | V2.0 GA 启动双 loading 闪屏（修法 1，已被 follow-up 方案 5 叠加）：用户首测发现"打开 app 主区开始 loading → loading ok → 突然又消失又 loading 一下 → grid ok"。根因：`ContentView.swift` 启动时 query 被两条 source 各跑一次 → `SmartFolderStore.state` 走 `.idle → .loading → .loaded([]) → .loading → .loaded([])` 两次循环，每次 `.loading` 让 `queryResult` 短暂变 `[]`，grid 整片 unmount → 闪。Source 1 = `.onAppear → wireIfReady → select(allRecent)`；Source 2 = `.onChange(of: folderStore.rootFolders)`（启动时 BookmarkManager 异步还原把 rootFolders 从 `[]` → 实际列表 → 触发）调 `bridge.sync` 后又主动 `await smartFolderStore.refreshSelected()`。修法（方案 1，最小 surface）：删 `.onChange(of: rootFolders)` 内的 `refreshSelected()` 调用，仅保留 `bridge.sync(with:)`。bridge 内部 `registerAndScan` / `unregister` 末尾都跑 `triggerDedupFullPass → onIndexChanged → refreshSelected`，刷新路径已经存在，主动 refresh 是冗余。文件：`Glance/ContentView.swift` 的 `.onChange(of: folderStore.rootFolders)` 闭包 |
| `6284a13` | Slice I ship 后 codex 5 项 P1 hardcode UI 常量违反 fix：(1)(2)(5) `.secondary` 三处 → `DS.Color.secondaryText`；(3) `.red` → `DS.Color.errorAccent`；(4) `.scaleEffect(0.7)` → `DS.IndexingProgress.spinnerScale`；(6) `.red.opacity(0.3)` → `DS.Color.errorAccent.opacity(DS.IndexingProgress.errorBorderOpacity)`。DesignSystem.swift 加 `IndexingProgress` enum + `Color.errorAccent` token。Tag `v2.0` 已 push origin（指向有 P1 的 commit），fixup commit 标 `[skip-codex]` 跳 push range 复审 |
| `2b2528e` | V2 M2 J.10 P1 fix — `n: 30` magic number 提取 `DS.Similarity.topNResults` (CLAUDE.md 禁止魔法数字硬规则) |
| `6de1ee3` | V2 M2 J.8 P1 fix — EphemeralResultView 5 个 hardcoded value (close button 28pt / bg opacity 0.15+0.08 / empty icon 48pt / top padding 80) 提取到 DS.Similarity tokens |
| `PENDING` | V2.1-beta1 ephemeral+preview ESC 状态机 fix — Slice J 单击 ephemeral cell 进 preview 后 ESC 失效 / 失焦后再 ESC 一次清空到 baseGrid（跳过 preview 这层）。codex:rescue 拍根因：ZStack 同层多独立 @FocusState 注定 race（preview 和 ephemeral 各持私有 isFocused，没有仲裁者），SwiftUI focus 路由不可靠；同时 ContentView 兜底 ESC 只看 currentEphemeral 一次清光跳 preview 层。修法（最小 scope，codex 推荐 P1 单一枚举 @FocusState 全重构暂留 K 阶段做）：(1) ContentView 兜底 ESC 改 modal layer 状态机：QV > preview > ephemeral 按顺序拨开，每次 ESC 只关一层；(2) EphemeralResultView 删自己的 onKeyPress(.escape) 让 ESC 走 ContentView 兜底（不依赖 view-level focus 路由）；(3) 删动态 `.focusable(selectedImageIndex == nil)` + onChange of selectedImageIndex 简化回静态 .focusable()；同 commit 补 specs/v2 M2 design + plan 落盘 |
| `24f3eef` | ephemeral 双击进 QV → ESC 退 QV 错误反弹到 preview（应回 ephemeral）：用户报"双击直接进 QV 应该 ESC 直接回 ephemeral"。根因：QV 内方向键通过 onIndexChange 回调把 `folderStore.selectedImageIndex` 写成了 Z（ContentView line 170-175），ESC 退 QV 时 `case .ephemeral` 分支没清这个值 → quickViewerIndex==nil 且 selectedImageIndex!=nil → previewOverlay 渲染条件成立 → preview 在 ephemeral 之上 fade in。V1 `case .grid` 早就处理过同问题（注释："QV 期间方向键写过的 selectedImageIndex 这里清回 nil 防止 preview 反弹 mount"）。修：mirror `.grid` 行为，case .ephemeral 加 `folderStore.selectedImageIndex = nil`。ephemeral 的 highlightedURL 已被 onChange(of: selectedImageIndex) non-nil 分支同步到 Z 不丢。正确路由现：ephemeral 双击 → QV → ESC → ephemeral（一步）；ephemeral 单击 → preview → 双击 → QV → ESC → preview → ESC → ephemeral（两步） |
| `3c53191` | EphemeralResultView preview/QV 方向键浏览后退回 highlight 同步（mirror V1 Bug 4 真解）：用户期望"在 ephemeral 视图单击/双击进 preview 或 QV，方向键浏览到 Z 再 ESC 退回 → ephemeral grid highlight 跟到 Z"——对齐 Photos.app / Finder Quick Look 行为。V1 ImageGridView 已通过 `.onChange(of: folderStore.selectedImageIndex)` non-nil 分支同步 highlightedURL（Bug 4 真解 commit b67ab3c 类），但 EphemeralResultView 这条监听缺失，退回时 highlight 仍停在原图。修：`EphemeralResultView.swift` 加同型 onChange — `if let idx = newValue, urls.indices.contains(idx) { highlightedURL = urls[idx] }`。preview 方向键已写 selectedImageIndex（ImagePreviewView.navigate 内置）+ QV 方向键已通过 QuickViewerOverlay.onIndexChange → ContentView 写 selectedImageIndex（line 170-175），两条上游链路完整，本次仅补 ephemeral 下游消费端 |
| `5b54249` + `6a8feee` | EphemeralResultView 键盘方向键 + Space 进 QV + QV 退出回 ephemeral（V2.1-beta1 J.8/J.10 两个 UX gap 一次修）：(1) `EphemeralResultView.swift` 加 `GeometryReader` + `ScrollViewReader` + `.onKeyPress(.leftArrow/.rightArrow/.upArrow/.downArrow/.space)` mirror `ImageGridView` keyboard pattern，`moveHighlight(by:colCount:proxy:)` + `computeColumnCount(width:)` helper；cell VStack 加 `.id(url)` 让 scrollTo 工作。J.8 创建时键盘是 known TODO（line 80-82 注释明示"focusable + focusTrigger 保留作未来键盘导航扩展用"），V2.1-beta1 ship 用户首测发现方向键无响应。(2) `ContentView.swift:201-206` `case .ephemeral` 分支原本"QV 退出清 ephemeral 跳 baseGrid"（J.10 plan-time trade-off：当时 ephemeral 无键盘导航 + 无焦点恢复机制，"无焦点死状态"风险）。本次加完键盘 + focusTrigger 后 trade-off 不再必要，改为 `ephemeralFocusTrigger = UUID()` 保留 ephemeral + 刷焦点（对齐 Photos.app / Finder Quick Look：QV → ESC 回上一层 ephemeral，再 ESC 走 ContentView 兜底状态机才回 baseGrid）。modal layer 顺序：QV > preview > ephemeral > baseGrid。同型代码已在 `.none` 分支用过（路径 4：grid → QV → 找类似 → ephemeral → ESC QV → 回 ephemeral），本次相当于把路径 3 也接到同模式 |
| `195361b` | QV 工具栏自动隐藏 2s→4s + 找类似按钮 hover tooltip 修复（V2.1-beta1 用户首测发现 2 个 UX bug）：(1) `QuickViewerOverlay.swift` `.onContinuousHover` 两个 phase 写死 `scheduleHide(after: 2.0)` / `scheduleHide(after: 1.0)` — 工具栏 1-2 秒就消失，鼠标稍微移到窗口边缘 / Traffic light 区域 / 屏幕外触发 `.ended` 1s 路径，体感"还没等"就 hide。修：两个魔法数字提取 `DS.Viewer.controlsAutoHideSeconds = 4.0`（对齐 macOS Quick Look ~4s 节奏），两 phase 共用同一常量行为一致。(2) `toolbarButton(找类似)` 在 `currentSupportsFeaturePrint=false` 时 `.allowsHitTesting(currentSupportsFeaturePrint)` 把 hit test 全关 → button 收不到任何 mouse event 包括 hover → `.help(title)` tooltip "该格式暂不支持类似图查找" 无法触发。L284-287 action 闭包内已有 `if currentSupportsFeaturePrint` guard 阻止误触发，`.allowsHitTesting` 行是冗余 + 反而挡掉 hover。删除后视觉 disable 仍靠 `DS.Similarity.buttonDisabledOpacity` 区分，tooltip 可正常浮出 |
| `PENDING` | V2 M2 J.11 codex round 3 P1 batch fix — (1) FeaturePrintIndexer runLoop 加 `nonisolated` 标注：之前 `@MainActor final class` 让 static func 继承 MainActor 隔离，`Task.detached → await Self.runLoop` 仍 hop 回 main thread，Vision + SQLite 在主线程跑阻塞 UI 17 分钟（codex:rescue 独立 review 确认为真 bug）；(2) FeaturePrintIndexer pendingTotal 走新加 `countImagesNeedingFeaturePrint()` COUNT(*) 单独 query，避免 `fetchImagesNeedingFeaturePrint(limit: Int.max)` 内部 `Int32(Int.max)` 溢出 trap；(3) EphemeralResultView `Color.gray` 两处 + `spacing: 0` 提取 `DS.Similarity.neutralOverlay` + `DS.Spacing.zero`；(4) QuickViewerOverlay 找类似 button `.opacity(1.0/0.4)` 提取 `DS.Similarity.buttonEnabledOpacity/buttonDisabledOpacity`；(5) FolderStoreIndexBridge `featurePrintIndexer?.enqueueIfNeeded()` 加 MainActor 隔离链注释（codex round 3 P1 #6 false positive，注释帮助下一轮 review）|
| `99d6a91` | pre-push hook cache 路径在 worktree 下失败：`touch .git/codex-reviewed-<sha>` 报 "Not a directory"。根因：当前 repo 是 git worktree（实际 gitdir 在 `~/.../ISeeImageViewer/.git/worktrees/glance-v2/`），`.git` 是文件不是目录。hook 硬编码 `.git/codex-reviewed-...` 等于在文件下创建子文件。修：用 `GIT_DIR=$(git rev-parse --git-dir)` 拿真实 gitdir，CACHE 路径改 `$GIT_DIR/codex-reviewed-$local_sha`。worktree + 普通仓库都正确。验证：`docs-only` 路径下 push 不再报 `touch:` 错误 |
| `378a4e1` | M3.L plan-time codex P1 — `Calendar.date(byAdding: .month, value: -1)` 月偏移 + `addingTimeInterval(-1)` 秒偏移两处魔法 `-1` 字面量违反 CLAUDE.md "禁止魔法数字"硬规则（codex pre-push hook 抓到）。修：抽 `private static let oneMonthBack: Int = -1` + `oneSecondBack: TimeInterval = -1` 两个命名常量。pre-push hook 反馈循环触发，按 hook PROMPT 第 2 条严格判定，是真 P1 不是误判 |
| `PENDING` | D15 Focus refactor 回归 — preview 方向键第二次失焦（bdb8307 后用户首测发现）：preview 单击 cell 进 → 按方向键切到下一张 ✓ → 第二次方向键 + ESC 全静默，鼠标点 view 又能动一次后立刻失焦循环。根因（codex:rescue 验证为 [HYPOTHESIS] 时序层 race，而非 SwiftUI same-value dedupe 机制）：ContentView 历史给 ImagePreviewView 挂 `.id(idx)` 让每次 navigate 整 view rebuild；旧 trigger UUID 模型每次发新值能强制 isFocused = true，重构后共享 `@FocusState.Binding focusTarget` 在 rebuild 时 binding 已 = `.preview`，新 view mount + `.focused($focusTarget, equals: .preview)` 在 SwiftUI focus 系统跟 `.id` teardown 的时序窗口里没拿到焦点。修法（codex 推荐的结构层 minimal fix）：**删 ContentView 上 ImagePreviewView 的 `.id(idx)`** —— 该 view 已有 `onChange(of: startIndex) { currentIndex = newValue; loadImage() }`（ImagePreviewView.swift:136-138）自反应，不依赖 rebuild。view 不重建 → onAppear 只在 preview 首开时触发一次 → focusTarget = .preview 单次 transition → 后续 navigate 焦点持续保留。`@StateObject previewVM` 留在 ContentView（parent-owned 模式继续保留，cache 跨 navigate 自然保留无干扰）。.transition(.asymmetric) 仍生效（跟 conditional render 绑定，不跟 .id 绑定）|
| `PENDING` | M3.M.5 codex re-review 抓到的真 bug — runSearch 里 `images` 跟 `urls` 长度不一致风险：原实现 `let urls = images.compactMap { ...resolveBookmark... }` 当任何 bookmark 解析失败时 urls 比 images 短一截；EphemeralRequest.search 同时存两个，`datesForBuckets = images.map { $0.birthTime }` 长度跟 images 一致；EphemeralResultView 的 `dates.count == urls.count` guard 不通过 → silently 退化成 flat grid，search 时间分段静默丢失。修法：用 `(IndexedImage, URL)` pair compactMap 一起过滤，再 unzip 出 resolvedImages + urls，保证三者同步同长度。背景：M3.M.6 push 时 codex 拦了 2 个 .thickMaterial P1 假阳，我用 SKIP_CODEX_REVIEW=1 bypass 跳过 → 真 bug 一同被跳过。事后 hook PROMPT 修了 Rule 9 假阳后再跑 codex 才暴露。沉淀教训：codex P1 不轻易 bypass（feedback memory `feedback_codex_prepush_no_easy_bypass.md`）|
| `84a1f5b` | OpenWith Slice 2（浏览所在文件夹）+ warm open 崩溃修复：(1) Slice 2 — QV 底部「浏览所在文件夹」按钮（仅外部打开场景）+ handleBrowseFolder（已加直接 selectFolder / 未加 NSOpenPanel 授权后 addFolder）；(2) **warm open（app 运行中 Finder 打开方式）app 自杀** → 单 Window scene 处理 open-document 窗口瞬间 close 触发默认 terminate-after-last-window-closed，加 `applicationShouldTerminateAfterLastWindowClosed=false` 修复（实测有效）；(3) warm open 窗口不自动置顶 = **未根治 backlog**（macOS 14 拒绝 app 自消费 open 事件时抢前台，5 种激活 API 真机全败，codex:rescue 三轮；当前 best-effort：NSRunningApplication.activate + 降级 orderFrontRegardless）。配套：AppState.windowIdentity/attachWindow/detachWindow + WindowAccessor windowWillClose + ContentView scheduleActivation/waitForAppActivation + DS.ExternalOpen。详见 `specs/OpenWith-plan.md` Slice 2 完成详细 |
| `147d0e0` | 删 `loadThumbnail` 的 `maxPixelSize: Int = 200` 魔法数字默认值（codex pre-push P1）。三个 caller 全传显式值（targetSize*scale / size*scale / DS.Viewer.filmstripThumbLoadSize），默认从未被用 → 删默认变必传参，无需新常量。该行因 Slice 2 给 loadThumbnail 加 nonisolated 进入 diff 才被复审到 |
| `9bee287` | 图片加载失败显占位而非无限 loading（方案 3，Slice 2）：grid cell / 预览 / QV 三处 image nil 既表"加载中"又表"失败"→ 无限转圈。修：新建共享 `ImageLoadFailedView`（compact 模式 grid cell 仅图标）+ 三处加 `loadFailed` 标志（SmartFolderImageCell / ImagePreviewViewModel / QuickViewerViewModel），load 结束 image 仍 nil → 显占位。兜真删磁盘文件 FSEvents race / 损坏文件 / 不支持格式。附带：`loadFullNSImage` / `loadThumbnail` 标 `nonisolated`——项目 default main-actor isolation 把这俩离主线程解码 helper 当 @MainActor，Task.detached 里调会 hop 回主线程解码（UI 卡）；标 nonisolated 既消 actor warning 又恢复真·后台解码 |
| `0a069e6` | 侧边栏移除文件夹后智能文件夹仍残留缩略图 + 点开一直 loading（方案 1 移除即清理，Slice 1）：根因 `FolderStoreIndexBridge.sync` 移除 diff 用内存 `registeredPaths`（启动空 → 从不对账清残留）。修：(1) `BookmarkManager.managedRootPaths()` 同步受管根权威集；(2) `IndexStore.fetchRootPaths()`（parent_root_id IS NULL AND root_path IS NOT NULL）+ `deleteOrphanImages()`（NOT EXISTS 防御性孤儿清扫）；(3) `sync` 移除段改 **DB+bookmark 权威对账（Guard B）**——删 DB 里不在 managedRootPaths 的 root（FK CASCADE 连删 images），不用异步滞后的 rootFolders（启动瞬态空集会误删整库），managedRootPaths 同步永不滞后能区分"瞬态空"vs"删到最后一个"；(4) ContentView 两处 sync 传 managedRootPaths。codex:rescue 设计 review 确认 Guard B 优于 Guard A。**方案 3（加载失败占位）= Slice 2 另提交。** 加载失败一直 loading 的兜底未做 |
| `cc78c41` | OpenWith Slice 1 实测发现的 4 个 bug（详见 `specs/OpenWith-plan.md` Slice 1 完成详细）：(1) 多图「打开方式」spawn 多空白窗口 → `WindowGroup`→单实例 `Window`；(2) 外部打开进 QV 的 ESC 须先点图才生效（onAppear 时窗口非 key，@FocusState 丢弃）→ `AppState.isWindowKey` + WindowAccessor windowDidBecomeKey 播种 + QV onChange 补 assert（codex:rescue 方案 c）+ application(open:) NSApp.activate；(3) 智能文件夹进 QV 首次悬停工具栏 tooltip 串成随机文件名（V2 cell 显式 `.help(relativePath)` tracking 在 overlay 下残留串扰）→ mainContent `.allowsHitTesting(quickViewerIndex == nil)`（codex:rescue 二诊）；(4) smart folder cell tooltip 改显完整路径（复用 loadThumb resolve 的 fileURL.path）。附带修 M3 `ParsedSearch`/`SearchSizeUnit` actor-isolation warning（标 `nonisolated`）|
| `6e5169b` | Slice B-α deferred polish 落地 — 时间分段 chip 反色实底对比强化（PENDING「chip 深浅色对比强化」选**方案 C**）：此前 chip 停在 `.thickMaterial` + 0.5pt hairline strokeBorder，dark+dark / light+light 同明度背景下半透明 material 边界融。改：`DS.SectionHeader` 新增 `chipFill` / `chipText` 两个 `AdaptiveColor`（dark 模式浅底 0.84 灰 + 深字 0.11 / light 模式深底 0.30 灰 + 浅字 0.97），跟背景永远拉开整级明度差，参考 macOS Photos.app 日期 pill 不透明实底；`SmartFolderGridView.sectionHeader` + `EphemeralResultView.sectionHeader` 两处时间分段 chip 同步从 `.thickMaterial`+strokeBorder → `chipFill`/`chipText` 实底；旧 `chipBorderWidth/chipBorderOpacity` hairline 常量保留给进度/错误 chip（IndexingProgress / FeaturePrint / banner）复用。scope 严格：仅动 `DS.SectionHeader` 段 + 两处 sectionHeader chip 渲染，不触 pinnedViews / moveHighlight / locate / 其他交互 |
| `a3e4ae0` | OpenWith 方向2 Slice1 真机验发现 2 bug + 1 调整（详见 OpenWith plan Slice 1 完成详细）：(1) **看图窗只显 1×1 像素、看不到图**（cold/warm 都中，用户报"主界面闪一下→看不到 QV→app 僵尸态点 Dock 无反应"）→ `createWindow` 误用 `contentViewController = NSHostingController`，AppKit 忽略 contentRect 改用 hosting `fittingSize`（初始 `EmptyView`=0）→ 窗口压成 1×1；改 `contentView = NSHostingView`（mirror `AboutWindowController` 已验证骨架）+ `autoresizingMask=[.width,.height]` 跟随 resize/全屏；(2) **看图窗首开键盘须先点鼠标**（ESC/F/方向键不响应）→ `isWindowKey` 在 QV mount 前就翻 true、`.onChange` 漏触发，仅剩 onAppear 那次 assert 被刚 mount 帧丢弃 → `requestKeyboardFocusIfWindowIsKey()` 下一 runloop 补一次 `isFocused`（QuickViewerOverlay 共享改动，主窗用默认行为无副作用）；(3) 交通灯保持隐藏（QV 自带 X 关窗，红绿灯冗余且丑，revert 掉中途加的 `managesHostTrafficLights`）。**真机验过：warm 置顶成功（方向2 核心赌注成立）/ 多图翻页 / 连换图不显旧图 / focus / ESC·⌘W·X 关窗 app 不退**。诊断手段：NSLog 经统一日志被 redact 成 `<private>`，改写沙盒文件 trace 定位（诊断埋点已清理） |
| （本次） | M3 搜索两交互 bug（方案经 codex review 收敛）：(1) **⌘F 焦点不落搜索框**（须先点鼠标才能输入）→ `openSearch()` 同帧设 `currentEphemeral=.search` 触发 `EphemeralResultView.onAppear` 抢焦点 `.ephemeral`，覆盖同帧设的 `.search`，两 view 争同一 `@FocusState focusTarget`；修：EphemeralResultView 加 `autoFocusOnAppear`（search 传 false 不抢）+ `openSearch` 焦点延迟一拍（`Task.yield` 后单点设 `.search`，每次 ⌘F 都跑覆盖重复 ⌘F onAppear 不 fire）。(2) **回车无反应**（实时搜已出结果，回车仅跳 200ms debounce 无视觉变化）→ 改回车语义=收 overlay + 结果留 ephemeral + 焦点移结果网格，网格内回车/空格均开图；新增 `submitSearch` + `SearchOverlayView.onSubmit`；EphemeralResultView 加 `defaultHighlightFirst`（search 进网格默认高亮第一张，`focusTarget`/`urls` 双 onChange 兜底异步结果到达 race，M2 similar 传 false 行为不变）|
| （本次 follow-up） | 接上条 — 真机验「回车进网格第一张没高亮」未生效：`maybeDefaultHighlightFirst` 在 `onChange(of: focusTarget)` 回调里重读 `self.focusTarget`，@FocusState 此刻未稳定拿到旧值 → guard 失败；urls 兜底又因回车 `submitSearch` 重查相同结果 `onChange(of: urls)` 值不变不 fire，两路全哑。修：focusTarget 路径改用 `newValue` 判断（避开重读 self 时序坑），urls 路径用稳定后的 `focusTarget`，helper 改 `applyDefaultHighlight(focusIsEphemeral:)` |
| （本次） | ephemeral 结果开图错位（pre-existing M2 + 波及 M3 搜索，codex 二审定方案 A）：QV/preview/inspector/find-similar 图源 ternary `smartFolderStore.selected != nil ? v2Urls : folderStore.images`（143/232/518/705 四处）漏 ephemeral 情况——从普通 V1 文件夹进 QV 点找类似（或 V1 模式 ⌘F 搜索）时 `selected==nil`，错用 `folderStore.images`（原文件夹图）而非结果集 `v2Urls` → 缩略图与开图对不上。修：四处加 `currentEphemeral != nil`；`openSearch` 无条件清 `selectedImageIndex`（堵 ⌘F-from-preview 误切 stale v2Urls，codex 二审划重点必须无条件、不能嵌 `if quickViewerIndex != nil`）。codex 先推 enum 重构、二审自我推翻改判方案 A 更优（A 贴合现有架构、不必给 ImageGridView 加 V1 单击 callback）|
| （本次） | `type:` modifier 搜不到（sqlite3 实测复现 + codex review）：DB `format` 列存**大写**标签（"PNG"/"WebP"，ImageMetadataReader.formatLabel），SearchService 把输入 lowercased 成 "png" → `format = 'png'`；SQLite TEXT `=` 大小写敏感 → 0 结果（design § 6.1 要求 type case-insensitive，属实现 bug）。修：SmartFolderQueryBuilder.emitStringAtom 加 `caseInsensitive` 参数，仅 `.format` 的 eq/ne 传 true → `format = ? COLLATE NOCASE`（大写归一对混合大小写 "WebP" 无效，只能 SQL 层 NOCASE）。同 commit 修 SearchService:59 假注释（原写"format 存 lowercase"）。size:/birth:/keyword 实测均正常（keyword 走 LIKE，ASCII 默认 case-insensitive，不动）|

---

## 待修复 Bug

| 状态 | 模块 | 问题描述 | 已知信息 |
|------|------|----------|----------|
| ✅ 已修（方案 1+3） | IndexStore + SmartFolder | 侧边栏移除文件夹（非物理删除）后，该文件夹的图仍残留在智能文件夹缩略图里，点开预览/QV 一直 loading。**已全部 ship：方案 1（`0a069e6` Slice 1，移除即清理：DB+bookmark 权威对账 + 孤儿清扫）+ 方案 3（`9bee287` Slice 2，加载失败显占位 + nonisolated 解码）。** 下方原始诊断保留：根因：`FolderStoreIndexBridge.sync` 的移除 diff 用内存 `registeredPaths`（启动时空）→ 启动从不对账清理 DB 残留 root；smart folder 查询 `FROM images` 不强制 JOIN folders → 残留 image 行照查出 → 缩略图显示；预览/QV 走 `computeV2Urls` 无 startAccessing 而移除时已 stopAccessing 撤 scope → 读不到一直 loading。**方案（用户拍板 1+3）**：(1) `sync` 移除 diff 改 DB 权威对账（`fetchRootPaths` vs incoming → deleteRoot FK CASCADE），**必须防瞬态空 incoming 误删整个索引**（加 didRestoreFolders 类 guard，过 codex review）；(3) 加载失败显占位提示而非无限 loading（grid cell / preview / QV 三处）。下一摊独立 commit |
| ✅ 已全解决（Slice2 已实施真机验过） | OpenWith 外部打开窗口生命周期 | **warm open 窗口不自动置顶**——原 V1 模型（复用图库主窗）下 macOS 14 拒绝 app 自消费 open 事件时抢前台，5 种激活 API 真机全败（旧 backlog）。**2026-06-04 方向2 Slice1 真机验证：warm 置顶成功** —— 自建独立 `ExternalViewerWindowController`（不复用主窗，commit `7a32dff` + 1×1/focus fix `a3e4ae0`）后置顶可控，方向2 核心赌注成立，本顽疾 warm 部分**解决**。**剩余同根缺陷（SwiftUI `Window` scene 仍在场，Slice1 硬边界保留）→ Slice2 一并根治**：(a) **cold 启动双窗**——app 未运行时 Finder 打开方式会同时拉起图库主窗 + 看图窗（SwiftUI 主 scene 无条件建主窗）；(b) **warm 看完关图后图库主窗不自动回来**——odoc 进来时 SwiftUI 主 scene 处理 open-document 把主窗瞬态 close（窗口数→0，`shouldTerminate=false` 防自杀），关看图窗后须点 Dock reopen 才重建主窗。两者根因都是 `Window("一眼")` scene 还在。**2026-06-04 Slice2 已实施 + 真机验过**：移除 Window scene → `Settings` scene 挂 .commands（菜单栏存活，D-OW13）+ AppDelegate 用 `MainWindowController` 自建图库主窗（自任 delegate 取代 WindowAccessor D-OW16）→ **cold 双窗 + warm 关图主窗丢失全解决**，外加 cold 看完即走 + 退出语义关窗驻留（像 Photos，D-OW15）。commit `519bd74`(Task1)~`58e98fd`(Task6)。设计/plan 见 `specs/2026-06-03-openwith-lightweight-viewer-{design,plan}.md` + `specs/2026-06-04-openwith-slice2-plan.md`，决策 D-OW5~16 |
| 间歇 / 待复现 | TrafficLightHide | 双击缩略图进入 QuickViewer 后，左上角 Traffic Lights 按钮异常显示（不应可见 / 或位置错位）；同时侧边栏右上的"收缩侧边栏"toolbar item 消失（这一条按 ContentView.swift:87 的 `.toolbar(quickViewerIndex != nil ? .hidden : .visible, for: .windowToolbar)` 是有意为之，但与 traffic lights 异常一起出现疑似关联）。证据：用户截图 `~/sync/ScreenShot_2026-05-04_223944_900.png`（grid 模式正常）+ `~/sync/ScreenShot_2026-05-04_224129_612.png`（进 QV 后 traffic lights 残留）。**复现状态**：用户同 session 内再尝试已无法稳定复现，疑似间歇性 race。**历史 fix**：commit `f00a584`（进 QV 隐藏 / 退出恢复）→ `a064033`（全屏中退 QV 后 traffic light 不恢复 fix）→ `45a61f1`（hideTrafficLights() 挂载位置修正）— 此 bug 已修过 3 次，可能仍有未覆盖的 race / 时序边界。**下次复现思路**：(1) 加 print 日志到 hideTrafficLights / showTrafficLights / NSWindowDelegate 回调；(2) 复现时记录精确链路（grid 单击/双击 / 是否经 preview / 是否全屏中 / NSWindow 状态）；(3) 对 NSWindow.standardWindowButton(.closeButton)?.isHidden 做断言式 dump |
| ✅ 已修（Slice1 + Slice2 真机验全通过 2026-06-08/06-09/06-15）；Slice3 = backlog；2026-06-07 用户报 + 截图 `~/sync/a2.png` `~/sync/a3.png` | MainWindow + QuickViewer | **QV 打开（含全屏）时主窗 toolbar 没隐藏** —— 顶部露出 `+`/分栏/ⓘ/外观 那条工具栏，看图界面不纯净。**根因=方向2 Slice2 regression**：`ContentView.swift:295` 的 `.toolbar(quickViewerIndex != nil ? .hidden : .visible, for: .windowToolbar)`（V1 commit `4162d7b` 加的 QV 隐藏逻辑，上一行 TrafficLightHide 项也引用过）是 SwiftUI **window scene 管理**的修饰符；方向2 Slice2 把主窗从 SwiftUI `Window` scene 改成 `MainWindowController` 自建 `NSWindow`+`NSHostingView(ContentView)`（不走 scene）后，`for: .windowToolbar` 隐藏指令桥接不过去 → **失效**（但 `.toolbar { ToolbarItem }` 内容仍桥到 titlebar 显示，所以 toolbar 露着）。`MainWindowController:66-70` styleMask `.titled`+`.fullSizeContentView` 且**未设** `titleVisibility=.hidden`（对比外部看图窗 `ExternalViewerWindowController:99-100` 设了 → 纯净）。**2026-06-08 尝试 3 轮全失败，已回滚到 `a2a8fd4` 干净态（QV toolbar 露但稳定）**。死结记录：(1) AppState `window.toolbar?.isVisible=false` + `titleVisibility=.hidden` 单设**无效** → **codex 一诊**：NSHostingView 当 contentView 时 `sceneBridgingOptions` 默认 `.all`，SwiftUI 把 `.toolbar{}`/`.navigationTitle` **持续复写**回 `NSWindow.toolbar`/`title`，AppKit 单次设值被下一帧 bridge 覆盖；(2) toggle `sceneBridgingOptions [] ↔ .all`（QV 时 `[]` 断复写）→ 隐藏可靠不闪，但恢复 `.all` **重建 NSToolbar 丢 NavigationSplitView column 布局** → detail 区按钮（ⓘ/外观/slider/排序）**飘到左边**（截图 `~/sync/z1.png` `z2.png`）；(3) 不 toggle + `Task.yield` 二次 reassert（**codex 二诊**）→ 布局保留，但「先露后藏」**闪一下**且第一次抢不赢 SwiftUI 复写、toolbar 没藏住（截图 `~/sync/z3.png`）。**根矛盾**：SwiftUI 在 bridging 下"拥有" toolbar visibility，AppKit 改它要么被复写(闪)、要么切 bridging 重建丢布局(飘左)，无法两全。**唯一干净解 = codex 方案 2（大改，重开会话专做）**：`sceneBridgingOptions = []` 永久 + MainWindowController **手动建 AppKit NSToolbar**，把 6 个按钮（+/分栏/ⓘ/外观/slider/排序）全 AppKit 重写 + 绑回 SwiftUI action → toolbar 完全归 AppKit 管，隐藏可靠（无复写）+ 布局可控。与 TrafficLightHide（上一行）同属「QV 窗口装饰隐藏」可一并设计。codex thread 可参考（一诊 sceneBridgingOptions / 二诊 deferred reassert）。**非 M3 chips 改动**（chips 13 commit 未碰 ContentView toolbar / MainWindowController / QV，git 可查）。**2026-06-08 方案2 Slice1 实施**：QV 迁 `MainQuickViewerWindowController` 独立无装饰窗（commit `ebd88bf` 骨架 / `701f20a` show-close-focus时序 / `e48007f` I1-I2 死结防御 / `07619c8` ContentView 原子迁移）+ become-key 焦点时序地基；windowedCover 态**真机验通过（2026-06-08，9 项全过：titlebar 纯净 + 同框跟随 + 焦点归还 + 找类似/⌘F + 状态保留 + 全屏 ESC）**；全屏状态机(**Slice2 实施完，inheritedMain 真机验过**，commit `5d47b3c`~`a4520c5`：全屏输入经 controller 路由 + 状态机（初版 4 态含 fullScreenAuxiliary 继承，后简化为 **3 态 + enteredFromMainFullScreen flag**）+ 防御修复 I-1 behavior 复位对称 / I-3 observer 生命周期对称 / M-1 inheritedMain transitioning 保护 / close transitioning guard 防全屏过渡中途关窗 / 主窗 willClose+miniaturize force close（绕 transitioning guard，主窗终结信号强制关 QV）防悬挂 / **inheritedMainFullScreen 改 codex 候选2（`31ff1b1`，真机验通过）：QV 自己 toggleFullScreen 进原生全屏新 Space（候选1 borderless+fullScreenAuxiliary 满屏覆盖真机踩 3 坑弃用——浮窗不满屏/ESC焦点/关闭塌主窗全屏）；走 documented 全屏生命周期，满屏 + ESC 退回主窗全屏 grid**)/边界(Slice3)未做。**遗留 backlog**：QV 全屏小图不铺满（fit 模式居中黑边，待定 fill）。设计/plan 见 `specs/v2/2026-06-08-qv-toolbar-{design,implementation-plan}.md` |

## 待开发

| 阶段 | 模块 | Spec | 优先级 | 前置依赖 | 说明 |
|------|------|------|--------|----------|------|
| ✅ 已完成 `84a1f5b` | OpenWith Slice 2 浏览所在文件夹 | `specs/OpenWith.md` + `specs/OpenWith-plan.md` Task 2.x | — | — | QV「浏览所在文件夹」按钮 + handleBrowseFolder 已 ship。OpenWith 功能（Slice 1 看单图 + Slice 2 浏览文件夹）完整 |
| ✅ 已完成 `7a32dff` | OpenWith 方向2 Slice1 自建独立看图窗 | `specs/2026-06-03-openwith-lightweight-viewer-{design,plan}.md` | — | — | 外部打开改自建 `ExternalViewerWindowController`（Preview 式独立看图窗，不复用图库主窗）+ `ViewerSession`（scope/terminateOnClose）+ QuickViewerViewModel deinit。Slice1 warm-only（terminateOnClose 恒 false，保留主 Window scene）；三轮 codex review 收敛。真机验过 warm 置顶/显图/focus（含 1×1 fix `a3e4ae0`） |
| ✅ 已完成 `519bd74`~`58e98fd` | OpenWith 方向2 Slice2 收回 lifecycle | `specs/2026-06-04-openwith-slice2-plan.md` | — | Slice1 | 移除 SwiftUI `Window` scene → `Settings` scene 挂 .commands（菜单栏存活 D-OW13）+ AppDelegate 自建 `MainWindowController` 图库主窗（自任 delegate 取代 WindowAccessor D-OW16）+ cold/warm lifecycle（D-OW14）+ 退出关窗驻留（D-OW15）。删 `ExternalOpenCoordinator.swift` + `WindowAccessor.swift` + ContentView externalOpen 残留 + QV onBrowseFolder + DS.ExternalOpen。**cold 双窗 + warm 关图主窗丢失全解决 + 冷启动看完即走**。两轮 codex plan review（抓 P1 delegate 双持）+ subagent-driven 实施 + 真机门控全过 |
| 🚧 实施中（**M4 · 初心核心闭环**）| 重复 / 相似图清理省空间 | design + 任务 1 plan 已 ship `specs/v2/2026-06-10-m4-design.md` + `specs/v2/2026-06-16-m4-task1-implementation-plan.md`（design 4 轮 codex review + plan 4 轮 codex review 收敛）；任务 1（只读总览）实施中：步骤 1 bridge 多播升级 D35 ✅ `5b77249` / 步骤 2 聚合查询 + DuplicateGroup + DS.Dedup ✅ `2abe08d` / 步骤 3 Model 状态机 + bridge observer 订阅 ✅ `989d5cb` / 步骤 4 View + 侧边栏入口 + 五态互斥 ✅ `9c93c10`~`3584910` / 步骤 5 /go 收尾 ✅。任务 2（删除闭环）推迟到卷类型验证矩阵跑通 | **高** | M1 去重(DedupPass) + M2 类似(queryTopN) 底层已有 | **回归初心**：底层 SHA256 去重 + Vision 相似已做，但用法被动（Inspector 单张看副本 / QV 选图找类似）+ **无删除功能**（grep 全项目只一个 `trash` icon 常量）。M4 补闭环：(1) **主动扫描总览**「X 组重复 / Y 组相似 · 共 Z GB」(2) **批量删除 / 移废纸篓**（不抢库红线：移废纸篓非直删、可撤销）。看图浏览退辅助。详见 memory `glance_mission_gap_m4` |

---

## 开发流程基础设施（2026-04-23 ~ 2026-04-25 落地）

| 工具 | 位置 | 作用 | 关键 commit |
|------|------|------|-------------|
| pre-push codex review hook | `.githooks/pre-push`（`core.hooksPath=.githooks`）| `git push` 时 codex 自动审待推 `.swift + *.md` diff，发现 `[P1]` 阻塞，`[P2]` 警告。docs-only 自动跳过。绕过：`git push --no-verify` / `SKIP_CODEX_REVIEW=1` / commit msg 含 `[skip-codex]` `[wip]` | 3d04775（建）/ 7751b8d（修启动日志误报） |
| `/go` 五步收尾命令 | `.claude/commands/go.md` | 任务收尾必跑：verify 三段 → 文档同步 → PENDING → commit+push → 一段话汇报。Step 1 红→修→重跑最多 5 轮；scope 例外 `[docs-only]` 跳 Step 1 | ffe9618（三步初版）→ 0b3d349（升 5 步） |
| `verify.sh` 三段 oracle | `scripts/verify.sh` | Stage 1 静态规则（ms）+ Stage 2 `xcodebuild build -quiet`（CONFIGURATION_BUILD_DIR=./build）+ Stage 3 单测占位。`--with-codex` 可选全项目 codex 审查。完整 log 留 `.verify-logs/` | ffe9618 / af4f733（路径与 make run 统一）/ 5984323（Stage 2 build 成功后 sync 到 `~/sync/Glance.app`；同步改 Makefile build target，两条 build 路径行为一致；用户本地测试机通过 Syncthing 拉取）/ 38adfd4（build 版本号注入 `CURRENT_PROJECT_VERSION=<commit>[-d].<MMDD-HHMM>` + sidecar `Glance.app.BuildInfo.txt`，关于面板显示 commit hash 取代不可靠 mtime）|
| PENDING durable 队列 | `specs/PENDING-USER-ACTIONS.md` | 不能自动验证的人工测试项入库累积；`/go` Step 3 追加，人工测完从 Pending 段剪到 Done 段保留历史 | ffe9618 |
| 汇报模板 | `.claude/commands/go.md` Step 5 | 编译行硬约束：`BUILD SUCCEEDED + 0 warnings + ./build/.app mtime + HEAD commit time`。CC 责任终点 = `./build/.app` 是 HEAD 产物（用户本地脚本拉取） | b9822ab / 0c3176d / ffd7ffd |

**工作流**（2026-04-23 用户澄清）：CC 在远程开发机写代码 + `verify.sh` / `make build` 编译到 `./build/`；用户在本地机通过脚本直接拉 `./build/Glance.app` 测试。CC 不教 `make run` / `Cmd+Q`，那是用户本地自动化的事。

**跨 session 持久规则**（写入 auto memory，下次 session 自动加载）：
- `feedback_build_before_handoff.md` — /go Step 5 编译行必须独立显眼（含 `./build/.app` mtime），禁止仅靠 verify "11 passed" 替代
- `feedback_verify_build_path_must_match_run.md` — verify.sh 必须 `CONFIGURATION_BUILD_DIR=./build` 与 Makefile 一致，不得用 `-derivedDataPath` 隔离
- `user_collaboration_style.md` — 协作偏好：新功能 / 设计选择 / bug 因果链不明朗 → 先方案后动手；明确 bug → 直接修

---

## Distribution（公开分发打包，2026-05-05 落地）

V1 走 **Developer ID 签名 + Notarization + DMG**（不上 Mac App Store），公开分发到 GitHub Releases。

**身份与配置**

| 项 | 值 | 备注 |
|---|---|---|
| Apple Developer Program | Hongjun Sun（个人）| 续订到 2027/05/05，年费 ¥688 |
| Team ID | `8KW8Z92GRA` | pbxproj `DEVELOPMENT_TEAM` 字段 |
| 签名 identity | `Developer ID Application: Hongjun Sun (8KW8Z92GRA)` | 装在 Mac mini 登录 keychain；私钥 .p12 备份在家里 MacStudio + 冷备份 |
| Bundle ID | `com.sunhongjun.glance` | 不变 |
| 部署目标 | macOS 14.0（Sonoma）| 26.2 → 14.0 降级，覆盖 ~85% 用户 |
| Marketing 版本 | `1.0.0` | 用户可见（关于面板 / DMG 文件名 / GitHub release tag） |
| Build 版本 | `<commit short>[-d].<MMDD-HHMM>` | 给开发者看，CFBundleVersion 字段，发布版仍带 -d 标记表示有未 commit 改动 |
| Hardened Runtime | `ENABLE_HARDENED_RUNTIME=YES` | 仅 release 脚本注入，不写到 pbxproj（Debug build 不受影响） |
| Entitlements | sandbox + user-selected read-only + bookmarks app-scope | 不需要 hardened runtime 额外 entitlements |

**入口**

```bash
make release        # 完整流程（含公证，5-15 分钟）
make release-dry    # 跳过公证（SKIP_NOTARIZE=1，本地干跑验证签名 + DMG，不耗 Apple quota）
```

**链路**（`scripts/release.sh`）

```
xcodebuild archive (Release + Hardened Runtime + manual signing + Developer ID Application)
  → exportArchive (scripts/ExportOptions.plist, method=developer-id, manual signing)
  → codesign --verify --deep --strict 验证
  → create-dmg (volname="Glance 1.0.0", drag-to-Applications layout)
  → xcrun notarytool submit --wait --keychain-profile glance-notary
  → xcrun stapler staple
  → spctl --assess Gatekeeper 验证
  → dist/Glance-1.0.0.dmg + SHA256
```

**首次跑前一次性配置 notarytool**（用户做）：

```bash
# App-specific password 在 https://appleid.apple.com/account/manage 「登录与安全 → App 专用密码」生成
xcrun notarytool store-credentials "glance-notary" \
  --apple-id 16414766@qq.com \
  --team-id 8KW8Z92GRA \
  --password <App-specific password>
```

凭据存入 login keychain，后续 `make release` 自动读，无需再输密码。

**分发渠道**：GitHub Releases（**仓库改 public 后**，DMG 上传 release，README 加下载按钮 + SHA256）

**已完成**

- `38adfd4` BuildVersionInfo（commit hash + sidecar）
- `bd25fd0` 关于面板 Copyright 注入（孙红军 / 16414766@qq.com / 小红书 382336617）
- `8f927d1 + 6f56072 + 09c418c` 自定义关于面板（点击复制 + toast）
- pbxproj 部署目标 26.2 → 14.0 / MARKETING_VERSION 1.0 → 1.0.0 / 加 DEVELOPMENT_TEAM
- `Makefile` 加 `release` / `release-dry` target
- `scripts/release.sh` + `scripts/ExportOptions.plist`
- `.gitignore` 加 `dist/`
- create-dmg via `brew install create-dmg`
- **2026-05-07 session 收口**：notarytool keychain profile 已重存 (5/5 配过但 5/7 ACL 丢失) / 部署目标降级 7 路径 smoke test 全过 / `make release` 真跑成功 (`504c102` 回填 release notes 元数据；公证 Submission ID `cb7db74c-afbb-4e12-98a5-912ca15eefff` Accepted / staple worked / universal binary 三处验证 x86_64+arm64) / `dist/Glance-1.0.0.dmg` 含本 session 6 fix + 真公证 + staple，可发布

**待办（Pending 用户操作 — 全是不可逆）**

- [ ] **DMG 干净 Mac Gatekeeper 实测**（推荐发出去前最后兜底）：把 `dist/Glance-1.0.0.dmg` 拷到一台**不是签名机**的 Mac → 双击挂载 → 拖 .app 到 Applications → 双击启动 → 期望直接打开不弹任何 Gatekeeper 警告
- [ ] **GitHub 仓库 visibility 改 public**（不可逆）：`gh repo edit sunhuaian2026/ISeeImageViewer --visibility public --accept-visibility-change-consequences` 或 GitHub 网页 Settings → Danger Zone
- [ ] **创建 v1.0.0 GitHub Release**（公开可见，不可逆）：`gh release create v1.0.0 dist/Glance-1.0.0.dmg --title "Glance 1.0.0 · 一眼" --notes-file docs/release-notes/v1.0.0.md`
- [ ] 小红书引流到 Release 下载链接（市场推广，可任何时候做）
- [ ] (可选 v1.0.1 cleanup) GitHub 仓库改名 ISeeImageViewer → Glance（GitHub 自动留旧路径 redirect）
- [ ] (可选 v1.0.1 cleanup) `release.sh` L191 `du -h` 取的是 disk usage 而非文件大小，输出 misleading（本次 3.4M vs 实际 2.4 MB），改用 `stat -f %z` 或类似按 byte 格式化

---

## 关键架构决策（新 session 必读）

1. **DesignSystem.swift**：所有 UI 常量的唯一来源，引用 `DS.*`，禁止硬编码。动画常量为 `DS.Anim.fast / normal / slow`（注意：旧名 `DS.Animation` 已废弃）。
2. **PBXFileSystemSynchronizedRootGroup**：`Glance/` 目录下新建 .swift 文件自动加入编译，无需改 xcodeproj。
3. **图片查看两级交互 + QV 入口仲裁** ⚠️ **QV overlay 模型已被下方第 11 条「QV-toolbar 方案2 独立窗」取代（2026-06-08）**——QV 不再是 `.overlay`、无 `quickViewerIndex` 哨兵、焦点恢复改 controller become-key 回调；entry 路由语义保留在 `handleQVDismiss`，本条单击→preview 逻辑仍有效：
   - 单击缩略图 → `folderStore.selectedImageIndex` 被设 → mainContent ZStack 渲染 `ImagePreviewView`（文件名通过 `ImageGridView.navigationTitle` 按 `selectedImageIndex` 动态决定显示在系统 toolbar，不在 `ImagePreviewView` 自身设）
   - 双击缩略图 → onDoubleClick 显式清 `selectedImageIndex = nil` + 设 `quickViewerEntry = .grid` + `quickViewerIndex = idx` → `QuickViewerOverlay` 渲染；关闭后按 entry 路由回 grid（保 `6da903c` 行为不进 preview）
   - 双击内嵌预览图片 → preview onQuickView 设 `quickViewerEntry = .preview` + `quickViewerIndex = idx` → `QuickViewerOverlay` 渲染；关闭后按 entry 路由回 preview，preview 通过 `.id(idx)` 重建显示 QV 浏览到的最后一张图
   - **QV 内方向键 / nav button / filmstrip tap** → `viewModel.currentIndex` 变 → `QuickViewerOverlay` 一处 `onChange(of: viewModel.currentIndex)` 上报 ContentView → 写 `selectedImageIndex` → ImageGridView `onChange(of: selectedImageIndex)` non-nil 分支自动同步 `highlightedURL` → ESC 退 QV 后 grid highlight (`.grid` 入口) / preview (`.preview` 入口) 都跟到当前位置（对齐 Finder Quick Look + Photos.app）
   - **入口来源 enum**：`private enum QuickViewerEntry { case grid, preview }` + `@State quickViewerEntry: QuickViewerEntry?`，dismiss 仲裁按 provenance 路由（`switch quickViewerEntry`），不依赖 `selectedImageIndex` 是否 nil 当哨兵 — 不破坏 `6da903c` 修过的"双击 cell 进 QV 后退出回 grid"
   - **mainContent 渲染条件收紧**：`if let idx = selectedImageIndex, quickViewerIndex == nil { ImagePreviewView(...) }` — QV 期间不渲染 preview，避免 `.id(idx)` 让 preview 在 QV 内方向键改 selectedImageIndex 时整体重建/loadImage
   - **焦点恢复**：QuickViewerOverlay 为 overlay 不会 trigger onAppear；通过 `ContentView.previewFocusTrigger` / `gridFocusTrigger`（UUID）信号驱动子 view onChange 重新 `isFocused = true`，按 `quickViewerEntry` 仲裁路由
4. **QuickViewerOverlay 覆盖方式**：用 `.overlay` 挂在 `NavigationSplitView` 上（不用 ZStack），确保铺满整个内容区。
5. **三栏布局**：`ContentView` = NavigationSplitView（Sidebar） + HStack（Detail + Inspector）。Inspector 用 `⌘I` 切换，宽度 `DS.Inspector.width`（260pt）。Inspector 按钮在无图片选中时禁用；切换文件夹或取消选图时自动关闭 Inspector。
6. **颜色系统**：光晕 `DS.Color.glowPrimary`（紫）/ `glowSecondary`（青绿）。`DS.Color.appBackground` (#121217) / `gridBackground` (#141419) 自 2026-05-06 起 **仅 QuickViewer / ImagePreviewView 引用**（QuickViewer 强制 dark 是设计选择，preview 内嵌底色保留）。FolderSidebarView + ImageGridView **不再** 用这两个值 —— 改让 NavigationSplitView + `listStyle(.sidebar)` 默认行为接管：sidebar 自动 NSVisualEffectView material `.sidebar` + state `.followsWindowActiveState`（失焦自动褪色，跟 Finder/Mail/Notes 一致），内容区用 NavigationSplitView 默认 NSColor.windowBackgroundColor / controlBackgroundColor（dark/light system semantic 派发）。`DS.Color.viewerBackground` 已废弃。
7. **树形侧边栏**：`FolderStore.rootFolders: [FolderNode]`（替代旧 `folders: [URL]`）。`discoverTree(at:)` 递归构建子文件夹树，`countImagesInTree(_:)` 统计各节点图片数。子文件夹继承父文件夹的 Security Scoped Bookmark，无需独立权限。
8. **loadThumbnail()**：定义在 `ImageGridView.swift`，internal 级别，`FilmstripCell` 复用。
9. **AppState**：全局 ObservableObject，持有 `NSWindow` 引用 + `isFullScreen` 状态，通过 `EnvironmentObject` 注入。
10. **构建**：项目根目录有 Makefile，用 `make build` / `make run`。
12. **侧边栏选中高亮**：使用 `List(selection:)` 绑定，完全依赖 macOS 系统渲染。聚焦时显示 Accent Color，失焦时显示灰色——这是 macOS 原生行为（Finder / Notes / 邮件均如此），用于传达键盘焦点所在，不做自定义覆盖。`listRowBackground` 选中行设为 `Color.clear`，让系统选中高亮独立渲染。
13. **AppearanceMode**：外观模式（system/light/dark）存在 `AppState.appearanceMode`，通过 `GlanceApp` 的 `preferredColorScheme` 驱动全局外观。`DS.Color.*` 背景/交互色（`appBackground` / `gridBackground` / `hoverOverlay` / `separatorColor`）为 `AdaptiveColor` 类型，实现 `ShapeStyle.resolve(in:)` 从 `EnvironmentValues` 读取 `colorScheme`——可正确响应 SwiftUI per-view `preferredColorScheme` 覆盖。`glowPrimary` / `glowSecondary` 保持 `SwiftUI.Color`（不需要自适应）。`QuickViewerOverlay` 保留 `.preferredColorScheme(.dark)`，其内部所有 `DS.Color.*` 始终解析为 dark 值。`FolderSidebarView` 移除了旧的 `.environment(\.colorScheme, .dark)`，背景改为 `DS.Color.appBackground` 自适应。`ImagePreviewView` 前景色使用 `Color.primary`（深色模式为白，浅色模式为黑）。

11. **QV/全屏看图独立窗（QV-toolbar 方案2，2026-06-08，取代第 3/4 条 overlay 模型）**：主窗 QV 从 `ContentView` 内 `.overlay { QuickViewerOverlay }` 改为 `MainQuickViewerWindowController` 单例管理的 **top-level 同框无装饰 NSWindow**（盖住主窗，复用 `ExternalViewerWindowController` 已验证纯净模式），修 toolbar regression（方向2 Slice2 后主窗自建 `NSWindow`+`NSHostingView` 让 SwiftUI 持续把 `.toolbar{}` 复写回 titlebar，AppKit 单设隐藏被覆盖）。要点：(a) 主窗 ContentView 视图树不动 → grid/sidebar/滚动/列宽状态天然保留（优于"条件切换根视图"方案）；(b) `quickViewerIndex` 哨兵拆成 `qvController.isPresenting`（ContentView 观察）+ 当前 index 归 controller；(c) 进出走 `presentQuickViewer` / `handleQVDismiss`，退出按 `QVDismissalReason{normal/findSimilar/commandF}` 经主窗 become-key 后回调（`MainWindowController.runAfterNextBecomeKey`，含主窗已-key fallback + generation guard）仲裁焦点 + prepareDismiss 同步清状态防 stale preview；(d) 全屏 **3 态**状态机（windowedCover / qvNativeFullScreen / transitioning）+ **`enteredFromMainFullScreen` flag**（主窗全屏来源标记，非独立态）：主窗已全屏时 QV 自己 toggleFullScreen 进原生全屏新 Space（codex 候选2 `31ff1b1` 真机验通过；候选1 borderless+fullScreenAuxiliary 满屏覆盖踩 3 坑弃用——浮窗不满屏/ESC焦点/关闭塌主窗全屏；退原生全屏（ESC/F/绿灯/手势/系统菜单任意方式）据 `enteredFromMainFullScreen` 统一 close 回主窗全屏 grid，进/退各一次 Space 切换动画，走 documented 全屏生命周期）；windowedCover/qvNativeFullScreen 保留"首 ESC 退全屏、次 ESC 关 QV"，close 加 transitioning guard 防过渡中途关窗。Slice1（windowedCover，9 项 2026-06-08）+ Slice2（全屏 6 项 2026-06-15 + inheritedMain 候选2 2026-06-09）真机验全过，整 regression 收口；Slice3 边界硬化 = backlog 未启动；小图全屏放大 = 独立 backlog 待重做。详见 `specs/v2/2026-06-08-qv-toolbar-{design,implementation-plan}.md`（D-QVT1~7）。

---

### V2 决策（2026-05-06 grill-with-docs 收尾沉淀）

V2 引入跨文件夹聚合（智能文件夹）+ 找回（搜索 + 类似图）。下面 10 条是 V2 设计阶段经过 brainstorming + grill 走完后筛过 "hard-to-reverse + surprising-without-context + real-trade-off" 三标准的决策。术语见 `CONTEXT.md`「跨文件夹聚合」段。

14. **D1 智能文件夹 = rule-based ONLY**：smart folder 永远是 query 结果，不存储 manual membership（不允许"用户拖图进收藏夹"）。Why: "不抢库"哲学红线——一旦引入"V2 自有的图组织数据"，用户卸载 V2 这些信息会丢，跟 Eagle / Photos lock-in 同质。How to apply: M4 用户自定义 smart folder 仍是规则形态，不开"添加图到 collection"接口；未来如有"打标记"诉求，引导用 macOS Finder Tags（OS 级 xattr）而非 V2 内部 DB。

15. **D2 受管文件夹默认全递归 + per-folder hide 剪枝**：V1 已加 root folder 自动纳入智能文件夹扫描范围（半显式）；扫描默认全递归所有子目录；任意 root 或子目录右键可 toggle "在智能文件夹中隐藏"，hide 状态可继承（hide root 默认 hide 整棵树，子目录可单独 unhide 取消继承）。Why: "仅 root 层"在 `类别/年份/` `项目/版本/` 这类常见嵌套素材组织下基本不可用；"glob 黑名单"对普通用户认知门槛过高。How to apply: IndexStore schema 含 `hide_in_smart_view: Bool` 字段（per FolderNode）；扫描时递归过滤；新加 root folder 默认 `hide=false`。

16. **D3 内容去重 = SHA256 + cheap-first 粗筛**：智能文件夹 grid 同字节图只显示一次。先按 `(file_size, format)` 粗筛 → 仅对 size 碰撞的子集算 SHA256（绝大多数图 size 唯一不算哈希）。代表项 = birth time 较早的副本，其他副本在 Inspector 副本段列出。Why: A 不去重首屏被重复图占位（普通用户首屏第一印象差），B/C 误判风险高（同名 size 截图碰撞 / inode 不区分 cp 副本），D 哈希在 cheap-first 优化下成本可控（1 万张图首次索引仅几秒~十几秒额外开销）。How to apply: **只影响 smart folder 呈现**，不影响磁盘真相；用户从 V1 进具体 folder 看仍能看到所有副本。Q4 找回时可加 `duplicates:true` 过滤器（M3 power feature）。

17. **D4 时间分段 5 段自然语言 + 严格午夜对齐**：智能文件夹 grid 时间分段固定 5 段（今天 / 昨天 / 本周 / 本月 / 更早），用 `Calendar.startOfDay` 严格对齐午夜；时区用 device local，不做 UTC 归一化。Why: 段数稳定 5 段不随时间增长（vs 月份分段无限增长，sidebar 滚动疲劳）；"本周/本月" 自动包含更新两段后剩余的图，无 overlap；可预测 > 智能（滚动 24h / 5h 缓冲会引入"为啥这张图不在'今天'了"的隐藏逻辑）。How to apply: V2 spec 定义 `TimeBucket` 枚举 + 边界算法；M3 加"按拍摄时间"smart folder 时单独走 EXIF DateTimeOriginal，不与本规则冲突。

18. **D5 跨 folder 来源标识 = hover tooltip（image viewer convention）**：智能文件夹 grid cell 跟 V1 cell **完全等同**，无来源角标 / 永久标签。鼠标 hover 显示 tooltip = 完整 relative path；点进 Quick Viewer 后 Inspector 永久显示绝对 path + "Show in Finder"按钮。Why: image 是视觉本体（缩略图本身就是身份），不像 note 依赖 folder context；Photos / Eagle / Lightroom 行业 convention 一致 hide-from-cell（Apple Notes 路线机械搬过来不适用）；保持 V1 视觉密度。How to apply: V2 不做"smart folder cell 加 folder name 行" / "缩略图角标 emoji" 类视觉装饰；以信息密度优先 + 行业 convention 优先。

19. **D6 规则引擎 = Spotlight-like AND/OR 平铺**：smart folder 规则支持 `字段 OP 值` 条件 + AND/OR 二层平铺组合（无嵌套，无 NOT）。Why: 内置 smart folder（"截图" / "大图"）需要 OR（如 `filename CONTAINS "Screenshot" OR path STARTS_WITH ~/Desktop`），仅 AND 表达不了；嵌套 GUI 编辑器（NSPredicate-shape）对普通用户认知门槛陡，普通用户已熟悉 Spotlight / Finder 智能文件夹的"任一/全部"切换 UI。NOT 在 GUI 上反直觉（"看不是 PNG 的图"普通用户更习惯说"看 JPEG / HEIC / RAW"）。How to apply: 规则 JSON 格式 day-1 设计成兼容嵌套（`{op: AND, children: [...]}` 树形结构），未来扩展 GUI 可吃嵌套时数据无需迁移。

20. **D7 IndexStore = forward-looking schema + 增量 ALTER TABLE 迁移**：M1 一次性 ship M1-M3 已知字段（M1 用 birth_time / file_size / format / filename / relative_path / folder_id / dimensions / content_sha256 / dedup_canonical；M2 加 feature_print / revision / supports_feature_print；M3 加 exif_capture_date 等）。存 `~/Library/Application Support/Glance/index.sqlite`。Schema 版本变化走 ALTER TABLE ADD COLUMN（老数据 NULL，后台 lazy 补）；迁移失败 fallback full re-index。Vision feature print revision 单独追踪：macOS 升级 revision 不匹配仅 re-index 该列。Why: 反复 ALTER TABLE 比一次 forward-looking 风险低；feature print 的 revision 解耦让 macOS 升级不污染其他字段。How to apply: M1 schema 设计阶段考虑 M2-M3 字段；migration 测试覆盖三个场景（v1→v2 增字段 / Vision revision 变 / migration 失败 fallback）。

21. **D8 搜索 / 类似图结果 = ephemeral 视图**：⌘F 搜索结果 + Quick Viewer "找类似" 结果**不**作为持久 entry 进 sidebar，仅切换主 grid 显示；ESC / 切换 sidebar entry / 关闭 Quick Viewer 即取消。提供"保存为智能文件夹"按钮（M3+，把当前搜索条件转成自定义 smart folder 持久化）。Why: sidebar 累积搜索历史会成为噪音（用户每次 ⌘F 都长一条 entry）；ephemeral 模式跟用户对"搜索是临时操作"的直觉一致。How to apply: 搜索/相似图 UI 用同一 `EphemeralResultView` 组件（统一返回路径与状态管理）；"保存为" 按钮 M1/M2 不上 M3 才上。
    - **2026-05-11 行为修正（5b54249 / 24f3eef）**：原文"关闭 Quick Viewer 即取消"已细化为分层模型——ephemeral 视图自身的 ESC 才取消 ephemeral 回 baseGrid；QV 关闭只回上一层（ephemeral 双击进 QV → 回 ephemeral / preview → 双击进 QV → 回 preview），保留 ephemeral 让用户继续浏览类似图 grid。对齐 Photos.app / Finder Quick Look 行为。Modal layer 顺序：QV > preview > ephemeral > baseGrid，每次 ESC 只关一层。原 "关 QV 即清 ephemeral" trade-off 是 J.10 plan-time 的 "无焦点死状态" 折中，加完 EphemeralResultView 键盘方向键 + focusTrigger 焦点恢复机制后该 trade-off 不再必要。

22. **D9 V2 timeline = 13-15 周 + 每 milestone 跟一个 minor 版本**：M1 4-5 周 / M2 3 周 / M3 3-4 周 / M4 2-2.5 周（M4 optional）。每 milestone 完成跟一个 minor 版本发布（M1 → V2.0-beta1，M2 → V2.1，M3 → V2.2，M4 → V2.3），不等全部 M1-M4 完成才发 V2 大版本。每个 milestone 是端到端 vertical slice（端到端可跑 + 用户可感知 + 独立可 ship）。Why: 横切式拆分把集成 bug 全推到末尾爆雷；vertical slice 让风险前置 + 用户每片都有可感知收益 + 反馈密度比 3 个月一次大版本高得多。How to apply: 写 implementation plan 时每个 milestone 验证三标准（可跑 / 可感知 / 可 ship）；不达标的切片要重组。

23. **D10 V2 scope freeze（18 项 explicit "不做"清单）**：culling 工作流 / tag 标签系统 / color palette / 自然语言搜索（CLIP）/ "已读未读" seen-state / 跨设备同步 / 导入到自有库 / 编辑调色旋转写回 / NSPredicate 嵌套规则 / NOT operator / glob 黑名单 / 视频动图 LivePhoto 索引 / iCloud Drive placeholder + 网络盘 + 外接设备 / OCR 文本搜索 / Photos Memories 智能相册推荐 / Favorites 收藏 Star ratings / 多 library 切换 / EXIF metadata 写回——共 18 项 V2 范围外。Why: 每项都有 brainstorming + grill 阶段的明确 trade-off 推演（详见 V2 spec 不做段）；scope freeze 是单人项目按时 ship 的核心保障。How to apply: 收到"V2 能不能加 X"诉求时先查这 18 条；命中即拒（refer 到此条），不命中再走"加新 feature 决策流程"。

### M2 决策（2026-05-11 brainstorming + plan-time 拍板）

24. **D11 后台 feature print 索引启动即跑**：GlanceApp / ContentView wireIfReady 在 IndexStore ready 后立即启动 FeaturePrintIndexer.start()，全库 lazy backfill；已抽过的 row 通过 `feature_print IS NULL` SQL 谓词自然跳过。Why: 用户首次点"找类似"大概率已抽完，"立刻可用"体验优先于"启动 0 CPU"；CPU 占用换感知一致性。How to apply: 不在 lazy 模式（用户首点找类似才开抽）也不在 settings 加 toggle（M2 不引 Settings 面板）；K 阶段实测如电池机感知不可接受再考虑切策略。

25. **D12 M2 = 2 slice（J 端到端 + K polish）**：J（V2.1-beta1）一次 ship 后台索引 + QV 找类似按钮 + EphemeralResultView 端到端；K（V2.1 GA）专做 Vision revision 迁移 + 失败重试 polish + 错误 banner + 性能验收。Why: J 必须 user-perceptible（违反 vertical slice 三标准否决"backend only"切法）；K 是 polish + revision 数据一致性，单独 ship 不引新 demo 按钮。How to apply: J ship 后用户拿到完整 demo；K 仅修 J 暴露的 polish 项，不动 J 的 UI 接口。

26. **D13 类似图 = 纯 top-30 不加阈值过滤**：SimilarityService.queryTopN 取距离最小的 30 张返回；不加 hard threshold（0.6 之类）也不加 UI 分隔线。Why: 阈值是魔数字，不同库分布最优阈值差异大；用户自己判"像不像"成本低于学习配置。How to apply: queryTopN 写死 n=30；M3+ 如有调整诉求改成 setting；K 阶段如收用户反馈"小库末尾不准"考虑加 fade-out UI 提示但不切数据。

27. **D14 部分库时允许查 + banner 提示**：feature print 全库未抽完时（pendingTotal > 0）"找类似"按钮不 disable；查询走 fetchAllFeaturePrintsForCosine 拿当前已抽 row 跑 cosine；EphemeralResultView 顶部 banner = "已索引 X / Y 张，结果为部分库"。Why: 1 万图首次抽 ~17 分钟；disable 体验 17 分钟死锁。部分可用 + 显式提示符合 "show progress, don't gate" 原则。How to apply: ContentView.computeBanner 算 indexed/total，indexed >= total → banner = nil（隐藏）；EphemeralResultView bannerText 是可选参数。

28. **D15 ephemeral+preview overlay ESC = ContentView 兜底状态机（临时方案，2026-05-11 J ship 后 codex:rescue 落地）**：M2 Slice J 引入 EphemeralResultView 后，ZStack 同层并存 ephemeral + previewOverlay 各持私有 @FocusState 注定 race（SwiftUI 没有跨 view 的焦点仲裁者），ESC 路由不可靠（preview 抢不到焦点时 ephemeral 抢着关，跳层 baseGrid）。临时修法：所有 ESC 集中到 ContentView body 的 `.onKeyPress(.escape)` 兜底，按 modal layer 状态机顺序处理（QV > preview > ephemeral > baseGrid，每次只关一层），子 view 不持自己的 ESC handler。Why: 最小 scope 跑通 Slice J 验收，避免一次性重构 5 文件的 V1+V2 焦点 dance（codex:rescue 推荐 P1 单一枚举 @FocusState scheme，但 V1 既有 grid+preview+QV 焦点 dance 都要改，回归风险高）。How to apply: K 阶段做完整 P1 重构（ContentView 持 `enum AppFocus { case grid, preview, ephemeral }` + `@FocusState appFocus: AppFocus?`，所有 view 改共享 binding `.focused($appFocus, equals: .xxx)`，删 trigger UUID 模式），届时移除 ContentView 兜底 ESC 状态机，恢复子 view 各自持 onKeyPress(.escape)，焦点单点仲裁不再 race。
    - **2026-05-11 终态落地**：父持有 `@FocusState focusTarget: AppFocus?` enum (`grid` / `preview` / `ephemeral`) 重构完成。变更概览：(1) ContentView 加 `AppFocus` enum + 单 `@FocusState`，删 `gridFocusTrigger` / `previewFocusTrigger` / `ephemeralFocusTrigger` 三个 UUID `@State`；(2) ImageGridView / SmartFolderGridView / ImagePreviewView / EphemeralResultView 改用 `@FocusState.Binding var focusTarget: AppFocus?` 接收 binding，`.focused($focusTarget, equals: .xxx)` 申请焦点；子 view 删本地 `@FocusState isFocused` + `.onChange(of: trigger)`；(3) 子 view 各自持 `.onKeyPress(.escape)`（preview / ephemeral 自闭层）— preview 走 `dismissPreview()` (focusTarget=nil + onDismiss)，ephemeral 走 `onClose()`；(4) ContentView body 删兜底 ESC `.onKeyPress(.escape)` 状态机；(5) QV close 路由（`onChange(of: quickViewerIndex)`）把 `triggerXxx = UUID()` 全替换为 `focusTarget = .grid/.preview/.ephemeral`；(6) preview close 路由（`onChange(of: selectedImageIndex)` newValue==nil 分支）写 `focusTarget = currentEphemeral != nil ? .ephemeral : .grid`。QuickViewerOverlay 保留本地 `@FocusState`（overlay 与 detail ZStack 结构平行，无 race）。

### M3 决策（2026-05-11 brainstorming + plan-time 拍板）

29. **D16 M3 搜索 input = 顶部 Spotlight 式 overlay**：⌘F 触发顶部 slide-in overlay（detail 区顶端，max 600pt 居中），跟 EphemeralResultView 概念同源（D8 搜索 = ephemeral）；不挂 toolbar field、不弹 sheet modal。Why: (a) 跟 D8「搜索是 ephemeral」心智一致 — input / 结果 / 关闭 同一条退出路径；(b) toolbar field 在 QV 隐藏路径下失效需要 fallback overlay，复杂度叠加；(c) sheet 模态跟 D15 modal 层级再叠一层会重新触发焦点 race；(d) 用户在看图 app 内 ⌘F 心智更接近 Spotlight / 浏览器 ⌘F 而非 Mail / Finder。How to apply: SearchOverlayView 复用 D15 共享 `@FocusState focusTarget: AppFocus?` 加 `.search` case，layer 顺序 `QV > search > preview > ephemeral > baseGrid`，子 view 自持 ESC handler；后期加 history / saved searches 时再考虑升级 sheet 形态。

30. **D17 M3 搜索 modifier 解析 = Silent partial（不报错）**：`type:invalidext` / `size:abc` 等 modifier 解析失败时，把整个 token fallback 当 keyword LIKE 拼接，不在 UI 报错不阻挡查询。只解析 3 个 modifier：`type:` / `size:` / `birth:`。Why: (a) 实时查（200ms debounce）下错误提示会高频抖动 — 输 "type:p" 还没打完报错 → 烦人；(b) Silent fallback 容错最强，跟 Spotlight / GitHub / Slack search 同款行为；(c) 严格 spec 三个 modifier 已覆盖 v2-design § 6.1 全部举例 — power user 再要更多走 M4 自定义 SmartFolder。How to apply: SearchService.parse 返回 `(modifiers, keyword)` 永不抛错；解析失败的 token 自动进 keyword pool；UI 永不显示 parse error。如 type/size/birth 之外字段命名（如 `path:`）也按 unknown modifier 当 keyword fallback。

31. **D18 M3 搜索继承 SmartFolder hide 规则**：搜索 query predicate 强制带 `.hidden = false` atom（mirror 内置 SmartFolder 的 common_filters），hidden subfolder 中的图搜不到。Why: (a) D8 搜索 = ephemeral 智能视图，跟 SmartFolder 是同类聚合视图，hide 语义应一致；(b) 用户 hide 一个 folder 是显式表示"不想看到这里的图"，搜索"find anywhere"破坏该意图；(c) 实现零成本（复用既有 .hidden atom）。How to apply: SearchService.compile 出来的 SmartFolderPredicate 必带 `.hidden = false` + `.managed = true` + `.dedupCanonicalOrNull = true` 三个 common filter，跟 BuiltInSmartFolders.lastMonth / screenshots / largeImages 同款；future 如需 "include-hidden" 走 M4 自定义 SmartFolder 而非 modifier。

32. **D19 EphemeralResultView 加 `showTimeBuckets: Bool` toggle 解 spec 内部矛盾**：`v2-design § 6.1`（搜索按 birth_time 倒序 + 时间分段）vs `m2-design § 5`（找类似禁用时间分段，top-30 distance 排）的冲突由 EphemeralResultView 加可选时间分段参数解决。M3 search 传 true 走 sectioned LazyVGrid + pinned chip header（mirror SmartFolderGridView），M2 similar 维持 false 走 flat LazyVGrid。Why: (a) D8 已锁 EphemeralResultView 是搜索 + 类似图的统一组件，split 两个组件破坏 D8；(b) 时间分段对搜索（大结果集 + birth_time 排序）有意义，对类似图（top-30 distance 排序）无意义 — toggle 表达两种语义；(c) 同时加 `emptyStateText: String` 参数让 caller 控制空态文案（空 input / 0 结果 / 找类似无结果三种场景文案不同）。How to apply: EphemeralResultView API 加 `showTimeBuckets: Bool` 默认 false（保 M2 行为）+ `emptyStateText: String`；showTimeBuckets=true 时 internal 走 `groupedByTimeBucket()` helper + pinnedViews 渲染（已有 SmartFolderGridView 模式可借鉴）。

33. **D20 M3 SearchService = 新 `Glance/Search/` module（不扩 SmartFolderEngine）**：新增 `Glance/Search/` 目录含 `SearchService.swift` + `SearchInput.swift` + `SearchOverlayView.swift`；SearchService 只做 parser + 编译成 SmartFolderPredicate；最终 SQL 仍走 SmartFolderQueryBuilder + IndexStore.fetch 复用既有 query 路径。Why: (a) mirror M2 `Glance/Similarity/` module 边界 — search 是独立 feature 不污染 SmartFolderEngine；(b) SmartFolderEngine 当前职责仅 "已注册 SmartFolder 编译执行"，search 是 ephemeral 即时构造的 SmartFolder-shape 查询，语义不同；(c) 后期 M4 用户自定义 SmartFolder 编辑器复用 SearchService 的 parser（"保存搜索为 SmartFolder" → parser 输出 predicate 直接持久化）→ module 独立利于演化。How to apply: 新建 `Glance/Search/` 顶层，3 文件清单 fixed；SearchService.parse 输入 String → ParsedSearch struct（modifiers + keyword）；SearchService.compile(ParsedSearch) → SmartFolderPredicate；不需要新建 SearchQueryEngine（直接借 SmartFolderQueryBuilder + IndexStore.fetch）。

### M3 搜索筛选 chips 决策（2026-06-07 brainstorming + 两轮 codex review 收敛，Slice N）

完整设计见 `specs/v2/2026-06-07-m3-chips-design.md`（D21-D27），实施 plan 见 `specs/v2/2026-06-07-m3-chips-implementation-plan.md`（Slice N1/N2）。下面是 Roadmap 级索引（编号用 chips-design 原生 D 号，不接上方全局序号）。

- **D21 三组 chip = 类型/大小/时间**：⌘F overlay 输入框下加三组可视化 chip，类型多选（checkbox）/ 大小·时间单选。普通用户点选不用记 `type:png` 语法，power user 命令式照旧。
- **D22 独立筛选状态**：chip 选中态存独立值类型 `SearchFilterState`，与 keyword（输入框）分离、互不耦合；避免和 keyword 解析耦合。
- **D23 类型走现有 `.inSet` + 同源大写标签**：类型多选编译成单个 `.inSet` atom，标签取 `ImageMetadataReader.canonicalFormatLabels`（与 DB `formatLabel` 输出逐字符同源，含混合大小写「WebP」），SQL builder 零改。
- **D24 只预设档，精确值留命令式**：大小档 >1/5/10MB、时间档 今天/本周/本月/今年；精确值（`size:>3.5mb` / `birth:2024-01`）仍走命令式 modifier。
- **D25 布局 = 输入框 + chip 行 + 缩小命令式 hint**。
- **D26 chip + 命令式同维冲突都 AND 不消解**：chip 选 PNG + 输入 `type:jpeg` → 两个 format 条件 AND（结果可能空），不做智能消解（可预测 > 智能）。
- **D27 生命周期**：openSearch 重置 chip / closeSearch 清空 chip（进入即空白）。
- **合并出口**：`SearchService.compile(filterState:keyword:now:)` 单点合并 chip atoms + keyword 解析（全 AND，common filter 单点注入）；「今天」档因 `resolveRelativeTime` 无当日午夜 token，在 `SearchTimeBucket.startToken` 预计算本地午夜 ISO；`runSearch` early-exit 条件改「keyword 空 AND filterState 空」（chip-only 不被挡）。
- **codex 两轮 review 抓 15 点已折入**：design 7（formatLabel 同源 / 今天预计算 / chip-only early-exit / common filter 单点 / popover ESC 两段 / 状态生命周期 / 「零改」诚实改成 3 处辅助改）+ plan 8（TimeBucket→SearchTimeBucket 避编译冲突 / 两 enum 加 Hashable / searchInput 不 promote @Binding 避 close-loop / 前向引用消除 / canonicalFormatLabels 补 TIFF·BMP / chip-only Enter / popover .onExitCommand / DS.Spacing.xxs→xs）。

### M4 决策（2026-06-16 brainstorming + 四轮 codex review 收敛）

- **D33 撤销 UI 升级 banner overlay**：ContentView 级 banner，跨视图持久（V1 folder / 智能文件夹 / 搜索 / 重复清理总览均可见），快速看图器在场期间不可见但状态保留，QV 关闭后回归。默认不自动消失（30s 或纯手动 dismiss）。未动 D30 决策骨架（无确认框 + 可撤销路径）只升级 UI 形态。
- **D34 撤销回补 DB 走显式 contract，禁止依赖 FSEvents 时机**：首选 `IndexStore.restoreImageFromSnapshot(_:)` 新 API 同步返回 row id；降级 `FolderStoreIndexBridge.requestRescan(folderId:relativePath:) async throws -> Int64` 新 API 返回时 row 已恢复或明确失败禁 fire-and-forget。snapshot 走 `fetchSnapshotForRestore` 新 query SELECT 全列保真（IndexedImageSnapshot 值类型对齐 images 表 15 个非 PK 列）。
- **D35 总览不是快照，订阅 bridge 多播 observer fan-out**：bridge 一次性架构升级 `addIndexChangedObserver` / `removeIndexChangedObserver` 替代原单播 `var onIndexChanged`，4 个 fire 点（孤儿清扫 / dedup full pass / dedup group / FSEvents handleEvents）改 `fireIndexChanged()` 调 dict.values 遍历 fan-out。**任务 1 步骤 1 prerequisite**：ContentView.swift L584 smartFolder 唯一既有 caller 同步迁移到 `addIndexChangedObserver`，DuplicateOverviewModel 作为第二 observer 在步骤 3 注册。Why: 单播 var 后注册覆盖前注册必断 V2 smartFolder 流量；`@StateObject` 模型长寿不 deinit 无法用 capture-old-callback 链式调用绕开。debounce 500ms 后 load() 由 DuplicateOverviewModel.scheduleReload 自持。
- **任务拆分**：任务 1（只读总览，零删除，先建立信任）+ 任务 2（删除闭环，推迟到卷类型验证矩阵跑通后开放）。任务 1 内部 5 步骤实施：步骤 1 bridge 多播升级 / 步骤 2 SQL 聚合查询 + DS 常量 + DuplicateGroup record / 步骤 3 DuplicateOverviewModel 状态机 / 步骤 4 view + 侧边栏入口 + 五态互斥（V1 folder / 智能文件夹 / 临时结果 / 搜索 overlay / 重复清理总览）/ 步骤 5 /go 收尾。
- **codex 四轮 review 抓 13 点已折入**：第一轮 4 P1 + 4 P2 + 2 P3（D33/D34/D35 新增 + API reality 纠正 + 边界 wording）；第二轮 3 P1 + 6 P2 + 1 P3（API reality mismatch：upsertImage 不存在改 restoreImageFromSnapshot / IndexedImage 字段不全引入 IndexedImageSnapshot / progress 路径不合法改 onIndexChanged hook）；第三轮 2 P1 + 2 P2（ownership 拍板 → bridge multicast 升级 + snapshot 字段补齐到 15 列）；第四轮 3 P2 + 1 P3（design 收敛进 writing-plans）。plan 阶段又 13 点（2 P1 + 5 P2 + 2 P3 + 五态互斥补全 = 4 轮）。
- **D-M4-1 V1 read-only bookmark → V2 read-write 迁移走 A 方向（2026-06-17 codex review 第五轮 推荐）**：M4 任务 2 步骤 1 spike 跑跨 root sandbox trashItem 三轮失败 NSCocoaErrorDomain code=513。根因 V1 `BookmarkManager.saveBookmark` 用了 `.securityScopeAllowOnlyReadAccess` flag，bookmark 数据本身就是 read-only scope，即使 entitlement 切到 read-write、resolve 出来的 scope 仍只能读（Apple NSURL.h 实证）。codex 评估 A/A2/B 三方向后推荐 A：**改 saveBookmark 去 `.securityScopeAllowOnlyReadAccess` flag + UserDefaults `bookmarkSchemaVersion = 2` int key 哨兵 + M4 删除入口首次触发清旧 bookmark（A1.5 变体, 不在 app 首启全清）+ UI 引导重选所有根目录**。A2 不可行（无公开 API 检测 bookmark 是否 read-only）。B 双 bookmark slot 破坏 D30「一键」UX 弃。同步修「pbxproj vs Glance.entitlements 两份事实漂移」硬伤（codex 抓的）— entitlements 文件也切 read-write 跟 pbxproj 同源。**风险无延迟雷**（codex review 第五轮 Q7 实证）：旧 V1 bookmark 不会"几天后自动失效"，永远不会自动升级，必须重建。详见 `specs/v2/2026-06-10-m4-design.md` 4.5.4 段 + `specs/v2/2026-06-16-m4-task2-implementation-plan.md` 步骤 1.6 + 2.0.5。

### OpenWith 方向 2 决策（2026-06-03 brainstorming + 三轮 codex review 收敛）

完整设计见 `specs/2026-06-03-openwith-lightweight-viewer-design.md`（D-OW5~D-OW11 + "为什么没有 SwiftUI 原生捷径"），实施 plan + codex 折入记录见 `specs/2026-06-03-openwith-lightweight-viewer-plan.md`。下面是 Roadmap 级索引。

34. **D-OW5/6/7 外部打开 = Preview/Quick Look 式独立看图窗**：Finder「打开方式」/ Dock 拖放打开图 = 自建独立看图窗（`ExternalViewerWindowController`，mirror `AboutWindowController` 骨架），**不复用图库主窗**；纯看图（砍找类似/搜索/浏览所在文件夹，回滚 Slice 2 `84a1f5b` 浏览按钮）；冷启动 ESC = app 退出（看完即走），warm = 只关看图窗、图库留。Why: 旧模型（单 Window scene 复用主窗 + AppDelegate 消费 open）跟系统对着干 → warm 崩溃（`84a1f5b` 临时挡）+ 置顶顽疾（待修复段 backlog，5 种激活 API 真机全败）；自建独立窗顺系统、置顶可控、语义符合"快速看一张图"。

35. **D-OW8 撤销"shouldTerminate 恢复默认 true"，改分阶段**：只要 SwiftUI 主 `Window` scene 还在（Slice 1），恢复 `true` 会被单 Window scene open-document 瞬态 close 触发自杀（codex plan-review P1）。改为 Slice 1 保持 `=false`；退出语义由 `ViewerSession.terminateOnClose` + Slice 2 自持窗口计数控制。

36. **D-OW9/10 真实窗口创建权从 SwiftUI scene 收回 AppDelegate + 禁扫 `NSApp.windows`**：Preview 式冷启动需"按是否由文件启动决定首窗建谁"，SwiftUI 无原生捷径（`handlesExternalEvents`/`openWindow`/`DocumentGroup`/`defaultLaunchBehavior` 逐条排除）、事后 `.close()` 主窗不可靠。Slice 2 新增 `MainWindowController` 把图库主窗也收回自建（**否决"不可见占位 Window scene"**——仍是 scene 留幽灵主窗）；cold/warm 判断用自持 `MainWindowController` 状态，**不扫 `NSApp.windows`**（混入 About/看图窗/隐藏最小化窗/系统 panel，会误判）。

37. **D-OW11 + Slice 切分 + 实现债**：看图窗用 `ViewerSession` 解二次打开（`.id(session.id)` 重建 viewModel 显新图，旧 session 进 `retiredSessions` 关窗才统一 end 避竞态）+ 注入 `viewerAppState` 防崩 + 自任 `NSWindowDelegate` 避 delegate 被抢 + close path 无条件 reset `isFullScreen`。两片拆：**Slice 1**（warm 验置顶 + 清实现债，不碰 lifecycle）→ 真机验过 → **Slice 2**（收 lifecycle 拿冷启动看完即走 + 删旧 `ExternalOpenCoordinator` 等残留）。Why: 把方向 2 核心赌注（自建窗置顶 + QuickViewer 搬迁）压在 Slice 1 前置风险，GUI 行为开发机 Mac mini 验不了靠真机迭代。

38. **D-OW12~16 Slice2 lifecycle 接管（2026-06-04 实施 + 真机验过）**：移除 SwiftUI `Window` scene、图库主窗收回 AppDelegate 自建，根治 cold 双窗 + warm 关图主窗丢失（同根：Window scene 还在）。**D-OW12** 对象 ownership 从 GlanceApp `@StateObject` 迁 `@MainActor AppDelegate`（BookmarkManager/FolderStore/AppState/IndexStoreHolder 4 个）。**D-OW13** App body 只留 `Settings { EmptySettingsView() }` 挂 `.commands`（About 菜单）——真机验过菜单栏 + 关于一眼 + ⌘Q + ⌘, 全存活，Settings-only scene 方案成立（曾是 Slice2 最大风险，备选纯 AppKit NSMenu 未启用）。**D-OW14** cold/warm 用 AppDelegate 自持 `hasFinishedLaunching`/`launchedForFileOpen` 判断（禁扫 NSApp.windows），`terminateOnClose=!hasFinishedLaunching`。**D-OW15** `applicationShouldTerminateAfterLastWindowClosed=false`（关窗驻留像 Photos/Preview，真机后从原拟 `true` 修正；cold 看完即走由 viewer `terminateOnClose` 独立控制不受影响）。**D-OW16** 图库主窗 delegate 单一归属 `MainWindowController` 自任 + 移除 ContentView `WindowAccessor`（解 codex review P1-1 delegate 双持地雷——MainWindowController 与 WindowAccessor 争 NSWindow.delegate；mirror Slice1 ExternalViewerWindowController 已验证模式）。流程：两轮 codex plan review 收敛（第一轮抓 P1-1）+ subagent-driven 逐 task 实施 + Task4 后真机硬门控全过。详见 `specs/2026-06-04-openwith-slice2-plan.md`。

---

## V2 进度

### M1 - 跨文件夹聚合 MVP（4-5 周）

| Slice | 状态 | Ship as | 完成日期 | 关键 commit |
|---|---|---|---|---|
| **A** ⭐ thin cross-folder MVP | ✅ 完成 | V2.0-beta1 | 2026-05-08 | 见下方表格 |
| B 时间分段 sticky header（5 段 chip）+ "本周新增" SF + hover tooltip | ✅ 完成 | V2.0-beta2 | 2026-05-09 | 见下方 Slice B 表 |
| D hide toggle 右键菜单（root + 子目录 + 状态继承）+ Inspector source path | ✅ 完成 | V2.0-beta3 | 2026-05-09 | 见下方 Slice D 表 |
| G FSEvents 增量监听 + 删 root folder 清理 | ✅ 完成 | V2.0-beta4 | 2026-05-09 | 见下方 Slice G 表 |
| H 内容去重 SHA256 + cheap-first 粗筛 | ✅ 完成 | V2.0-beta5 | 2026-05-09 | 见下方 Slice H 表 |
| I 首次索引进度 UI + 错误处理 + SmartFolderStore enum-state 重构 | ✅ 完成 | V2.0 GA | 2026-05-09 | 见下方 Slice I 表 |

### Slice A 完成详细（19 task）

**完成 commit 列表**（按时序，对应 plan task 编号）：

| Task | Goal | Commit |
|---|---|---|
| A.1 | IndexDatabase sqlite3 thin wrapper | `01f2b4b` |
| A.2 | IndexStoreSchema v1 forward-looking | `d7ad2b0` |
| A.3 | IndexStore high-level entry + auto-migrate | `de802b7` |
| A.4 | ManagedFolder + folders 表 CRUD | `be9f9fe` |
| A.5 | IndexedImage + images 表 CRUD + CompiledSmartFolderQuery | `8a08327` |
| A.6 | ImageMetadataReader（URL → birth_time/size/format/dimensions）| `fb085ba` |
| A.7 | FolderScanner（递归扫描 + 写入 IndexStore）| `5ce3b2a` |
| A.8 | SmartFolder + Predicate/Atom/Op/Value structs | `c681e9a` |
| A.9 | SmartFolderQueryBuilder（Predicate → SQL）| `f47b2a1` |
| A.10 | SmartFolderEngine（compile + execute）| `c47ae25` |
| A.11 | BuiltInSmartFolders（"全部最近"）| `603383b` |
| A.12 | SmartFolderStore @MainActor + 项目级 nonisolated retrofit | `c6e600f` |
| **merge** | merge main → v2/dev（V1 bug fix 21 commits 拉进来）| `86b2a24` |
| - | verify.sh allow-list 加 SQLite3（macOS 系统 framework）| `1fc32d9` |
| - | M1 plan A.13/A.17 reality check 重跑（merge 后修订 V1 现状假设）| `c5d73a8` |
| A.13 | GlanceApp 注入 IndexStoreHolder | `b49feb7` |
| A.14 | FolderStoreIndexBridge（订阅 rootFolders + 注册 + scan）| `1600a99` |
| A.15 | SmartFolderListView（sidebar 智能文件夹 UI）| `536b0fe` |
| A.16 | SmartFolderGridView（cross-folder grid + V1 loadThumbnail 复用）| `6449552` |
| A.17 | ContentView 改造（sidebar VStack + V2 wire-up + EnvironmentObject 双注入）| `879078f` |
| A.17 P3 | codex review 修法（Preview env 注入 + stale query guard）| `557bb39` |
| A.18 P0 | insertImageIfAbsent SELECT-first（让 constraint violation 真实 surface 取代 OR IGNORE 静默吞）| `f83cc9b` |
| A.18 P0 | root bookmark 替代 per-child bookmark（macOS sandbox 不允许给 enumerator 子文件创建 .withSecurityScope bookmark）| `7ef8d81` |
| A.18 follow-up | V2 grid 加最小交互（单击预览 / 双击 QuickViewer）| `a9b3ac2` |
| A.18 follow-up | V2 grid 加 navigationTitle / highlight + v2Urls 替代 folderStore.images | `26c457a` |
| A.18 P0 | QV transition insertion 改 .identity 消除 baseGrid 暴露（codex:rescue 真根因 fix，前 2 次诊断错）| `553c0f6` |
| A.18 follow-up | V2 grid 加 keyboard 支持（mirror V1 ImageGridView：focus / arrow / space / F）| `9ea131e` |
| A.18 P1 | inspectorURL V2 mode 用 v2Urls 替代 folderStore.images（v2Urls 拆分后 Inspector 显空）| `2dd7c1b` |
| A.18 follow-up | V2 cell 视觉对齐 V1 ThumbnailCell（方形 + scaledToFill + hover scale + HiDPI）| `6da2689` |
| A.19 | Slice A 收尾 + Roadmap + PENDING + 完整 commit | （本次）|

### Slice A 关键技术决策（实施过程沉淀）

**1. P0 P0：bookmark sandbox 限制**
sandbox app 不允许给 enumerator 出来的子 URL 创建 `.withSecurityScope` bookmark（子 URL 仅通过 active 父 scope 隐式访问）。结果：FolderScanner 不能给每个 image 单独存 bookmark，全部 image row 共享所属 root 的 bookmark；读图时 resolve(rootBookmark) → startAccessing → root.appendingPathComponent(relative_path) 重建子 URL。`IndexedImage.urlBookmark` 字段语义从"image 自己的 bookmark"变成"image 所在 root 的 bookmark"，字段名 Slice I rename 候选。

**2. INSERT OR IGNORE 不能给 schema 用**
SQLite OR IGNORE 吞掉所有 constraint violation（NOT NULL / FK / CHECK / UNIQUE），不只是 UNIQUE 冲突。诊断错误时混淆"行不存在"vs"行被 IGNORE"。修法：SELECT-first → INSERT (no IGNORE) 让真实错误 surface + 错误消息加 record dump（folder_id / relative_path / filename / format / file_size / bookmark_size）。

**3. V1/V2 双源耦合 trade-off**
ImagePreviewView / QuickViewerOverlay / Inspector 在 V2 mode 用 ContentView 本地 `@State v2Urls`，V1 mode 用 `folderStore.images`，避开 V1 排序保护逻辑（onChange of images → 关 QV）误关 V2 QV。Slice I 重构候选：让这些 view 不直接依赖 folderStore.images，完全走显式参数。

**4. SwiftUI transition 时序导致视觉闪烁**
QuickViewer 用 `.transition(.opacity)` fade in 跟 preview 同时退场，中间时间窗口 baseGrid 透过两层半透明暴露。修法：QV insertion 改 `.identity`（即时出现）+ removal 保留 `.opacity`（fade out）。codex:rescue 独立 trace 发现的根因，前 2 次自诊断走偏教训：bug 修 ≥2 次必须 codex:rescue review。

**5. V2 grid 视觉/交互完整 mirror V1 ImageGridView**
A.18 实测发现 plan A.16 把 V2 cell 标"无交互"导致用户测不下去，且 V2 cell aspectRatio.fit + 矩形不规则视觉割裂感强。修法：单击/双击 + navigationTitle + highlight + keyboard + scaledToFill 方形 + hover scale + HiDPI 像素，全部 mirror V1 ThumbnailCell pattern；共享 `folderStore.thumbnailSize` 让 V1 toolbar slider 同步控制 V2 cell 大小。

### Slice A 累积模型（V2.0-beta1 deliverables）

- 1 个内置 SmartFolder："全部最近"（rule：managed=true AND hidden=false AND dedupCanonicalOrNull=true，order: birth_time desc）
- 1 个 cross-folder grid view（SmartFolderGridView）+ 1 个 sidebar UI（SmartFolderListView）
- IndexStore 持久化：~/Library/Containers/com.sunhongjun.glance/Data/Library/Application Support/Glance/index.sqlite
- folders 表 + images 表（v1 schema 含 M1+M2+M3 forward-looking 字段）+ 5 个 index
- FolderScanner 单次递归扫描（无 FSEvents 增量，Slice G 才上）
- V1/V2 selection 互斥 + V2 keyboard 完整支持 + Inspector 共享路径
- **不含**：时间分段 sticky header（B）/ hide toggle 菜单（D）/ FSEvents（G）/ dedup（H）/ 进度 UI（I）

### Slice B 进度（合并 B + C + E，ship → V2.0-beta2）

| Sub | Goal | 状态 | Commit |
|---|---|---|---|
| B-α | TimeBucket（5 段算法）+ SmartFolderGridView LazyVGrid sectioned + sticky pinnedViews + chip section header（Capsule + thickMaterial + strokeBorder） | ✅ 完成 | `25d6a94`（主体）；4 轮 follow-up：`60a2de2` 黑横条 / `bd4cfa7` ↑↓+hit-test+P1 / `c5b048a` chip 形态破横条 / `ef08f72` chip 对比强化 + DS.SectionHeader |
| B-β | BuiltInSmartFolders 加 thisWeekAdded（规则：managed AND !hidden AND dedupCanonical AND birth_time BETWEEN_DURATION ['-7d','now']）+ sidebar 自动出现 | ✅ 完成 | `7e2893a` |
| B-γ | /go 五步收尾 + Roadmap ✅ + tag V2.0-beta2 | ✅ 完成 | `cf43e04` |

### Slice D 进度（合并 D + F，ship → V2.0-beta3）

| Sub | Goal | 状态 | Commit |
|---|---|---|---|
| D.1 | hide toggle 端到端：IndexStore CRUD（setRootHidden / upsertSubfolderHide / effectiveHidden / folderIdForRootPath）+ SmartFolderQueryBuilder `.hidden` walk SQL（path-length DESC 取最具体 explicit）+ FolderSidebarView contextMenu（root + 子目录两层动态 label）+ ContentView 桥（V1 URL → IndexStore 坐标） | ✅ 完成 | `a39a6c5`（主体）+ `4f318b5`（P1+P2 fix：ON CONFLICT WHERE 子句 + 嵌套 root 最长前缀 + Roadmap 当前进度同步）+ `6d8d234`（Bug Fix 段同步） |
| D.2 | Inspector 来源 path 段 + Show in Finder 按钮 | ✅ 完成 | `a576198`（主体）+ `e073001`（Inspector.md spec 同步） |
| D.3 | /go 五步 + Roadmap ✅ + tag V2.0-beta3 | ✅ 完成 | `94eb6fb` |

### Slice G 进度（FSEvents 增量监听 + 删 root 清理，ship → V2.0-beta4）

| Sub | Goal | 状态 | Commit |
|---|---|---|---|
| G.1 | 删 root 清理：IndexStore.deleteRoot（FK CASCADE 连删 images + subfolder hide rows）+ FolderStoreIndexBridge.sync 加 remove diff | ✅ 完成 | `8df97af`（主体）+ `a478f29`（P1 fix） |
| G.2 | FSEventsWatcher Swift wrapper（CoreServices FSEventStreamCreate）+ 每 root 一个 stream lifecycle + ItemCreated → insertImageIfAbsent | ✅ 完成 | `8df97af`（主体）+ `a478f29`（P1 fix 拆 FSEvent.swift） |
| G.3 | FSEvents Removed → deleteImage / Modified → updateImageMetadata / Renamed → 按 file exists 拆 delete + insert | ✅ 完成 | `8df97af`（主体） |
| G.4 | /go 五步 + Roadmap ✅ + tag V2.0-beta4 | ✅ 完成 | `8df97af` + `a478f29`（P1 fix policy 违反） |

### Slice H 进度（内容去重 SHA256 + cheap-first 粗筛，ship → V2.0-beta5）

| Sub | Goal | 状态 | Commit |
|---|---|---|---|
| H.1 | SHA256 计算 + dedup pass 后端：ContentHasher.swift / DedupPass.swift（runFullPass + reEvaluateGroup + orphan cleanup）/ IndexStore CRUD（setContentSHA256/setDedupCanonical/resetSHA256AndCanonical/promoteOrphanDuplicates/fetchCandidateGroups/fetchImagesInGroup/fetchImageGroupKey/fetchImageIdByPath/fetchDuplicates/fetchDuplicatesByFullPath）+ FolderStoreIndexBridge handle hooks（registerAndScan/handleCreated/handleModified/handleRemoved/unregister 五处） | ✅ 完成 | `80806d4`（主体）+ `870cf80`（codex P1 误判 doc-only 跳 review） |
| H.2 | Inspector 副本段：ImageInspectorView 加 duplicatesProvider closure + 副本 Section 条件展示（fullPath truncation .middle + Show in Finder per row）+ ContentView 注入 IndexStore.fetchDuplicatesByFullPath | ✅ 完成 | `80806d4`（主体） |
| H.3 | /go 五步 + Roadmap ✅ + tag V2.0-beta5 | ✅ 完成 | `80806d4` + `870cf80`（codex P1 误判 doc-only 跳过 review） |

### Slice I 进度（首次索引进度 UI + 错误处理 + enum-state 重构，ship → V2.0 GA）

| Sub | Goal | 状态 | Commit |
|---|---|---|---|
| I.1 | 首次索引进度 chip：IndexingProgress + IndexingProgressView（Capsule + thickMaterial mirror Slice B chip 风格）+ IndexStoreHolder.progress @Published + bridge.onScanProgress 回调 + ContentView mainContent ZStack 顶层挂 | ✅ 完成 | `2ce04b0`（主体）+ `6284a13`（P1 fix DS tokens） |
| I.2 | 错误处理 + 取消 + 进度持久化：schema migration v2 加 folders.last_processed_path 字段 + IndexStore 3 method (set/clear/fetchLastProcessedPath) + FolderScanner Task.isCancelled 检测 + resume from cursor (字典序 skip) + 每 100 张写 cursor + bridge currentScanTask cancel + onScanError 回调 + IndexStoreHolder.lastError + ContentView 红色 banner overlay + chip X 按钮 | ✅ 完成 | `2ce04b0`（主体）+ `6284a13`（P1 fix DS tokens） |
| I.3 | SmartFolderStore enum-state 重构：4 态 .idle/.loading/.loaded/.error 替代 selected/queryResult/isQuerying/lastError 四独立 @Published；computed accessors 兼容旧 view 调用；stale-write guard 走 state pattern match | ✅ 完成 | `2ce04b0`（主体） |
| I.4 | /go 五步 + Roadmap ✅ + tag v2.0（最终 GA） | ✅ 完成 | `2ce04b0`（主体）+ `6284a13`（P1 fix） |

**Slice I 关键决策**（4 项 plan-time 拍板）：
- 进度条形态：左上角浮动 chip（mirror Slice B chip 风格）
- 持久化粒度：每 100 张 indexed 写一次 last_processed_path（折中 SQLite IO + resume 跨度）
- enum state 命名：4 态 `.idle/.loading/.loaded/.error`（不引入 `.empty`，视为 loaded with empty list）
- 取消 vs 暂停：M1 仅 cancel 中断（粗暴 + 重启 resume），不实现 pause/resume 细粒度

**Slice H 关键决策**（4 项 plan-time 拍板）：
- SHA256 计算时机：root 扫完跑一次 dedup full pass + FSEvents 增量加图时单张实时算（cheap-first：仅 candidate group 算 SHA256）
- canonical tie-breaker：earliest birth_time + 最小 id
- modify 后 SHA256 invalidation：reset content_sha256 + dedup_canonical 到 NULL，trigger reEvaluateGroup
- rename 行为：delete old + insert new（沿用 Slice G 行为，Slice H SHA256 后副本检测自动 link）

**Slice H 性能边界**：
- 仅对 (file_size, format) 撞的 candidate row 算 SHA256，**不全量算所有图**
- 1 万张图典型 candidate ~5-10%，SHA256 总耗时 SSD M1 ~5-10s（Task.detached utility 跑后台不阻塞 grid）

**Slice G 关键决策**（4 项 plan-time 拍板，全 OK）：
- FSEvents stream lifecycle：每 root 一个 stream（删 root 单独 invalidate）
- callback 线程模型：watcherQueue 派发 → Task @MainActor → IndexStore serial queue → onIndexChanged → SmartFolderStore.refreshSelected
- modify 处理粒度：仅 metadata UPDATE（content_sha256 / dedup_canonical 是 Slice H 字段保留 NULL）
- rename 行为：delete old + insert new（不追踪 inode dedup，Slice H SHA256 后副本检测自动 link）

**Slice D 关键决策**（4 项细节执行时拍板，全 OK）：
- 稀疏 explicit 模型：folders 表只对显式设过 hide 的目录存 row（root 行 register 时已存）；未 explicit 的目录读 default 0
- toggle 二态语义：toggle hide/unhide 切换，row 始终保留；无第三态"重置为继承"
- subfolder lazy insert：首次右键子目录 toggle → IndexStore upsertSubfolderHide 写入新 row（ON CONFLICT update）
- menu label 动态文案：当前 effective hidden → "在智能文件夹中显示" / 否则 "在智能文件夹中隐藏"

**Slice B-α 关键决策**（执行时拍板，全 A）：
- bucket 归属计算：客户端单遍 group（O(n)，queryResult 已 birth DESC）
- sticky 实现：`LazyVGrid(pinnedViews: [.sectionHeaders])` 原生
- 空段处理：完全隐藏（today/yesterday/thisWeek/thisMonth/earlier 动态 0-5 段）
- 跨 bucket 键盘导航：保留 colCount-based flat queryResult 算法不动（视觉分组不影响 ↑↓ 步长）
- "本周新增"边界：`-7d/now` 滑窗（spec 已定，与 D4 自然周"本周"段双轨语义清晰）

### M2 - 类似图查找（3 周）

| Slice | 状态 | Ship as | 完成日期 | 关键 commit |
|---|---|---|---|---|
| **J** ⭐ thin similarity MVP | ✅ 完成 | V2.1-beta1 | 2026-05-11 | 见下方表格 |
| **K** Vision revision 迁移 + 重试 polish + 文案 | ✅ 完成 | V2.1 GA | 2026-05-11 | 见下方表格 |

### Slice J 完成详细（11 task）

| Task | Goal | Commit |
|---|---|---|
| J.1 | SimilarityService（Vision wrapper）| `af635d6` |
| J.2 | IndexStore 5 fp CRUD method | `4dad954` |
| J.3 | FeaturePrintIndexer pipeline | `c92ab4b` |
| J.4 | IndexStoreHolder fp progress hook | `ca2191d` |
| J.5 | ContentView wireIfReady 启动 indexer | `63aa9d7` |
| J.6 | FolderStoreIndexBridge handleCreated enqueue | `74d84e3` |
| J.7 | FeaturePrintProgressView + DS.Similarity tokens | `7eb2c01` |
| J.8 | EphemeralResultView | `2dd9b41` |
| J.9 | QV toolbar 找类似按钮 | `12d07e2` |
| J.10 | ContentView ephemeral state + 端到端 | `554a9ff` |
| J.11 | /go 收尾 + tag V2.1-beta1 | （本次）|

### Slice K 完成详细（3 task + 1 deferred）

| Task | Goal | Commit |
|---|---|---|
| K.1 | Vision revision 迁移：SimilarityService.currentRevision + IndexStore.resetFeaturePrintsWithStaleRevision + ContentView.wireIfReady 启动期对比 reset；reset >0 → info banner "Vision 模型已更新，正在重新索引 X 张图片" | （本次）|
| K.2 | 失败重试 polish：FeaturePrintIndexer.runLoop 加 in-memory `retryCounts: [Int64: Int]`，`extractFailed` < `DS.Similarity.extractRetryThreshold (3)` 不标 unsupported 让下批自然重试；threshold 通过参数传入绕 MainActor 隔离；`unsupportedFormat` / `archiveFailed` 仍立即永久标 | （本次）|
| K.3 | 错误 banner 文案润色：3 处 `feature print 索引...` → `类似图特征索引...`（用户面向 中文 术语，跟 V2 UI / 类似图按钮文案对齐）| （本次）|
| K.4 | 性能验收（10k 图大库 indexing time < 20min / query response < 500ms）| 🚧 deferred 等用户大库测试 |

### M3 - 搜索 + 新内置 SF（3-4 周）

| Slice | 状态 | Ship as | 完成日期 | 关键 commit |
|---|---|---|---|---|
| **L** 三个新内置 SmartFolder（上个月 / 截图 / 大图）| ✅ 完成 | V2.2-beta1 | 2026-05-11 | 见下方表格 |
| **M** ⌘F 全局搜索（filename/path LIKE + modifier parser）| ✅ 完成 | V2.2 GA | 2026-05-11 | 见下方表格 |
| **N** 搜索筛选 chips（类型/大小/时间三组可视化 chip）| ✅ 完成（待真机验）| V2.2 GA | 2026-06-07 | 见下方表格 |

### Slice L 完成详细（2 task）

| Task | Goal | Commit |
|---|---|---|
| L.1 | SmartFolderQueryBuilder.resolveRelativeTime 加 `last-month-start` / `last-month-end` token：Calendar.current 算自然月边界（dateInterval(of: .month) + dateByAdding -1 month），timezone 跟 D4 同源 device local；跨年自动处理（1 月 → 上年 12 月）| （本次）|
| L.2 | BuiltInSmartFolders 加 3 个 static SmartFolder：上个月（birth_time BETWEEN last-month-start/end）/ 截图（filename CONTAINS "Screenshot" OR "截图"，spec 的 path STARTS_WITH "~/Desktop" 分支不上 — IndexStore 存 relative_path 跨 root 无法判绝对路径，加 absolute_path 列跟收益不平衡）/ 大图（file_size > 5MB OR (width > 4000 AND height > 4000)，OR 内嵌 AND 是 D6 平铺）；阈值常量 (5_000_000 / 4000 / "Screenshot" / "截图") 命名在 BuiltInSmartFolders 内（domain 语义不入 DS）；`all` 数组扩展 5 项 sidebar 顺序：全部最近 / 本周新增 / 上个月 / 截图 / 大图 | （本次）|

### Slice M 完成详细（6 task）

| Task | Goal | Commit |
|---|---|---|
| M.1 | SearchInput + SearchService（parser + compile）| `1873e43` + `0b2d50a` (P1 fix size overflow + birth DST) |
| M.2 | SearchService inline 8 case 自检通过 | `e0b9912` |
| M.3 | SearchOverlayView + DS.Search tokens + AppFocus.search case 占位 | `0bfb1e7` |
| M.4 | EphemeralResultView 加 showTimeBuckets + emptyStateText + datesForBuckets API；sectioned 渲染 helper（M2 .similar 路径行为不变）| `90ffe6c` |
| M.5 | ContentView ⌘F search 集成（EphemeralRequest.search + searchTask debounce/cancel + QV 同帧切换）| `d315c78` |
| M.6 | /go 收尾 + tag v2.2 | （本次）|
| M.7 | 真机验发现 2 交互 bug 修复（codex review 收敛）：⌘F 焦点不落 input（焦点竞争 → `autoFocusOnAppear` gate + `Task.yield` 延迟单点设焦点）+ 回车无反应（改语义=收 overlay 进结果网格浏览，回车/空格开图，`defaultHighlightFirst` 双 onChange 兜底高亮）| （本次）|

### Slice N 完成详细（搜索筛选 chips，7 task）

> design `specs/v2/2026-06-07-m3-chips-design.md`（D21-D27）+ plan `specs/v2/2026-06-07-m3-chips-implementation-plan.md`（N1/N2，两轮 codex review 折入）。subagent-driven 实施，一 task 一 commit，每 task verify.sh 编译把关（0 error 0 warning）。

| Task | Goal | Commit |
|---|---|---|
| N1.1 | `ImageMetadataReader.formatLabel` 公开化（private→internal）+ `canonicalFormatLabels`（chip 类型选项唯一权威，与 formatLabel 输出逐字符同源大写标签，含 WebP/TIFF/BMP）| `928f620` |
| N1.2 | `SearchFilterState` 值类型 + `SearchSizeBucket`/`SearchTimeBucket` enum（避开 FolderBrowser/TimeBucket 命名冲突）+ `toAtoms`（类型 inSet / 大小 > / 时间 between；今天=本地午夜预计算 ISO）+ `_debugSelfCheck` | `e98d1a9` |
| N1.3 | `SearchService.compile(filterState:keyword:now:)` 单一出口合并 chip atoms + keyword 解析（全 AND，common filter 单点注入避叠加）+ 扩 `_debugSelfCheck` 验 chip-only/chip+keyword/命令式共存 | `929283a` |
| N1.4 | `ContentView.runSearch` 改签名 keyword+filterState + chip-only early-exit（双空 guard）+ 一致快照（snapKeyword/snapFilter/snapNow 防 debounce 期 chip tap race）+ open/closeSearch D27 生命周期 | `b3ccabf` |
| N2.1 | `DS.Search.chip*` 常量（chipSpacing/cornerRadius/H·VPadding/selectedOpacity/popoverMinWidth）| `72f31c9` |
| N2.2 | `SearchChipBar` UI — 三组 chip + 原生 `.popover`（类型 checkbox 多选 / 大小·时间单选 largecircle）+ 每 popover `.onExitCommand` ESC 两段不冒泡 | `6e6e82c` |
| N2.3 | chip bar 接入 SearchOverlayView（`@Binding filterState` + onChipChange，插在 inputRow/hintRow 间）+ ContentView 调用点即时查（skipDebounce）；searchInput 保持 local @State 避 closeSearch close-loop | `482c773` |

