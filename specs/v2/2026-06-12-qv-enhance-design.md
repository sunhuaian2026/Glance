# Glance V2 快速看图器 看图增强 设计 — 去重决策流的键盘驱动操作集

> 状态：design draft（2026-06-12，决策已与军哥拍板，本文档把它落成正式 design + reality check）
> 决策来源：脑暴定稿（范围/交互原则/具体交互均为定论，本文档不重新设计，只落架构 + 受影响点核对）
> 上游决策：`specs/v2/2026-05-06-v2-design.md`（D1-D10）/ `2026-05-10-m2-design.md`（D11-D14）/ Roadmap V2 决策段（D15-D27）/ `2026-06-10-m4-design.md`（D28-D32）
> 本文档新增决策：**D33-D40**（grep 确认现有最大 D 编号 = D32，往后排；D-OW 系列是 OpenWith 独立命名空间，不冲突）
> 下一步：codex review → `superpowers:writing-plans` 拆 task（逐符号 reality check）→ 实施 → 真机验
> 术语：见 `CONTEXT.md`；与 M4 关系见第 10 节

---

## 1. 一句话定位

> 把 快速看图器（看大图界面）从「纯欣赏」升级成「去重决策工作台」：看一张大图时，能**临时旋转/翻转**摆正、角落小字告诉你**分辨率·大小**（决定留大删小）、键盘一键**移废纸篓**、右键复制图片/路径/在 Finder 显示。全程键盘驱动、零新增可见按钮、不喧宾夺主——主角永远是图。

---

## 2. 范围

### 2.1 做什么（本设计 deliverables）

1. **临时旋转/翻转** — 快速看图器 内 L/R 旋转 90°、可选水平/垂直翻转。**临时**：关 快速看图器 还原，不改文件、不写 EXIF。
2. **删除（移废纸篓）** — 快速看图器 内 Delete / ⌘⌫ 把当前图移系统废纸篓，对齐 M4 的 `TrashService`，删后自动跳下一张。
3. **复制图片 / 复制路径 / 在 Finder 显示** — ⌘C 复制图片到剪贴板、⌘⌥C 复制文件路径、⌘⇧R 在 Finder 中显示。
4. **决策信息上屏** — 看大图时角落半透明小字常显 `分辨率 · 文件大小`（如 `4000×3000 · 2.5MB`），帮判断「留大删小」，不挡图。这是去重决策必需，普通看图 app 没有。
5. **右键菜单** — 把上述操作 + 旋转聚成一个 `contextMenu`，作为快捷键的可发现入口（快速看图器 当前无 contextMenu，新建）。
6. **删除反馈** — toast「已移废纸篓 [撤销]」，几秒消失，不常驻。

### 2.2 不做什么（scope freeze）

- **评分 / 收藏 / 标签** — 砍掉。那是「抢库」，违背 Glance「不抢库」红线（CONTEXT/Roadmap 红线）。
- **常驻底栏「去重控制台」** — 不在本设计内，**并入 M4**（M4 的 侧边栏 重复清理入口 + 总览，是「批量决策」视角；本设计是「单张连续决策」视角，两者互补，见第 10 节）。
- **持久旋转 / 写 EXIF / 改文件** — 旋转是临时态，关 快速看图器 即还原（D34）。不提供「保存旋转后的图」。
- **底部悬浮缩放工具栏加按钮** — 绝不往 Capsule 工具栏加任何按钮（D33）。所有新操作走键盘 + 右键菜单，屏幕零新增可见按钮。
- **批量删除 / 多选** — 快速看图器 是单张视图，一次删当前一张。批量走 M4 总览。
- **撤销栈 / 多步撤销** — 删除只给「最近一次」单步撤销 toast（mirror M4 D30），不做撤销历史。

---

## 3. 核心交互原则（最高优先，凌驾一切实现选择）

**不喧宾夺主**：

1. **主角是图**。去重清理本质是「快速连续决策流」（看一张 → 要不要 → 删/留 → 下一张），**键盘驱动为主**。
2. **零新增可见按钮**。所有新操作走 **键盘快捷键 + 右键菜单**。屏幕上不出现任何新的常驻按钮 / 图标。
3. **底部悬浮缩放工具栏（Capsule）保持不动，绝不往里加按钮**（D33）。它是悬浮的，加了就挤。现有结构（reality check 确认 QuickViewerOverlay.swift:280-331）：`适合⌘0 / 1:1·0 / 缩小⌘- / zoomPercent / 放大⌘= / [找相似图] / 全屏F`，本设计**一个不加**。
4. **信息上屏是唯一新增的常驻可见元素**，但它是**半透明小字、不可交互、不挡图**（角落 overlay，非按钮），是去重决策的必要信息，不违反「零按钮」原则。

---

## 4. plan-time 决策（D33-D40，编入 `specs/Roadmap.md` V2 决策段）

| ID | 决策 | 理由 |
|---|---|---|
| **D33** | **零新增可见按钮 + 底部 Capsule 工具栏冻结**。所有新操作只走快捷键 + 右键 `contextMenu`，底部缩放 Capsule 一个按钮不加。 | 不喧宾夺主核心原则；Capsule 悬浮，加按钮就挤；去重是键盘流，按钮反而拖慢连续决策。 |
| **D34** | **旋转/翻转 = 纯临时态，存活于 ViewModel 内存，关 快速看图器 / 切图即丢**。不改文件、不写 EXIF、不持久。旋转状态用 `rotationQuarterTurns: Int`（0-3，顺时针 90° 步进）+ `flippedH` / `flippedV: Bool`。 | 旋转只为「摆正了看清楚再决策」，不是编辑器。持久化 = 改用户文件 = 抢库风险 + sandbox 写权限复杂度，违背「只看」定位。切图丢旋转符合「每张独立决策」直觉。 |
| **D35** | **删除 = 移废纸篓，复用 M4 `TrashService`（同一套，不各做各的）**。快速看图器 删当前图 → `TrashService.trashItems([当前图])` → 删 DB row（若该图在 IndexStore）+ 自动导航下一张 + 可撤销 toast。 | M4 已设计 `TrashService.trashItems/restoreItems`（移废纸篓 + 撤销 + 跨 root scope）。快速看图器 删除是「单张版」，必须复用同一服务保证行为一致（同样移废纸篓、同样 DB 一致、同样撤销语义），否则两条删除路径漂移。 |
| **D36** | **信息上屏 = 角落半透明小字常显 `分辨率 · 文件大小`**，跟随 controls 自动隐藏（与顶栏/工具栏同 `controlsVisible` 节奏）。数据源 = `ImageMetadataReader.read(at:)`（已有，不解码像素，轻量）。 | 去重决策必需信息（留大删小）；放角落小字不挡图；跟随 controls 隐藏 = 鼠标静止后连同其他 UI 一起淡出，纯欣赏时不干扰。复用现成 metadata reader 避免重复读盘逻辑。 |
| **D37** | **右键 `contextMenu` 是快捷键的可发现镜像**。菜单项 = 旋转左/右 + 水平翻转/垂直翻转 + 复制图片 + 复制路径 + 在 Finder 显示 + 移到废纸篓，每项标注其快捷键（SwiftUI `Button` 自带 `.keyboardShortcut` 或在标题注明）。 | 快捷键不可见 → 用户发现不了。右键菜单是 macOS 原生「操作发现」入口，零屏幕占用（不点不出现），完美符合「零常驻按钮」。 |
| **D38** | **快捷键全部走 快速看图器 自己的 `.onKeyPress`（快速看图器 独立 NSWindow，与主窗快捷键不在同响应链，天然不冲突）**。新键：L / R（旋转）、Delete / ⌘⌫（删除）、⌘C（复制图片）、⌘⌥C（复制路径）、⌘⇧R（Finder 显示）、⌘I（信息浮层切换，可选）。 | reality check：快速看图器 已迁独立 NSWindow（`MainQuickViewerWindowController`），快速看图器 为 key 时主窗 SwiftUI 工具栏 的 `.keyboardShortcut("i")` 等不在响应链，快速看图器 内重定义同键不冲突（不同窗口/不同 first responder）。详见第 8 节冲突表。 |
| **D39** | **旋转影响渲染管线的全链路在 `ZoomScrollView` + `imageLayer` 里统一处理；90°/270° 旋转时 fitScale 宽高互换**。旋转改变有效显示尺寸 → 必须重算 `fitScale` / `clampOffset` / `canPan` 的「图尺寸」口径（见第 6 节受影响点）。 | reality check：VM 现无 rotation 状态，`fitScale`/`clampOffset`/`canPan` 全部基于 `image.size`。90/270° 后视觉宽=原高、视觉高=原宽，若不互换会算错 fit 比例和 pan 边界，图会越界或留错边。 |
| **D40** | **删除后导航策略 = 删当前图 → 跳下一张（无下一张则跳上一张，整组删空则关 快速看图器）**。被删 URL 从 `images` 数组移除（快速看图器 内 working copy），`currentIndex` 调整后 `loadCurrentImage`。 | 去重连续决策流：删了就该自动到下一张，不该停在空位让用户再按一下。mirror 常见看图 app 删除行为。 |

---

## 5. 模块架构

### 5.1 扩展模块（reality check：均已 Read 实际文件）

| 模块 | 改动 | reality check 锚点 |
|---|---|---|
| `QuickViewer/QuickViewerViewModel.swift` | 加旋转/翻转状态 + 操作方法 + 受影响的尺寸计算改造（第 6 节）。加「删当前图」working-copy 数组维护 + 导航调整（D40）。 | 现有：`images: [URL]`（let，**不可变** → 删除需改成 working copy，见 6.4）/ `currentIndex` / `scale` / `offset` / `baseScale` / `viewportSize` / `fitScale(for:in:)`（:169）/ `clampOffset()`（:177）/ `canPan`（:56）/ `goBack`/`goForward`/`goTo`/`resetToFit`。**现无 rotation 状态**。 |
| `QuickViewer/ZoomScrollView.swift` | 旋转的视觉变换在 SwiftUI `imageLayer` 应用（`.rotationEffect` + `.scaleEffect(x:y:)` 翻转），`ZoomScrollView`（NSView）只负责手势→VM，**渲染在 imageLayer 不在此**。本文件的 `scrollWheel`/`mouseDragged` anchor 计算若涉及旋转后坐标，需复核（见 6.3）。 | 现有：`scrollWheel`（:31，cursor anchor）/ `mouseDragged`（:64，pan delta）/ `mouseDown`（:48，双击 fit↔1:1）。NSView 不画图，画图在 Overlay 的 `imageLayer`（`Image(nsImage:).frame(w*scale,h*scale).offset()`，:209-218）。 |
| `QuickViewer/QuickViewerOverlay.swift` | 加：(a) 新 `.onKeyPress`（L/R/Delete/⌘⌫/⌘C/⌘⌥C/⌘⇧R/⌘I）；(b) `imageLayer` 加 `.rotationEffect`/翻转；(c) 信息上屏角落 overlay；(d) `contextMenu`；(e) toast 槽（删除反馈）。**底部 `bottomToolbar` 一行不改（D33）**。 | 现有：`.onKeyPress` 块（:157-186，ESC/space/←/→/⌘0/0/⌘=/⌘-/f/⌘f）/ `imageLayer`（:204-226）/ `bottomToolbar`（:280-331）/ `controlsVisible`（:30，auto-hide）/ `topBar`（:230）。无 `contextMenu`，无 toast。 |
| `QuickViewer/MainQuickViewerWindowController.swift` | 旋转/删除/复制操作所需的外部能力（如「删 DB row 的回调」「TrashService 注入」）按现有 `onDismiss`/`onIndexChange`/`onFindSimilar`/`onCommandF` 等闭包注入模式追加（避免 VM 直接依赖 IndexStore/TrashService）。 | 现有：快速看图器 已是独立无装饰 NSWindow 单例；Overlay 已有 5 个 `onXxx` 闭包注入口（onDismiss/onIndexChange/onFindSimilar/onCommandF/onToggleFullScreen，:11-27）。新能力沿用此 pattern。 |

### 5.2 复用模块（不改）

| 模块 | 复用点 |
|---|---|
| `IndexStore/ImageMetadataReader.swift` | `read(at:) -> ImageMetadata?`（:18）提供 `fileSize: Int64` / `dimensionsWidth: Int?` / `dimensionsHeight: Int?`（不解码像素）→ 信息上屏数据源（D36）。`ByteCountFormatter` 格式化字节（系统，非魔法数字）。 |
| `Dedup/TrashService.swift`（M4 新建） | `trashItems(...)` / `restoreItems(...)` → 快速看图器 删除复用（D35）。**依赖 M4 先落地 TrashService**（见第 10 节时序）。 |
| `DesignSystem.swift` | 信息上屏 / contextMenu 图标走 `DS.Icon.*`（已有 `trash`/`info`，旋转/翻转/复制图标按需加到 `DS.Icon`）；颜色/间距/圆角走 `DS.Color`/`DS.Spacing`/`DS.Toolbar.cornerRadius`；toast 时长复用 M4 拟定的 `DS.Dedup.undoToastDurationSeconds`（见第 10 节，M4 风险 1 已提出独立常量）。**禁硬编码**。 |

### 5.3 新增 DS 常量（待 writing-plans 精化，全部命名，禁魔法数字）

- `DS.Icon.rotateLeft` / `rotateRight`（如 `rotate.left` / `rotate.right`）、`flipHorizontal` / `flipVertical`、`copy`（如 `doc.on.doc`）、`copyPath`、`finder`（如 `arrow.right.doc.on.clipboard` 或 `magnifyingglass`，待定）。
- `DS.Viewer.infoBadgeOpacity`（信息上屏背景透明度）、`DS.Viewer.infoBadgeCornerRadius`、信息上屏的 padding（复用 `DS.Spacing.*`）。
- 旋转步进角度 90° 用命名常量（如 `DS.Viewer.rotationStepDegrees = 90`），不裸写 90。

---

## 6. 旋转 — VM 改动 + 受影响点（D39 核心，最高实现风险）

> reality check 关键结论：VM 现在**完全没有 rotation 概念**，`fitScale`/`clampOffset`/`canPan`/`imageLayer` 全部假设「显示尺寸 = image.size」。加旋转后，90°/270° 时**视觉宽高互换**，所有用到 `image.size.width/height` 的地方都要按「有效显示尺寸」改。这是本设计最容易出 bug 的点，逐个列清。

### 6.1 新增状态（VM）

```
@Published var rotationQuarterTurns: Int = 0   // 0/1/2/3，顺时针 90° 步进
@Published var flippedH: Bool = false
@Published var flippedV: Bool = false
```

- `rotateLeft()` → `rotationQuarterTurns = (rotationQuarterTurns + 3) % 4`（逆时针）+ 重算尺寸相关态。
- `rotateRight()` → `rotationQuarterTurns = (rotationQuarterTurns + 1) % 4` + 重算。
- `toggleFlipH()` / `toggleFlipV()` → 翻转布尔取反（翻转不改宽高，不影响 fit/pan 边界，只影响渲染镜像）。
- 切图（`goBack`/`goForward`/`goTo`）时**重置旋转/翻转为 0/false**（D34 临时态 + 每张独立）。`resetToFit` 一并处理或单列 `resetRotation()`。

### 6.2 有效显示尺寸 helper（受影响点的统一口径）

新增计算属性，**所有原先读 `image.size` 算 fit/pan 边界的地方改读这个**：

```
// 旋转后图在屏幕上占的「有效尺寸」：90/270° 宽高互换，0/180° 不变。
func effectiveImageSize(_ image: NSImage) -> CGSize {
    let isQuarterRotated = (rotationQuarterTurns % 2 == 1)
    return isQuarterRotated
        ? CGSize(width: image.size.height, height: image.size.width)
        : image.size
}
```

### 6.3 逐个受影响点（writing-plans 必须逐项改 + reality check）

| 受影响 | 现状（行号） | 旋转后改动 |
|---|---|---|
| `fitScale(for:in:)` | :169，用 `image.size.width/height` 算 fit 比例 | 改用 `effectiveImageSize`（90/270° 宽高互换后才能算对 fit），否则横图竖放会算错缩放。 |
| `clampOffset()` | :177，`scaledW = image.size.width * scale` | `scaledW/H` 改用 `effectiveImageSize` × scale，否则 pan 边界算错，旋转后能拖出界或拖不到边。 |
| `canPan` | :56，`scale > fitScale(...)` | fitScale 已改 → 自动正确，但确认其内部 `image.size` 也已切到 effective。 |
| `imageLayer` 渲染 | Overlay :209-218，`.frame(w*scale,h*scale).offset()` | 加 `.rotationEffect(.degrees(Double(rotationQuarterTurns)*90))` + `.scaleEffect(x: flippedH ? -1:1, y: flippedV ? -1:1)`。**frame 仍用原始 `image.size`**（rotationEffect 绕中心转，SwiftUI 自动算 bounding box）；offset 仍是 VM.offset。**顺序**：先 frame → rotationEffect → scaleEffect → offset，需在 writing-plans 实测层叠顺序（rotation 与 scaleEffect 翻转的组合次序会影响视觉，先转后镜像 vs 先镜像后转结果不同）。 |
| `setScale(anchor:viewSize:)` | VM :120，cursor-anchored zoom | anchor 是 viewport 坐标，与旋转无关（旋转在渲染层，viewport 坐标系不变）→ **大概率不用改**，但 writing-plans 实测旋转 90° 后滚轮缩放锚点是否仍跟手（若偏移，说明 anchor 需按旋转逆变换，列为风险 R-rotate-anchor）。 |
| `scrollWheel`/`mouseDragged` anchor | ZoomScrollView :39/:64 | NSView bounds 坐标系不随旋转变（旋转在 SwiftUI imageLayer，不在 NSView）→ 同上，预期不改，写 plan 时实测验证。 |
| `applyViewportSize`/`onImageLoaded` | VM :147/:156，fit 重算 | 内部调 `fitScale`，fitScale 改了即正确；确认这两处也走 effective 口径。 |

### 6.4 删除导致 `images` 不可变问题（D40 连带）

- reality check：`QuickViewerViewModel.images` 是 `let`（:18，不可变），`prefetchCache`/导航全基于固定数组。
- 删除当前图需从可见序列移除该 URL → **方案**：`images` 改 `private(set) var`（仍对外只读），加 `removeCurrent()`：删数组元素 + 调整 `currentIndex`（D40 导航策略）+ 清该 idx 的 prefetch + 重新 `loadCurrentImage`。
- **风险 R-images-mutation**：`images` 是 `init` 时从 caller（ContentView 的 `computeV2Urls` 等）传入的快照。快速看图器 内删除后，**caller 侧的源数组不会同步**（快速看图器 working copy 与 grid 数据分离）。关 快速看图器 回到 grid 时，grid 仍显示已删图直到下次 scan/FSEvents 刷新。这是「快速看图器 删除」与「grid 视图」的一致性边界，需 writing-plans 决策：(a) 接受短暂不一致（FSEvents 会刷）；或 (b) 删除时通过 `onIndexChange`-style 回调通知 caller 同步移除。倾向 (a)（M4 删除也靠 FSEvents 最终一致），但列此供 review。

---

## 7. 信息上屏（D36）

- **位置**：快速看图器 角落（建议左下或右下，避开顶栏文件名气泡与底部 Capsule；writing-plans 实测哪个角不撞导航 navButton），半透明小字气泡（mirror `topBar` 的 `Color(white:0,opacity:0.35)` 气泡风格，:255）。
- **内容**：`\(width)×\(height) · \(ByteCountFormatter().string(fromByteCount: fileSize))`，如 `4000×3000 · 2.5MB`。无 metadata（读失败）→ 隐藏整个气泡（不显「未知」噪声）。
- **数据源**：当前图 URL → `ImageMetadataReader.read(at:)`（:18，不解码像素，磁盘只读元数据，轻量）。在后台 Task 读，避免阻塞主线程（mirror VM 现有 `Task.detached` load 模式）。切图时重读。
- **可见性**：跟随 `controlsVisible`（:30）—— 鼠标静止 auto-hide 时连同顶栏/工具栏一起淡出（`.opacity(controlsVisible ? 1 : 0)`），纯欣赏不干扰。
- **不可交互**：`.allowsHitTesting(false)`，纯展示，不抢手势/焦点。

---

## 8. 快捷键全表 + 冲突核对（reality check 已 grep 全项目）

> 核对方法：`grep -rn "onKeyPress\|keyboardShortcut"` 全项目（见 reality check）。快速看图器 是**独立 NSWindow**，快速看图器 为 key 时主窗 SwiftUI `.keyboardShortcut` 不在响应链 → 快速看图器 内 `.onKeyPress` 自管，与主窗/其他 view 的键**不冲突**（不同窗口 first responder）。下表「冲突」列只看 **快速看图器 自身 onKeyPress 块**（QuickViewerOverlay.swift:157-186）内是否已占用。

### 8.1 快速看图器 现有已占用键（不可动）

| 键 | 现行为 | 行号 |
|---|---|---|
| ESC / Space | dismiss 或退全屏 | :157-158 |
| ← / → | 上/下一张 | :159-160 |
| 0 | 1:1 | :161-168 |
| ⌘0 | 适合窗口 | :161-168 |
| ⌘= | 放大 | :169 |
| ⌘- | 缩小 | :173 |
| F | 全屏切换 | :179-186 |
| ⌘F | 找相似图/搜索（onCommandF） | :179-186 |

### 8.2 本设计新增键（冲突核对结果）

| 键 | 新行为 | 与 快速看图器 现有键冲突？ | 核对结论 |
|---|---|---|---|
| **L** | 旋转左（逆时针 90°） | 否（快速看图器 未占用裸 L） | ✅ 安全 |
| **R** | 旋转右（顺时针 90°） | 否（快速看图器 未占用裸 R） | ✅ 安全 |
| **Delete**（⌫ / forwardDelete） | 移废纸篓 | 否 | ✅ 安全。建议同时绑 `.delete` 与 `.deleteForward` 两个 KeyEquivalent 容错。 |
| **⌘⌫**（⌘+Delete） | 移废纸篓（macOS 习惯键，与 Delete 等价） | 否 | ✅ 安全。Finder「移到废纸篓」标准键，符合用户肌肉记忆。 |
| **⌘C** | 复制图片到剪贴板 | 否 | ✅ 安全 |
| **⌘⌥C** | 复制文件路径 | 否 | ✅ 安全 |
| **⌘⇧R** | 在 Finder 中显示 | 否 | ✅ 安全 |
| **⌘I** | 信息浮层切换（可选；信息默认常显，⌘I 可做「钉住/展开更多」或切换显隐） | 否（快速看图器 块内未占用 I；主窗 ⌘I 是另一窗口的 Inspector，不同响应链不冲突，见下注） | ✅ 安全，但**语义待定**（见风险 R-cmdI） |

> **⌘I 跨窗口说明**：主窗 `ContentView` 有 `.keyboardShortcut("i", .command)` 打开 Inspector（ContentView.swift:208），但那挂在 NavigationSplitView 工具栏 上、属主窗响应链。快速看图器 是独立 NSWindow，快速看图器 为 key 时主窗那个 ⌘I 不触发。快速看图器 内可安全重定义 ⌘I。两者不会同时活跃（不同窗口为 key）。

> **裸 L / R 与文本输入**：快速看图器 内无文本输入框（搜索框 ⌘F 走的是主窗 overlay，快速看图器 关掉后才浮），裸字母键不会误触输入，安全。

---

## 9. 右键菜单结构（D37，快速看图器 新建 contextMenu）

挂在 快速看图器 主图区（`ZoomScrollView` overlay 或整个 ZStack）。SwiftUI `contextMenu`，每项 `Button` 标题含快捷键提示（如 `Label("旋转右", systemImage: …)` + 注 `R`）：

```
旋转左            L
旋转右            R
─────────
水平翻转
垂直翻转
─────────
复制图片          ⌘C
复制路径          ⌘⌥C
在 Finder 中显示   ⌘⇧R
─────────
移到废纸篓         ⌫        (destructive 角色，红色)
```

- 「移到废纸篓」用 `.destructive` role（系统红色），与其他项视觉区分。
- 翻转两项不标快捷键（翻转较少用，只走右键；旋转更常用故给 L/R）—— 待军哥确认是否也给翻转快捷键（见风险 R-flip-keys）。
- contextMenu 不点不出现 → 零屏幕常驻占用，符合 D33。

---

## 10. 与 M4 的关系（删除统一 + 常驻底栏归属）

| 维度 | 快速看图器 增强（本设计） | M4（重复清理） | 关系 |
|---|---|---|---|
| 视角 | 单张连续决策（看一张 → 删/留 → 下一张） | 批量决策（一张总览，整组勾选一键删） | **互补**，非重复 |
| 删除实现 | 复用 M4 `TrashService.trashItems/restoreItems`（D35） | 定义 `TrashService`（M4 4.1） | **共用同一服务**，行为一致（移废纸篓 + 撤销 + DB 一致） |
| 撤销 toast | 「已移废纸篓 [撤销]」单张版 | 「已移 N 张到废纸篓 [撤销]」批量版 | 同 D30 语义，同 `DS.Dedup.undoToastDurationSeconds` 常量 |
| 常驻底栏「去重控制台」 | **不做，归 M4** | M4 侧边栏 入口 + 主区总览承载 | 本设计明确不碰常驻底栏 |
| DB 一致 | 删 DB row（若图在 IndexStore）+ reEvaluate 受影响组 | 同套（deleteImage + reEvaluateGroup） | 复用 M4 已设计的 IndexStore CRUD |

> **时序依赖（关键）**：本设计的删除（D35）**依赖 M4 的 `TrashService` 先落地**。`TrashService` 是 M4 任务 2 的 deliverable（M4 design 8.2，"全项目首个碰真实文件的代码"）。
> **建议实施顺序**：旋转/翻转 + 信息上屏 + 复制/路径/Finder + 右键菜单（不依赖 TrashService）可先做、独立 ship；**删除（D35/D40）排在 M4 任务 2 之后**，或与 M4 任务 2 合并实施。writing-plans 阶段按此切 任务，把「删除」单独成片置于 TrashService 就绪后（风险前置 + 不阻塞前 4 项）。

---

## 11. 错误处理边界

| 场景 | 处理 |
|---|---|
| **删除：security scope 失效 / bookmark stale** | 复用 M4 `TrashService` 的错误语义（M4 第 6 节）：该图标失败，不删 DB row，toast 提示失败原因（盘未连接？）。 |
| **删除：文件已被外部删除** | `FileManager.trashItem` 抛 `NSFileNoSuchFileError` → 视作已不占空间，仍从 快速看图器 `images` 移除 + 删 DB row（清 stale），导航下一张。 |
| **删除整组删空 / 删到最后一张** | D40：无下一张跳上一张；`images` 空 → 关 快速看图器（`onDismiss`）。 |
| **旋转后缩放重算** | 旋转触发 `effectiveImageSize` 变化 → 必须重跑 `fitScale`（若当前 `zoomMode == .fit`，缩放比例要更新）+ `clampOffset`（pan 边界重算）。**旋转时若处于 custom zoom，是否重置回 fit**？倾向旋转保持当前 zoom 但重 clamp（不强制回 fit，避免打断观察）；待 writing-plans 实测 custom zoom 下旋转的 offset 是否需重映射（见风险 R-rotate-zoom）。 |
| **信息上屏：metadata 读失败** | 隐藏整个信息气泡，不显「未知」（D36）。 |
| **复制图片：当前图未加载完 / 加载失败** | `currentNSImage == nil` → ⌘C / contextMenu「复制图片」disable 或 no-op；复制路径/Finder 显示仍可用（只需 URL，不需解码）。 |
| **在 Finder 显示：文件已删** | `NSWorkspace.activateFileViewerSelecting` 对不存在路径 → 系统静默/弹 Finder 空窗，toast 提示「文件不存在」。 |
| **旋转/翻转无图时按 L/R** | `currentNSImage == nil` → no-op（旋转状态可改但无渲染目标，切图重置，无害）。 |

---

## 12. 任务 拆分（writing-plans 阶段精化，此处给倾向）

> vertical 任务 三标准：端到端可跑 + 用户可感知 + 独立可 ship。倾向把「不依赖 TrashService」的能力先 ship。

- **任务 1 — 旋转/翻转 + 信息上屏**（不碰文件，最安全）：L/R 旋转、翻转、`effectiveImageSize` 全链路改造、角落信息气泡。端到端：快速看图器 内按 L 图转 90° + 角落显分辨率·大小。用户可感知：摆正看图 + 决策信息。独立 ship：纯渲染/读元数据，零风险。
- **任务 2 — 复制图片 / 复制路径 / 在 Finder 显示 + 右键菜单**（只读 + 系统能力，不删文件）：⌘C/⌘⌥C/⌘⇧R + contextMenu（含旋转项）。端到端：右键菜单可见所有操作 + 复制/Finder 生效。独立 ship：不依赖 TrashService。
- **任务 3 — 删除（移废纸篓）**：依赖 M4 `TrashService` 就绪。Delete/⌘⌫ + 撤销 toast + DB 一致 + 导航下一张。**排在 M4 任务 2 之后或合并**。端到端：快速看图器 内 ⌫ 图进废纸篓 + 自动下一张 + 可撤销。

---

## 13. 待军哥确认的风险（Read 代码后发现，未擅自改决策）

> 决策本身（范围/交互原则/具体交互）是定论，未推翻。以下是实现层面的待定项 + 与现有架构的潜在摩擦，供拍板/codex review。

1. **R-rotate-anchor — 旋转后滚轮/手势缩放锚点是否跟手**：`setScale(anchor:viewSize:)`（VM :120）与 `scrollWheel`（ZoomScrollView :39）的 anchor 是 viewport 坐标。旋转在 SwiftUI imageLayer（`.rotationEffect`），NSView bounds 坐标系不随旋转变 → 预期锚点仍对（旋转在渲染层之上）。但 90°/270° 后图的「内容朝向」与坐标系错开，滚轮缩放锚点是否仍视觉跟手需**真机实测**。若偏移，需对 anchor 做旋转逆变换。**建议**：任务 1 真机验「旋转 90° 后滚轮缩放锚点跟不跟手」，列 PENDING。

2. **R-rotate-zoom — custom zoom 状态下旋转的 offset 重映射**：旋转时若处于放大平移态（custom zoom + 非零 offset），旋转 90° 后 offset 的 x/y 语义与图内容错位（原来往右看的内容旋转后变往下）。**两选项**：(a) 旋转时若 `zoomMode == .custom` 则重置回 fit（简单，但打断观察）；(b) 旋转时把 offset 按 90° 旋转重映射（体验好，复杂）。倾向 (a) 先做、(b) 列 backlog。待拍板。

3. **R-images-mutation — 快速看图器 删除后与 grid 数据一致性**（第 6.4 节）：`images` 是 caller 传入快照，快速看图器 内删除不同步回 grid 源数组。关 快速看图器 回 grid 仍显示已删图直到 FSEvents/scan 刷新。倾向接受短暂不一致（M4 删除同样靠 FSEvents 最终一致），但若军哥要求即时同步，需加 caller 回调。待拍板。

4. **R-cmdI — ⌘I 语义未定**：信息上屏默认常显（跟 controls 隐藏）。那 ⌘I 做什么？选项：(a) 切换信息气泡显隐（默认显，⌘I 钉住/隐藏）；(b) 打开完整 EXIF inspector（复用 `ImageInspectorViewModel`，但 快速看图器 是独立窗，inspector 是主窗 SwiftUI，跨窗实现复杂）；(c) 本设计不做 ⌘I，信息常显即够。**倾向 (c) 或 (a)**——(b) 跨窗成本高、且「完整 EXIF」偏离「去重决策只需分辨率·大小」初心。待拍板。

5. **R-flip-keys — 翻转是否给快捷键**：当前设计旋转给 L/R、翻转只走右键菜单（翻转较少用）。是否也给翻转快捷键（如 ⇧L/⇧R 或 H/V）？倾向不给（避免键位膨胀），待军哥确认。

6. **R-trashservice-dep — 删除依赖 M4 TrashService 时序**（第 10 节）：快速看图器 删除（D35）必须等 M4 `TrashService` 落地。若军哥希望 快速看图器 删除先于 M4 完整交付上线，需把 `TrashService` 从 M4 任务 2 提前抽出独立先做。倾向按第 12 节顺序（快速看图器 任务 1/2 先 ship，删除 任务 3 跟 M4 任务 2 节奏）。待拍板实施顺序。

7. **R-rotate-render-order — rotationEffect 与 flip scaleEffect 层叠顺序**（第 6.3 节）：`.rotationEffect` 与 `.scaleEffect(x:-1)`（翻转）的应用次序影响视觉结果（先转后镜像 ≠ 先镜像后转）。需 writing-plans 阶段实测定序并固化，避免「旋转+翻转组合」出非预期镜像。属实现细节，列此供 review 知悉。
