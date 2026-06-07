# Glance V2 M3 设计 — 搜索筛选 Chips

> 状态：design lock v2（2026-06-07，brainstorming 5 Q&A + 7 提案点 + codex review 吸收后产出）
> 上游：M3 全局搜索（`specs/v2/2026-05-11-m3-design.md`，D16-D20）；本文档是 M3 Slice M 的交互扩展
> 决策延续：M3 决策 D16-D20 → 本文档新增 D21-D27（写入 `specs/Roadmap.md`「关键架构决策」段）
> 触发动机：命令式 modifier（`type:png` / `size:>1mb` / `birth:>2026-01-01`）是 power user 语法，普通用户不会敲；需可视化「点选」入口

---

## 1. 一句话定位

在 M3 搜索 overlay 上叠一层**可视化筛选 chip**（类型 / 大小 / 时间三组），让普通用户**点选**而非敲命令；命令式语法保留给 power user 处理精确值。chip 底层复用既有 `SmartFolderAtom` 引擎，**SQL query builder 零改**（类型多选用现有 `.inSet`），仅 metadata / state / 触发层有 3 处小改（见 §4.3）。

---

## 2. 范围

### 2.1 做什么

1. **三组筛选 chip**：类型（多选）/ 大小（单选）/ 时间（单选），位于搜索输入框下方
2. **chip popover**：点 chip 弹出选项面板；类型 checkbox 多选，大小/时间单选
3. **独立筛选状态**：chip 选中态独立于输入框；输入框只管 keyword
4. **合并查询**：chip 状态 + keyword → 一条 query（全 AND + common filters，单点注入）
5. **即时触发**：chip 点选立即查询；keyword 仍 200ms debounce
6. **命令式共存**：命令式语法保留，缩小为 hint 行

### 2.2 不做什么（scope freeze）

- **自定义入口**（大小数字框 / 时间日期选择器）— 精确值走命令式
- **多于三组维度** — 留 M4
- **chip 状态持久化** — `openSearch` 即重置，⌘F 重开空白
- **chip + 命令式同维度冲突消解** — 都 AND，0 结果文案引导（D26）
- **类型 chip 的 case-insensitive** — chip 用与 DB 同源的标签值精确匹配，不需要

---

## 3. 决策（D21-D27，写入 Roadmap）

| ID | 决策 | 依据 |
|---|---|---|
| D21 | chip 三组维度 = 类型 / 大小 / 时间 | 1:1 映射现有 type/size/birth modifier |
| D22 | chip = 独立筛选状态（不写进输入框文字） | 分工清晰：chip=结构化筛选 / 输入框=自由 keyword；可单独清除某 chip |
| D23 | 类型多选用现有 `.inSet`，**SQL builder 零改** | `emitStringAtom` 已有 `.inSet` case（`column IN (?)`）；chip 用与 DB **同源**的标签值精确匹配 |
| D24 | 只预设档，精确值靠保留的命令式 | YAGNI；命令式给 power user 用武之地 |
| D25 | 布局 = 输入框 + chip 行 + 缩小命令式 hint | chip 给普通用户、hint 教 power user |
| D26 | chip + 命令式同维度冲突 = 都 AND，不特殊处理 | 罕见；0 结果文案已有引导，消解逻辑收益不抵复杂度 |
| D27 | `openSearch` 重置 + `closeSearch` 清空 chip 选中态 | 搜索是 ephemeral，重开空白心智一致 |

---

## 4. 模块架构

### 4.1 新增

| 文件 | 责任 |
|---|---|
| `Glance/Search/SearchFilterState.swift` | chip 选中态值类型：`selectedFormats: Set<String>` / `selectedSize: SizeBucket?` / `selectedTime: TimeBucket?` + 两 enum（档位→bytes / range）+ `isEmpty` + `toAtoms() -> [SmartFolderAtom]`。**「今天」档在此层预计算本地午夜 ISO**（见 §5.3）|
| `Glance/Search/SearchChipBar.swift` | chip 行 UI：三 chip 按钮 + 各 popover（类型 checkbox / 大小·时间单选）+ 选中态显示 + 单组清除；ESC/焦点交接见 §6 |

### 4.2 扩展

| 模块 | 改造 |
|---|---|
| `Glance/Search/SearchService.swift` | 新增 `compile(filterState:keyword:) -> SmartFolderPredicate` **单一出口**：common filters + `filterState.toAtoms()` + `parse(keyword).modifiers` + keyword 文本 OR，全 AND。**common filter 只在此处注入一次**（codex：避免调旧 compile 再套层导致三重叠加）|
| `Glance/Search/SearchOverlayView.swift` | 输入框行下插入 `SearchChipBar`；hint 行缩小；`@Binding filterState` + `onFilterChange`（即时触发）|
| `Glance/ContentView.swift` | `@State searchFilterState`；`runSearch` 改接收 keyword+filterState 合并，**early-exit 条件改 `keyword.isEmpty && filterState.isEmpty`**（codex：否则 chip-only 查询被挡）；task 内对 keyword+filterState 取**一致快照**（debounce 期间 filterState 可能被 chip tap 改）；`openSearch` 重置 filterState、`closeSearch` 清空（D27）|
| `Glance/IndexStore/ImageMetadataReader.swift` | `formatLabel` 改 **public/internal**（或提取 `static let canonicalFormatLabels: [String]`）作 chip 类型选项的**唯一权威来源**（codex：避免手写大写跟 DB 的 "WebP" 不一致）|

### 4.3 引擎改动盘点（修正「零改」）

| 层 | 改动 | 说明 |
|---|---|---|
| `SmartFolderQueryBuilder` | **零改** | `.inSet`/`emitIntAtom`/`emitTimeAtom` 全现成 |
| `ImageMetadataReader.formatLabel` | 公开化 | chip 标签同源（小改）|
| `SearchFilterState`（新）| 「今天」预计算本地午夜 ISO | 不新增 `resolveRelativeTime` token（codex：该 token 不存在，未知 token 静默返 now → 空结果）|
| `ContentView.runSearch` | early-exit 条件 + 快照 | 支持 chip-only 查询 |

> 诚实修正：design v1 说「引擎零改」过乐观。真相是 **SQL builder 零改**，但上述 3 处辅助层要动（codex review 抓出）。

---

## 5. 档位（D21 三组具体值）

### 5.1 类型（多选）
选项 = `ImageMetadataReader.formatLabel` 的标签集**原样**（`PNG · JPEG · HEIC · GIF · WebP · RAW`，注意 `WebP` 混合大小写）。选中 → `format inSet [选中标签]`，与 DB 存储**逐字符相等**，无需 NOCASE。chip 标签必须引用 `formatLabel` 同源常量，禁止手写。

### 5.2 大小（单选）
`>1MB · >5MB · >10MB`，decimal（1MB=1_000_000，与 `size:` modifier 一致）。选中 → `file_size > bucket.bytes`。

| 档 | bytes |
|---|---|
| >1MB | 1_000_000 |
| >5MB | 5_000_000 |
| >10MB | 10_000_000 |

### 5.3 时间（单选）
`今天 · 本周 · 本月 · 今年`，选中 → `birth_time betweenDuration [start, now]`。

| 档 | start | 实现 |
|---|---|---|
| 今天 | 当日 00:00（device local）| **`SearchFilterState` 层用 `Calendar.current.startOfDay(for:)` 算出 Date → ISO string** 直接塞进 `relativeTimeRange.start`；**不经** `resolveRelativeTime`（无此 token）|
| 本周 | `-7d` | 复用 `resolveRelativeTime` `-Nd`（与「本周新增」内置 SF 同源滚动窗）|
| 本月 | `-30d` | 同上 |
| 今年 | `-365d` | 同上 |

> end 统一 `now`。「今天」用日历午夜而非 -1d 更贴直觉；其余滚动窗。真机验后若用户期望自然边界再调（PENDING）。

---

## 6. UI / 布局（D25）+ popover 焦点/ESC（codex R4 补强）

```
┌──────────────────────────────────────────┐
│ 🔍 搜索...                              ✕  │   输入框行
│ [类型 ▾]  [大小 ▾]  [时间 ▾]                │   chip 行（新）
│ 提示：type:png · size:>3mb · birth:>日期    │   命令式 hint（缩小灰字）
└──────────────────────────────────────────┘
```

- chip 未选：`[类型 ▾]`；选中：`[类型: PNG +1 ▾]` 高亮 + 首值 + 计数
- popover：类型 checkbox 多选；大小/时间单选 list（再点已选 = 取消）；popover 内「清除本组」
- 用 SwiftUI 原生 `.popover`（系统管层级/dismiss）
- **ESC 两段语义**（codex：ESC 现绑 TextField，焦点在 popover 时不触发）：
  1. popover 开着 → ESC（或点外）先关 popover，焦点归还 TextField
  2. popover 关 / 无 popover → ESC 关 search overlay（现有 `onClose`）
- popover dismiss 后焦点显式回 `.search`（TextField），保证连续输入
- UI 常量走 `DS.Search.chip*`（新增）

---

## 7. 数据流

```
chip 点选 / keyword 输入
   │  chip → 即时；keyword → 200ms debounce（D24）
   ▼  runSearch(filterState:keyword:)：cancel 上个 task + 取 (keyword, filterState) 一致快照
   ▼  guard !(keyword.isEmpty && filterState.isEmpty) else { 清结果; return }   ← codex 修正
   ▼  SearchService.compile(filterState:keyword:)  ← common filter 单点注入
   │    AND( managed, hidden=false, dedupCanonicalOrNull,
   │         filterState.toAtoms()                      ← 类型 inSet / 大小 > / 时间 between
   │         parse(keyword).modifiers,                  ← 命令式仍在 keyword 内解析
   │         OR(filename LIKE, relative_path LIKE) )    ← keyword 文本（非空时）
   ▼  SmartFolderQueryBuilder.compile → IndexStore.fetch
   ▼  currentEphemeral = .search(...) → EphemeralResultView
```

- **触发**：chip 点选无 debounce 即时；keyword 仍 debounce；两路同一 `runSearch`，复用现有 `searchTask` cancel + `Task.isCancelled` guard。
- **冲突（D26）**：chip 类型=PNG + 命令式 `type:jpeg` → `format IN ('PNG') AND format='jpeg' COLLATE NOCASE` → 空。静默，0 结果文案引导。
- **命令式 type 大小写**：`type:` 的 `format eq` 已在 commit `d860b72` 加 `COLLATE NOCASE`，命令式单用正常。chip 走 `inSet`（同源标签精确匹配）。

---

## 8. 验收

1. 三段 verify 全绿，0 error 0 warning
2. 端到端：⌘F → 点类型选 PNG+JPEG → 即时出结果 → 点大小 >5MB → 收窄 → keyword 叠加 → 合并正确
3. **chip-only**（无 keyword 只点 chip）能查出结果（codex 修正点专项验）
4. **「今天」档**能查出今天的图（非空，验预计算午夜，codex 硬缺陷专项验）
5. **WebP chip** 能命中 WebP 图（验同源标签精确匹配）
6. 单独清某 chip / closeSearch 全清 / ⌘F 重开空白（D27）
7. popover ESC 两段 + 焦点归还（codex R4 专项验）
8. 命令式 + M2 找类似 + 纯 keyword 回归不退化
9. D21-D27 写入 Roadmap；CLAUDE.md 文件结构加新文件

---

## 9. Slice 拆分（留 writing-plans 细化）

- **Slice N1**：`SearchFilterState`（含「今天」预计算 + `toAtoms`）+ `formatLabel` 公开化 + `SearchService.compile(filterState:keyword:)` 合并 + `runSearch` early-exit/快照（端到端可跑：写死一组 filterState 验合并 + chip-only）
- **Slice N2**：`SearchChipBar` UI + popover（含 ESC 两段/焦点交接）+ 接入 overlay + 即时查 + 状态生命周期（用户可感知、可 ship 的完整交互）
- **Slice N3**（可选 polish）：单独清除 / 选中态视觉 / a11y

> 每片须满足端到端可跑 + 用户可感知 + 独立可 ship（CLAUDE.md 切片纪律）。

---

## 10. 已知风险

| # | 风险 | 缓解 |
|---|---|---|
| R1 | 时间「本周/本月」滚动窗 vs 用户预期自然边界 | 标滚动窗，真机验后按反馈调（PENDING）|
| R2 | chip + 命令式同维冲突致空结果 | D26 接受；0 结果文案引导 |
| R3 | 即时（chip）+ debounce（keyword）两路 stale 覆盖 | 复用 searchTask cancel；两路一致快照（codex）|
| R4 | popover 叠 overlay 的焦点/ESC | §6 两段 ESC + 焦点归还（codex 补强）|
| R5 | 类型标签集与 formatLabel 漂移 | chip 标签引用 formatLabel 同源常量；新增格式两处同步注释互指 |
| R6 | 「今天」token 不存在静默返 now → 空（codex 硬缺陷）| §5.3 在 filterState 层预计算午夜 ISO，不经 resolveRelativeTime |
| R7 | common filter 双重/三重叠加 | §4.2 单一出口注入（codex）|
| R8 | chip-only 被 early-exit 挡掉（codex）| runSearch 条件改 `keyword.isEmpty && filterState.isEmpty` |

---

## 11. Self-Review checklist

- [x] Placeholder scan：无 TBD/TODO 残留
- [x] 一致性：§4 架构 / §5 档位 / §7 数据流三处 atom 映射对齐
- [x] Scope：单 implementation plan 可承载（2-3 slice）
- [x] Ambiguity：D21-D27 依据明确；时间「今天」预计算 vs 滚动窗已显式区分
- [x] codex 吸收：7 点（标签同源 / 今天预计算 / chip-only early-exit / common filter 单点 / popover ESC / 状态生命周期 / 零改修正）全部落入 §4.2/§4.3/§5/§6/§7/§10
- [x] 「零改」诚实修正为「SQL builder 零改 + 3 处辅助层小改」
