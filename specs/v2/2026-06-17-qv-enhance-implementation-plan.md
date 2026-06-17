# Glance V2 快速看图器增强 implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan 任务-by-任务. Steps use checkbox (`- [ ]`) syntax for tracking.

> **design 反链**: [`specs/v2/2026-06-12-qv-enhance-design.md`](2026-06-12-qv-enhance-design.md)(29281 bytes, 2026-06-12 brainstorming 阶段)
> **状态**: plan draft 待 codex review → 军哥拍板 → 实施
> **术语**: 见 `CONTEXT.md`「术语字典」D 段(独立子系统不塞 M 序号, 用「任务 A/B/C」)
> **配对**: 本 plan 落 `specs/v2/2026-06-17-qv-enhance-implementation-plan.md`

---

**Goal:** 把快速看图器(QuickViewer)从「纯欣赏」升级成「去重决策工作台」: 临时旋转/翻转 + 决策信息上屏 + 一键复制/Finder + 右键 contextMenu + 一键移废纸篓。

**Architecture:** SwiftUI 渲染层(`.rotationEffect`/`.scaleEffect`)处理旋转视觉, ViewModel 持临时旋转状态(关窗即丢, 切图重置, 不写 EXIF 不改文件); 删除复用 M4 已 ship 的 `TrashService`(走单张适配层封装 URL→TrashInput→TrashOutcome 路径); 全部新操作走 `.onKeyPress` 快捷键 + 右键 contextMenu(零新增可见按钮)。

**Tech Stack:** SwiftUI(macOS 14+) / AppKit(NSPasteboard/NSWorkspace) / 复用 `ImageMetadataReader`(IndexStore) + `TrashService`(M4) + `MainQuickViewerWindowController`(独立 NSWindow 单例)

**最小真实改动集**(codex P2 收口):
- 必改 QuickViewer 4 文件: `QuickViewerViewModel.swift` / `QuickViewerOverlay.swift` / `MainQuickViewerWindowController.swift` / 新建 `QuickViewerTrashCoordinator.swift`
- 必改 `DesignSystem.swift`(常量)
- 必改 `ContentView.swift`(wire onTrash/onUndoTrash + schema gate 注入 BookmarkManager)
- 可选 `IndexedImage.swift`(若现 `fetchSnapshotForRestore(folderId:relativePath:)` 不支持按 fullPath, 加新 entry)
- **注**: `ExternalViewerWindowController.swift:73` 也直接构造 `QuickViewerOverlay`(OpenWith 路径), 任务 C 新参数 `onTrash`/`onUndoTrash` 设默认值 `= nil` → OpenWith 路径继承"不可删除"语义不接 trash 入口(codex P1 收, 详见任务 C.5/C.6/C.9)

---

## 任务全表

| 任务 | 一句话 | 文件触及数 | 估时 | 依赖 | 用户独立感知 |
|---|---|---|---|---|---|
| **任务 A** | 临时旋转 L/R + 翻转 H/V + 信息上屏角落小字 | 4(VM + Overlay + ZoomScrollView 复核 + DS) | 1-2 天 | 无 | 按 L 图转 90° + 角落显「4000×3000 · 2.5MB」 |
| **任务 B** | 复制图片 + 复制路径 + Finder 显示 + 右键 contextMenu | 3(Overlay + DS + 复制/Finder helper) | 0.5-1 天 | A.6 + B.4 合并改 .onKeyPress("r") → A 先 ship | 右键弹菜单 + ⌘C/⌘⌥C/⌘⇧R 真生效 |
| **任务 C** | Delete/⌘⌫ 移废纸篓 + 单张撤销 toast + working-copy 数组维护 | 5(Coordinator + VM 改 mutable + Overlay + MainQVController + ContentView wire) | 2-3 天 | M4 `TrashService` 已 ship `78b856e` + 任务 A+B | 按 Delete 图进废纸篓 + 自动下一张 + toast「已移废纸篓」(撤销:文件恢复, 列表稍后刷新) |

**总估时**: 4-6 天。**实施顺序硬约束(codex P1 改)**: **A → B → C 严格串行**, 不并行。理由: 任务 A 和 B 都改 `QuickViewerOverlay.swift` 且 A.6/B.4 都触 `.onKeyPress("r")`(裸 R 旋转 / ⌘⇧R Finder 显示), 并行 subagent 会 merge 冲突 + 两步改同一行。

---

## 总体时序

```
任务 A (旋转/翻转 + 信息) → 任务 B (复制/Finder + 右键) → 任务 C (删除闭环)
```

- A 必须先 ship: A.6 加 `.onKeyPress("r")` 裸 R 触发 rotateRight; 任务 B 的 B.4 需要把同一 `.onKeyPress("r")` 改成分支(裸 R 旋转 + ⌘⇧R Finder 显示), 必须在 A 已 ship 的基础上修改
- 任务 C 必须等 B ship: 右键 contextMenu(B.5)要加「移到废纸篓」项(C.10); 信息上屏(A) 帮用户决策删不删
- M4 `TrashService` 已 ship(commit `78b856e`), 不阻塞任务 C 启动

---

## 风险与对策

### 设计层风险(design 第 13 节)

| ID | 风险 | 对策 | 触发任务 |
|---|---|---|---|
| **R-rotate-anchor** | 旋转 90° 后滚轮缩放锚点是否仍视觉跟手 | 任务 A 实施期真机实测; 若偏移 → 对 anchor 做旋转逆变换(列 PENDING) | A |
| **R-rotate-zoom** | custom zoom 状态下旋转 offset 重映射 | 任务 A 选方案 (a): 旋转时若 `zoomMode == .custom` 重置回 fit; (b) backlog | A |
| **R-images-mutation** | 快速看图器删除后跟 grid 数据不一致(caller 不知道) | 任务 C 选方案 (a) 接受短暂不一致(FSEvents 最终一致 mirror M4 重复清理); 通过 `onIndexChange` 类回调通知 ContentView 可选 backlog | C |
| **R-cmdI** | ⌘I 语义未定 | 任务 A 选方案 (c) 不做 ⌘I, 信息常显跟随 controlsVisible 即够 | A |
| **R-flip-keys** | 翻转是否给快捷键 | 任务 B 选**不给**(避免键位膨胀), 仅右键菜单 | B |
| **R-trashservice-dep** | 删除依赖 M4 TrashService 时序 | **已消解**: M4 任务 2 `78b856e` 已 ship TrashService, 任务 C 可直接接 | C |
| **R-rotate-render-order** | `.rotationEffect` + `.scaleEffect(-1)` 翻转的应用次序 | 任务 A 实测固化: 先 `.rotationEffect` 再 `.scaleEffect` (绕中心转后再镜像); 如果视觉错位反过来试 | A |

### plan 时新发现风险

| ID | 风险 | 对策 | 触发任务 |
|---|---|---|---|
| **R-trash-adapter** | `TrashService.trashItems([TrashInput])` 不收 URL, 需要 URL→folder_id+relative_path 反查 + `fetchSnapshotForRestore` 拿 IndexedImageSnapshot + 构造 `TrashInput`(带 `GroupKey`)。 | 任务 C 新建「单张删除适配层」`QuickViewerTrashCoordinator`(URL → reverse lookup IndexStore → 构造 `GroupKey(fileSize:format:)` 对齐 `TrashOutcome.swift:42` 真实定义, **codex P0 收**); 不接 IndexStore 的 V1 老 bookmark 图不能删(走 schema gate 拦截, 详 C.12) | C |
| **R-images-let** | VM `images: [URL]` 是 `let`(QuickViewerViewModel.swift:18), 不可变。`prefetchCache/prefetchTasks/导航 canGoBack/canGoForward` 全部基于固定数组语义 | 任务 C 改 `let images: [URL]` → `private(set) var images: [URL]` + 新增 `removeCurrent()` 方法 + 调整 `currentIndex` + **codex P0**: prefetch cache 用 `Int` idx 当 key, 删一张后 `> currentIndex` 的 key 全错位 → 选「全清重建」`clearPrefetchCache()` 而非单 key remove + 重 `loadCurrentImage`; 同步审视所有读 `images.count`/`images.indices` 的点(grep 全文件) | C |
| **R-onkey-modifier-flags** | 现有 `.onKeyPress` ⌘=/⌘- 检查 `NSEvent.modifierFlags.contains(.command)`(Overlay :162/170/174) 是全局 NSEvent.modifierFlags 而非 event.modifiers; 但 ⌘F 用了 event.modifiers(:180)。新 ⌘C/⌘⌥C/⌘⇧R/⌘⌫ 用哪种? | 任务 B/C 统一用 `event.modifiers`(mirror :180 现代写法), 与 ⌘=/- 不同源(那段是历史遗留待统一, 不在本 plan 范围) | B + C |
| **R-pasteboard-image-fidelity** | NSPasteboard 复制 NSImage 时各 paste target 行为(Finder paste / Slack paste / Notes paste)对 PNG/JPG/HEIC 不同格式的还原可能不一致 | 任务 B 用 `NSPasteboard.general.writeObjects([nsImage])` 简单路径; 复杂 fidelity 列 backlog | B |
| **R-finder-reveal-not-exist** | 文件已外部删除时 `NSWorkspace.activateFileViewerSelecting` 会弹 Finder 空窗 | 任务 B 调前 `FileManager.fileExists` 预检, 失败显 toast(用任务 C 的 toast 槽; 若 C 未 ship 则简单 print + helpDialog; 真实顺序 A+B 先 ship 时此场景概率极低可暂忽略) | B |
| **R-trash-outcome-timing**(codex P0) | 计划原 C.6 先 `removeCurrent()` 再 await `onTrash`, 但 `TrashService.trashItems` 是 best-effort 可能 failure/cancelled, 失败也跳下一张 UX 完全反转 | C.6 改: 先 `await onTrash(url) -> TrashOutcome?` 拿 outcome, 仅 `outcome?.successCount == 1` 才 `removeCurrent()`; 失败保留当前图 + 显失败 toast(toast 槽 C.7 配套) | C |
| **R-trash-no-reEvaluate**(codex P0) | trash/restore 成功后没触发 `DedupPass.reEvaluateGroup + promoteOrphanDuplicates`, 重复组状态漂移; M4 `DuplicateOverviewModel.swift:257/334` 已有现成模式 | C.2 `QuickViewerTrashCoordinator.trash`/`restore` 成功路径 mirror `DuplicateOverviewModel` 调 `DedupPass.reEvaluateGroup(store:fileSize:format:) + promoteOrphanDuplicates()`, 再 `bridge.triggerIndexChanged()` 让总览刷新 | C |
| **R-fullpath-prefix-match**(codex P0) | 计划原 C.3 「找出 root 包含此 path 的 folder_id」前缀匹配会把 `/a/b` 和 `/a/b2` 都命中误伤 | C.3 改: 新增 `fetchSnapshotForRestore(byFullPath:)` 用项目已有精确匹配范式 `JOIN folders + f.root_path \|\| '/' \|\| i.relative_path = ?`(mirror `IndexedImage.swift:412/582`), 不做字符串前缀推断 | C |
| **R-schema-gate-injection**(codex P0) | 计划原 C.12 想在 `QuickViewerOverlay` 查 `bookmarkManager.currentSchemaVersion`, 但 QV 独立窗口只注入 `viewerAppState`(MainQuickViewerWindowController.swift:134), 没有 `BookmarkManager`, 拿不到 | C.12 下沉 schema gate 到 `QuickViewerTrashCoordinator.trash` 入口前(Coordinator 已 attach BookmarkManager); Overlay 仅触发 onTrash callback 不做 schema 判, schema 不通过 Coordinator 返回 `nil + 失败原因 enum`, Overlay 据此显失败 toast | C |
| **R-external-viewer-callsite**(codex P1) | `QuickViewerOverlay` 有另一个直接构造点在 `ExternalViewerWindowController.swift:73`(OpenWith 路径), C.6/C.8/C.9 加 `onTrash`/`onUndoTrash` 没考虑这里 | C.5/C.6/C.9 新参数设默认值 `= nil`; OpenWith 路径继承"不可删除"语义(看图器单 session 场景不挂主索引, 删除入口不放); plan 头部「最小真实改动集」段已明示 | C |
| **R-undo-restore-fidelity**(codex P1) | plan 原文「toast 撤销回原位」与 C.8 「不回补 VM.images, 靠 FSEvents 最终一致」矛盾 | 选「文件恢复, 列表稍后刷新」语义(mirror M4 全局 banner): toast 文案改成「已恢复 (列表稍后刷新)」, 不在 QV 内立刻 reinsert; 跟 M4 撤销行为对齐避免两个系统漂移 | C |

---

## 任务 A: 旋转/翻转 + 信息上屏

**用户独立感知兑现**: 用户独立完成后能在快速看图器内按 **L/R** 把图转 90°、按右键菜单选「水平翻转/垂直翻转」摆正; 角落自动显「4000×3000 · 2.5MB」帮判断留大删小; 关窗即还原不写文件。

### Files
- **Modify**: `Glance/QuickViewer/QuickViewerViewModel.swift`(加旋转/翻转状态 + helper + 切图重置)
- **Modify**: `Glance/QuickViewer/QuickViewerOverlay.swift`(加 .onKeyPress L/R + imageLayer rotationEffect/scaleEffect + 信息角落 overlay)
- **Modify**: `Glance/DesignSystem.swift`(加 DS.Icon.rotateLeft/Right/flipH/flipV + DS.Viewer.rotationStepDegrees/infoBadge*)
- **Read-only 复核**: `Glance/QuickViewer/ZoomScrollView.swift`(NSView 坐标系, 预期不改)

### 不改范围
- `bottomToolbar` 一行不动(D33 零新增可见按钮)
- `images: [URL]` 仍 `let`(任务 C 才改可变)
- `TrashService` 不接(任务 C)
- `MainQuickViewerWindowController.show` 不加新 callback(任务 A 全部在 Overlay 内部, 不需外部能力注入)

### 步骤

- [ ] **A.1 加 DS 常量**(`DesignSystem.swift`): `DS.Icon.rotateLeft = "rotate.left"` / `rotateRight = "rotate.right"` / `flipHorizontal = "arrow.left.and.right.righttriangle.left.righttriangle.right"` / `flipVertical = "arrow.up.and.down.righttriangle.up.righttriangle.down"` + `DS.Viewer.rotationStepDegrees = 90` + `DS.Viewer.infoBadgeOpacity = 0.35`(mirror topBar 气泡 :255) + `DS.Viewer.infoBadgeCornerRadius`(复用 `DS.Toolbar.cornerRadius`); commit `feat(快速看图器增强-A.1): DS.Icon + DS.Viewer 旋转/翻转/信息上屏常量`

- [ ] **A.2 VM 加旋转/翻转状态 + helper**(`QuickViewerViewModel.swift`): 加 `@Published var rotationQuarterTurns: Int = 0` / `@Published var flippedH: Bool = false` / `@Published var flippedV: Bool = false`; 加 `func rotateLeft()` / `rotateRight()` / `toggleFlipH()` / `toggleFlipV()`; 加 `func effectiveImageSize(_ image: NSImage) -> CGSize`(90/270° 宽高互换); 加 `private func resetRotationAndFlip()` 给切图调用; 不改 `fitScale`/`clampOffset`/`canPan` 内部(A.3 一起改); commit `feat(快速看图器增强-A.2): VM 加 rotation/flip @Published 状态 + helper`

- [ ] **A.3 VM `fitScale/clampOffset/canPan/applyViewportSize/onImageLoaded` 改 effectiveImageSize 口径**: 全部 `image.size` 读取替换为 `effectiveImageSize(image)`; `canPan` 内部 `fitScale(for:in:)` 已自动正确; **重点**: `clampOffset` 的 `scaledW = image.size.width * scale` 改 `effectiveImageSize(image).width * scale`; rotateLeft/Right 末尾调 `clampOffset()` + `applyViewportSize` 走 fit 重算; commit `feat(快速看图器增强-A.3): VM fitScale/clampOffset 全链路改 effectiveImageSize 口径`

- [ ] **A.4 VM 切图重置旋转/翻转**: `goBack()` / `goForward()` / `goTo(index:)` 三处 `currentIndex` 变更后调 `resetRotationAndFlip()` + 既有 `resetToFit()`(顺序: 重置 rotation 在前, fitScale 重算在后, 否则按 rotation>0 算 effective size 跟切图意图不符); commit `feat(快速看图器增强-A.4): VM 切图自动重置 rotation/flip 为 0/false (D34 每张独立)`

- [ ] **A.5 Overlay imageLayer 加 rotationEffect + scaleEffect**(`QuickViewerOverlay.swift`): `imageLayer` 内 `Image(nsImage:)` 的 modifier 链按顺序加: `.frame(原 image.size × scale)` → `.rotationEffect(.degrees(Double(viewModel.rotationQuarterTurns) * Double(DS.Viewer.rotationStepDegrees)))` → `.scaleEffect(x: viewModel.flippedH ? -1 : 1, y: viewModel.flippedV ? -1 : 1)` → `.offset(viewModel.offset)`; **顺序固化**: 先 rotation 再 scaleEffect(绕中心转后镜像, 视觉直觉); 若任务 A 真机验视觉错(如先镜像后转产生反方向旋转), 反过来试; commit `feat(快速看图器增强-A.5): Overlay imageLayer 加 rotationEffect + flip scaleEffect`

- [ ] **A.6 Overlay .onKeyPress 加 L/R**: 在现有 `.onKeyPress(.escape)` 等链最后加 `.onKeyPress(.init("l"), phases: .down) { _ in viewModel.rotateLeft(); return .handled }` + `.onKeyPress(.init("r"), phases: .down) { _ in viewModel.rotateRight(); return .handled }`; commit `feat(快速看图器增强-A.6): Overlay .onKeyPress 加 L/R 触发 VM rotateLeft/Right`

- [ ] **A.7 信息上屏 view + 数据加载**(`QuickViewerOverlay.swift`): 新增 `@State private var currentMetadata: ImageMetadata?`; 在 `.onChange(of: viewModel.currentIndex)` 同位置加 `Task.detached(priority: .userInitiated)` 读 `ImageMetadataReader.read(at: viewModel.images[currentIndex])` 回主线程赋值; 新增 `private var infoBadge: some View` 渲染「`\(width)×\(height) · \(ByteCountFormatter().string(fromByteCount: fileSize))`」, 失败/缺字段 → 整 view 返回 EmptyView; 挂在 ZStack 的角落(建议左下, 避开 topBar 关闭按钮 + bottomToolbar; 设 `.padding(.leading, DS.Spacing.lg).padding(.bottom, DS.Viewer.filmstripHeight + DS.Spacing.md)`); 透明度 `.opacity(controlsVisible ? 1 : 0)` 跟随 controls auto-hide; `.allowsHitTesting(false)` 不抢手势; commit `feat(快速看图器增强-A.7): 信息上屏角落气泡 (分辨率 · 大小) 跟随 controlsVisible 隐藏`

- [ ] **A.8 跑 `./scripts/verify.sh` 三段验**: Stage 1 grep + Stage 2 xcodebuild 0 error 0 warning + Stage 3 跳 test; 失败 → 修 → 重跑 ≤ 5 轮; commit log 干净后进 A.9

- [ ] **A.9 CC 自闭环功能级验**(Mac mini Ghostty/tmux/screencapture/AX 工具链): (1) `open ~/sync/Glance.app` 进任一图 → 双击进快速看图器; (2) 按 L → 截图看图转 -90°; 按 R 复位 + 再按 R 转 +90°; (3) 右键 contextMenu 暂不动(任务 B); (4) 角落看「4000×3000 · X MB」气泡可见; 静止鼠标 3 秒后角落气泡跟 topBar 一起淡出; (5) 切下一张 → rotation 重置为 0 验通; (6) 截图存证 `~/sync/glance-qv-enhance-A-*.png`

- [ ] **A.10 PENDING 军哥本机真机验**(写入 `specs/PENDING-USER-ACTIONS.md`): (a) R-rotate-anchor 真机验: 旋转 90° 后滚轮缩放锚点是否跟手(若偏移列后续修复); (b) R-rotate-zoom 真机验: 放大平移后按 L/R, 选 (a) 重置回 fit 行为是否符合直觉; (c) R-rotate-render-order 真机验: rotation + flip 组合视觉是否符合直觉(先转后镜像); commit `docs(快速看图器增强-A.10): 任务 A ship + CC 自闭环验 + PENDING [docs-only]`

### 验证计划
- **CC 自闭环**: A.9 步, Mac mini Ghostty/tmux 工具链, screencapture 验视觉 + AX 验状态
- **军哥本机 PENDING**: A.10 步 3 项(锚点跟手 / zoom 重置体验 / 组合渲染)
- **回滚**: 任务 A 全部改在新增字段/方法 + 既有方法内 effective 口径替换, 风险低; 回滚 = `git revert A.2..A.7` 单 commit 串

---

## 任务 B: 复制图片 + 复制路径 + Finder 显示 + 右键 contextMenu

**用户独立感知兑现**: 用户独立完成后能在快速看图器内**右键弹出 contextMenu**(含旋转/翻转/复制/Finder); ⌘C 复制图片到剪贴板能在 Finder/Notes/Slack 粘贴; ⌘⌥C 复制文件路径; ⌘⇧R 在 Finder 中显示当前图。

### Files
- **Modify**: `Glance/QuickViewer/QuickViewerOverlay.swift`(加 .onKeyPress ⌘C/⌘⌥C/⌘⇧R + contextMenu)
- **Modify**: `Glance/DesignSystem.swift`(加 DS.Icon.copy/copyPath/finder)
- **Create or inline**: 复制/Finder helper 函数(轻量, inline 到 Overlay; 若多处复用考虑独立 `QuickViewer/QuickViewerPasteboardHelpers.swift` — 任务 B 选 inline, 不预创建文件)

### 不改范围
- VM 不动(任务 B 只读 URL/NSImage, 无状态变更)
- `bottomToolbar`/`topBar` 不动(D33)
- `MainQuickViewerWindowController.show` 不加新 callback
- 翻转不给快捷键(R-flip-keys 选「不给」, 翻转仅 contextMenu)

### 步骤

- [ ] **B.1 加 DS 常量**(`DesignSystem.swift`): `DS.Icon.copy = "doc.on.doc"` / `DS.Icon.copyPath = "doc.on.doc.fill"` / `DS.Icon.finder = "magnifyingglass.circle"`; commit `feat(快速看图器增强-B.1): DS.Icon 加 copy/copyPath/finder`

- [ ] **B.2 Overlay 加复制图片 helper**(`QuickViewerOverlay.swift`): 新增 `private func copyImageToPasteboard()`: `guard let nsImage = viewModel.currentNSImage else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([nsImage])`; commit `feat(快速看图器增强-B.2): Overlay 加复制图片 helper (NSPasteboard.general.writeObjects)`

- [ ] **B.3 Overlay 加复制路径 + Finder 显示 helper**: 新增 `private func copyCurrentPath()`: `guard let url = viewModel.images[safe: viewModel.currentIndex] else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string)`; 新增 `private func revealInFinder()`: `guard let url = viewModel.images[safe: viewModel.currentIndex] else { return }; guard FileManager.default.fileExists(atPath: url.path) else { /* 失败暂 noop, R-finder-reveal-not-exist 任务 C toast ship 后再加提示 */ return }; NSWorkspace.shared.activateFileViewerSelecting([url])`; commit `feat(快速看图器增强-B.3): Overlay 加复制路径 + Finder 显示 helper`

- [ ] **B.4 Overlay .onKeyPress 加 ⌘C / ⌘⌥C / ⌘⇧R + 替换 A.6 单步 R 为合并版本**: 在现有 .onKeyPress 链末尾加 ⌘C 分支: `.onKeyPress(.init("c"), phases: .down) { event in if event.modifiers.contains(.command) && event.modifiers.contains(.option) { copyCurrentPath(); return .handled }; if event.modifiers.contains(.command) { copyImageToPasteboard(); return .handled }; return .ignored }`; **替换 A.6 的 `.onKeyPress(.init("r"), phases: .down) { _ in viewModel.rotateRight(); return .handled }`** 为合并版本: `.onKeyPress(.init("r"), phases: .down) { event in if event.modifiers.contains(.command) && event.modifiers.contains(.shift) { revealInFinder(); return .handled }; viewModel.rotateRight(); return .handled }`(同 .onKeyPress("r") 内分支: ⌘⇧R Finder, 裸 R 旋转, 否则两个 .onKeyPress("r") 系统只挂一个); **审视**: 必须确保 A.6 的 R handler 被本步**整体替换**, 不留两个 .onKeyPress("r")(SwiftUI 同 key 多 handler 仅挂最后一个会丢前者); commit `feat(快速看图器增强-B.4): Overlay .onKeyPress ⌘C 复制图 / ⌘⌥C 复制路径 / ⌘⇧R Finder + 合并 R 单 onKeyPress 分支`

- [ ] **B.5 Overlay 加 contextMenu**(D37 — 快捷键可发现镜像): 在 ZoomScrollView 那个外层 `.overlay { imageLayer }`(Overlay :82)后或主 ZStack 上挂 `.contextMenu { ... }`; 菜单结构按 design 第 9 节:
   ```
   Button { viewModel.rotateLeft() } label: { Label("旋转左 (L)", systemImage: DS.Icon.rotateLeft) }
   Button { viewModel.rotateRight() } label: { Label("旋转右 (R)", systemImage: DS.Icon.rotateRight) }
   Divider()
   Button { viewModel.toggleFlipH() } label: { Label("水平翻转", systemImage: DS.Icon.flipHorizontal) }
   Button { viewModel.toggleFlipV() } label: { Label("垂直翻转", systemImage: DS.Icon.flipVertical) }
   Divider()
   Button { copyImageToPasteboard() } label: { Label("复制图片 (⌘C)", systemImage: DS.Icon.copy) }
       .disabled(viewModel.currentNSImage == nil)
   Button { copyCurrentPath() } label: { Label("复制路径 (⌘⌥C)", systemImage: DS.Icon.copyPath) }
   Button { revealInFinder() } label: { Label("在 Finder 中显示 (⌘⇧R)", systemImage: DS.Icon.finder) }
   // (任务 C 加「移到废纸篓」.destructive Button)
   ```
   commit `feat(快速看图器增强-B.5): Overlay 加 contextMenu — 旋转/翻转/复制/Finder 七项 (任务 C 加废纸篓项)`

- [ ] **B.6 跑 `./scripts/verify.sh` 三段验**: Stage 1+2+3 全过, 失败 ≤ 5 轮修

- [ ] **B.7 CC 自闭环功能级验**: (1) 起 Glance 进任一图双击进快速看图器; (2) AX dump 右键菜单结构(`tell process Glance` → contextMenu 命中 → dump items); (3) ⌘C 后 `osascript -e 'tell app "System Events" to keystroke "v"'` 到 textedit 验图粘贴 OR `pbpaste` 看路径; (4) ⌘⇧R 验 Finder 窗弹出 + 当前图被高亮(用 AX `windows` 拉 Finder 当前 selection); (5) 截图存证

- [ ] **B.8 PENDING 军哥本机真机验**: (a) 右键菜单视觉(图标 + 文字 + 快捷键 hint)是否对齐 macOS 习惯; (b) ⌘C 粘贴到 Slack/Notes/Finder 三处图片 fidelity OK; (c) ⌘⌥C 路径粘贴(可能要按 ⌘⇧ . 看 Finder 路径栏); (d) ⌘⇧R Finder 反高亮当前图; commit `docs(快速看图器增强-B.8): 任务 B ship + CC 自闭环 + PENDING [docs-only]`

### 验证计划
- **CC 自闭环**: B.7 步, AX 拉 contextMenu 结构 + pbpaste 验路径 + osascript paste 验图
- **军哥本机 PENDING**: B.8 步 4 项(视觉/图 fidelity/路径/Finder)
- **回滚**: 全部加在 Overlay 内, 无状态变更, 回滚 = revert B.2..B.5

---

## 任务 C: Delete/⌘⌫ 移废纸篓 + 单张撤销 toast

**用户独立感知兑现**: 用户独立完成后能在快速看图器内按 **Delete 或 ⌘⌫** 真把当前图移系统废纸篓 + 自动跳下一张 + 角落弹「已移废纸篓 [撤销]」toast 几秒消失 + 点撤销文件恢复(列表稍后刷新, 跟 M4 全局 banner 语义对齐); 右键 contextMenu 末尾出现红色「移到废纸篓」项。失败场景(权限/V1 老 bookmark/卷已弹出)显失败 toast 不跳图。

### Files
- **Create**: `Glance/QuickViewer/QuickViewerTrashCoordinator.swift`(单张删除适配层: URL → reverse lookup IndexStore → 构造 TrashInput → 调 TrashService → 处理 TrashOutcome → 调 UI callback)
- **Modify**: `Glance/QuickViewer/QuickViewerViewModel.swift`(`images: [URL]` 改 `private(set) var` + `removeCurrent()` 方法 + 导航调整 D40)
- **Modify**: `Glance/QuickViewer/QuickViewerOverlay.swift`(加 .onKeyPress Delete/⌘⌫ + contextMenu 加废纸篓项 + 新 onTrash callback + toast slot)
- **Modify**: `Glance/QuickViewer/MainQuickViewerWindowController.swift`(`show()` 加 `onTrash: ((URL) async -> Void)?` 参数, 透传给 Overlay)
- **Modify**: `Glance/ContentView.swift`(`qvController.show(...)` callsite 加 onTrash 闭包, 内部调 QuickViewerTrashCoordinator)
- **Modify**: `Glance/DesignSystem.swift`(`DS.QuickViewerTrash` 命名空间: toast 自动消失时长 / toast 配色 复用 M4 `DS.Dedup.bannerAutoDismissSeconds` 或新增)

### 不改范围
- `TrashService.swift` 不改(直接复用 M4 API)
- `IndexStore.fetchSnapshotForRestore/restoreImageFromSnapshot` 不改(直接复用 M4 API)
- M4 的 `TrashUndoBanner.swift` 全局 banner 不复用(本任务 toast 是快速看图器内 overlay, 跟全局 banner 性质不同; 走独立 toast view)
- 不做撤销栈(只「最近一次」单步撤销, mirror M4 D30)

### 步骤

- [ ] **C.1 加 DS 常量 + 文档**(`DesignSystem.swift`): 新增 `enum QuickViewerTrash { static let toastAutoDismissSeconds: Double = 5.0; static let toastBackgroundOpacity: Double = 0.45; static let toastCornerRadius: CGFloat = 8 }`; commit `feat(快速看图器增强-C.1): DS.QuickViewerTrash 加 toast 时长 + 配色常量`

- [ ] **C.2 新建 QuickViewerTrashCoordinator**(`QuickViewer/QuickViewerTrashCoordinator.swift`): `@MainActor final class QuickViewerTrashCoordinator: ObservableObject`; 持 `weak var indexStore: IndexStore?` + `weak var bridge: FolderStoreIndexBridge?` + `weak var bookmarkManager: BookmarkManager?`(codex P0 schema gate 下沉到 Coordinator 入口); 装配 API `func attach(indexStore: IndexStore, bridge: FolderStoreIndexBridge, bookmarkManager: BookmarkManager)`。
   **主 API**: `func trash(url: URL) async -> TrashOutcome?` —
   (a) **schema gate**(codex P0 修): `guard bookmarkManager?.currentSchemaVersion ?? 0 >= 2 else { return nil }` 失败提示由 Overlay toast 处理;
   (b) 调 `indexStore.fetchSnapshotForRestore(byFullPath: url.path)` 反查 snapshot;
   (c) snapshot 不存在(未入库图 / V1 老 bookmark) → return nil;
   (d) **GroupKey 构造**(codex P0 修): `TrashService.TrashInput(snapshot: snapshot, groupKey: GroupKey(fileSize: snapshot.fileSize, format: snapshot.format))` — 对齐 `TrashOutcome.swift:42` 真实定义(GroupKey 是 fileSize+format 两字段值类型, **不是** singleton 工厂);
   (e) `TrashService.trashItems([input], cancellation: TrashCancellationToken(), progress: { _, _ in })`;
   (f) 成功 (`outcome.successCount == 1`)后: `indexStore.deleteImage(folderId: snapshot.folderId, relativePath: snapshot.relativePath)` + **`DedupPass.reEvaluateGroup(store: indexStore, fileSize: snapshot.fileSize, format: snapshot.format) + indexStore.promoteOrphanDuplicates()`**(codex P0 修, mirror `DuplicateOverviewModel.swift:257/334`) + `bridge.triggerIndexChanged()`(让总览/智能文件夹刷新);
   (g) 返回 outcome(给 Overlay 判 success/failure 决定是否 removeCurrent + toast 文案);
   加对称 `func restore(outcome: TrashOutcome) async -> RestoreOutcome?` 调 `TrashService.restoreItems + indexStore.restoreImageFromSnapshot` + 同样 `DedupPass.reEvaluateGroup + promoteOrphanDuplicates + bridge.triggerIndexChanged`;
   commit `feat(快速看图器增强-C.2): 新建 QuickViewerTrashCoordinator 单张删除适配层 + schema gate + reEvaluateGroup`

- [ ] **C.3 IndexStore 加 `fetchSnapshotForRestore(byFullPath:)`**(精确 SQL 匹配, **codex P0 修**避免前缀误伤): grep 验证现有签名 `IndexedImage.swift:735` `fetchSnapshotForRestore(folderId:relativePath:)` → 加新 entry `func fetchSnapshotForRestore(byFullPath fullPath: String) throws -> IndexedImageSnapshot?`; **SQL 用精确匹配范式**(mirror `IndexedImage.swift:412/582` 既有 pattern): `SELECT ... FROM images i JOIN folders f ON i.folder_id = f.id WHERE f.root_path || '/' || i.relative_path = ?`, **不做**字符串前缀推断(`/a/b` 不会误匹 `/a/b2`); 找到 row 后复用既有 `fetchSnapshotForRestore(folderId:relativePath:)` 内部解析 logic 拼 IndexedImageSnapshot; commit `feat(快速看图器增强-C.3): IndexedImage.fetchSnapshotForRestore(byFullPath:) 精确 SQL 反查 entry`

- [ ] **C.4 VM `images` 改 mutable + `removeCurrent()` + D40 导航**(`QuickViewerViewModel.swift`): `let images: [URL]` → `private(set) var images: [URL]`; 新增 `func removeCurrent()`:
   (a) 校验 `currentIndex` 合法 + `images.count >= 1`;
   (b) `images.remove(at: currentIndex)`;
   (c) **prefetch cache 全清重建**(codex P0 修, 选「全清」非单 key remove): `clearPrefetchCache()` 把 `prefetchCache` + `prefetchTasks` 整体清掉, **不**做 `removeValue(forKey: currentIndex)`(会让 `> currentIndex` 所有 key 错位); 后续 `loadCurrentImage` 内部会触发 prefetchAdjacent 重建;
   (d) **D40 导航策略**: 若 `images.isEmpty` → 不调 `loadCurrentImage` + 设 `currentNSImage = nil` + 设标志位 `wasEmptied = true`(让 Overlay 触发 onDismiss); 否则若 `currentIndex >= images.count` → `currentIndex = images.count - 1`; 调 `resetRotationAndFlip() + resetToFit() + loadCurrentImage()` 加载下一张;
   (e) 注意 `progress`/`canGoBack`/`canGoForward` computed 自动跟;
   commit `feat(快速看图器增强-C.4): VM images 改 private(set) var + removeCurrent + 全清 prefetch + D40 导航`

- [ ] **C.5 MainQuickViewerWindowController `show()` 加 onTrash callback**(`MainQuickViewerWindowController.swift`): `show()` 签名末加 `onTrash: ((URL) async -> TrashOutcome?)? = nil` 参数(**默认值 nil**, codex P1 修兼容 ExternalViewerWindowController.swift:73 OpenWith 路径不传); 存到 `private var onTrash: ((URL) async -> TrashOutcome?)?`(类内成员); 透传给 `QuickViewerOverlay(... onTrash: onTrash)`(mirror 5 个既有 onXxx 闭包注入 pattern); **注**: ExternalViewerWindowController OpenWith 路径不传 → OpenWith 看图器无删除入口(单 session 不挂主索引)语义符合 OpenWith 定位; commit `feat(快速看图器增强-C.5): MainQuickViewerWindowController.show 加 onTrash callback (默认 nil 兼容 OpenWith 路径)`

- [ ] **C.6 Overlay 接 onTrash + Delete/⌘⌫ + toast state**(`QuickViewerOverlay.swift`):
   (a) `init` 加 `onTrash: ((URL) async -> TrashOutcome?)?` 参数(默认 nil) + 存为 `let`;
   (b) 新增 `@State private var trashUndoOutcome: TrashOutcome?`(单张版 toast state) + `@State private var trashFailureMessage: String?`(失败 toast state, codex P0 修支持失败显式提示) + `@State private var trashDismissTask: Task<Void, Never>?`(toast auto-dismiss timer);
   (c) **关键改动**(codex P0 修): `private func handleTrashCurrent() async`(改 async):
       ```
       guard let url = viewModel.images[safe: viewModel.currentIndex], let onTrash else { return }
       let outcome = await onTrash(url)
       if let outcome, outcome.successCount == 1 {
           viewModel.removeCurrent()              // ← 仅成功才 removeCurrent
           trashUndoOutcome = outcome
           scheduleTrashDismiss()
           if viewModel.images.isEmpty { onDismiss() }
       } else if let outcome, outcome.failures.count == 1 {
           trashFailureMessage = outcome.failures.first?.reason ?? "移废纸篓失败"
           scheduleTrashDismiss()                  // 失败 toast 也 auto-dismiss
       } else {
           trashFailureMessage = "无法删除该图(可能未入库 / V1 老 bookmark / 已升级 V2 才能删)"
           scheduleTrashDismiss()
       }
       ```
   (d) 加 `.onKeyPress(.init(.delete)) { Task { await handleTrashCurrent() }; return .handled }` + `.onKeyPress(.init("⌫"), phases: .down) { event in if event.modifiers.contains(.command) { Task { await handleTrashCurrent() }; return .handled }; return .ignored }` (**codex P2**: 实施期先用 SwiftUI 文档 + 真机实测确认 `.onKeyPress(.delete)` 是否覆盖 backspace; 若不覆盖则补 `.onKeyPress(.init(.deleteForward))` 兜底; 当前 Glance 项目 grep 既有用法只覆盖 `escape/space/arrows` 等无 delete 对照);
   commit `feat(快速看图器增强-C.6): Overlay 接 onTrash + Delete/⌘⌫ + handleTrashCurrent 成功才 removeCurrent + 失败 toast`

- [ ] **C.7 Overlay toast view + auto-dismiss**(`QuickViewerOverlay.swift`):
   (a) **outcome 回流方式**(决策): 走 `onTrash` callback 返回值(`async -> TrashOutcome?`), 不用双向 binding (已在 C.5/C.6 写明);
   (b) 新增 `private var trashToast: some View` 角落 view(放右上 padding 或 topBar 下方):
       ```
       if let outcome = trashUndoOutcome {
           HStack {
               Text("已移废纸篓")
               Button("撤销") { Task { await handleUndoTrash() } }
               Button("×") { trashUndoOutcome = nil; trashDismissTask?.cancel() }
           }
           .padding(...)
           .background(Color(white: 0, opacity: DS.QuickViewerTrash.toastBackgroundOpacity),
                       in: RoundedRectangle(cornerRadius: DS.QuickViewerTrash.toastCornerRadius))
       } else if let msg = trashFailureMessage {
           HStack {
               Image(systemName: "exclamationmark.triangle")
               Text(msg)
               Button("×") { trashFailureMessage = nil; trashDismissTask?.cancel() }
           }
           .padding(...)
           .background(Color.red.opacity(DS.QuickViewerTrash.toastBackgroundOpacity),
                       in: RoundedRectangle(cornerRadius: DS.QuickViewerTrash.toastCornerRadius))
       }
       ```
   (c) `private func scheduleTrashDismiss()` 复刻现有 `scheduleHide` pattern, sleep `DS.QuickViewerTrash.toastAutoDismissSeconds` 后 `trashUndoOutcome = nil; trashFailureMessage = nil`;
   (d) toast 挂在 ZStack 角落(建议右下, 不撞 navButton 也不撞 A.7 信息上屏左下); 跟 `controlsVisible` 是否联动? — **不联动**(撤销/失败 toast 是反馈通知, 不应随鼠标静止隐藏; 跟 M4 全局 banner 行为对齐);
   commit `feat(快速看图器增强-C.7): Overlay toast view + auto-dismiss + 成功/失败双 toast 渲染`

- [ ] **C.8 Overlay 撤销逻辑接线**(`QuickViewerOverlay.swift`):
   (a) `init` 加 `onUndoTrash: ((TrashOutcome) async -> Void)?` 参数(默认 nil) + 存为 `let`;
   (b) `handleUndoTrash() async`: `guard let outcome = trashUndoOutcome, let onUndoTrash else { return }; await onUndoTrash(outcome); await MainActor.run { trashUndoOutcome = nil; trashFailureMessage = "文件恢复, 列表稍后刷新"; scheduleTrashDismiss() }` — **撤销文案**(codex P1 修): 显式说明「文件恢复, 列表稍后刷新」, **不**承诺「回原位立刻可见」(VM `images` 不 reinsert 撤销图, 跟 M4 全局 banner 行为对齐, 靠 FSEvents/scan 最终一致, 详 R-undo-restore-fidelity);
   (c) ContentView 接 callback 调 `quickViewerTrashCoordinator.restore(outcome:)`(详 C.11);
   commit `feat(快速看图器增强-C.8): Overlay 撤销路径 — onUndoTrash callback + 文件恢复列表稍后刷新文案`

- [ ] **C.9 MainQuickViewerWindowController 加 onUndoTrash 透传**(`MainQuickViewerWindowController.swift`): `show()` 签名加 `onUndoTrash: ((TrashOutcome) async -> Void)? = nil` 参数(默认 nil, codex P1 兼容 OpenWith) + 存成员 + 透传给 Overlay; commit `feat(快速看图器增强-C.9): MainQuickViewerWindowController.show 加 onUndoTrash 透传 (默认 nil)`

- [ ] **C.10 Overlay contextMenu 加「移到废纸篓」.destructive 项**(`QuickViewerOverlay.swift`): 在 B.5 加的 contextMenu 末尾追加: `Divider() + Button(role: .destructive) { Task { await handleTrashCurrent() } } label: { Label("移到废纸篓 (⌫)", systemImage: DS.Icon.trash) }`; commit `feat(快速看图器增强-C.10): contextMenu 末加移到废纸篓 destructive 项`

- [ ] **C.11 ContentView wire onTrash + onUndoTrash + 装配 Coordinator**(`ContentView.swift`):
   (a) 加 `@StateObject private var quickViewerTrashCoordinator = QuickViewerTrashCoordinator()`;
   (b) `wireIfReady` 末尾调 `quickViewerTrashCoordinator.attach(indexStore: store, bridge: bridge, bookmarkManager: bookmarkManager)`(三依赖注入, schema gate 在 Coordinator 入口);
   (c) `qvController.show(...)` callsite 加 `onTrash: { url in await quickViewerTrashCoordinator.trash(url: url) }` + `onUndoTrash: { outcome in _ = await quickViewerTrashCoordinator.restore(outcome: outcome) }`;
   commit `feat(快速看图器增强-C.11): ContentView 装配 Coordinator + show callsite 接 onTrash/onUndoTrash`

- [ ] **C.12 schema gate 已下沉到 Coordinator 入口**(codex P0 修, 本步骤 nearly no-op):
   schema gate (`bookmarkManager.currentSchemaVersion >= 2`) 在 C.2 `QuickViewerTrashCoordinator.trash()` 入口已实现, schema < 2 时 Coordinator 直接返回 nil; C.6 `handleTrashCurrent` 拿到 nil → 走「无 outcome 失败」分支显 toast 「无法删除该图(可能未入库 / V1 老 bookmark / 已升级 V2 才能删)」;
   **不复用** M4 BookmarkMigrationCoordinator 引导 sheet(快速看图器是模态全屏看图, 弹 sheet UX 突兀);
   **取代** 原 C.12 在 Overlay 内查 schema 的设计(避免给 Overlay 注入 BookmarkManager);
   本步实际工作 = 写注释 + 文档 PENDING, 无代码改动;
   commit `docs(快速看图器增强-C.12): schema gate 下沉到 Coordinator 入口实现说明 + 注释 [docs-only]`

- [ ] **C.13 跑 `./scripts/verify.sh` 三段验**: 全过

- [ ] **C.14 CC 自闭环功能级验**: 复杂场景需军哥本机 — CC 这步只验「按 Delete 不崩 + handleTrashCurrent 走到 onTrash callback」(用 log 验或断点验), 不真删用户文件

- [ ] **C.15 PENDING 军哥本机真机验**(写入 PENDING-USER-ACTIONS.md): (a) 端到端: 快速看图器双击进 → Delete 真删图 + ~/.Trash 见文件 + DB row 删 + 自动跳下一张 + toast 出 + 撤销文件回原位 + 撤销后下次切回该图能再看到(看 FSEvents 是否补回 DB); (b) 删到最后一张 → 关快速看图器(D40); (c) V1 老 bookmark 图按 Delete → toast 提示走 V2 升级(C.12 gate); (d) 右键 contextMenu「移到废纸篓」点击同 Delete 行为; (e) ⌘⌫ 等同 Delete; commit `docs(快速看图器增强-C.15): 任务 C ship + CC 自闭环 + PENDING [docs-only]`

### 验证计划
- **CC 自闭环**: C.14 步, 主要验编译 + handleTrashCurrent 触发链路, 不真删文件
- **军哥本机 PENDING**: C.15 步 5 项(端到端/删空关窗/V1 gate/contextMenu/⌘⌫)
- **回滚**: 任务 C 改动较深(VM 改 mutable + 跨 5 文件), 回滚 = revert C.1..C.12 串; 若已部分 ship 但发现重大问题, 可单 revert ContentView wire (C.11) 让 UI 失活, 保留 Coordinator + VM 改造留 backlog 重做

---

## 实施记录回填表

(任务 ship 后回填 commit hash, mirror M4 任务 2 plan 末尾历史「完成详细」表 pattern)

### 任务 A 完成详细
| 步骤 | 文件 | commit | 备注 |
|---|---|---|---|
| A.1 DS 常量 | DesignSystem.swift | `<pending>` | |
| A.2 VM 状态 + helper | QuickViewerViewModel.swift | `<pending>` | |
| A.3 effectiveImageSize 全链路 | QuickViewerViewModel.swift | `<pending>` | |
| A.4 切图重置 | QuickViewerViewModel.swift | `<pending>` | |
| A.5 imageLayer rotation/scaleEffect | QuickViewerOverlay.swift | `<pending>` | |
| A.6 .onKeyPress L/R | QuickViewerOverlay.swift | `<pending>` | (B.4 合并替换) |
| A.7 信息上屏 | QuickViewerOverlay.swift | `<pending>` | |
| A.8 verify.sh | — | `<pending>` | |
| A.9 CC 自闭环 | — | `<pending>` | 截图存证 |
| A.10 PENDING | PENDING-USER-ACTIONS.md | `<pending>` | |

### 任务 B 完成详细
| 步骤 | 文件 | commit | 备注 |
|---|---|---|---|
| B.1 DS 常量 | DesignSystem.swift | `<pending>` | |
| B.2 复制图 helper | QuickViewerOverlay.swift | `<pending>` | |
| B.3 复制路径 + Finder | QuickViewerOverlay.swift | `<pending>` | |
| B.4 .onKeyPress ⌘C/⌘⌥C/⌘⇧R + R 合并 | QuickViewerOverlay.swift | `<pending>` | |
| B.5 contextMenu | QuickViewerOverlay.swift | `<pending>` | |
| B.6 verify.sh | — | `<pending>` | |
| B.7 CC 自闭环 | — | `<pending>` | |
| B.8 PENDING | PENDING-USER-ACTIONS.md | `<pending>` | |

### 任务 C 完成详细
| 步骤 | 文件 | commit | 备注 |
|---|---|---|---|
| C.1 DS.QuickViewerTrash | DesignSystem.swift | `<pending>` | |
| C.2 QuickViewerTrashCoordinator | QuickViewerTrashCoordinator.swift(新) | `<pending>` | |
| C.3 fetchSnapshotForRestore(byFullPath:) | IndexedImage.swift | `<pending>` | (可能 skip) |
| C.4 VM removeCurrent + D40 | QuickViewerViewModel.swift | `<pending>` | |
| C.5 show 加 onTrash | MainQuickViewerWindowController.swift | `<pending>` | |
| C.6 Overlay onTrash + Delete/⌘⌫ | QuickViewerOverlay.swift | `<pending>` | |
| C.7 toast view + outcome 回流 | QuickViewerOverlay.swift | `<pending>` | |
| C.8 撤销接线 | QuickViewerOverlay.swift | `<pending>` | |
| C.9 show 加 onUndoTrash | MainQuickViewerWindowController.swift | `<pending>` | |
| C.10 contextMenu 加废纸篓项 | QuickViewerOverlay.swift | `<pending>` | |
| C.11 ContentView wire | ContentView.swift | `<pending>` | |
| C.12 schemaVersion gate | QuickViewerOverlay.swift | `<pending>` | |
| C.13 verify.sh | — | `<pending>` | |
| C.14 CC 自闭环 | — | `<pending>` | 限编译 + 链路验, 不真删 |
| C.15 PENDING | PENDING-USER-ACTIONS.md | `<pending>` | |

---

## Self-review checklist(写完 plan 跑一遍)

- [x] **Spec coverage**: design D33-D40 八项决策全部映射到任务 A/B/C 步骤; design 第 12 节 3 任务划分对齐
- [x] **Placeholder scan**: 无 TBD/TODO/「补错误处理」式占位; 每步含具体 API 签名/文件路径/commit message
- [x] **Type consistency**: `rotationQuarterTurns: Int` / `flippedH: Bool` / `effectiveImageSize(NSImage) -> CGSize` / `removeCurrent()` / `TrashOutcome` / `TrashInput { snapshot, groupKey }` / `QuickViewerTrashCoordinator.trash(url:) -> TrashOutcome?` 命名各步一致
- [x] **任务独立可发版**: 每任务独立 ship 用户可感知(A=旋转+信息; B=右键+复制+Finder; C=删除闭环); 实施期严格串行 A→B→C(codex P1 修, 不并行) — A 改 .onKeyPress("r") 裸 R, B 要替换为合并分支(裸 R + ⌘⇧R)
- [x] **Reality check 深到字段级**: 已 Read VM/Overlay/ZoomScrollView/MainQVController/TrashService/TrashOutcome 6+ 文件 + codex review 补 grep `IndexedImage.swift:412/582/735` SQL 范式; 发现 (1) `TrashService.trashItems([TrashInput])` 不收 [URL] → 加 QuickViewerTrashCoordinator 适配层; (2) `images: [URL]` 是 `let` → 改 `private(set) var`; (3) A.6 + B.4 同 .onKeyPress("r") 需合并; (4) **codex P0**: GroupKey 真实定义 `(fileSize:format:)` 非 singleton; (5) **codex P0**: prefetch cache 删一张 idx 漂移; (6) **codex P0**: byFullPath 反查需精确 SQL 不能前缀; (7) **codex P0**: trash 成功才 removeCurrent 不能反过来; (8) **codex P0**: schema gate 注入链路缺 → 下沉 Coordinator; (9) **codex P1**: ExternalViewerWindowController.swift:73 callsite 漏算 → 默认值 nil; (10) **codex P1**: 撤销「回原位」承诺 vs 「FSEvents 最终一致」实现矛盾 → 文案降级
- [x] **CLAUDE.md 术语字典**: plan 散文清「`vertical slice`/`Vertical slice`/`Slice`/`片`」改「任务/独立可发版/任务 X 完成详细」(codex P1 修); 代码符号(`QuickViewerOverlay`/`QuickViewerViewModel` 等英文)豁免; 元描述里禁用词字面用 `` ` `` backtick 包(如 `禁用 \`Slice\` / \`VS\` / \`切片\` 等`)防 grep 误判
- [x] **测试与验证**: 每任务标 CC 自闭环 + 军哥本机 PENDING 双层验证; verify.sh 三段嵌每任务收尾
- [x] **回滚方式**: 每任务列 revert 范围 + 部分回滚降级路径

---

## Execution Handoff

Plan 已 codex review 折入(2026-06-17), 接下来:

1. **codex review v1**(已完成): codex:rescue read-only review 抓 **5 P0 + 4 P1 + 2 P2**, 全部已折入 plan(见上方风险表 + 各步骤 「codex P0/P1 修」 标记)
2. 军哥拍板「go」 — 等待
3. 走 `superpowers:subagent-driven-development` skill, **A → B → C 严格串行**(codex P1 修, 不并行), 每任务 dispatch fresh subagent 实施, 主 agent 简短汇报 + 每步 build 绿 + commit 落地

### codex review v1 折入对照表(2026-06-17 单轮)

| codex 级别 | 简称 | 修法落地步骤 |
|---|---|---|
| P0 | C.6 删图时序 | C.6 改 handleTrashCurrent 先 await onTrash 拿 outcome, successCount==1 才 removeCurrent; 失败显失败 toast |
| P0 | GroupKey 定义 + 缺 reEvaluateGroup | C.2 改 `GroupKey(fileSize:format:)` 对齐 TrashOutcome.swift:42 真实定义; trash/restore 后调 DedupPass.reEvaluateGroup + promoteOrphanDuplicates |
| P0 | prefetch 索引漂移 | C.4 选「全清重建」`clearPrefetchCache()` 代替单 key remove |
| P0 | byFullPath 前缀误伤 | C.3 改用精确 SQL `f.root_path \|\| '/' \|\| i.relative_path = ?` mirror IndexedImage.swift:412/582 |
| P0 | schema gate 注入链路 | C.12 下沉到 Coordinator 入口 + ContentView wire 加 BookmarkManager 注入(C.11) |
| P1 | ExternalViewer callsite | C.5/6/9 新参数全设默认值 nil + plan 头「最小真实改动集」明示 OpenWith 路径无删除入口 |
| P1 | A/B 不并行 | 任务全表 + 总体时序段明示 A→B→C 严格串行, B.4 改写「替换 A.6 的 .onKeyPress("r")」 |
| P1 | 撤销文案降级 | C.7/C.8 toast 文案改「文件恢复, 列表稍后刷新」对齐 M4 全局 banner 不承诺 QV 内立刻 reinsert |
| P1 | 术语清洗 | 全文 grep `vertical slice`/`Vertical slice`/`Slice`/`片` 散文清掉改「任务/独立可发版」; 元描述禁用词字面用 backtick 包 |
| P2 | Delete 键位双绑 | C.6 加注「实施期真机确认 .onKeyPress(.delete) 是否覆盖 backspace, 不覆盖则补 .deleteForward」 |
| P2 | 触及文件范围收口 | plan 头部加「最小真实改动集」明示 7 文件 |

**选择题**: subagent-driven 还是 inline? 项目偏好 subagent-driven(详见 M4 任务 1/2 节奏)。
