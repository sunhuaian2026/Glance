# 重复清理 V2 重设计 — Design

> **状态**: brainstorming draft (v2 — codex review 折入 3 P0 + 4 P1 + 3 P2)
> **日期**: 2026-06-19
> **子系统**: 重复清理 V2(独立子系统,不塞 M 编号;mirror 快速看图器增强 / OpenWith 子系统约定)
> **关联**: 现有 M4 任务 1+2 的 `Glance/Dedup/*` + `IndexStore.fetchDuplicateGroups` SQL
> **设计来源**: Claude Design 高保真原型(`/tmp/dedupe_design_v2/design_handoff_dedupe_cleanup/` — README + DuplicateCleanup.dc.html + 4 张截图)
>
> **v2 修订摘要**(2026-06-19 codex review APPROVE-WITH-FIXES 后):
> - **codex P0 (SHA256 invariant 根因)**: 同组同 sha256 必然同 fileSize — D3 算法砍 size-ratio 分支只保留 `duplicateCount >= 3`;`pendingTrashCount` / `pendingReclaimableBytes` 不再以 userKeepId 动态计算(同组同体积切谁都不变);★ 推荐(体积最大) 角标全砍(无判别价值)
> - **codex P0 (focus chain 接入)**: 既有 `ContentView.@FocusState focusTarget` 仲裁链加 `.dedupOverlay` case,不另起 `overlayFocused`
> - **codex P1 (recommendedKeepId 注释)**: §2.2 注释口径统一(= DedupPass canonical = earliest birth_time + 最小 id;不是体积最大)
> - **codex P1 (reload prune 清单扩展)**: `reviewedGroupIds` / `expandedGroupIds` / `focusReviewQueue` / `focusReviewIndex` 全部 prune;浮层开时 reload 自动推进/关
> - **codex P1 (任务 A+B 合并)**: 任务 A+B 合并成「任务 AB」,不留过渡态
> - **codex P1 (click-outside 锁定)**: D-dedup-7 锁 A 点击外部关闭浮层(macOS Spotlight 标准模态)
> - **codex P2 (★ 矛盾消失)**: ★ 全砍后 §4.4 与 D-dedup-12 矛盾自动消失
> - **codex P2 (TrashInput 命名空间)**: 改 `TrashService.TrashInput` 命名空间精确
> - **codex P2 (PENDING 浮层 stale state)**: §10 PENDING 加浮层 reload stale state 验项
> - **新决策**: D-dedup-14 登记 SHA256 invariant(本期 design 的根本约束,后续 plan / commit 引用必须遵守);D-dedup-15 登记 focus chain 接入既有仲裁链(P0-3 修)

---

## §0 写在前面

### 严格 scope 锁定

军哥已锁 D1-D6 倾向方案,本 design 不再回头探索这 6 项:

| # | 锁定方案 |
|---|---------|
| D1 | per-item 选保留张 = **临时态**(@Published in-memory,不写 DB `dedup_canonical`,DedupPass 算法 ground truth 不污染) |
| D2 | 跳过组 = **session 态**(in-memory flag,重启 / 重扫消失,不加 DB 字段) |
| D3 | needsReview 算法 = **副本数 ≥ 3 张**(原 v1 含 size-ratio 分支被 codex P0 抓 SHA256 invariant 同组同体积恒成立,v2 砍 size-ratio 分支只保留 `duplicateCount >= 3`) |
| D4 | 主题切换 = **跟随全局 `AppearanceMode`**,砍掉设计稿顶栏深/浅分段控件(项目已有完整三档体系) |
| D5 | 分页加载 = **砍掉**,用 LazyVStack 全量渲染(macOS 原生范式,符合「克制」红线) |
| D6 | 逐组审阅浮层 = **ZStack overlay + .ultraThinMaterial 背景**(最接近设计稿,无 SwiftUI .sheet chrome) |

### 初心红线对齐

- ✅ **不抢库**: per-item 选择临时态,不污染 DedupPass canonical;DB schema 不动
- ✅ **回归初心**: 这是「找重复 → 一览 → 批量清理省硬盘空间」核心闭环增强,不是看图浏览功能堆叠

### SHA256 invariant 关键约束(v2 加,D-dedup-14)

**Glance 重复清理基于 `content_sha256`(DedupPass SHA256 内容哈希)**,所以:

- `IndexStore.fetchDuplicateGroups` SQL 按 `content_sha256` 分组 → **同组所有成员必然 fileSize 完全相等**(字节级相同的内容才会进同组)
- 任何「比较成员 fileSize 差异」的算法(原 v1 needsReview size-ratio 分支)在本数据模型下**永远恒成立或永远恒不成立**,无判别价值
- 任何「user 切换保留张省更多/更少字节」的 UX(原 v1 `pendingReclaimableBytes` 动态计算)**不存在** — 同组任何成员被删都省同样字节
- 「★ 推荐(体积最大)」UI 角标在 SHA256 模型下无意义 — 所有成员体积相同,无最大可言

**这是本期 design 的根本数据模型约束。后续 plan / commit / PR 引用本设计时必须遵守此 invariant。**

---

## §1 用户故事 + 范围

### 主用户故事

> 军哥(用户)扫到几十组重复图,**不想被无尽长列表淹没**。Glance 应该:
> 1. **绝大多数组自动留最优**(DedupPass 已做 — earliest birth_time + 最小 id)→ 用户审阅成本 0
> 2. **副本数 ≥ 3 张的「大组」**显式标「待确认」→ 组太大用户介入价值高,让用户点开来挑保留张(SHA256 invariant 下副本数是唯一有效判别维度,详见 §5 + D-dedup-14)
> 3. **提供逐组审阅模式**:模态全屏左右对比大图 + 键盘 ← → Enter Esc → 用户连续审阅 N 组不出戏
> 4. **筛选 / 排序 / 搜索**:筛选「全部 / 待确认 / 已自动」,排序「可省 / 张数 / 名称」,文件名搜索
> 5. **per-item 改保留张**:点任意缩略图 → 该图变保留张,其它自动转待删(临时态,不污染 DedupPass);**语义是「我对原图位置/folder 的偏好」**(例如想留「素材」目录里的而非「Downloads」里的)而非「省更多字节」(SHA256 同组同体积,字节数恒定)
> 6. **跳过整组**:本次清理不动这组(临时态,重扫消失)
> 7. **一次性「移入废纸篓」**:复用既有 TrashService + TrashUndoBanner

### 范围(做)

| 区域 | 做什么 | 当前实现 | 设计稿来源 |
|------|--------|---------|-----------|
| 顶栏 | 标题「重复清理」+ 主操作按钮「移入废纸篓 (N)」 | 现有 `navigationTitle("重复清理")` + statsBar 内的 trashAction | 截图 01 顶栏 |
| 汇总条 | 大数字「N 组重复 / 可省 X」+ 双徽标「✓ 自动留最优 / ⚠ 建议你确认」+「逐组审阅 ›」 | 当前只有简单 statsBar 行 | 截图 01 汇总条 |
| 工具条 | 筛选 pills「全部 / 待确认 / 已自动」+ 排序分段「可省 / 张数 / 名称」+ 搜索框 | 无 | 截图 01 工具条 |
| 列表 | 紧凑行卡片(叠放缩略图 + 标题 + 删 N 徽 + 跳过按钮 + chevron) | 现有 `DuplicateGroupRowView`(整组 checkbox + 缩略图横排) | 截图 01 / 03 列表行 |
| 展开区 | 点 chevron 展开,90×66 缩略图横排,**点任意缩略图 = 设为保留张**(v2:**无 ★ 推荐角标** — SHA256 invariant 下无意义) | 现有展开默认折起;点击无反应 | 截图 03 展开区 |
| 浮层 | 「逐组审阅」模态全屏 — 300×214 大图对比 + 键盘 ← → Enter Esc + 进度「i / N」(v2:**无 ★ 推荐(体积最大)角标** — SHA256 invariant 下无意义) | 完全没有 | 截图 02 |

### 不做(本期)

| 项 | 理由 |
|----|------|
| 顶栏深/浅分段控件 | D4 — 跟随全局 AppearanceMode,项目已有完整三档体系,独立切换是冗余 |
| 分页加载「加载更多」 | D5 — LazyVStack 几百组无压力,符合「克制」红线;web 习惯不进 macOS |
| 写回 DB `dedup_canonical` 永久化用户手选 | D1 — 临时态语义;若用户希望永久化是 followup decision,本期不动 DB |
| DB 加 `dedup_skipped` 字段永久跳过 | D2 — session 态;永久跳过是 followup,本期不动 schema |
| 智能挑选 / 全部保留批量按钮 | 设计稿 DuplicateCleanup 主交付**没有**这两按钮(只 CleanupComparison 三变体里有);DedupPass 已默认「智能挑选」,无需冗余按钮;「全部保留」= 全跳过,跳过按钮已能做 |
| 主题切换独立分段(深/浅) | 同 D4 |
| 「重新扫描」按钮 | 现状 FSEvents 自动触发,加按钮反而混淆「为什么不自动?」;若用户要手动 trigger 是 followup |
| ★ 推荐(体积最大)角标(展开区 + 浮层均不显示) | **v2 砍全砍** — SHA256 invariant 下同组所有成员 fileSize 完全相等,「体积最大」不存在;视觉上挂角标会误导用户以为「这张是体积更大的原图,其它是压缩副本」(SHA256 模型下这是错的) |

---

## §2 真实 API 表(grep + Read 已核对,2026-06-19)

### §2.1 DuplicateOverviewModel(`Glance/Dedup/DuplicateOverviewModel.swift`)

**保留不动的 stored properties:**
- `@Published private(set) var state: DuplicateOverviewState`
- `@Published private(set) var selectedSha256s: Set<String>` — **改用法**: 不再是「整组勾选清掉副本」,改为「跳过组 ID 集合」语义 → 重命名为 `skippedGroupIds`(D2)
- `@Published private(set) var trashState: TrashOperationState`
- `@Published private(set) var lastTrashOutcome: TrashOutcomeEvent?`
- `private var indexStore: IndexStore?`
- `private weak var bridge: FolderStoreIndexBridge?`
- `private weak var bookmarkManager: BookmarkManager?`
- `private weak var folderStore: FolderStore?`
- `private weak var migrationCoordinator: BookmarkMigrationCoordinator?`
- `private var observerToken: UUID?`
- `private var pendingReload: DispatchWorkItem?`
- `private var loadGeneration: Int`
- `private var currentCancellationToken: TrashCancellationToken?`

**保留不动的方法:**
- `static func placeholder() -> DuplicateOverviewModel`
- `func attach(indexStore:bridge:bookmarkManager:folderStore:migrationCoordinator:)` — 签名不动
- `func load() async`
- `func scheduleReload()`
- `func cancelTrash() async`
- `func undo(outcome: TrashOutcome) async`
- `private func currentGroups() -> [DuplicateGroup]`
- `private nonisolated static func fetchGroups(store: IndexStore) throws -> [DuplicateGroup]`
- `private nonisolated static func makeMember(from row: DuplicateGroupMemberRow) -> DuplicateGroupMember`

**需要改的方法 / 属性:**
- `toggleSelection(sha256:)` → 改名 `toggleSkip(groupId:)` + 语义反转(变跳过组操作)
- `clearSelection()` → 改名 `clearSkips()`
- `replaceSelectedSha256s(_:)` → 改名 `replaceSkippedGroupIds(_:)`(prune 用)
- `selectedDuplicateCount` → 改成 `pendingTrashCount`(**v2 修正**: 未跳过组的 `duplicates.count` 之和 — SHA256 invariant 同组同体积,与 userKeepId 切换**无关**,切谁删几张都不变;**因此本字段是 group-level 静态求和**)
- `selectedReclaimableBytes` → 改成 `pendingReclaimableBytes`(**v2 修正**: 未跳过组的 `group.reclaimableBytes` 之和 — SQL 已算好,与 userKeepId **无关**)
- `trashSelected()` — **核心改造**: 改为 `trashPending()`,扫所有未跳过组,按 `userKeepIdByGroup` 决定每组保留张(语义是「保留 path/folder 偏好」而非「省更多字节」),其它进 TrashInput;collectTrashInputs 改名 + 用 userKeepId 而非 dedup_canonical=1

**需要新增的 stored properties(临时态,不写 DB):**
- `@Published private(set) var userKeepIdByGroup: [String: Int64]` — 每组用户手选保留张 image.id(D1);group.id(sha256) 不在 dict 中时 = 走 DedupPass canonical
- `@Published private(set) var skippedGroupIds: Set<String>` — 跳过组 sha256 集合(D2);取代旧 `selectedSha256s` 语义
- `@Published var filter: DedupListFilter = .all` — 筛选 pills 选中态
- `@Published var sortOption: DedupSortOption = .reclaimableDesc` — 排序选中态
- `@Published var searchQuery: String = ""` — 搜索框文本
- `@Published private(set) var expandedGroupIds: Set<String> = []` — 列表展开态
- `@Published var focusReviewOpen: Bool = false` — 浮层开关
- `@Published private(set) var focusReviewQueue: [String] = []` — 浮层审阅队列(sha256 数组)
- `@Published var focusReviewIndex: Int = 0` — 浮层当前索引
- `@Published private(set) var reviewedGroupIds: Set<String> = []` — **v2 加**(从 §5.3 提到 §2.1 显式声明): 已通过浮层审阅过的组 sha256 集合;needsReview && reviewed = true 时列表行徽章变「已确认」;codex P1 (reload prune 清单扩展) 范围

**需要新增的方法:**
- `func setUserKeep(groupId: String, memberId: Int64)` — D1 点缩略图设保留张;同时 unskip 该组(mirror 原 setKeep)
- `func toggleSkip(groupId: String)` — D2 跳过 / 恢复整组
- `func clearSkips()` — 重置全部跳过
- `func toggleExpand(groupId: String)` — 展开 / 收起组
- `func resetUserKeep(groupId: String)` — 重置该组回 DedupPass 推荐(暴露给「重置」按钮 — backlog,本期 plan 不实施)
- `func openFocusReview()` — 收集所有 needsReview 且未跳过的组,启动浮层
- `func closeFocusReview()` — 关闭浮层
- `func focusReviewNext()` — 浮层 → 一组
- `func focusReviewPrev()` — 浮层 ← 一组
- `func focusReviewConfirm()` — 浮层 Enter — 当前组沿用既有 userKeepId(或 DedupPass canonical),不跳过 → 推进;最后一组关闭
- `func focusReviewSkip()` — 浮层「跳过此组」— 当前组 skip,推进;最后一组关闭

**需要新增的 computed accessors:**
- `var filteredSortedGroups: [DuplicateGroup]` — 应用 filter + sort + searchQuery 后的结果集(view 直接读)
- `var autoCount: Int` — 已自动留最优组数(non-needsReview)
- `var reviewCount: Int` — 待确认组数(needsReview 且未审阅)
- `var pendingTrashCount: Int` — 未跳过组的 `duplicates.count` 之和(v2: SHA256 invariant 同组同体积,与 userKeepId 无关 — 切谁删几张都不变;实现 = `model.filteredSortedGroups.filter { !isSkipped($0.id) }.reduce(0) { $0 + $1.duplicateCount }`)
- `var pendingReclaimableBytes: Int64` — 未跳过组的 `group.reclaimableBytes` 之和(v2: SQL 已算好,与 userKeepId 无关)
- `var trashEnabled: Bool` — pendingTrashCount > 0
- `func userKeepId(for group: DuplicateGroup) -> Int64` — 取该组用户手选保留张 id;无则取 DedupPass canonical id(单一权威读取入口)
- `func isSkipped(groupId: String) -> Bool` — skip 态查询
- `func isExpanded(groupId: String) -> Bool` — 展开态查询
- `func needsReview(group: DuplicateGroup) -> Bool` — D3 算法(详见 §5)

### §2.2 DuplicateGroup / DuplicateGroupMember(`Glance/Dedup/DuplicateGroup.swift`)

**保留不动的字段:**

```swift
struct DuplicateGroup: Identifiable, Equatable {
    let id: String                          // sha256
    let canonical: DuplicateGroupMember     // DedupPass 推荐保留张
    let duplicates: [DuplicateGroupMember]  // DedupPass 推荐副本
    let reclaimableBytes: Int64             // 注意: 这是 DedupPass 算的,用户改 userKeepId 后实际可省会变
}

struct DuplicateGroupMember: Identifiable, Equatable {
    let id: Int64
    let folderId: Int64
    let urlBookmark: Data
    let relativePath: String
    let fileSize: Int64
    let fullPath: String
    let isCanonical: Bool   // DedupPass 推荐保留张标记
}
```

**新增 helper(non-stored):**
```swift
extension DuplicateGroup {
    /// 该组所有成员(canonical + duplicates)统一数组,供 D1 per-item 选择遍历
    var allMembers: [DuplicateGroupMember] {
        [canonical] + duplicates
    }

    /// 推荐保留张 — DedupPass canonical(= earliest birth_time + 最小 id tie-breaker;
    /// **不是体积最大** — SHA256 invariant 下同组所有成员 fileSize 完全相等,无最大可言);
    /// model.userKeepId 无手选时回退到这个。
    var recommendedKeepId: Int64 { canonical.id }

    /// 副本数(总成员 - 1)
    var duplicateCount: Int { duplicates.count }
}
```

**v2 注**: v1 曾包含 `membersSortedBySize` helper 用于 size-ratio 算法 + ★ 推荐(体积最大),v2 全砍 — SHA256 invariant 下成员体积完全相等,排序结果不确定且无判别价值。

**为什么不加 stored 字段** — D1/D2 临时态语义,所有「用户选了什么」都集中在 `DuplicateOverviewModel.@Published` dict / set,DuplicateGroup 保持纯数据,不污染。

### §2.3 IndexStore SQL(`Glance/IndexStore/IndexedImage.swift`)

**保留不动:**
- `func fetchDuplicateGroups() throws -> [DuplicateGroupRow]`(line 643)
- `func fetchDuplicateGroupMembers(sha256: String) throws -> [DuplicateGroupMemberRow]`(line 678)
- `func deleteImage(folderId: Int64, relativePath: String) throws`(line 109)
- `func restoreImageFromSnapshot(_ snapshot: IndexedImageSnapshot) throws -> Int64`(line 850)
- `func fetchSnapshotForRestore(folderId: Int64, relativePath: String) throws -> IndexedImageSnapshot?`(line 768)
- `func promoteOrphanDuplicates() throws`(line 391)

**不动 schema** — D1/D2 临时态,不加列。

### §2.4 TrashService / TrashOutcome / TrashUndoBanner(`Glance/Dedup/Trash*.swift`)

**保留不动:**

```swift
// 嵌套在 TrashService 内的命名空间(v2 codex P2 精确化)
struct TrashService.TrashInput { let snapshot: IndexedImageSnapshot; let groupKey: GroupKey }

static func trashItems(
    _ items: [TrashInput],
    cancellation: TrashCancellationToken,
    progress: @Sendable @escaping (Int, Int) -> Void
) async -> TrashOutcome

static func restoreItems(
    _ items: [TrashSuccess],
    cancellation: TrashCancellationToken
) async -> RestoreOutcome

struct TrashOutcome / TrashSuccess / TrashFailure / RestoreOutcome / RestoreSuccess / RestoreFailure
actor TrashCancellationToken
```

`TrashUndoBanner` view 完全保留,本期不动。

**model.trashPending() 改造**: collectTrashInputs 用 `userKeepId(for: group)` 决定哪个 member 留,其它进 TrashInput。skippedGroupIds 中的组完全不参与。

### §2.5 FolderStoreIndexBridge(`Glance/IndexStore/FolderStoreIndexBridge.swift`)

**保留不动:**
- `func addIndexChangedObserver(_ observer: @escaping () -> Void) -> UUID`(line 45)
- `func removeIndexChangedObserver(_ token: UUID)`(line 52)
- `func triggerIndexChanged()`(line 69)
- `func requestRescan(folderId: Int64, relativePath: String) async throws -> Int64`(line 380)

### §2.6 AppearanceMode(`Glance/FullScreen/AppState.swift`)

**保留不动:**
- `enum AppearanceMode: String, CaseIterable`(line 9)
- `@Published var appearanceMode: AppearanceMode`(line 51)

**D4 锁** — 重复清理 V2 view 完全不感知主题,跟随全局自动切换。无独立分段控件。

### §2.7 ContentView 装配 + 五态互斥(`Glance/ContentView.swift`)

**保留不动的接线:**
- `@StateObject private var duplicateOverviewModel`(line 121)
- `@State private var showDuplicateOverview: Bool`(line 128)
- `.onChange(of: showDuplicateOverview)` 五态互斥块(line 392-410)
- `.onChange(of: duplicateOverviewModel.lastTrashOutcome?.id)` banner 触发(line 423)
- `.environmentObject(duplicateOverviewModel)`(line 268)
- `wireIfReady()` 内的 `duplicateOverviewModel.attach(...)`(line 751)

**唯一可能需要小改:**
- `.onChange(of: duplicateOverviewModel.groups) { _, newGroups in ... }` prune 块(line 416)— 当前 prune `selectedSha256s`(原整组勾选语义);改名后 prune `skippedGroupIds`(同名同语义,只改字段名)

### §2.8 SmartFolderListView.DuplicateCleanupRow(`Glance/FolderBrowser/SmartFolderListView.swift`)

**保留不动**(line 44 — 侧边栏 入口行,签名不变)。

### §2.9 loadThumbnail(`Glance/FolderBrowser/ImageGridView.swift`)

**保留不动:**
- `nonisolated func loadThumbnail(url: URL, maxPixelSize: Int) async -> NSImage?`(line 284)
- 新 view 中所有 thumbnail load 均复用此顶层函数(已在 DuplicateMemberCell.loadThumb 验过)

---

## §3 数据模型变更

**结论: 零 SQL schema 变更,零 DB migration。** 全部新状态在 `DuplicateOverviewModel.@Published` dict / set 里,内存态。

| 新增 in-memory state | 类型 | 用途 |
|---------------------|------|------|
| `userKeepIdByGroup` | `[String: Int64]` | D1 — 每组用户手选保留张;dict 不含该 group.id 时回退 DedupPass canonical |
| `skippedGroupIds` | `Set<String>` | D2 — 跳过组集合;改名自旧 selectedSha256s |
| `filter` | `enum DedupListFilter` | 工具条筛选选中态 |
| `sortOption` | `enum DedupSortOption` | 工具条排序选中态 |
| `searchQuery` | `String` | 搜索框文本 |
| `expandedGroupIds` | `Set<String>` | 列表展开态 |
| `focusReviewOpen` | `Bool` | 浮层开关 |
| `focusReviewQueue` | `[String]` | 浮层审阅队列(sha256 数组) |
| `focusReviewIndex` | `Int` | 浮层当前索引 |

**新增 enum(`Glance/Dedup/DedupListFilter.swift` 新文件;mirror SmartFolderState 单文件单 enum 约定):**

```swift
enum DedupListFilter: String, CaseIterable {
    case all
    case needsReview
    case auto
}

enum DedupSortOption: String, CaseIterable {
    case reclaimableDesc   // 可省空间降序(默认)
    case countDesc         // 副本数降序
    case nameAsc           // 标题 localeCompare 升序
}
```

**重启 / 重扫后行为(D1/D2 session 态语义明确):**
- 重启 app: 所有 in-memory state 归默认值;DedupPass 算的保留张回归权威
- 重扫(FSEvents 触发 model.scheduleReload → load): in-memory state **不会主动清空**;但 ContentView 现有 prune 块(line 416)扩展为**全量 prune**(codex P1 (reload prune 清单扩展) 修):
  - `skippedGroupIds` ∩ 新 groups.id(原 v1 已做)
  - `userKeepIdByGroup` entry 满足 (group.id 仍在 ∧ memberId 仍在 group.allMembers) 才保留
  - `reviewedGroupIds` ∩ 新 groups.id
  - `expandedGroupIds` ∩ 新 groups.id
  - 浮层若开着(`focusReviewOpen == true`):重新计算 `focusReviewQueue = reviewedGroupIds 还需 review 的;若 currentGroupId(队列[index])已不在新 groups → 自动推进 focusReviewIndex 到下一存活组,如全推完则 closeFocusReview()
- 若用户在重扫窗口期改过保留张,FSEvents reload 后该组若仍在 groups 中且该 member 仍存活,他的选择保留;若被合并 / 拆分到别的组或 member 已删,选择丢失(prune 移除,可接受)

---

## §4 UI 状态机(6 区域)

### §4.1 顶栏

```
[trash icon] 重复清理                           [移入废纸篓 (N)]
```

- 标题左侧: 红色背景 trash icon(macOS systemImage `trash.fill`,圆角矩形容器,DS.Dedup 危险色背景)
- 标题: 「重复清理」16px / 字重 700
- 右侧主操作按钮: 「移入废纸篓 (N)」红色 borderedProminent
  - N = `model.pendingTrashCount`
  - disabled when N == 0 → opacity 0.45
  - 点击 = `Task { await model.trashPending() }`
  - 删除中态(`trashState == .trashing`)换 ProgressView linear + 「取消」按钮(沿用现有)
- **删掉**: 设计稿原有的「深/浅」分段控件(D4)

### §4.2 汇总条

```
┌─────────────────────────────────────────────────────────────────┐
│ 扫描结果          [✓ 18 组]              [! 6 组]                │
│ 24 组重复         已自动留最优           建议你确认   [逐组审阅 ›]│
│ 可释放约 23 MB                                                   │
└─────────────────────────────────────────────────────────────────┘
```

- 左块: 小标签「扫描结果」(11.5px / sub 灰)→ 大数字「{groupCount} 组重复」(23px / 字重 760)→「可释放约 {totalReclaimable}」(12.5px,数字用 keep 绿)
- 竖分隔线 1px × 48px
- 中块(flex:1,横向 gap:26px):
  - 绿色徽标 ✓(checkmark.seal,30×30 圆角 8px,keepBg/keep)+「{autoCount} 组 / 已自动留最优」
  - 警告徽标 !(exclamationmark.triangle,30×30 圆角 8px,warnBg/warn)+「{reviewCount} 组 / 建议你确认」
- 右块: 「逐组审阅 ›」按钮
  - reviewCount > 0: warnBg 底 / warn 字 → 点击 `model.openFocusReview()`
  - reviewCount == 0: chip 底 / faint 字 / opacity 0.5 disabled

### §4.3 工具条

```
[全部 24] [待确认 6] [已自动 18]      排序 [可省][张数][名称]  🔍 搜索文件名…
```

- 左 — 筛选 pills(gap:6px):
  - 「全部 {n}」/「待确认 {n}」/「已自动 {n}」,n = 对应分类的组数
  - 圆角 20px,padding 6px 13px,12.5px / 580
  - 选中: text 底 + panel 字反色;未选中: chip 底 + sub 字 + border 边
  - 点击 → `model.filter = .xx`
- 中 — flex:1 撑开
- 右 — 排序分段控件: 标签「排序」+ 三选项「可省 / 张数 / 名称」,选中项 head 底 + text 字
- 最右 — 搜索框: chip 底 + 1px 边 + 圆角 8px,宽 190px,内含放大镜 SVG + TextField,placeholder「搜索文件名…」,绑 `model.searchQuery`

### §4.4 列表区

```
ScrollView(.vertical) {
    LazyVStack(spacing: DS.Dedup.groupRowSpacing) {
        ForEach(model.filteredSortedGroups) { group in
            DedupGroupRow(group: group)
        }
    }
}
```

**单行卡片(DedupGroupRow):**

```
┌──────────────────────────────────────────────────────────────────┐
│ [叠放缩略图] [组标题]                                  [删 N] [跳过] [v] │
│   3 张      保留 card.png · 可省 2.2 MB  [待确认 ⚠]                 │
└──────────────────────────────────────────────────────────────────┘
```

- 行头(HStack,gap:13px,padding 10px 14px,align center):
  - **叠放缩略图按钮**(52×40): 底层一张偏移灰块 + 上层 48×36 圆角 6px 缩略图(canonical),右下角小角标显示「{memberCount} 张」。点击 = 切展开态(`model.toggleExpand(groupId:)`)。**缩略图加载策略**: 复用 `loadThumbnail(url:maxPixelSize:)`,显示 `group.canonical`(若用户改过 userKeepId 则显示用户选的那张)的缩略图
  - **中间信息**(VStack,flex:1):
    - 第一行: 组标题 13.5px / 620(溢出省略)+ 可选徽章「待确认」(warnBg/warn)或「已确认」(keepBg/keep,= 用户已通过浮层审阅过)
    - 第二行: 「保留 {keepedMember.filename} · 可省 {group.reclaimableBytes}」(11px / sub,size 绿色);**v2 修正**: 「可省」直接读 `group.reclaimableBytes` 静态字段(SHA256 invariant 同组同体积,与 userKeepId 切换无关);仅「保留 {filename}」是动态(userKeepId 切换会改 filename — 这是「path/folder 偏好」语义价值)
  - **删除数徽章**: 「删 N」(dangerBg/dangerFg)或「已跳过」(chip/sub),圆角 20px,padding 3px 9px,11px / 600
  - **跳过/恢复按钮**: 透明底 + 1px 边 + 圆角 6px,「跳过此组」or「恢复清理」(根据 skip 态),点击 `model.toggleSkip(groupId:)`
  - **展开 chevron**(24×24,faint 色): `transform: rotate(0/180deg)`,`.animation(.easeInOut(duration: 0.18), value: expanded)`
- 已跳过组: 整行 opacity 0.55

**展开区(group.expanded == true):**

```
┌──────────────────────────────────────────────────────────────────┐
│ [▼ 行头]                                                         │
├──────────────────────────────────────────────────────────────────┤
│ [card.png 1.3MB] [card_copy.png 1.2MB] [card_v2.png 800KB]      │
│  ✓ 保留 ★ 推荐    ✕ 待删             ✕ 待删                       │
└──────────────────────────────────────────────────────────────────┘
```

- 顶部 1px 分隔线
- 内部 HStack + .padding 12px 14px 14px,gap 11px,flex-wrap(用 FlexLayout 或多行 HStack 包装 — 90px cell wrap)
- 每张缩略图按钮宽 90px:
  - 90×66 圆角 8px 缩略图(loadThumbnail maxPixel 180)
  - 保留态(`member.id == model.userKeepId(for: group)`): 2px keep 绿描边 + 左上「✓ 保留」徽标
  - 待删态(非保留且组未跳过): rgba(10,10,12,0.42) 暗罩 + 右上 18px 圆形 danger 底 白色 ✕ 角标 + opacity 0.55
  - **v2 砍**: 原 v1 写「★ 推荐(体积最大)」角标 — SHA256 invariant 下同组同体积,★ 无判别价值,展开区**不显示任何 ★** (codex P0-2 修)
  - 跳过态: 全部缩略图 opacity 0.55,无 ✕ 角标,无暗罩(整组不删)
  - 图下: 「{filename} · {folderName}」(10.5px / faint,溢出省略,宽 90px);**v2 修正**: 不显示「· {size}」(全成员同体积,显示反而误导);改显 folder name 强化「path/folder 偏好」语义
- 点任意缩略图 = `model.setUserKeep(groupId: group.id, memberId: member.id)` → 该图变保留张,其余转待删 + 该组若 skip 则取消

### §4.5 逐组审阅浮层 — D6

```
ZStack {
    主界面(背后,被 .ultraThinMaterial 模糊覆盖)
    .ultraThinMaterial(rgba 0,0,0,0.55 等效)
    对话框(780px,head 底,圆角 18px,阴影)
}
.zIndex(999)
```

**对话框结构(VStack):**

```
┌──[ 逐组审阅 ] 开发者文档页              1 / 6   [×]──┐
│  点选你想保留的那一张,其余将被删除。提示: ← → 切换  │
│  组,回车确认                                       │
│                                                    │
│   ┌─────────────┐    ┌─────────────┐              │
│   │ ★ 推荐(体积最大)│   │             │              │
│   │             │    │             │              │
│   │             │    │             │              │
│   │   docs.png  │    │  docs copy   │              │
│   │  ✓ 保留     │    │   待删       │              │
│   └─────────────┘    └─────────────┘              │
│   docs.png            docs copy.png                │
│   测试图片 · 1.1 MB   截图 · 1.1 MB                 │
│                                                    │
│  [上一组]                 [跳过此组]  [确认并继续 ›]│
└────────────────────────────────────────────────────┘
```

- 头部(padding 16px 22px,底部 1px 分隔):
  - 左: 「逐组审阅」标签(warnBg/warn,圆角 20px)+ 组标题(15px / 680)
  - 右: 「{focusReviewIndex+1} / {focusReviewQueue.count}」+ 关闭 ✕ 按钮(28×28 圆角 7px,chip 底),点 = `model.closeFocusReview()`
- 主体(flex:1,padding 22px,ScrollView 必要时):
  - 提示文字「点选你想保留的那一张,其余将被删除。提示: ← → 切换组,回车确认」(12.5px / sub)
  - HStack(flex-wrap,gap 14px,居中)— 大图对比每张宽 300px:
    - 300×214 圆角 12px(loadThumbnail maxPixel 600;若超过 cell 实际尺寸不影响,用户看大图就要清晰)
    - **v2 砍**: 原 v1 写「★ 推荐(体积最大)」左上角标 — SHA256 invariant 下无判别价值,浮层**不显示任何 ★**(codex P0-2 修)
    - 保留态: 3px keep 描边 + 右下「✓ 保留」徽(12px / 700)
    - 待删态: rgba(10,10,12,0.4) 暗罩 + 右下「待删」徽(danger 底)+ opacity 0.55
    - 图下: 文件名(13px / 600)+「{文件夹} · {filename.ext}」(11.5px / faint);**v2 修正**: 砍「· {size}」(同体积无意义),改显完整 folder 路径强化「path 偏好」决策辅助
  - 点缩略图 = `model.setUserKeep(groupId: currentGroup.id, memberId:)` → 立即更新视觉,不自动推进
- 底部操作条(padding 14px 22px,顶部 1px 分隔,panel 底):
  - 左: 「上一组」(透明 + 1px 边),disabled when focusReviewIndex == 0,点击 `model.focusReviewPrev()`
  - 右: 「跳过此组」(chip 底,点击 `model.focusReviewSkip()`)+「确认并继续 ›」/「确认并完成」(keep 绿实底,点击 `model.focusReviewConfirm()`)
    - 文案: 「确认并完成」when `focusReviewIndex == focusReviewQueue.count - 1`,否则「确认并继续 ›」

### §4.6 空态 / 错态 / 重扫中态

完全沿用 §2.1 现有 view 的三态(emptyState「没找到重复图」/ errorState「加载失败」/ rescanningState「重新扫描中…」),仅样式上跟设计稿对齐(空态绿 ✓ 圆形 icon + 「重复项已全部处理」)。

---

## §5 needsReview 算法(D3 — v2 重写)

### §5.1 规则(v2 codex P0-1 修)

```swift
func needsReview(group: DuplicateGroup) -> Bool {
    // SHA256 invariant(D-dedup-14): 同组所有成员 fileSize 完全相等,体积比恒 1.0。
    // 唯一有判别价值的维度是「组太大,自动判优风险高」 — 用副本数。
    // 阈值 3 = 副本 ≥ 3 张(组共 ≥ 4 张),用户值得手动审一遍挑保留 path/folder。
    return group.duplicateCount >= 3
}
```

**为什么不是 ≥ 2 / ≥ 4**:
- `≥ 2`(组 ≥ 3 张) — 太敏感,大量组进 needsReview,失去筛选意义
- `≥ 4`(组 ≥ 5 张) — 太宽松,组共 4 张(3 张副本)用户也想审
- `≥ 3` 是经验阈值,可在 follow-up 调整(若军哥真机验觉得太敏感/宽松)

### §5.2 边界 case(v2 重写)

| Case | needsReview 输出 | 理由 |
|------|-----------------|------|
| 单成员组(理论上 DedupPass 不产出,防御) | false | 没副本,`duplicateCount = 0 < 3` |
| 2 张组(1 张副本) | false | `duplicateCount = 1 < 3` → 自动留 DedupPass canonical |
| 3 张组(2 张副本) | false | `duplicateCount = 2 < 3` → 自动留 |
| **4 张组(3 张副本)** | **true** | `duplicateCount = 3 >= 3` → 待确认(阈值边界,刚刚命中) |
| 10 张组(9 张副本) | true | 副本数远 ≥ 3 → 待确认(组太大用户介入价值最高) |

**v2 已知缺陷**: 此 needsReview 算法 SHA256 模型下唯一可用维度就是 `duplicateCount`,无法基于成员内容差异(SHA256 字节级相同就是相同)。这是 SHA256 invariant 的天然约束(D-dedup-14),非算法 bug。

### §5.3 reviewed 标记语义

- `model.focusReviewConfirm()` 把当前组从 `needsReview && !reviewed` 状态推进到「已审阅」— 视觉上行卡片徽章从「待确认」(warnBg/warn)变「已确认」(keepBg/keep)
- 「已确认」是**临时态**: 不写 DB,session 内有效;FSEvents 重扫后该组若仍存在,reviewed 状态在内存中保留;app 重启清空
- 工具条筛选「已自动」分类语义: 该组 `needsReview == false`(自动归类)或 `needsReview == true && reviewed == true`(用户审阅过)

为承载 reviewed 状态,在 §2.1 已声明 `@Published private(set) var reviewedGroupIds: Set<String>`(v2 整合到 §2.1 stored properties 列表;同 skippedGroupIds 平级 @Published in-memory):
- `func markReviewed(groupId: String)` — focusReviewConfirm / focusReviewSkip 内部调
- `func isReviewed(groupId: String) -> Bool` — view / filter 用

---

## §6 逐组审阅浮层(D6 — ZStack overlay + .ultraThinMaterial)

### §6.1 渲染位置

**在 ContentView 主 ZStack 内挂 `.overlay`(zIndex 高),而非 .sheet:**

```swift
// ContentView.body 主区
ZStack {
    // 既有: baseGrid / SmartFolderGridView / 临时结果 / 搜索 overlay / 重复清理总览(DedupCleanupV2View)
    // 既有: previewOverlay
}
.overlay(alignment: .center) {
    if duplicateOverviewModel.focusReviewOpen {
        DedupFocusReviewOverlay()
            .environmentObject(duplicateOverviewModel)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
.animation(.easeOut(duration: 0.18), value: duplicateOverviewModel.focusReviewOpen)
```

**为什么不用 .sheet:**
1. 设计稿要求**全屏 modal 但无 sheet chrome**(无下拉、无 dismiss bar、无 macOS 标题栏)
2. 自定义关闭路径(ESC / × / 确认完最后一组自动关)— sheet 默认 ESC 行为不可控
3. 与既有 QuickViewer 独立 NSWindow 模式风格统一(不强行嵌 SwiftUI 内置 chrome)

### §6.2 背景模糊层

```swift
Rectangle()
    .fill(.ultraThinMaterial)
    .overlay(SwiftUI.Color.black.opacity(0.4))   // 加深背景以 mirror 设计稿 rgba(0,0,0,0.55) 效果
    .ignoresSafeArea()
    .onTapGesture { model.closeFocusReview() }   // v2 锁 A: 点击外部关闭(D-dedup-7)
```

**D-dedup-7 锁定 A**(v2 codex P1 (click-outside 锁定) 拍板): **点击外部关闭浮层** — macOS Spotlight / Quick Look 标准模态行为,符合用户习惯;误触风险存在但远低于阻断标准交互的代价。对话框本体 `.contentShape(Rectangle())` 拦截点击事件不冒泡到背景层。

### §6.3 焦点策略 + 键盘(v2 codex P0-3 重写)

**v1 设计缺陷(codex P0-3 抓)**: 原方案另起 `overlayFocused: FocusState` 与现有 `ContentView.@FocusState focusTarget` 仲裁链脱节,SwiftUI 内层 `.focused()` 抢权未必能阻止 body 级 ancestor `.onKeyPress(.init("f"))` 监听,模态期 ⌘F 等快捷键拦截**未经验证**。

**v2 修复**: **接入既有 `focusTarget` 仲裁链**,不另起一套:

```swift
// ContentView.swift 现有 enum FocusTarget(查 ContentView.swift L154-158 / SearchOverlayView.swift L52-67)
enum FocusTarget {
    case grid       // V1/V2 grid 焦点
    case preview    // 内嵌预览
    case search     // ⌘F 搜索框 input
    case dedupOverlay   // v2 新增 — 逐组审阅浮层焦点
}

// 浮层打开 / 关闭时切 focusTarget
extension DuplicateOverviewModel {
    func openFocusReview() {
        // ...计算队列...
        focusReviewOpen = true
        // 副作用: ContentView .onChange(of: focusReviewOpen) 时切
        //   focusTarget = .dedupOverlay (打开) / 上一个值 (关闭)
    }
    func closeFocusReview() {
        focusReviewOpen = false
    }
}

// ContentView 仲裁
.onChange(of: duplicateOverviewModel.focusReviewOpen) { _, isOpen in
    if isOpen {
        previousFocusTarget = focusTarget   // 保存以便关闭后归还
        focusTarget = .dedupOverlay
    } else {
        focusTarget = previousFocusTarget ?? .grid   // 默认归还 grid
        previousFocusTarget = nil
    }
}

// 浮层 view
DedupFocusReviewOverlay()
    .focused($focusTarget, equals: .dedupOverlay)   // 同既有 SearchOverlay 模式
    .onKeyPress(.leftArrow)  { model.focusReviewPrev(); return .handled }
    .onKeyPress(.rightArrow) { model.focusReviewNext(); return .handled }
    .onKeyPress(.return)     { model.focusReviewConfirm(); return .handled }
    .onKeyPress(.escape)     { model.closeFocusReview(); return .handled }
```

**关键变化**:
1. **同既有焦点链** — `.focused($focusTarget, equals: .dedupOverlay)` mirror `SearchOverlayView` 现有用法(SearchOverlayView.swift:52 已验证模式),不引入第二个 `@FocusState`
2. **`focusTarget = .dedupOverlay`** 时,body 级 `.onKeyPress(.init("f"))` 等监听仍然挂着,但 SwiftUI 单焦点链下事件先路由到 focusTarget 当前持有者 = 浮层,浮层 `.onKeyPress(.escape)` 等返回 `.handled` 后**事件不冒泡**到 ancestor(SwiftUI focus chain 标准行为)
3. **⌘F 等系统快捷键**: 仍由 macOS 路由到 first responder 链,浮层 focused 时 first responder = 浮层 hosting view → ⌘F 不到搜索框。**已证实安全**(SearchOverlay 用同模式 ⌘F 期间也不撞)
4. **归还**: 关闭时 `focusTarget = previousFocusTarget` 显式归还(避免 SwiftUI 某些场景 nil 后 focus 漂移到不该的视图)

**新增 ContentView state**: `@State private var previousFocusTarget: FocusTarget?`(单一职责: 保存浮层打开前的焦点状态以便归还)

### §6.4 ESC 双段语义

| 场景 | ESC 行为 |
|------|---------|
| 重复清理总览 + 浮层未开 | **无行为**(grep 确认 ContentView 顶层无 `.onKeyPress(.escape)` handler,沿用现状不加 — 总览不是临时态视图,用户切走用 侧边栏 即可,ESC 退出语义对总览无价值) |
| 浮层开 | 关浮层,主区不动(由浮层 `.onKeyPress(.escape)` 单层处理) |

**注**: 不模仿快速看图器 ESC 退全屏的两段(那个是 NSWindow level 全屏退出);本浮层是 SwiftUI ZStack overlay,只有一段「关浮层」。

### §6.5 进入 / 退出转场动画

- 进入: `.transition(.opacity.combined(with: .scale(scale: 0.96)))` + `.animation(.easeOut(duration: 0.18))`
- 退出: 反向 — `.animation(.easeIn(duration: 0.15))`
- 背景模糊: 跟随 overlay 一起 fade in/out

---

## §7 决策登记(D-dedup-N)

> 编号约定: `D-dedup-N`(mirror `D-OW` / `D-QV` / `D-mb`)。本期 design 锁的硬决策记此段,后续 plan / commit / PR 引用必须带含义。

| 编号 | 决策 | 锁定方案 | 理由 |
|------|------|---------|------|
| **D-dedup-1** | per-item 选保留张持久化 | **临时态**(@Published in-memory `userKeepIdByGroup`,不写 DB) | 不污染 DedupPass canonical(算法 ground truth);初心红线「不抢库」延伸语义 — 用户每次清理是独立 session,DedupPass 永远讲事实;若用户希望永久化是 followup decision |
| **D-dedup-2** | 跳过组持久化 | **session 态**(@Published in-memory `skippedGroupIds`,不写 DB) | 跳过 = 「这次不处理」,不是「永久标记这组永远不清」;后者是不同语义,加 DB 字段是 followup |
| **D-dedup-3** | needsReview 算法(**v2 codex P0-1 重写**) | **`duplicateCount >= 3`** (砍 v1 size-ratio 分支) | SHA256 invariant(D-dedup-14): 同组 sha256 → fileSize 完全相等 → 体积比恒 1.0 < 1.1 永远成立,三档 filter 全塌进「待确认」;砍掉此分支;阈值 ≥ 3 经验值,可 follow-up 调整 |
| **D-dedup-4** | 主题切换 | **跟随全局 AppearanceMode**,砍设计稿独立分段 | 项目已有完整深/浅/系统三档体系;独立分段是冗余且与全局设置不一致风险 |
| **D-dedup-5** | 分页加载 | **砍掉**,LazyVStack 全量渲染 | macOS 原生范式;LazyVStack 几百组无压力;符合「克制」红线;「加载更多」是 web 思维强行进 native |
| **D-dedup-6** | 逐组审阅浮层实现 | **ZStack overlay + .ultraThinMaterial 背景**,而非 .sheet / NSWindow | 设计稿要求全屏 modal 无 sheet chrome;自定义 ESC / × / click-outside 关闭路径不能用 sheet;NSWindow 独立窗对总览不必要(总览本身在主窗,浮层在主窗上即可) |
| **D-dedup-7** | 点击外部蒙层是否关闭浮层 | **锁定 A: 点击外部关闭**(macOS Spotlight 风格) | 标准 macOS 模态行为;v2 codex P1 (click-outside 锁定) 拍板;对话框本体 `.contentShape(Rectangle())` 拦截 inner 点击不冒泡 |
| **D-dedup-8** | reviewed 状态持久化 | **session 态**(@Published `reviewedGroupIds`,不写 DB) | 跟 D-dedup-2 同语义;app 重启清空合理,因为 needsReview 是动态算的,组本身可能下次扫描就消失 |
| **D-dedup-9** | trashPending 的「保留张」来源 | **优先用 `userKeepIdByGroup`,无则回退 DedupPass `canonical`** | model.userKeepId(for:) 是单一权威入口;保留张 ≠ canonical 时用户手选优先 |
| **D-dedup-10** | 砍掉「智能挑选」/「全部保留」批量按钮 | **不做** | DedupPass 默认就是「智能挑选」,无需按钮重置;「全部保留」= 全跳过,跳过按钮已能做;设计稿 DuplicateCleanup 主交付本身没这两按钮(只 CleanupComparison 三变体里有) |
| **D-dedup-11** | 砍掉「重新扫描」按钮 | **不做** | FSEvents 自动 ingest + bridge.triggerIndexChanged + model.scheduleReload 已经做了实时刷新;加按钮反而混淆「为什么不自动?」 |
| **D-dedup-12** | ★ 推荐(体积最大)角标(**v2 codex P0-2 全砍**) | **展开区 + 浮层均不显示 ★** | SHA256 invariant(D-dedup-14): 同组成员 fileSize 完全相等,「体积最大」不存在;★ 角标会误导用户以为「这张是体积更大的原图」 |
| **D-dedup-13** | 「待确认」徽章是否在筛选 = needsReview 时仍渲染 | **仍渲染** | 视觉一致性: 筛选不影响单行卡片的徽章语义;徽章是组属性不是筛选结果 |
| **D-dedup-14** | **SHA256 invariant**(v2 新增,根本数据模型约束) | **同 sha256 → fileSize 完全相等**;后续 plan/commit/PR 引用本设计时必须遵守 | DedupPass 基于 SHA256 内容哈希,字节级相同才进同组;任何「比较成员 fileSize 差异」算法在本模型下永远恒成立或恒不成立,无判别价值;任何「user 切换保留张省更多/更少字节」UX 不存在 |
| **D-dedup-15** | focus chain 接入既有仲裁链(**v2 codex P0-3 修**) | **`ContentView.@FocusState focusTarget` 加 `.dedupOverlay` case;不另起 `overlayFocused`** | v1 设计另起焦点链未证拦截,SwiftUI 单焦点链 mirror SearchOverlayView 现有模式(L52 已验证);浮层关闭显式归还 `previousFocusTarget` |

---

## §8 风险段

### §8.1 per-item 切换时 in-flight thumb load 竞态

**场景**: 用户在展开区快速点 A → B → C 切换保留张,每次点击触发 view 重 render → DuplicateMemberCell 的 `.task(id: member.id)` 重启 loadThumb。

**风险**: 旧 task 还没取消时新 task 已启动 → 多个 background thread 抢 thumbnail 写回。

**缓解**: 现有 `DuplicateMemberCell.loadThumb` 已用 `Task.detached + Task.isCancelled` guard(line 297),`.task(id:)` SwiftUI 自动取消上一轮 task。低风险。

### §8.2 跨视图切换时 state 残留

**场景**: 用户在重复清理总览选了几个保留张 + 跳过几个组,切到智能文件夹/搜索,回来。

**风险**: state 应该保留还是清空?

**结论**: **保留**(单一 ContentView 持 `@StateObject duplicateOverviewModel` app 寿命,切走 = view 不渲染但 state 在;切回 = 状态原样)。这是 model 持有状态的天然行为,符合用户预期(我刚才挑了一半,切走查个东西,回来不丢失)。

**例外**: app 重启清空(D-dedup-1/2/8)。

### §8.3 FSEvents 重扫后 userKeepIdByGroup 残留

**场景**: 用户在 group A(sha256=X)挑保留张 m1;FSEvents 触发重扫,group A 的成员变了(其中一张被外部删了),m1 已不在新成员里。

**风险**: `userKeepId(for: group)` 返回 m1.id,但 m1 已经不在 group 里 → view 渲染哪张?

**缓解**: `userKeepId(for:)` 的实现:
```swift
func userKeepId(for group: DuplicateGroup) -> Int64 {
    if let userId = userKeepIdByGroup[group.id],
       group.allMembers.contains(where: { $0.id == userId }) {
        return userId
    }
    return group.recommendedKeepId   // 回退 DedupPass canonical
}
```

**清理时机**: ContentView 的 `.onChange(of: duplicateOverviewModel.groups)` prune 块(line 416)扩展 — 既 prune `skippedGroupIds`(原 selectedSha256s)又 prune `userKeepIdByGroup`(同语义,移除不在新 groups 的 entry)。

### §8.4 trashPending 期间用户改保留张

**场景**: 用户点「移入废纸篓」,trashState = .trashing,这时用户在另一展开行点改保留张。

**风险**: trashPending 已 snapshot `selectedSha256s` 和 `groups`(line 196-197),但 userKeepIdByGroup 没 snapshot → trashPending 中间读取 model.userKeepId 可能拿到改后的 id。

**缓解**: 在 `trashPending()` 入口处一次性 snapshot 所有依赖:
```swift
let snapshotKeepIds = self.userKeepIdByGroup
let snapshotSkipped = self.skippedGroupIds
let snapshotGroups = self.groups
let inputs = await collectTrashInputs(
    store: store,
    groups: snapshotGroups,
    skippedGroupIds: snapshotSkipped,
    userKeepIds: snapshotKeepIds
)
```

trashing 过程中即便用户改了 model 状态,collectTrashInputs 走的是 snapshot,不影响。

### §8.5 撤销 banner 与新设计兼容性

**TrashUndoBanner contract** — 现有 banner 显示「已移 N 张到废纸篓 + [撤销] [×]」,N = `outcome.trash.successCount`。

新设计的 trashPending 输出仍是 TrashOutcome,banner 渲染逻辑不变。**零兼容性问题。**

### §8.6 SHA256 invariant 教训(v2 重写)

**v1 设计错误**: 我 brainstorming 时把「★ 推荐(体积最大)」当作有效信号,把 needsReview size-ratio 当作判别维度,实际上同 sha256 必然同 fileSize(D-dedup-14)。

**v2 已修**:
- D-dedup-3 砍 size-ratio 分支,只保留 `duplicateCount >= 3`
- D-dedup-12 ★ 全砍
- 列表行 / 浮层文案均不显示「· {size}」(展开区 cell / 浮层 cell 都改),改显 folder 路径
- D-dedup-14 显式登记 SHA256 invariant,后续 plan / commit 引用必守

**剩余设计哲学**(无冲突):
- DedupPass canonical(SQL 层)→ 一定要选一个保留张,「earliest birth_time + 最小 id」是稳定的事实层定义
- userKeepId(view 层)→ 用户对 path/folder 偏好(例如想留「素材」目录里的而非「Downloads」里的)
- view 层默认保留张 = DedupPass canonical;用户主动改 → userKeepId 覆盖

**跨项目沉淀触发**: 本期遗漏是「写 plan 引用已有代码先 Read 实际文件」+「调研数据模型时漏问 invariant」的延伸 — `fetchDuplicateGroups` SQL 的 `GROUP BY content_sha256` 加上 `INSERT INTO images ... fileSize, contentSHA256` 的 unique 约束应该立刻让我意识到「同组同体积」。后续 plan 阶段任何引用「成员体积差异」的描述必须先核 SHA256 invariant。

### §8.7 浮层焦点 vs 主窗其它键盘 listener(v2 codex P0-3 重写)

**v2 修复方案**(§6.3 已详述): 接入既有 `ContentView.@FocusState focusTarget` 仲裁链,加 `.dedupOverlay` case;浮层 view 加 `.focused($focusTarget, equals: .dedupOverlay)`(mirror `SearchOverlayView.swift:52` 已验证模式)。

**与 SearchOverlay 类比**: 既有 ⌘F 搜索 overlay 用同一 `focusTarget = .search` 模式,⌘F 期间 ContentView body 级 `.onKeyPress(.init("f"))` 不撞 — 已实证。重复清理浮层 `focusTarget = .dedupOverlay` 复用同一机制,**无新增技术风险**。

**关闭归还**: `focusTarget = previousFocusTarget ?? .grid`(显式归还,避免 SwiftUI 漂移)。`previousFocusTarget` 在浮层打开瞬间保存。

**v2 增量风险点**: 若用户在浮层打开期间用 侧边栏 切到智能文件夹(showDuplicateOverview = false),五态互斥块(ContentView L392-410)会强制清状态,但 `focusReviewOpen` 不在五态互斥列表里 → 浮层 stale 显示。**缓解**: ContentView 五态互斥块每个 onChange 入口加 `duplicateOverviewModel.closeFocusReview()` 兜底(关浮层后焦点链自动归还正确目标)。归入任务 AB 实施清单。

### §8.8 删除中态用户开浮层

**场景**: trashState = .trashing,用户点「逐组审阅 ›」。

**风险**: 浮层打开,但 model.groups 可能在 trash 完成时 reload 改变,浮层 focusReviewQueue 含 stale group。

**缓解**:
- 选 a: trashing 期间「逐组审阅 ›」按钮 disabled
- 选 b: 允许打开,model.focusReviewQueue 重新从最新 groups 拉(focusReviewQueue 已是 sha256 数组,reload 后若 sha256 不在新 groups 中 → currentGroup nil → 自动推进或关闭)
- **倾向选 a** — 简单 + 防误用。trashing 是有限时长(几秒)操作,disabled 体验 OK。

---

## §9 任务粒度初拟(vertical 切分,留给 writing-plans 细化)

> 按 CLAUDE.md「## 处理 issue 流程」第 2/3 步硬约束: 每片满足端到端可跑 + 用户可感知 + 独立可 ship 三条。本段只是初拟方向,writing-plans skill 产 implementation-plan.md 时会细化到具体 commit / 改动 / 测试计划。

**初拟 5 个任务(代号 AB / C / D / E / F,v2 codex P1 (任务 A+B 合并) 修: A+B 合并成 AB 不留过渡态)**:

### 任务 AB — Model 重构骨架 + 新 View 主体(v2 合并,6-9 commit)

**合并理由**(codex P1 (任务 A+B 合并)): v1 拆 A+B 时任务 A 单独 ship 会让旧 checkbox UI 语义从「整组勾选清掉副本」变成「跳过整组」,用户可见行为处于过渡态,违反「独立可 ship」原则。v2 合并 — Model + View 同任务,**不在中间留过渡 commit**。

- `DedupListFilter` / `DedupSortOption` enum 新建(`Glance/Dedup/DedupListFilter.swift`)
- `DuplicateOverviewModel` 改造: selectedSha256s → skippedGroupIds + 新增 userKeepIdByGroup / reviewedGroupIds / filter / sortOption / searchQuery / expandedGroupIds / focusReview* 字段;trashSelected → trashPending(用 userKeepId 而非 SQL dedup_canonical=1)
- `DuplicateGroup` extension 加 helper(allMembers / recommendedKeepId / duplicateCount;**v2 不加 `membersSortedBySize`** — 砍 ★ 推荐后无用)
- ContentView prune 块**全量扩展**(codex P1 (reload prune 清单扩展)): skippedGroupIds + userKeepIdByGroup + reviewedGroupIds + expandedGroupIds + focusReviewQueue/Index;五态互斥块每个 onChange 入口加 `closeFocusReview()` 兜底(§8.7)
- `DedupCleanupV2View` 新文件替换 `DuplicateOverviewView`(后者 git mv 改名 → 新文件)
- 顶栏 + 汇总条 + 工具条 + 列表(基础展开)实现
- DS.Dedup 段扩展(汇总条 / 工具条 / 列表行 / 展开区缩略图 90×66 等新常量)
- 展开区 per-item 选择(点缩略图 setUserKeep);**v2 砍** ★ 推荐角标
- 列表行动态文案修正(v2): 「保留 {filename} · 可省 {static}」— 仅 filename 是动态
- ContentView mainContent ZStack 替换 `DuplicateOverviewView()` → `DedupCleanupV2View()`
- **端到端可跑**: 全新 UI 上线,per-item 选择 + 跳过组 + 筛选/排序/搜索全部可用
- **用户可感知**: 视觉完全新设计,所有交互 → trash 按钮 trashPending
- **独立可 ship**: 编译 0 error 0 warning,verify.sh 三段过,一次性切换不留过渡态

### 任务 C — needsReview 算法 + 待确认徽章(1-2 commit)

- model `needsReview(group:)` 实装
- 汇总条 ✓ autoCount / ! reviewCount 徽标
- 列表行「待确认」/「已确认」徽章
- 筛选「待确认 / 已自动」分类联动
- **端到端可跑**: 用户可以一眼看出哪些组要确认
- **用户可感知**: 视觉强提示
- **独立可 ship**: 单独 commit

### 任务 D — 逐组审阅浮层(3-4 commit)

- `DedupFocusReviewOverlay` 新文件
- ZStack overlay + .ultraThinMaterial 背景
- 大图对比布局(loadThumbnail maxPixel 600);**v2 砍** ★ 推荐(体积最大)角标
- **focus chain 接入既有 `focusTarget` 仲裁链**(v2 P0-3 修): ContentView FocusTarget enum 加 `.dedupOverlay` case + 新增 `@State previousFocusTarget: FocusTarget?` + `.onChange(of: focusReviewOpen)` 仲裁切换 + 浮层 `.focused($focusTarget, equals: .dedupOverlay)` mirror SearchOverlayView
- 键盘 ← → Enter Esc(浮层 `.onKeyPress`,返回 `.handled` 阻止冒泡)
- 上一组 / 跳过 / 确认 / 关闭按钮
- 浮层入口: 汇总条「逐组审阅 ›」按钮 → model.openFocusReview()
- click-outside 关闭(D-dedup-7 锁 A): 背景层 `.onTapGesture { model.closeFocusReview() }`;对话框 `.contentShape(Rectangle())` 拦截 inner 点击不冒泡
- **端到端可跑**: 用户可连续审阅 N 组
- **用户可感知**: 全新工作流
- **独立可 ship**: 任务 C 之后单独可 ship

### 任务 E — 进入 / 退出动画 + 浮层边界细节(1-2 commit)

- `.transition(.opacity.combined(with: .scale))`,easeOut/easeIn 时长 0.18s/0.15s
- 浮层 click-outside dismiss(D-dedup-7,军哥拍板后决定加不加)
- 焦点归还主区
- ESC 双段语义确认(§6.4)
- trashing 期间「逐组审阅 ›」disabled(§8.8)
- **端到端可跑**: 视觉打磨完成
- **用户可感知**: 浮层进出顺滑无突兀
- **独立可 ship**: 收尾 commit

### 任务 F — 文档同步 + verify + PENDING 收尾(1-2 commit)

- specs/Roadmap.md「重复清理 V2」段
- CLAUDE.md 项目文件结构同步
- D-dedup-N 决策段沉淀到 specs/Roadmap.md「关键架构决策」段
- PENDING-USER-ACTIONS.md 加军哥真机验项(列表交互 / 浮层键盘 / 不同筛选/排序/搜索组合 / trashPending + undo / 跨视图 state 保留 / app 重启清空)
- /go 五步 Stage 1d 字典检查
- **端到端可跑**: ship 状态
- **用户可感知**: 真机肉眼验
- **独立可 ship**: 收尾 commit

---

## §10 测试 / 验收

### §10.1 单测(可加,非阻塞 — 项目无 XCTest target,等价用 verify.sh 三段)

- `needsReview(group:)` 各边界 case 验(§5.2 表逐行 — v2 简化后仅 5 case)
- `userKeepId(for:)` 回退路径(userKeepIdByGroup 中 entry 但 id 不在 group.allMembers)
- `filteredSortedGroups` 三种 filter × 三种 sort × 有/无 searchQuery 组合
- `pendingTrashCount` / `pendingReclaimableBytes` 与 userKeepId 切换无关性验证(v2 codex P0-2)

### §10.2 PENDING 军哥本机肉眼验

| # | 项 | 通过标准 |
|---|---|---|
| 1 | 总览顶栏 + 汇总条 + 工具条三区域视觉 | 跟截图 01 对得上,中文文案 OK |
| 2 | 点缩略图改保留张 | 该图绿描边出现,其它图暗罩 + ✕,组「保留」文案更新 |
| 3 | 跳过组 | 整行 opacity 0.55,「删 N」变「已跳过」,「移入废纸篓 (N)」N 数字下降 |
| 4 | 三筛选 pill | 全部/待确认/已自动 切换,列表正确过滤 |
| 5 | 三排序选项 | 可省/张数/名称 切换,列表正确排序 |
| 6 | 搜索文件名 | 输入「card」过滤出含 card 文件名的组 |
| 7 | 「逐组审阅 ›」 | 浮层打开,显示第一组待确认 |
| 8 | 浮层键盘 ← → Enter Esc | 各键正确路由(切组 / 确认 / 关) |
| 9 | 浮层最后一组「确认并完成」 | 按钮文案变,点击关浮层 |
| 10 | 「移入废纸篓 (N)」 | TrashOutcome 弹出 banner,跳过组的文件未移入废纸篓 |
| 11 | 撤销 | banner 撤销按钮把文件 restore 回原 path + DB row 回 |
| 12 | 跨视图切换 state 保留 | 切到智能文件夹/搜索回来,选择 + 跳过 + 展开态全在 |
| 13 | app 重启 state 清空 | 重启后所有选择 / 跳过 / 展开 / filter 归默认 |
| 14 | 跟随全局 AppearanceMode | 深/浅/系统切换 → 总览跟着切换 |
| 15 | 重扫期间 state 兼容 | 删一张被选中保留张的图,FSEvents reload 后 view 退回 DedupPass canonical(无 crash) |
| 16 | **浮层打开时 FSEvents reload**(v2 codex P2 (PENDING 浮层 stale state) 新增) | 浮层打开看第 i 组,外部删该组某张 → FSEvents 触发 reload → 浮层 currentGroup 已不在新 groups → 自动推进 focusReviewIndex(全推完则 closeFocusReview);无 crash,无 stale 渲染 |
| 17 | **点击浮层外部背景**(v2 D-dedup-7 锁 A 新增) | 点击模糊背景层 → 浮层关闭;点击对话框 inner 区域不触发关闭 |
| 18 | **focus chain 归还**(v2 P0-3 新增) | 浮层关闭后 ⌘F 仍能正常打开搜索 overlay(焦点链没漂移到错误目标) |
| 19 | **needsReview 阈值边界验**(v2 P0-1 重写后) | 4 张组(3 副本)进「待确认」;3 张组(2 副本)进「已自动」;此阈值是否符合直觉 — 军哥真机定夺是否调整 |

---

## §11 下一步

**当前状态**: design v2(codex review APPROVE-WITH-FIXES 已折入 3 P0 + 4 P1 + 3 P2,军哥拍板「按此走」 — 2026-06-19)

1. ✅ design v1 写完 + spec self-review pass + verify.sh 三段过(14 项)
2. ✅ codex:rescue read-only review → APPROVE-WITH-FIXES verdict(3 P0 + 4 P1 + 3 P2)
3. ✅ verdict 报告军哥 → 军哥拍板「按此走,折入 v2」
4. ✅ 本次 v2 折入所有 P0/P1/P2 + 新增 D-dedup-14 (SHA256 invariant) + D-dedup-15 (focus chain)
5. ⏳ commit design v2 (`[docs-only]`)
6. ⏳ 进 `superpowers:writing-plans` skill 产 implementation-plan.md
7. ⏳ plan 定稿 → codex review plan → verdict 报军哥 → 折入(若需)
8. ⏳ 进 `superpowers:subagent-driven-development` 实施(任务 AB / C / D / E / F 共 5 任务,~12-18 commit 量级)

---

> **本 design.md(v2)写作纪律遵循**:
> - CONTEXT.md 术语字典 A-D 段(已逐字符核对): 全文使用「重复清理 / 去重 / 保留张 / 缩略图 / 工具栏 / 侧边栏 / 快速看图器 / 任务 / toast 提示 / 全屏」等中文规范;未使用 `QV` / `SF` / `IS` / `Slice` / `canonical`(正文) / `Sandbox`(中文场景) 等弃用别名;代码符号(`DedupPass` / `DuplicateGroup` / `IndexStore` / `DuplicateOverviewModel` 等)保留英文
> - 真实 API 表(§2)每个引用符号已 grep + Read 实际代码核对(跨项目沉淀「写 plan 引用已有代码先 Read」反应)
> - 严格 scope 锁定段(§0): D1-D6 锁定,无回头探索
> - 决策段(§7): D-dedup-N 编号 + 一句话理由(mirror `D-OW` / `D-QV` / `D-mb` 约定)
> - 不抢库 + 克制红线对齐(§0 + §7 D-dedup-1)
