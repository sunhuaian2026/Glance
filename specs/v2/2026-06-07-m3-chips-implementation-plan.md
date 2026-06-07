# M3 搜索筛选 Chips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐 task 实施。Steps 用 checkbox（`- [ ]`）追踪。
> **验证范式（项目无 XCTest target，CLAUDE.md 例外）**：纯逻辑 task 用 `SearchService._debugSelfCheck` 式 inline assert + `./scripts/verify.sh` 三段；UI/交互 task 用 verify 编译 + PENDING 真机验。不写 XCTest。

**Goal:** 给 M3 搜索 overlay 加可视化筛选 chip（类型多选 / 大小·时间单选），普通用户点选、power user 仍用命令式。

**Architecture:** chip 选中态存独立值类型 `SearchFilterState`，与 keyword 分离；`SearchService.compile(filterState:keyword:)` 单一出口合并成 `SmartFolderPredicate`（common filter + chip atoms + keyword 解析，全 AND）；SQL builder 零改（类型走现有 `.inSet`），仅 `formatLabel` 公开化 + 「今天」预计算 + `runSearch` early-exit 三处辅助改。

**Tech Stack:** Swift / SwiftUI；sqlite3 C API（既有 IndexStore）；`SmartFolderAtom` DSL 引擎。

**上游 design:** `specs/v2/2026-06-07-m3-chips-design.md`（D21-D27）

---

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `Glance/Search/SearchFilterState.swift` | chip 选中态值类型 + `SearchSizeBucket`/`SearchTimeBucket` enum + `toAtoms` + 「今天」预计算 + `_debugSelfCheck` | Create |
| `Glance/Search/SearchChipBar.swift` | chip 行 UI + 三 popover + 选中态/清除 + ESC/焦点交接 | Create |
| `Glance/Search/SearchService.swift` | 加 `compile(filterState:keyword:)` 单一出口；`_debugSelfCheck` 扩验 | Modify |
| `Glance/IndexStore/ImageMetadataReader.swift` | `formatLabel` 公开化 + `static let canonicalFormatLabels` | Modify |
| `Glance/Search/SearchOverlayView.swift` | 插入 `SearchChipBar` + `@Binding filterState` + `onFilterChange` | Modify |
| `Glance/ContentView.swift` | `@State searchFilterState` + `runSearch` 改签名/early-exit/快照 + open/closeSearch 生命周期 | Modify |
| `Glance/DesignSystem.swift` | `DS.Search.chip*` 常量 | Modify |

---

## Slice N1 — 状态 + 合并 + 引擎辅助改（端到端：写死 filterState 验合并 + chip-only）

### Task N1.1: `formatLabel` 公开化 + canonical 标签集

**Files:**
- Modify: `Glance/IndexStore/ImageMetadataReader.swift`

- [ ] **Step 1: 把 `formatLabel` 从 private 改 internal，并加 canonical 标签集常量**

把现有 `private static func formatLabel` 的 `private` 去掉，并在 enum 内加：

```swift
    /// chip 类型选项的唯一权威来源。顺序 = chip 显示顺序。
    /// 必须与 formatLabel 输出的标签**逐字符一致**（含 "WebP" 混合大小写），
    /// 否则 chip 的 `format IN (...)` 精确匹配会漏命中（design R5）。
    /// 新增格式时：formatLabel 加分支 + 此处加标签，两处同步。
    static let canonicalFormatLabels: [String] = ["PNG", "JPEG", "HEIC", "GIF", "WebP", "TIFF", "BMP", "RAW"]

    static func formatLabel(for utType: UTType) -> String {   // 去掉 private
```

- [ ] **Step 2: 编译**

Run: `./scripts/verify.sh`
Expected: `build: SUCCEEDED, 0 code warnings`

- [ ] **Step 3: Commit**

```bash
git add Glance/IndexStore/ImageMetadataReader.swift
git commit -m "refactor(IndexStore): formatLabel 公开化 + canonicalFormatLabels（chips 类型选项同源）"
```

---

### Task N1.2: `SearchFilterState` 值类型

**Files:**
- Create: `Glance/Search/SearchFilterState.swift`

- [ ] **Step 1: 写 `SearchFilterState` + 两 enum + toAtoms + 「今天」预计算**

```swift
//
//  SearchFilterState.swift
//  Glance
//
//  M3 chips — chip 选中态值类型（D22 独立筛选状态）。与 keyword 分离，
//  SearchService.compile(filterState:keyword:) 合并。nonisolated：被 nonisolated
//  compile 及 Task.detached 访问。
//

import Foundation

nonisolated struct SearchFilterState: Equatable {
    var selectedFormats: Set<String> = []      // 值 = ImageMetadataReader.canonicalFormatLabels 子集
    var selectedSize: SearchSizeBucket? = nil
    var selectedTime: SearchTimeBucket? = nil

    var isEmpty: Bool { selectedFormats.isEmpty && selectedSize == nil && selectedTime == nil }

    /// 转成 SmartFolderAtom（类型 inSet / 大小 > / 时间 between）。now 注入便于测试与一致快照。
    func toAtoms(now: Date) -> [SmartFolderAtom] {
        var atoms: [SmartFolderAtom] = []
        if !selectedFormats.isEmpty {
            // D23：inSet + 同源大写标签精确匹配，无需 NOCASE。sorted 让输出稳定（测试/缓存友好）。
            atoms.append(.init(field: .format, op: .inSet, value: .stringArray(selectedFormats.sorted())))
        }
        if let size = selectedSize {
            atoms.append(.init(field: .fileSize, op: .greaterThan, value: .int(size.bytes)))
        }
        if let time = selectedTime {
            atoms.append(.init(field: .birthTime, op: .betweenDuration,
                               value: .relativeTimeRange(start: time.startToken(now: now), end: "now")))
        }
        return atoms
    }
}

/// 大小档（decimal，与 size: modifier 一致；1MB=1_000_000）。
/// Hashable：SearchFilterState Equatable + ForEach(id:\.self) 需要（codex）。
nonisolated enum SearchSizeBucket: CaseIterable, Hashable {
    case mb1, mb5, mb10
    var bytes: Int64 { switch self { case .mb1: return 1_000_000; case .mb5: return 5_000_000; case .mb10: return 10_000_000 } }
    var label: String { switch self { case .mb1: return ">1MB"; case .mb5: return ">5MB"; case .mb10: return ">10MB" } }
}

/// 时间档。今天=本地午夜预计算 ISO（resolveRelativeTime 无此 token）；其余滚动窗 -Nd。
/// 命名 SearchTimeBucket 避开 Glance/FolderBrowser/TimeBucket.swift 既有类型（codex 编译冲突）。
/// Hashable：同 SearchSizeBucket。
nonisolated enum SearchTimeBucket: CaseIterable, Hashable {
    case today, week, month, year
    var label: String { switch self { case .today: return "今天"; case .week: return "本周"; case .month: return "本月"; case .year: return "今年" } }

    /// betweenDuration 的 start token。end 统一 "now"。
    func startToken(now: Date) -> String {
        switch self {
        case .today:
            // design §5.3 + codex R6：当日 00:00 无 resolveRelativeTime token，这里直接算本地午夜 → ISO。
            let midnight = Calendar.current.startOfDay(for: now)
            return Self.isoFormatter.string(from: midnight)
        case .week:  return "-7d"
        case .month: return "-30d"
        case .year:  return "-365d"
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
}
```

- [ ] **Step 2: 加 `_debugSelfCheck`（DEBUG inline 验证，mirror SearchService 模式）**

在文件末尾加：

```swift
#if DEBUG
extension SearchFilterState {
    /// inline 验证 toAtoms 映射正确。调用方式：临时挂 GlanceApp.onAppear。
    static func _debugSelfCheck() {
        let now = Date()
        // 空态
        assert(SearchFilterState().isEmpty, "default should be empty")
        // 类型多选 → inSet
        var s = SearchFilterState(); s.selectedFormats = ["PNG", "JPEG"]
        let a = s.toAtoms(now: now)
        assert(a.count == 1 && a[0].field == .format && a[0].op == .inSet, "formats → 1 inSet atom")
        if case .stringArray(let xs) = a[0].value { assert(xs == ["JPEG", "PNG"], "sorted") } else { assertionFailure("stringArray") }
        // 大小 → file_size >
        var s2 = SearchFilterState(); s2.selectedSize = .mb5
        let a2 = s2.toAtoms(now: now)
        assert(a2.count == 1 && a2[0].field == .fileSize && a2[0].op == .greaterThan)
        if case .int(let b) = a2[0].value { assert(b == 5_000_000) } else { assertionFailure("int") }
        // 时间「今天」→ between，start 是 ISO（含 'T'），不是 "-Nd"
        var s3 = SearchFilterState(); s3.selectedTime = .today
        let a3 = s3.toAtoms(now: now)
        assert(a3.count == 1 && a3[0].op == .betweenDuration)
        if case .relativeTimeRange(let start, let end) = a3[0].value {
            assert(start.contains("T") && end == "now", "today start = ISO midnight, end = now")
        } else { assertionFailure("relativeTimeRange") }
        // 时间「本周」→ -7d
        var s4 = SearchFilterState(); s4.selectedTime = .week
        if case .relativeTimeRange(let start, _) = s4.toAtoms(now: now)[0].value { assert(start == "-7d") }
        // 组合 3 维 → 3 atoms
        var s5 = SearchFilterState(); s5.selectedFormats = ["PNG"]; s5.selectedSize = .mb1; s5.selectedTime = .month
        assert(s5.toAtoms(now: now).count == 3, "3 dims → 3 atoms")
        print("[SearchFilterState] _debugSelfCheck: all passed")
    }
}
#endif
```

- [ ] **Step 3: 编译**

Run: `./scripts/verify.sh`
Expected: `build: SUCCEEDED, 0 code warnings`

- [ ] **Step 4: Commit**

```bash
git add Glance/Search/SearchFilterState.swift
git commit -m "feat(Search): SearchFilterState — chip 选中态值类型 + toAtoms + 今天预计算"
```

---

### Task N1.3: `SearchService.compile(filterState:keyword:)` 单一出口

**Files:**
- Modify: `Glance/Search/SearchService.swift`

- [ ] **Step 1: 加新 compile 重载（common filter 单点注入）**

在 `compile(_ parsed:)` 下方加（**不调旧 compile**，common filter 在此唯一注入，避免叠加 codex Q2/R7）：

```swift
    /// chips + keyword 合并出口。common filter 只在此注入一次。
    /// now 注入：与 runSearch 的一致快照对齐（SearchTimeBucket.today / -Nd 都依赖 now）。
    static func compile(filterState: SearchFilterState, keyword: String, now: Date = Date()) -> SmartFolderPredicate {
        var atoms: [SmartFolderPredicate] = [
            .atom(.init(field: .managed, op: .eq, value: .bool(true))),
            .atom(.init(field: .hidden, op: .eq, value: .bool(false))),
            .atom(.init(field: .dedupCanonicalOrNull, op: .eq, value: .bool(true)))
        ]
        // chip atoms（类型 inSet / 大小 > / 时间 between）
        atoms.append(contentsOf: filterState.toAtoms(now: now).map { .atom($0) })
        // keyword 内仍解析命令式 modifier + 自由关键字
        let parsed = parse(keyword)
        atoms.append(contentsOf: parsed.modifiers.map { .atom($0) })
        if !parsed.keyword.isEmpty {
            atoms.append(.or([
                .atom(.init(field: .filename, op: .contains, value: .string(parsed.keyword))),
                .atom(.init(field: .relativePath, op: .contains, value: .string(parsed.keyword)))
            ]))
        }
        return .and(atoms)
    }
```

- [ ] **Step 2: 扩 `_debugSelfCheck` 验合并（chip-only / chip+keyword / 命令式共存）**

在 `SearchService._debugSelfCheck` 末尾 `print` 前加：

```swift
        // --- chips compile 合并 ---
        // chip-only：类型 PNG，无 keyword → 3 common + 1 format inSet
        var fcOnly = SearchFilterState(); fcOnly.selectedFormats = ["PNG"]
        if case .and(let xs) = compile(filterState: fcOnly, keyword: "") {
            assert(xs.count == 4, "chip-only: 3 common + 1 inSet")
        } else { assertionFailure("compile .and") }
        // chip + keyword：类型 PNG + "cat" → 3 common + 1 inSet + 1 OR(keyword)
        if case .and(let xs) = compile(filterState: fcOnly, keyword: "cat") {
            assert(xs.count == 5, "chip + keyword: +OR")
        } else { assertionFailure("compile .and") }
        // chip + 命令式（keyword 内 size:>1mb）：3 common + 1 inSet + 1 fileSize
        if case .and(let xs) = compile(filterState: fcOnly, keyword: "size:>1mb") {
            assert(xs.count == 5, "chip + 命令式 modifier")
        } else { assertionFailure("compile .and") }
        // 空 filterState + 空 keyword → 只 3 common（runSearch 会 early-exit，这里只验结构）
        if case .and(let xs) = compile(filterState: SearchFilterState(), keyword: "") {
            assert(xs.count == 3, "empty → 3 common only")
        } else { assertionFailure("compile .and") }
```

- [ ] **Step 3: 编译 + 确认 SQL 经 QueryBuilder 不报错（手动核对一次生成 SQL）**

Run: `./scripts/verify.sh`
Expected: `build: SUCCEEDED, 0 code warnings`

> 可选：临时在 GlanceApp.onAppear 调 `SearchFilterState._debugSelfCheck()` + `SearchService._debugSelfCheck()`，run 一次看 console 两行 "all passed"，确认后移除调用（函数保留作 regression）。

- [ ] **Step 4: Commit**

```bash
git add Glance/Search/SearchService.swift
git commit -m "feat(Search): compile(filterState:keyword:) 单一出口合并 chip + keyword（common filter 单点注入）"
```

---

### Task N1.4: `ContentView.runSearch` 改签名 + early-exit + 快照 + 生命周期

**Files:**
- Modify: `Glance/ContentView.swift`

- [ ] **Step 1: 加 `@State searchFilterState`**

在 `@State private var searchTask` 附近加：

```swift
    /// M3 chips — chip 选中态（D22 独立筛选状态）。openSearch 重置、closeSearch 清空（D27）。
    @State private var searchFilterState = SearchFilterState()
```

- [ ] **Step 2: 改 `runSearch` 签名为 keyword + filterState，改 early-exit + 一致快照**

把现有 `runSearch(input:skipDebounce:)` 整体替换为：

```swift
    /// chips + keyword 合并查询。chip 点选 skipDebounce=true 即时；keyword onChange debounce。
    private func runSearch(keyword: String, filterState: SearchFilterState, skipDebounce: Bool) {
        searchTask?.cancel()
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        // codex 修正：chip-only（keyword 空但有 chip）不能被挡，条件改双空。
        guard !(trimmed.isEmpty && filterState.isEmpty) else {
            currentEphemeral = .search(query: "", images: [], urls: [])
            return
        }
        guard let store = indexStoreHolder.store else { return }
        // 一致快照：debounce 期间 chip tap 可能改 filterState（codex R3）。
        let snapKeyword = keyword
        let snapFilter = filterState
        let snapNow = Date()
        searchTask = Task.detached(priority: .userInitiated) {
            if !skipDebounce {
                try? await Task.sleep(for: .milliseconds(DS.Search.debounceMs))
                guard !Task.isCancelled else { return }
            }
            let predicate = SearchService.compile(filterState: snapFilter, keyword: snapKeyword, now: snapNow)
            let folder = SmartFolder(id: "ephemeral-search", displayName: "搜索",
                                     predicate: predicate, sortBy: .birthTime, sortDescending: true, isBuiltIn: false)
            let images: [IndexedImage]
            do {
                let compiled = try SmartFolderQueryBuilder.compile(folder, now: snapNow)
                images = try store.fetch(compiled, limit: nil)
            } catch {
                await MainActor.run { indexStoreHolder.lastError = "搜索失败：\(error.localizedDescription)" }
                return
            }
            guard !Task.isCancelled else { return }
            let resolvedPairs: [(IndexedImage, URL)] = images.compactMap { img in
                var stale = false
                guard let rootURL = try? URL(resolvingBookmarkData: img.urlBookmark,
                                             options: [.withSecurityScope], bookmarkDataIsStale: &stale) else { return nil }
                return (img, rootURL.appendingPathComponent(img.relativePath))
            }
            let resolvedImages = resolvedPairs.map { $0.0 }
            let urls = resolvedPairs.map { $0.1 }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                // query 文案：keyword 优先，否则示意 chip 生效
                let q = snapKeyword.isEmpty ? "筛选" : snapKeyword
                self.currentEphemeral = .search(query: q, images: resolvedImages, urls: urls)
            }
        }
    }
```

- [ ] **Step 3: 改 `openSearch` / `closeSearch` / `submitSearch` 的 filterState 生命周期 + 调用点**

`openSearch()` 内 `currentEphemeral = .search(...)` 后加（D27 重置，覆盖反复 ⌘F）：

```swift
        searchFilterState = SearchFilterState()   // D27：进入即空白
```

`closeSearch()` 内 `currentEphemeral = nil` 同 withAnimation 块后加：

```swift
        searchFilterState = SearchFilterState()   // D27：清空
```

`submitSearch(input:)`：guard 改为认 filterState（codex：chip-only 按 Enter 也要进网格），runSearch 改新签名：

```swift
    private func submitSearch(input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !(trimmed.isEmpty && searchFilterState.isEmpty) else { return }   // codex：chip-only Enter 也生效
        runSearch(keyword: input, filterState: searchFilterState, skipDebounce: true)
        withAnimation(DS.Anim.normal) { showSearchOverlay = false }
        focusTarget = .ephemeral
    }
```

- [ ] **Step 4: 改 SearchOverlayView 调用点的 onInputChange（keyword 路径）**

`mainContent` 里 `SearchOverlayView(... onInputChange:)` 改为：

```swift
                    onInputChange: { input, skipDebounce in
                        runSearch(keyword: input, filterState: searchFilterState, skipDebounce: skipDebounce)
                    },
```

> 注：N1 阶段 SearchOverlayView 还没接 filterState binding（N2 做）；此处 filterState 暂恒为空，keyword 路径行为与改前等价，保证 N1 可独立编译/ship。

- [ ] **Step 5: 编译**

Run: `./scripts/verify.sh`
Expected: `build: SUCCEEDED, 0 code warnings`

- [ ] **Step 6: 端到端自验（临时写死 filterState 验 chip-only 路径）**

临时在 `openSearch()` 的重置行改成 `searchFilterState = { var s = SearchFilterState(); s.selectedFormats = ["PNG"]; return s }()`，build+run，⌘F 不输入任何字，应直接出 PNG 结果（验 chip-only early-exit + 合并 + fetch 通）。**验完改回 `SearchFilterState()`**。

- [ ] **Step 7: Commit**

```bash
git add Glance/ContentView.swift
git commit -m "feat(Search): runSearch 接 filterState — chip-only early-exit + 一致快照 + 生命周期（N1 完）"
```

---

## Slice N2 — chip UI + popover + 接入（用户可感知完整交互）

### Task N2.1: `DS.Search.chip*` 常量

**Files:**
- Modify: `Glance/DesignSystem.swift`

- [ ] **Step 1: 在 `DS.Search` 段加 chip 常量**

```swift
        // M3 chips
        static let chipSpacing: CGFloat = 8
        static let chipCornerRadius: CGFloat = 8
        static let chipHPadding: CGFloat = 10
        static let chipVPadding: CGFloat = 5
        static let chipSelectedOpacity: CGFloat = 0.18   // 选中态 accent 填充
        static let popoverMinWidth: CGFloat = 180
```

- [ ] **Step 2: 编译 + commit**

Run: `./scripts/verify.sh` → SUCCEEDED
```bash
git add Glance/DesignSystem.swift
git commit -m "feat(Search): DS.Search chip 常量"
```

---

### Task N2.2: `SearchChipBar` UI + 三 popover

**Files:**
- Create: `Glance/Search/SearchChipBar.swift`

- [ ] **Step 1: 写 SearchChipBar（三 chip + popover；类型 checkbox 多选 / 大小·时间单选）**

```swift
//
//  SearchChipBar.swift
//  Glance
//
//  M3 chips — 搜索筛选 chip 行（D21/D22/D25）。chip 选中态绑父 SearchFilterState。
//  popover 用 SwiftUI 原生 .popover（系统管层级/dismiss，design R4）。
//

import SwiftUI

struct SearchChipBar: View {
    @Binding var filterState: SearchFilterState
    /// 任一 chip 变更 → 通知父即时查询（skipDebounce）。
    let onChange: () -> Void

    @State private var showTypePopover = false
    @State private var showSizePopover = false
    @State private var showTimePopover = false

    var body: some View {
        HStack(spacing: DS.Search.chipSpacing) {
            typeChip
            sizeChip
            timeChip
            Spacer(minLength: 0)
        }
    }

    // MARK: 类型（多选）
    private var typeChip: some View {
        chipButton(title: typeTitle, selected: !filterState.selectedFormats.isEmpty) { showTypePopover = true }
        .popover(isPresented: $showTypePopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(ImageMetadataReader.canonicalFormatLabels, id: \.self) { fmt in
                    Button {
                        if filterState.selectedFormats.contains(fmt) { filterState.selectedFormats.remove(fmt) }
                        else { filterState.selectedFormats.insert(fmt) }
                        onChange()
                    } label: {
                        HStack {
                            Image(systemName: filterState.selectedFormats.contains(fmt) ? "checkmark.square.fill" : "square")
                            Text(fmt); Spacer()
                        }
                    }.buttonStyle(.plain)
                }
                Divider()
                Button("清除") { filterState.selectedFormats = []; onChange() }.buttonStyle(.plain)
            }
            .padding(DS.Spacing.sm).frame(minWidth: DS.Search.popoverMinWidth)
            .onExitCommand { showTypePopover = false }   // codex R4：ESC 关本 popover，不冒泡到 overlay
        }
    }
    private var typeTitle: String {
        let s = filterState.selectedFormats.sorted()
        if s.isEmpty { return "类型" }
        return s.count == 1 ? "类型: \(s[0])" : "类型: \(s[0]) +\(s.count - 1)"
    }

    // MARK: 大小（单选）
    private var sizeChip: some View {
        chipButton(title: filterState.selectedSize.map { "大小: \($0.label)" } ?? "大小",
                   selected: filterState.selectedSize != nil) { showSizePopover = true }
        .popover(isPresented: $showSizePopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(SearchSizeBucket.allCases, id: \.self) { b in
                    Button {
                        filterState.selectedSize = (filterState.selectedSize == b) ? nil : b
                        onChange(); showSizePopover = false
                    } label: {
                        HStack {
                            Image(systemName: filterState.selectedSize == b ? "largecircle.fill.circle" : "circle")
                            Text(b.label); Spacer()
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(DS.Spacing.sm).frame(minWidth: DS.Search.popoverMinWidth)
            .onExitCommand { showSizePopover = false }   // codex R4
        }
    }

    // MARK: 时间（单选）
    private var timeChip: some View {
        chipButton(title: filterState.selectedTime.map { "时间: \($0.label)" } ?? "时间",
                   selected: filterState.selectedTime != nil) { showTimePopover = true }
        .popover(isPresented: $showTimePopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(SearchTimeBucket.allCases, id: \.self) { b in
                    Button {
                        filterState.selectedTime = (filterState.selectedTime == b) ? nil : b
                        onChange(); showTimePopover = false
                    } label: {
                        HStack {
                            Image(systemName: filterState.selectedTime == b ? "largecircle.fill.circle" : "circle")
                            Text(b.label); Spacer()
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(DS.Spacing.sm).frame(minWidth: DS.Search.popoverMinWidth)
            .onExitCommand { showTimePopover = false }   // codex R4
        }
    }

    // MARK: chip 按钮通用
    private func chipButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Text(title).font(.caption)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, DS.Search.chipHPadding).padding(.vertical, DS.Search.chipVPadding)
            .background(selected ? Color.accentColor.opacity(DS.Search.chipSelectedOpacity) : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: DS.Search.chipCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: DS.Search.chipCornerRadius)
                .strokeBorder(selected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
```

> 注：`DS.Spacing` 现有键 = zero/xs/sm/md/lg/xl（codex 确认无 xxs），上面已用 `xs`。其余引用已存在符号前仍按 CLAUDE.md grep 确认。

- [ ] **Step 2: 编译 + commit**

Run: `./scripts/verify.sh` → SUCCEEDED（0 warning）
```bash
git add Glance/Search/SearchChipBar.swift
git commit -m "feat(Search): SearchChipBar — 三组 chip + 原生 popover（类型多选/大小·时间单选）"
```

---

### Task N2.3: 接入 SearchOverlayView + ContentView + 即时查 + ESC 两段/焦点

**Files:**
- Modify: `Glance/Search/SearchOverlayView.swift`
- Modify: `Glance/ContentView.swift`

> codex 修正：**不**把 `searchInput` 提升为 `@Binding`（否则 closeSearch 重置会触发 overlay `.onChange(searchInput)` → 重新 fire search → 重建刚清空的结果，close-loop bug）。`searchInput` 保持 SearchOverlayView local `@State`；chip 变更时由 overlay 把当前 `searchInput` 经 callback 带出。closeSearch 收 overlay 后 view 重建，local searchInput 自动清空，无需父重置 keyword。

- [ ] **Step 1: SearchOverlayView 加 filterState binding + onChipChange + 插入 chip 行**

`SearchOverlayView` 加成员（`searchInput` 维持现有 local `@State` 不动）：

```swift
    @Binding var filterState: SearchFilterState
    /// chip 变更 → caller 即时查询。参数 = 当前 keyword（searchInput），让 chip + keyword 合并。
    let onChipChange: (_ keyword: String) -> Void
```

`body` 的 `VStack` 内、`inputRow` 与 `hintRow` 之间插入（onChange 带上当前 searchInput）：

```swift
            SearchChipBar(filterState: $filterState, onChange: { onChipChange(searchInput) })
```

hint 行文案（命令式提示，缩小灰字）已有，无需改。

- [ ] **Step 2: ContentView 调用点传 filterState binding + onChipChange（即时查）**

`mainContent` 的 `SearchOverlayView(...)` 加参数：

```swift
                    filterState: $searchFilterState,
                    onChipChange: { keyword in
                        runSearch(keyword: keyword, filterState: searchFilterState, skipDebounce: true)
                    },
```

> keyword 路径（onInputChange）已在 N1.4 Step4 改为带 `searchFilterState`；chip 路径在此。两路都带 `searchFilterState`，合并一致。无需 `currentSearchKeyword`（codex：消除前向引用 + binding 副作用）。

- [ ] **Step 3: ESC 两段 + 焦点（design §6 / codex R4）**

- popover ESC：N2.2 每个 popover content 已挂 `.onExitCommand { showXxxPopover = false }`（关本 popover，不冒泡）
- overlay ESC：仍由 SearchOverlayView TextField `.onKeyPress(.escape)` → `onClose` 关 overlay（现有，不动）
- 焦点：popover 关后 SwiftUI 默认把焦点交回触发它的 chip 按钮。**留 PENDING 真机决定**：若实测 popover 关后不能继续打字（焦点没回 TextField），再把 `@FocusState.Binding` 透传给 SearchChipBar 并在 dismiss 时显式 `focusTarget = .search`；先不预加透传（YAGNI）。

- [ ] **Step 5: 编译**

Run: `./scripts/verify.sh`
Expected: `build: SUCCEEDED, 0 code warnings`

- [ ] **Step 6: Commit**

```bash
git add Glance/Search/SearchOverlayView.swift Glance/ContentView.swift
git commit -m "feat(Search): chip bar 接入 overlay + keyword 提升 + 即时查 + ESC 两段（N2 完）"
```

---

## Slice N3 — Polish（可选，按真机反馈触发）

不预定 task。候选：chip 选中态视觉微调 / 单组清除按钮显式化 / a11y label / 时间档自然边界（若用户反馈滚动窗不符预期）。

---

## 文档同步（实施完成后，随末个 commit 或单独 docs commit）

- `specs/Roadmap.md`：Bug Fix/决策段加 D21-D27 + M3 chips slice 表
- `CLAUDE.md` 文件结构：加 `SearchFilterState.swift` / `SearchChipBar.swift` + `ImageMetadataReader` formatLabel 公开化备注
- `specs/PENDING-USER-ACTIONS.md`：追加真机验项（见下）

### PENDING 真机验项（实施后追加）

- chip 类型多选 PNG+JPEG 即时出结果（验 inSet 同源匹配）
- WebP chip 命中 WebP 图（验混合大小写精确匹配）
- chip-only（不输字只点 chip）出结果（验 early-exit 修正）
- 「今天」档出今天的图、非空（验预计算午夜，codex 硬缺陷）
- 大小 >5MB / 时间本周 即时收窄
- chip + keyword 叠加合并正确
- popover ESC 两段（先关 popover 再关 overlay）+ 焦点归还输入框
- 单组清除 / closeSearch 全清 / ⌘F 重开空白（D27）
- 命令式 type:/size:/birth: + M2 找类似 + 纯 keyword 回归不退化

---

## Self-Review

**1. Spec coverage（design §2.1 → task）:**
- 三组 chip → N2.2 ✓ / 独立状态 → N1.2 ✓ / 合并查询单点 → N1.3 ✓ / 即时触发 → N1.4+N2.3 ✓ / 命令式共存 → N1.3 keyword parse ✓ / 布局+hint → N2.3 ✓
- design 3 处辅助改：formatLabel → N1.1 ✓ / 今天预计算 → N1.2 ✓ / runSearch early-exit → N1.4 ✓
- codex 7 点：标签同源 N1.1 / 今天预计算 N1.2 / chip-only early-exit N1.4 / common filter 单点 N1.3 / popover ESC N2.3 Step4 / 状态生命周期 N1.4 Step3 / 零改修正（design 已注）✓

**2. Placeholder scan:** 无 TBD/TODO 残留；UI 代码完整给出；唯一「实施时确认」是 `DS.Spacing.xxs` 是否存在（已标 grep 兜底，非 placeholder 是真实工程注意项）。

**3. Type consistency:** `SearchFilterState`/`SearchSizeBucket`/`SearchTimeBucket`/`toAtoms(now:)`/`compile(filterState:keyword:now:)`/`runSearch(keyword:filterState:skipDebounce:)`/`canonicalFormatLabels` 跨 task 命名一致；chip 标签值 = `canonicalFormatLabels`（与 DB formatLabel 同源）。

**4. Slice 纪律:** N1 端到端可跑（写死 filterState 验 chip-only，Step6）+ 独立可 ship（keyword 路径不退化）；N2 用户可感知完整 chip 交互。各片满足三条。

**5. codex plan review 吸收（第二轮 8 点）:** `TimeBucket`→`SearchTimeBucket` 避冲突（N1.2）/ 两 enum 加 `Hashable`（N1.2）/ `searchInput` 不 promote `@Binding` 避 close-loop（N2.3）/ N2.3 前向引用消除 / `canonicalFormatLabels` 补 TIFF·BMP（N1.1）/ chip-only Enter（N1.4 submitSearch）/ popover `.onExitCommand`（N2.2）/ `DS.Spacing.xxs`→`xs`（N2.2）。codex 确认对的：call site 全覆盖 / compile 单点注入 / 符号名 / SmartFolder init / _debugSelfCheck 断言。
