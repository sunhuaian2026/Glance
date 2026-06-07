# Glance V2 M3 设计 — 搜索筛选 Chips

> 状态：design lock（2026-06-07，brainstorming 5 Q&A + 7 提案点确认后产出）
> 上游：M3 全局搜索（`specs/v2/2026-05-11-m3-design.md`，D16-D20）；本文档是 M3 Slice M 的交互扩展
> 决策延续：M3 决策 D16-D20 → 本文档新增 D21-D27（写入 `specs/Roadmap.md`「关键架构决策」段）
> 触发动机：命令式 modifier（`type:png` / `size:>1mb` / `birth:>2026-01-01`）是 power user 语法，普通用户不会敲；需可视化「点选」入口

---

## 1. 一句话定位

在 M3 已有的搜索 overlay 上叠一层**可视化筛选 chip**（类型 / 大小 / 时间三组），让普通用户**点选**而非敲命令；命令式语法保留给 power user 处理精确值。chip 选项底层复用既有 `SmartFolderAtom` 引擎，**类型多选用现有 `.inSet`、引擎零改**。

---

## 2. 范围

### 2.1 做什么

1. **三组筛选 chip**：类型（多选）/ 大小（单选）/ 时间（单选），位于搜索输入框下方
2. **chip popover**：点 chip 弹出选项面板；类型 checkbox 多选，大小/时间单选
3. **独立筛选状态**：chip 选中态独立于输入框；输入框只管 keyword
4. **合并查询**：chip 状态 + keyword → 合并成一条 query（全 AND + common filters）
5. **即时触发**：chip 点选立即查询；keyword 仍 200ms debounce
6. **命令式共存**：命令式语法保留，缩小为 hint 行（教 power user）

### 2.2 不做什么（scope freeze）

- **自定义入口**（大小数字框 / 时间日期选择器）— 精确值走命令式（`size:>3mb` / `birth:2026-03-15`）
- **多于三组维度**（像素尺寸 / 收藏 / 来源文件夹）— 留 M4
- **chip 状态持久化** — `closeSearch` 即清空，⌘F 重开空白（搜索是 ephemeral）
- **chip + 命令式同维度的冲突消解** — 都 AND，用户负责（D26）
- **类型多选的 case-insensitive** — chip 用 DB 大写标签精确匹配，不需要

---

## 3. 决策（D21-D27，写入 Roadmap）

| ID | 决策 | 依据 |
|---|---|---|
| D21 | chip 三组维度 = 类型 / 大小 / 时间 | 1:1 映射现有 type/size/birth modifier，引擎复用最大化 |
| D22 | chip = 独立筛选状态（不写进输入框文字） | 分工清晰：chip=结构化筛选 / 输入框=自由 keyword；选中态高亮直观、可单独清除某 chip |
| D23 | 类型多选用现有 `.inSet`，引擎零改 | `emitStringAtom` 已有 `.inSet` case（`column IN (?)`）；chip 用 DB 大写标签（"PNG"/"WebP"）精确匹配，无需 NOCASE |
| D24 | 只预设档，精确值靠保留的命令式 | YAGNI；命令式刚好有 power user 用武之地，两层用户各取所需 |
| D25 | 布局 = 输入框 + chip 行 + 缩小命令式 hint | chip 给普通用户、hint 教 power user，两层都照顾 |
| D26 | chip + 命令式同维度冲突 = 都 AND，不特殊处理 | 罕见（同时点 chip 类型=PNG 又敲 type:jpeg）；特殊消解逻辑收益不抵复杂度 |
| D27 | `closeSearch` 清空 chip 选中态 | 搜索是 ephemeral 视图，重开空白心智一致 |

---

## 4. 模块架构

### 4.1 新增

| 文件 | 责任 |
|---|---|
| `Glance/Search/SearchFilterState.swift` | chip 选中态值类型：`selectedFormats: Set<String>` / `selectedSize: SizeBucket?` / `selectedTime: TimeBucket?` + `SizeBucket`/`TimeBucket` enum（封装档位 → bytes / range token）+ `isEmpty` + `toAtoms() -> [SmartFolderAtom]` |
| `Glance/Search/SearchChipBar.swift` | chip 行 UI：三个 chip 按钮 + 各自 popover；多选 checkbox / 单选 list；选中态显示（"类型: PNG +1 ▾"） |

### 4.2 扩展

| 模块 | 改造 |
|---|---|
| `Glance/Search/SearchService.swift` | `compile` 重载/扩展：接收 `(filterState: SearchFilterState, keyword: String)`，把 chip atoms + keyword parse 结果合并成 `SmartFolderPredicate`（全 AND + common filters）。原 `parse(_:)` 保留（命令式仍在 keyword 内解析） |
| `Glance/Search/SearchOverlayView.swift` | 输入框行下方插入 `SearchChipBar`；hint 行缩小为命令式提示；新增 `@Binding filterState` + `onFilterChange` callback（即时触发查询） |
| `Glance/ContentView.swift` | 新增 `@State searchFilterState: SearchFilterState`；`runSearch` 改为接收 keyword + filterState 合并；`openSearch`/`closeSearch` 初始化/清空 filterState（D27） |

### 4.3 引擎（零改确认）

- 类型多选：`SmartFolderAtom(field: .format, op: .inSet, value: .stringArray(["PNG","JPEG"]))` → `SmartFolderQueryBuilder.emitStringAtom` 既有 `.inSet` case 输出 `format IN (?,?)`。chip 选项值用 `ImageMetadataReader.formatLabel` 的大写标签，与 DB 存储一致，精确匹配无需 NOCASE。
- 大小单选：`.fileSize greaterThan .int(bucket.bytes)` → 既有 `emitIntAtom`
- 时间单选：`.birthTime betweenDuration .relativeTimeRange(...)` → 既有 `emitTimeAtom` + `resolveRelativeTime`

**结论：QueryBuilder 一行不改。** 全部走既有 emit。

---

## 5. 档位（D21 三组具体值）

### 5.1 类型（多选）
`PNG · JPEG · HEIC · GIF · WebP · RAW`（取 `ImageMetadataReader.formatLabel` 标签集，大写原样）。选中 → `format inSet [选中标签]`。

### 5.2 大小（单选）
`>1MB · >5MB · >10MB`，decimal 单位与 `size:` modifier 一致（1MB=1_000_000）。选中 → `file_size > bucket.bytes`。

| 档 | bytes |
|---|---|
| >1MB | 1_000_000 |
| >5MB | 5_000_000 |
| >10MB | 10_000_000 |

### 5.3 时间（单选）
`今天 · 本周 · 本月 · 今年`，滚动窗语义（复用 `resolveRelativeTime` 的 `-Nd` token），选中 → `birth_time betweenDuration [start, now]`。

| 档 | range start token | 语义 |
|---|---|---|
| 今天 | 当日 00:00（device local） | 今天创建 |
| 本周 | `-7d` | 近 7 天（与「本周新增」内置 SmartFolder 同源滚动窗，避免双轨歧义）|
| 本月 | `-30d` | 近 30 天 |
| 今年 | `-365d` | 近 365 天 |

> 「今天」用当日 00:00 而非 `-1d`，更贴用户直觉；其余用滚动窗。真机验后若用户期望自然边界（本周=周一起 / 本月=1 号起）再调，留 PENDING。

---

## 6. UI / 布局（D25）

```
┌──────────────────────────────────────────┐
│ 🔍 搜索...                              ✕  │   输入框行（现有）
│ [类型 ▾]  [大小 ▾]  [时间 ▾]                │   chip 行（新）
│ 提示：type:png · size:>3mb · birth:>日期    │   命令式 hint（缩小灰字）
└──────────────────────────────────────────┘
```

- chip 未选中：`[类型 ▾]` 中性态；选中：`[类型: PNG +1 ▾]` 高亮 + 显首个值 + 计数
- 点 chip 弹 popover：类型 = checkbox 多选；大小 / 时间 = 单选 list（再点已选项 = 取消）
- chip 右侧选中态可点 × 单独清除该组（或 popover 内「清除」）
- 所有 UI 常量走 `DS.*`（新增 `DS.Search.chip*` 段）

---

## 7. 数据流

```
chip 点选 / keyword 输入
   │
   ▼  chip → 即时；keyword → 200ms debounce（D24 触发时机）
   │
   ▼  SearchService.compile(filterState:, keyword:)
   │    atoms = common filters(managed/hidden/dedup)
   │          + filterState.toAtoms()         ← 类型 inSet / 大小 > / 时间 between
   │          + parse(keyword).modifiers      ← 命令式仍在 keyword 内解析
   │          + keyword 文本 OR(filename, relative_path)
   │    全部 AND
   │
   ▼  SmartFolderQueryBuilder.compile → IndexStore.fetch
   │
   ▼  currentEphemeral = .search(...)  → EphemeralResultView
```

- **触发**：chip 点选走无 debounce 的即时查询路径；keyword onChange 仍 debounce。两路最终都调同一 `runSearch(filterState:keyword:)`。
- **冲突（D26）**：chip 类型=PNG + 命令式 `type:jpeg` → `format IN ('PNG') AND format = 'jpeg'` → 空。不消解。
- **空查询**：filterState 与 keyword 全空 → 跳查询（沿用现有 isEmpty guard），EphemeralResultView 显 hint 空态。

---

## 8. 验收

1. 三段 verify 全绿，0 error 0 warning
2. 端到端：⌘F → 点「类型」选 PNG+JPEG → 即时出结果 → 点「大小 >5MB」→ 结果收窄 → keyword 叠加 → 合并正确
3. 单独清某 chip / closeSearch 全清（D27）
4. 命令式回归：保留的 `type:`/`size:`/`birth:` + keyword 仍正常
5. M2 找类似、纯 keyword 搜索不退化
6. D21-D27 写入 Roadmap；CLAUDE.md 文件结构加 `SearchFilterState.swift` / `SearchChipBar.swift`

---

## 9. Slice 拆分（留 writing-plans 细化）

按 vertical slice 初步设想（writing-plans 阶段定稿）：

- **Slice N1**：`SearchFilterState` + `SearchService.compile(filterState:keyword:)` 合并逻辑（端到端可跑：先用一组写死的 filterState 验证 query 合并正确）
- **Slice N2**：`SearchChipBar` UI + popover + 接入 overlay，三组 chip 点选即时查（用户可感知、可 ship 的最小完整交互）
- **Slice N3**（可选 polish）：单独清除 / 选中态视觉打磨 / a11y

> 每片须满足端到端可跑 + 用户可感知 + 独立可 ship（CLAUDE.md 切片纪律）。

---

## 10. 已知风险

| # | 风险 | 缓解 |
|---|---|---|
| R1 | 时间「本周/本月」滚动窗 vs 用户预期自然边界不一致 | design 标滚动窗，真机验后按反馈调（PENDING）；与「本周新增」内置 SF 同源减少歧义 |
| R2 | chip + 命令式同维度冲突致空结果，用户困惑 | D26 接受；0 结果文案已有「检查拼写或减少 modifier」引导 |
| R3 | 即时触发（chip）+ debounce（keyword）两路并发 stale 覆盖 | 复用现有 searchTask cancel 机制；chip 路径也 cancel 在途 task |
| R4 | popover 在 overlay（顶层 zIndex）上再叠层，焦点/ESC 层级 | popover 用 SwiftUI 原生 `.popover`（系统管理层级/dismiss），不自建 overlay 层 |
| R5 | 类型标签集与 formatLabel 漂移（新增格式 chip 漏列） | chip 标签集与 `formatLabel` 同源；新增格式时两处同步（加 TODO 注释互指）|

---

## 11. Self-Review checklist

- [x] Placeholder scan：无 TBD/TODO 残留
- [x] 一致性：§4 架构 / §5 档位 / §7 数据流三处 atom 映射对齐
- [x] Scope：单 implementation plan 可承载（2-3 slice）
- [x] Ambiguity：D21-D27 每条依据明确；时间滚动窗语义已显式标注 + 留调整余地
- [x] 引擎零改结论已用代码位置（emitStringAtom .inSet）佐证
