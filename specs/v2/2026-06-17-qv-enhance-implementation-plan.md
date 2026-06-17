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

---

## 任务全表

| 任务 | 一句话 | 文件触及数 | 估时 | 依赖 | vertical slice 兑现 |
|---|---|---|---|---|---|
| **任务 A** | 临时旋转 L/R + 翻转 H/V + 信息上屏角落小字 | 4(VM + Overlay + ZoomScrollView 复核 + DS) | 1-2 天 | 无 | 按 L 图转 90° + 角落显「4000×3000 · 2.5MB」 |
| **任务 B** | 复制图片 + 复制路径 + Finder 显示 + 右键 contextMenu | 3(Overlay + DS + 复制/Finder helper) | 0.5-1 天 | 无(可与 A 并行 ship) | 右键弹菜单 + ⌘C/⌘⌥C/⌘⇧R 真生效 |
| **任务 C** | Delete/⌘⌫ 移废纸篓 + 单张撤销 toast + working-copy 数组维护 | 5(Coordinator + VM 改 mutable + Overlay + MainQVController + ContentView wire) | 2-3 天 | M4 `TrashService` 已 ship `78b856e` | 按 Delete 图进废纸篓 + 自动下一张 + toast 撤销回原位 |

**总估时**: 4-6 天。任务 A+B 可并行(同一会话 dispatch 两 subagent), 任务 C 等 A+B ship 后单独跑(VM 改动较深)。

---

## 总体时序

```
任务 A (旋转/翻转 + 信息) ───┐
                             ├──→ 任务 C (删除闭环, 等 A+B ship)
任务 B (复制/Finder + 右键) ─┘
```

- 任务 A/B 互相不依赖, 改同文件(`QuickViewerOverlay.swift`) 但不同段, 可同 session 串行 commit 或两 subagent 并行(并行需 worktree 隔离)
- 任务 C 必须等 A+B ship: 右键 contextMenu(B) 要加「移到废纸篓」项; 信息上屏(A) 帮用户决策删不删
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
| **R-trash-adapter** | `TrashService.trashItems([TrashInput])` 不收 URL, 需要 URL→folder_id+relative_path 反查 + `fetchSnapshotForRestore` 拿 IndexedImageSnapshot + 构造 `TrashInput`(带 `GroupKey`)。快速看图器单张场景**无 GroupKey 概念**(GroupKey 是 dedup 组概念) | 任务 C 新建「单张删除适配层」`QuickViewerTrashCoordinator`(URL → reverse lookup IndexStore → 单张 GroupKey 用 sha256 兜底或空 group sentinel); 不接 IndexStore 的 V1 老 bookmark 图不能删(回退到 banner 提示) | C |
| **R-images-let** | VM `images: [URL]` 是 `let`(QuickViewerViewModel.swift:18), 不可变。`prefetchCache/prefetchTasks/导航 canGoBack/canGoForward` 全部基于固定数组语义 | 任务 C 改 `let images: [URL]` → `private(set) var images: [URL]` + 新增 `removeCurrent()` 方法 + 调整 `currentIndex` + 清该 idx prefetch + 重 `loadCurrentImage` + 更新 progress 字符串。同步审视所有读 `images.count`/`images.indices` 的点(grep 全文件) | C |
| **R-onkey-modifier-flags** | 现有 `.onKeyPress` ⌘=/⌘- 检查 `NSEvent.modifierFlags.contains(.command)`(Overlay :162/170/174) 是全局 NSEvent.modifierFlags 而非 event.modifiers; 但 ⌘F 用了 event.modifiers(:180)。新 ⌘C/⌘⌥C/⌘⇧R/⌘⌫ 用哪种? | 任务 B/C 统一用 `event.modifiers`(mirror :180 现代写法), 与 ⌘=/- 不同源(那段是历史遗留待统一, 不在本 plan 范围) | B + C |
| **R-pasteboard-image-fidelity** | NSPasteboard 复制 NSImage 时各 paste target 行为(Finder paste / Slack paste / Notes paste)对 PNG/JPG/HEIC 不同格式的还原可能不一致 | 任务 B 用 `NSPasteboard.general.writeObjects([nsImage])` 简单路径; 复杂 fidelity 列 backlog | B |
| **R-finder-reveal-not-exist** | 文件已外部删除时 `NSWorkspace.activateFileViewerSelecting` 会弹 Finder 空窗 | 任务 B 调前 `FileManager.fileExists` 预检, 失败显 toast(用任务 C 的 toast 槽; 若 C 未 ship 则简单 print + helpDialog; 真实顺序 A+B 先 ship 时此场景概率极低可暂忽略) | B |

---

## 任务 A: 旋转/翻转 + 信息上屏

**Vertical slice 兑现**: 用户独立完成后能在快速看图器内按 **L/R** 把图转 90°、按右键菜单选「水平翻转/垂直翻转」摆正; 角落自动显「4000×3000 · 2.5MB」帮判断留大删小; 关窗即还原不写文件。

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

**Vertical slice 兑现**: 用户独立完成后能在快速看图器内**右键弹出 contextMenu**(含旋转/翻转/复制/Finder); ⌘C 复制图片到剪贴板能在 Finder/Notes/Slack 粘贴; ⌘⌥C 复制文件路径; ⌘⇧R 在 Finder 中显示当前图。

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

- [ ] **B.4 Overlay .onKeyPress 加 ⌘C / ⌘⌥C / ⌘⇧R**: 在现有 .onKeyPress 链末尾加: `.onKeyPress(.init("c"), phases: .down) { event in if event.modifiers.contains(.command) && event.modifiers.contains(.option) { copyCurrentPath(); return .handled }; if event.modifiers.contains(.command) { copyImageToPasteboard(); return .handled }; return .ignored }` + `.onKeyPress(.init("r"), phases: .down) { event in if event.modifiers.contains(.command) && event.modifiers.contains(.shift) { revealInFinder(); return .handled }; viewModel.rotateRight(); return .handled }`(注意 R 已被 A.6 占, 改写成同 keypress 内分支: ⌘⇧R Finder, 裸 R 旋转, 否则两个 .onKeyPress("r") 系统只挂一个); **注意**: A.6 的 `.onKeyPress(.init("r"), phases: .down) { _ in viewModel.rotateRight(); return .handled }` 必须替换成本步的合并版本, 避免冲突; commit `feat(快速看图器增强-B.4): Overlay .onKeyPress ⌘C 复制图 / ⌘⌥C 复制路径 / ⌘⇧R Finder 显示 + 合并裸R+⌘⇧R 单 onKeyPress`

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

**Vertical slice 兑现**: 用户独立完成后能在快速看图器内按 **Delete 或 ⌘⌫** 真把当前图移系统废纸篓 + 自动跳下一张 + 角落弹「已移废纸篓 [撤销]」toast 几秒消失 + 点撤销文件回原位; 右键 contextMenu 末尾出现红色「移到废纸篓」项。

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

- [ ] **C.2 新建 QuickViewerTrashCoordinator**(`QuickViewer/QuickViewerTrashCoordinator.swift`): `@MainActor final class QuickViewerTrashCoordinator: ObservableObject`; 持 `weak var indexStore: IndexStore?` + `weak var bridge: FolderStoreIndexBridge?`; 装配 API `func attach(indexStore: IndexStore, bridge: FolderStoreIndexBridge)`; 主 API: `func trash(url: URL) async -> TrashOutcome?` — (a) 调 `indexStore.fetchSnapshotForRestore(byFullPath:)`(若 IndexStore 无此 API, 看下 step C.3 是否要补 entry)反查 snapshot; (b) snapshot 不存在(V1 老 bookmark 图 / 未入库图) → return nil + log; (c) 构造 `TrashService.TrashInput(snapshot: snapshot, groupKey: GroupKey.singleton(snapshot.contentSHA256 ?? "no-sha-\(snapshot.id)"))` — 注: GroupKey 是 dedup 概念, 单张快速看图器删图无组, 用 sha256 作 group key(若图无 sha256 用 image id 兜底, 保 GroupKey 唯一); (d) `TrashService.trashItems([input], cancellation: TrashCancellationToken(), progress: { _, _ in })`; (e) 成功后 `indexStore.deleteImage(folderId:relativePath:)` + `bridge.triggerIndexChanged()`(让总览/智能文件夹刷新); (f) 返回 outcome; 加对称 `func restore(outcome: TrashOutcome) async -> RestoreOutcome` 调 `TrashService.restoreItems + indexStore.restoreImageFromSnapshot`; commit `feat(快速看图器增强-C.2): 新建 QuickViewerTrashCoordinator 单张删除适配层 (URL → snapshot → TrashInput → TrashOutcome)`

- [ ] **C.3 IndexStore 加 `fetchSnapshotForRestore(byFullPath:)`**(若现有 `fetchSnapshotForRestore` 只支持 `folderId+relativePath`, 加单 URL 友好的 entry 给 QuickViewerTrashCoordinator): grep 验证现有签名 → 若已有按 fullPath 反查的方法直接复用跳过本步; 否则在 `IndexedImage.swift` 新增 `func fetchSnapshotForRestore(byFullPath fullPath: String) throws -> IndexedImageSnapshot?`(先反查 `folders` 表找出 root 中包含此 path 的 folder_id + 算 relative_path, 再调既有 `fetchSnapshotForRestore(folderId:relativePath:)`); commit `feat(快速看图器增强-C.3): IndexStore.fetchSnapshotForRestore(byFullPath:) 单 URL 反查 entry` *(若 C.2 写完发现已有等效 API 则跳本步, plan 标注 "skipped")*

- [ ] **C.4 VM `images` 改 mutable + `removeCurrent()` + D40 导航**(`QuickViewerViewModel.swift`): `let images: [URL]` → `private(set) var images: [URL]`; 新增 `func removeCurrent()`: (a) 校验 `currentIndex` 合法 + `images.count >= 1`; (b) `images.remove(at: currentIndex)`; (c) `prefetchCache.removeValue(forKey: currentIndex)` + `prefetchTasks[currentIndex]?.cancel(); prefetchTasks.removeValue(forKey: currentIndex)`; (d) **D40 导航策略**: 若 `images.isEmpty` → 不调 `loadCurrentImage` + 设 `currentNSImage = nil` + 设标志位 `wasEmptied = true`(让 Overlay 触发 onDismiss); 否则若 `currentIndex >= images.count` → `currentIndex = images.count - 1`; 调 `resetRotationAndFlip() + resetToFit() + loadCurrentImage()` 加载下一张; (e) 注意 `progress`/`canGoBack`/`canGoForward` computed 自动跟; commit `feat(快速看图器增强-C.4): VM images 改 private(set) var + removeCurrent + D40 导航策略`

- [ ] **C.5 MainQuickViewerWindowController `show()` 加 onTrash callback**(`MainQuickViewerWindowController.swift`): `show()` 签名末加 `onTrash: ((URL) async -> Void)? = nil` 参数; 存到 `private var onTrash: ((URL) async -> Void)?`(类内成员); 透传给 `QuickViewerOverlay(... onTrash: onTrash)`(mirror 5 个既有 onXxx 闭包注入 pattern); commit `feat(快速看图器增强-C.5): MainQuickViewerWindowController.show 加 onTrash callback`

- [ ] **C.6 Overlay 接 onTrash + Delete/⌘⌫ + toast state**(`QuickViewerOverlay.swift`): (a) `init` 加 `onTrash: ((URL) async -> Void)?` 参数 + 存为 `let`; (b) 新增 `@State private var trashUndoOutcome: TrashOutcome?`(单张版 banner state) + `@State private var trashDismissTask: Task<Void, Never>?`(toast auto-dismiss timer); (c) 新增 `private func handleTrashCurrent()`: `guard let url = viewModel.images[safe: viewModel.currentIndex], let onTrash else { return }; Task { await onTrash(url); /* outcome 由 ContentView 通过新 binding 写回, 见 C.7 */ }; viewModel.removeCurrent(); if viewModel.images.isEmpty { onDismiss() }`; (d) 加 `.onKeyPress(.init(.delete)) { handleTrashCurrent(); return .handled }` + `.onKeyPress(.init("⌫")) { event in if event.modifiers.contains(.command) { handleTrashCurrent(); return .handled }; return .ignored }`(⌘⌫ 用 keyEquivalent backspace + .command modifier; 若 SwiftUI `.onKeyPress(.delete)` 已覆盖 backspace 则纯 Delete 一路即可); commit `feat(快速看图器增强-C.6): Overlay 接 onTrash callback + Delete/⌘⌫ 触发 + handleTrashCurrent helper`

- [ ] **C.7 Overlay toast view + outcome 回流 binding**(`QuickViewerOverlay.swift`): (a) 决策: `onTrash` callback 返回 outcome OR ContentView 通过新 `onTrashOutcomeChanged: ((TrashOutcome?) -> Void)?` callback 推回 — 选**前者**(返回值简单不需要双向 binding); (b) 改 `onTrash: ((URL) async -> TrashOutcome?)?`(signature 加返回值); handleTrashCurrent 改 `Task { let outcome = await onTrash(url); await MainActor.run { trashUndoOutcome = outcome; scheduleTrashDismiss() } }`; (c) 新增 `private var trashToast: some View` 角落 view(放右上 padding 或 topBar 下方): `if let outcome = trashUndoOutcome { HStack { Text("已移废纸篓 (\(outcome.successCount) 张)"); Button("撤销") { handleUndoTrash() }; Button("×") { trashUndoOutcome = nil; trashDismissTask?.cancel() } }.padding(...).background(Color(white: 0, opacity: DS.QuickViewerTrash.toastBackgroundOpacity), in: RoundedRectangle(cornerRadius: DS.QuickViewerTrash.toastCornerRadius)) }`; (d) `private func scheduleTrashDismiss()` 复刻现有 `scheduleHide` pattern, sleep `DS.QuickViewerTrash.toastAutoDismissSeconds` 后 `trashUndoOutcome = nil`; commit `feat(快速看图器增强-C.7): Overlay toast view + auto-dismiss + outcome 通过 onTrash 返回值回流`

- [ ] **C.8 Overlay 撤销逻辑接线**(`QuickViewerOverlay.swift`): handleUndoTrash 实现 — 由于撤销需要 Coordinator + 涉及 VM 数据回补, 走 `onUndoTrash: ((TrashOutcome) async -> Void)?` 新 callback 注入(mirror onTrash 注入路径); ContentView 接 callback 调 `quickViewerTrashCoordinator.restore(outcome:)`; 撤销成功后 toast 切「撤销完成」文案再 auto-dismiss(简单做 2 阶段, 不做单独 RestoreOutcome state); **注**: VM 的 `images` 不回补撤销图(快速看图器关后下次开依靠 FSEvents/scan 重建数据, 跟 M4 全局 banner 同 — R-images-mutation 选 (a) 接受短暂不一致); commit `feat(快速看图器增强-C.8): Overlay 撤销路径 — onUndoTrash callback + 2 阶段 toast`

- [ ] **C.9 MainQuickViewerWindowController 加 onUndoTrash 透传**(`MainQuickViewerWindowController.swift`): `show()` 签名加 `onUndoTrash: ((TrashOutcome) async -> Void)?` 参数 + 存成员 + 透传给 Overlay; commit `feat(快速看图器增强-C.9): MainQuickViewerWindowController.show 加 onUndoTrash 透传`

- [ ] **C.10 Overlay contextMenu 加「移到废纸篓」.destructive 项**(`QuickViewerOverlay.swift`): 在 B.5 加的 contextMenu 末尾追加: `Divider() + Button(role: .destructive) { handleTrashCurrent() } label: { Label("移到废纸篓 (⌫)", systemImage: DS.Icon.trash) }`; commit `feat(快速看图器增强-C.10): contextMenu 末加移到废纸篓 destructive 项`

- [ ] **C.11 ContentView wire onTrash + onUndoTrash + 装配 Coordinator**(`ContentView.swift`): (a) 加 `@StateObject private var quickViewerTrashCoordinator = QuickViewerTrashCoordinator()`; (b) `wireIfReady` 末尾调 `quickViewerTrashCoordinator.attach(indexStore: store, bridge: bridge)`; (c) `qvController.show(...)` callsite 加 `onTrash: { url in await quickViewerTrashCoordinator.trash(url: url) }` + `onUndoTrash: { outcome in _ = await quickViewerTrashCoordinator.restore(outcome: outcome) }`; commit `feat(快速看图器增强-C.11): ContentView 装配 QuickViewerTrashCoordinator + show callsite 接 onTrash/onUndoTrash`

- [ ] **C.12 schema gate**(V1 老 bookmark 防御): 跟 M4 任务 2 步骤 A.5 同模式, `handleTrashCurrent()` 前查 `bookmarkManager.currentSchemaVersion >= 2`; < 2 → toast 提示「需先升级 V2 才能删图」+ 不调 onTrash; 复用 M4 已 ship 的 BookmarkMigrationCoordinator 引导 UI? — 决策: **不复用引导 sheet**(快速看图器是模态全屏看图, 弹引导 sheet UX 突兀); 改用 toast 「重复清理走完升级后再回快速看图器删图」+ 关 toast; commit `feat(快速看图器增强-C.12): 快速看图器删图加 schemaVersion >= 2 gate 防 V1 老 bookmark scope 失败`

- [ ] **C.13 跑 `./scripts/verify.sh` 三段验**: 全过

- [ ] **C.14 CC 自闭环功能级验**: 复杂场景需军哥本机 — CC 这步只验「按 Delete 不崩 + handleTrashCurrent 走到 onTrash callback」(用 log 验或断点验), 不真删用户文件

- [ ] **C.15 PENDING 军哥本机真机验**(写入 PENDING-USER-ACTIONS.md): (a) 端到端: 快速看图器双击进 → Delete 真删图 + ~/.Trash 见文件 + DB row 删 + 自动跳下一张 + toast 出 + 撤销文件回原位 + 撤销后下次切回该图能再看到(看 FSEvents 是否补回 DB); (b) 删到最后一张 → 关快速看图器(D40); (c) V1 老 bookmark 图按 Delete → toast 提示走 V2 升级(C.12 gate); (d) 右键 contextMenu「移到废纸篓」点击同 Delete 行为; (e) ⌘⌫ 等同 Delete; commit `docs(快速看图器增强-C.15): 任务 C ship + CC 自闭环 + PENDING [docs-only]`

### 验证计划
- **CC 自闭环**: C.14 步, 主要验编译 + handleTrashCurrent 触发链路, 不真删文件
- **军哥本机 PENDING**: C.15 步 5 项(端到端/删空关窗/V1 gate/contextMenu/⌘⌫)
- **回滚**: 任务 C 改动较深(VM 改 mutable + 跨 5 文件), 回滚 = revert C.1..C.12 串; 若已部分 ship 但发现重大问题, 可单 revert ContentView wire (C.11) 让 UI 失活, 保留 Coordinator + VM 改造留 backlog 重做

---

## 实施记录回填表

(任务 ship 后回填 commit hash, mirror M4 任务 2 plan 末尾「Slice X 完成详细」表)

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
- [x] **Vertical slice**: 每任务独立 ship 用户可感知(A=旋转+信息; B=右键+复制+Finder; C=删除闭环); 任务 A/B 独立可用; 任务 C 等 A+B ship 后跟进
- [x] **Reality check 深到字段级**: 已 Read VM/Overlay/ZoomScrollView/MainQVController/TrashService 6 文件; 发现 `TrashService.trashItems([TrashInput])` 签名不是 design 写的 `[URL]` → 加 QuickViewerTrashCoordinator 适配层; 发现 `images: [URL]` 是 `let` → 任务 C 改 `private(set) var`; 发现 A.6 + B.4 都用 .onKeyPress("r") 需合并; 全部进 plan 风险表 + 步骤
- [x] **CLAUDE.md 术语字典**: plan 全文用「快速看图器」/「任务 A/B/C」, 禁用 Slice/VS/切片/QV/SF 等; 代码符号(`QuickViewer*`)豁免
- [x] **测试与验证**: 每任务标 CC 自闭环 + 军哥本机 PENDING 双层验证; verify.sh 三段嵌每任务收尾
- [x] **回滚方式**: 每任务列 revert 范围 + 部分回滚降级路径

---

## Execution Handoff

Plan 已写完(本文件), 接下来:

1. **codex:rescue 做 read-only review**(全局规则: plan 定稿必走 codex review 再交军哥) — 主 agent 接手做, 不在本 plan 范围
2. review 结论汇报军哥
3. 军哥拍板「go」后, 走 `superpowers:subagent-driven-development` skill, 任务 A → 任务 B → 任务 C 串行(或 A/B 并行+ C 等), 每任务 dispatch fresh subagent 实施, 主 agent 简短汇报 + 每步 build 绿 + commit 落地

(选择题 A 是 subagent-driven, 选 B 是 inline executing-plans, 项目偏好 subagent-driven — 详见 M4 任务 1/2 既有节奏)
