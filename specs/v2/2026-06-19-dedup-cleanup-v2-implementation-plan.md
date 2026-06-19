# 重复清理 V2 重设计 — Implementation Plan

> **For agentic workers**: 用 `superpowers:subagent-driven-development` 一任务一 subagent 执行;步骤用 `- [ ]` 复选框跟踪。每个任务 ship 前必跑 `make verify` 三段 oracle(`scripts/verify.sh` — 静态规则 + xcodebuild build + 单测占位),全过才 commit。**Swift SwiftUI 项目无 XCTest target,跳 TDD 五段;验证等价 = verify.sh 三段 + PENDING 真机验**(CLAUDE.md 全局例外条款)。
>
> **来源**: design v2 commit `f92e07d` (`specs/v2/2026-06-19-dedup-cleanup-v2-design.md`)
>
> **目标产出**: 重复清理 V2 子系统 端到端 ship,5 任务 ~15 commit。
>
> **v2 修订摘要**(2026-06-19 plan codex review APPROVE-WITH-FIXES 后,0 P0 + 3 P1 + 3 P2):
> - **codex P1 (D.1 焦点符号名)**: 实际 enum 名是 `AppFocus`(不是 `FocusTarget`),已全文修正;`previousFocusTarget` → `previousAppFocus: AppFocus?`
> - **codex P1 (§4 reality check 补全)**: `BookmarkMigrationCoordinator.start(model:bookmarkManager:folderStore:bridge:)` 4 参数签名 + `TrashOutcomeEvent { id; trash; undoResult }` 字段 补进表格
> - **codex P1 (AB.9.3 删文件交接协议)**: 显式 subagent 完 AB.9.2 后停手 → main agent 仲裁请求军哥 → 军哥说 go 才 `git rm`(main agent 单一原子操作)
> - **codex P2 (sortSegmentWidth DS 化)**: 已提常量 `DS.Dedup.sortSegmentWidth: CGFloat = 180`(跟 searchBoxWidth 风格一致)
> - **codex P2 (AB 大 commit 粒度 / search 性能)**: 按 codex 建议留 follow-up — 当前 tradeoff 可接受,等真机用撞墙再调

**Goal**: 把当前简单整组 checkbox + 删除按钮的「重复清理总览」UI 重写为 per-item 选保留张 + 跳过组 + 筛选/排序/搜索 + 逐组审阅模态浮层的工作流(Claude Design 高保真原型 + 军哥锁定 D1-D6 + codex review v2)。

**Architecture**: SwiftUI MVVM。复用既有 `IndexStore` SQL(`fetchDuplicateGroups`/`fetchDuplicateGroupMembers`,SHA256 invariant 同组同体积)+ `TrashService`/`TrashOutcome`/`TrashUndoBanner`(整 trash + undo + banner 流不动)+ `FolderStoreIndexBridge.triggerIndexChanged`/`addIndexChangedObserver`(跨视图刷新)。新增层只有: `DuplicateOverviewModel` in-memory state 扩展(`userKeepIdByGroup` / `skippedGroupIds` / `reviewedGroupIds` / filter / sort / query / expand / focusReview*),5 个新 view(`DedupCleanupV2View` 主体 + 4 个 private subview)+ 1 个浮层(`DedupFocusReviewOverlay`),+ 2 个新 enum(`DedupListFilter` / `DedupSortOption`)+ `ContentView.FocusTarget` 加 `.dedupOverlay` case。零 SQL migration、零 DB schema 变更。

**Tech Stack**: Swift 5.9+ / SwiftUI(macOS 14+)/ AppKit `NSWindow` 接管的图库主窗 + 独立 `NSWindow` 看图器(看图器不动)/ `IndexStore` (sqlite3 C API)/ `TrashService` (FileManager.trashItem)/ `loadThumbnail` (ImageIO CGImageSourceCreateThumbnailAtIndex)。

## Global Constraints

(来自 design v2 + CLAUDE.md 项目段 + CONTEXT.md 术语字典 + Roadmap.md 红线;**每个任务的需求隐式包含本段**。)

1. **D1**: per-item 选保留张 = 临时态 `@Published userKeepIdByGroup: [String: Int64]`,**不写 DB** `dedup_canonical`
2. **D2**: 跳过组 = 临时态 `@Published skippedGroupIds: Set<String>`,**不加 DB 字段**
3. **D3**: needsReview = `group.duplicateCount >= 3` (砍 v1 size-ratio 分支,SHA256 invariant 同组同体积恒成立)
4. **D4**: 主题跟随全局 `AppearanceMode`(`Glance/FullScreen/AppState.swift:9-15`),**砍掉独立深/浅分段控件**
5. **D5**: **无分页**,`LazyVStack` 全量渲染(macOS 原生范式)
6. **D6**: 逐组审阅浮层 = `ZStack .overlay` + `.ultraThinMaterial`,**不是 `.sheet`,不是独立 `NSWindow`**
7. **D-dedup-7**: **点击外部关闭浮层**(macOS Spotlight 标准模态)
8. **D-dedup-14 SHA256 invariant**: 同组所有成员 `fileSize` 完全相等;**任何「成员体积差异」算法 / ★ 推荐(体积最大)UI / 「user 切换保留张省更多/更少字节」文案都禁止**
9. **D-dedup-15 focus chain**: 接入既有 `ContentView.@FocusState focusTarget(类型 `AppFocus?`)`(mirror `SearchOverlayView.swift:52` 模式),**不另起 `overlayFocused`**
10. **不抢库**: 不污染 `DedupPass` canonical 算法 ground truth
11. **不删文件**: 任何文件删除前必须先报告(CLAUDE.md「文件操作底线」)
12. **术语字典**(CONTEXT.md A-D 段强约束): commit message + plan.md + .md 文档必须遵守;`verify.sh` Stage 1d 字典扫报红即阻塞
13. **commit message 格式**:
    - 代码改动 (`.swift`): `<type>(<scope>): <change> (任务 X.N)`,例 `feat(重复清理 V2): DuplicateOverviewModel 字段重构 (任务 AB.2)`
    - 纯文档 (`.md`): 末尾加 `[docs-only]`,例 `docs(重复清理 V2): plan v2 codex review 折入 [docs-only]`
14. **作为 docs-only 改动跳过 Stage 2** 是允许的(纯文档 commit `verify.sh` 三段也都过即可,Stage 2 编译不受 .md 影响)
15. **不在中间留过渡态 commit**: 每个 commit ship 后,`make build` + `make run` 用户用都不会卡;`v2/dev` 任意 commit 都可 release(任务 AB 内 commit 顺序按下面设计可拆,但中间编译可能短暂红 — **强约束**: AB 内任意 commit 都必须编译过 + verify 三段过,**不允许「先合并 commit 再 fix」**)

---

## §1 任务总览表

| 任务 | 名称 | commit 数 | 依赖 | 端到端可跑 | 用户可感知 | 独立可 ship |
|------|------|----------|------|-----------|-----------|------------|
| **AB** | Model 重构 + 新 View 主体 | 9 | (无) | ✅ 每 commit 编译过 + verify 过 | ✅ AB.9 完成后视觉全新 + 全交互可用 | ✅ AB 完成后是一个完整 v0.5 alpha,不依赖 C/D/E/F |
| **C** | needsReview 算法 + 待确认徽章 | 1 | AB | ✅ | ✅ 汇总条双徽标 + 列表行徽章 + 筛选「待确认/已自动」语义 | ✅ |
| **D** | 逐组审阅浮层 | 4 | C | ✅ | ✅ 浮层全交互 + 键盘 ← → Enter Esc + click-outside | ✅ |
| **E** | 进出动画 + 浮层边界 | 1 | D | ✅ | ✅ 浮层 fade in/out + trashing 期禁用 + reload 自动推进 | ✅ |
| **F** | 文档同步 + PENDING 收尾 | 1 | E | ✅ | ⏭️ `[docs-only]`,无代码改动 | ✅ |

**总 commit 数估算**: ~15-16 commit。

**关键依赖**:
- 任务 C 依赖 AB 中 `DuplicateOverviewModel` 的 `filteredSortedGroups` accessor 框架
- 任务 D 依赖 C 中 `needsReview` 算法(浮层只审阅 needsReview 组)
- 任务 D.1 依赖 ContentView 现有 `FocusTarget` enum(查 `Glance/ContentView.swift:154-158`,若不存在则 D.1 内新建)
- 任务 E 依赖 D 完成的浮层基础结构

---

## §2 任务细节

### 任务 AB — Model 重构骨架 + 新 View 主体

> **总体**: 9 个 commit;**每个 commit 必须编译过 + verify.sh 三段过 + zero 用户可感知中间过渡态**。

#### AB.1 — 新 enum 文件(1 commit)

**Files**:
- Create: `Glance/Dedup/DedupListFilter.swift`
- Create: `Glance/Dedup/DedupSortOption.swift`

**Interfaces 产出**:
- `DedupListFilter` 提供 view 工具条筛选 pills 选中态值类型
- `DedupSortOption` 提供 view 工具条排序分段选中态值类型

**Steps**:

- [ ] **AB.1.1**: Create `Glance/Dedup/DedupListFilter.swift`

```swift
//
//  DedupListFilter.swift
//  Glance
//
//  重复清理 V2 — 工具条筛选 pills 三档值类型 (design v2 §2.1 + §4.3)
//  联动 needsReview (D3 = duplicateCount >= 3) + reviewedGroupIds 判断
//

import Foundation

enum DedupListFilter: String, CaseIterable, Equatable {
    case all
    case needsReview
    case auto
}
```

- [ ] **AB.1.2**: Create `Glance/Dedup/DedupSortOption.swift`

```swift
//
//  DedupSortOption.swift
//  Glance
//
//  重复清理 V2 — 工具条排序分段三档值类型 (design v2 §4.3)
//  · reclaimableDesc: SQL group.reclaimableBytes DESC (默认)
//  · countDesc: group.duplicates.count DESC
//  · nameAsc: canonical.relativePath localeCompare 升序
//

import Foundation

enum DedupSortOption: String, CaseIterable, Equatable {
    case reclaimableDesc
    case countDesc
    case nameAsc
}
```

- [ ] **AB.1.3**: Run `make verify` — 期望 14/14 pass(2 新文件无引用方不报 warning)

- [ ] **AB.1.4**: Commit

```
git add Glance/Dedup/DedupListFilter.swift Glance/Dedup/DedupSortOption.swift
git commit -m "feat(重复清理 V2): DedupListFilter + DedupSortOption enum (任务 AB.1)"
```

---

#### AB.2 — `DuplicateOverviewModel` 字段 + 方法重构(1 commit)

**Files**:
- Modify: `Glance/Dedup/DuplicateOverviewModel.swift`

**改动点**:

1. **字段重命名**: `selectedSha256s` → `skippedGroupIds`(同类型 `Set<String>`,语义反转 — 跳过组而非整组勾选)
2. **新增 stored properties** (design v2 §2.1 列表):
   - `@Published private(set) var userKeepIdByGroup: [String: Int64] = [:]`
   - `@Published private(set) var reviewedGroupIds: Set<String> = []`
   - `@Published var filter: DedupListFilter = .all`
   - `@Published var sortOption: DedupSortOption = .reclaimableDesc`
   - `@Published var searchQuery: String = ""`
   - `@Published private(set) var expandedGroupIds: Set<String> = []`
   - `@Published var focusReviewOpen: Bool = false`
   - `@Published private(set) var focusReviewQueue: [String] = []`
   - `@Published var focusReviewIndex: Int = 0`
3. **方法重命名**: `toggleSelection(sha256:)` → `toggleSkip(groupId:)`;`clearSelection()` → `clearSkips()`;`replaceSelectedSha256s(_:)` → `replaceSkippedGroupIds(_:)`
4. **方法新增**:
   - `func setUserKeep(groupId: String, memberId: Int64)` — 同时 unskip 该组
   - `func toggleExpand(groupId: String)`
   - `func markReviewed(groupId: String)`
   - `func openFocusReview()` — 收集 `needsReview && !reviewed && !skipped` 的组,init queue + index = 0,set focusReviewOpen = true
   - `func closeFocusReview()`
   - `func focusReviewNext() / focusReviewPrev() / focusReviewConfirm() / focusReviewSkip()`
   - `func userKeepId(for group: DuplicateGroup) -> Int64` — 单一权威读取入口(dict 中且 id 在 allMembers 才返回,否则回退 `group.recommendedKeepId`)
   - `func isSkipped(groupId:) -> Bool` / `isExpanded(groupId:) -> Bool` / `isReviewed(groupId:) -> Bool`
5. **accessor 重命名 + 重写**:
   - `selectedDuplicateCount` → `pendingTrashCount`:**v2 SHA256 invariant** — 未跳过组的 `duplicates.count` 之和(与 userKeepId 切换无关)
   - `selectedReclaimableBytes` → `pendingReclaimableBytes`:未跳过组的 `group.reclaimableBytes` 之和(SQL 已算好,与 userKeepId 无关)
6. **accessor 新增**:
   - `var filteredSortedGroups: [DuplicateGroup]` — 应用 filter + sort + searchQuery 后的结果集(`needsReview` 算法本任务暂返回 `false`,任务 C 实装)
   - `var autoCount: Int` / `var reviewCount: Int` — 用 `needsReview()` 算(任务 C 实装真值后这俩自动变化)
   - `var trashEnabled: Bool` — `pendingTrashCount > 0`
7. **核心改造**: `trashSelected()` → `trashPending()`:
   - 入口加 snapshot 全依赖:`let snapshotKeepIds = self.userKeepIdByGroup; let snapshotSkipped = self.skippedGroupIds; let snapshotGroups = self.groups`
   - `collectTrashInputs` 改名 → `collectTrashInputsFromPending`,签名加 `skippedGroupIds` + `userKeepIds` 两参数
   - 过滤逻辑:`groups.filter { !snapshotSkipped.contains($0.id) }.flatMap { group in group.allMembers.filter { $0.id != userKeepId(snapshotKeepIds, group) } }`
   - 其它 trash 主流程 (deleteImage / reEvaluateGroup / triggerIndexChanged / load / lastTrashOutcome / clearSkips) 不动
8. **D1 临时态语义**: `setUserKeep` 内部除写 dict 外,**不调** `IndexStore.setDedupCanonical`(D1 锁定不污染 DedupPass)

**注释要求**: 所有新增 stored properties + 方法首行注释必须显式标注「design v2 §X.Y」+「D-dedup-N 锁定」+「v2 SHA256 invariant」语义(便于后续 review 时 grep 反查锁定方案出处)。

**风险点**:
- 字段重命名后 ContentView prune 块(line 416)+ DuplicateOverviewView 还引用旧字段名 → **必须同 commit 内一并改 ContentView + DuplicateOverviewView 所有引用**,否则编译红
- 或者本 commit 内**新旧字段名共存**(`selectedSha256s` 暂留作 alias)→ 但这违反「不留过渡态」+ 用户可能看到 stale 行为 → **不推荐**

**方案锁定**: 本 commit 同时改 `DuplicateOverviewModel.swift` + ContentView 所有 `selectedSha256s` / `selectedDuplicateCount` 引用 + DuplicateOverviewView 所有 `selectedSha256s` 引用 → 一次编译过。

**Steps**:

- [ ] **AB.2.1**: grep + Read 实际引用点,核对待改清单

```bash
grep -rn "selectedSha256s\|selectedDuplicateCount\|selectedReclaimableBytes\|replaceSelectedSha256s\|toggleSelection\|clearSelection" Glance/ specs/v2/ | head -30
```

  期望命中: `DuplicateOverviewModel.swift` × 多次 + `ContentView.swift` × ~5 处 + `DuplicateOverviewView.swift` × ~2 处。

- [ ] **AB.2.2**: 编辑 `DuplicateOverviewModel.swift` — 按上表 1-8 项全改

- [ ] **AB.2.3**: 编辑 `ContentView.swift` — 把所有 `selectedSha256s` → `skippedGroupIds`,`selectedDuplicateCount` → `pendingTrashCount`,`replaceSelectedSha256s` → `replaceSkippedGroupIds`,`toggleSelection(sha256:)` → `toggleSkip(groupId:)`

- [ ] **AB.2.4**: 编辑 `DuplicateOverviewView.swift` — 同上替换(本 view 任务 AB.9 会整体删除,这一步先保持编译过)

- [ ] **AB.2.5**: Run `make verify` — 期望 14/14 pass(注意:本 commit 暂不动用户行为 — 旧 UI 的「整组勾选」原 onClick 现在调 `toggleSkip` 语义变了,**但用户能不能看到这层变化?** 当前 `DuplicateGroupRowView` 文案是「选择此组清掉 N 张副本」,语义变成「跳过/恢复此组」会让用户疑惑 → **AB.2 这一 commit 的「用户可感知变化」是 BUG**)

> **修正**: AB.2 commit 不要单独 ship — 跟 AB.9 整 view 替换合并(同一 commit 或前后紧贴的 commit 中 ContentView 切换 view 引用)。**但这违反 commit 粒度建议**。
>
> **重新设计 AB 顺序**: AB.2 改 model 字段时,DuplicateOverviewView 现有「整组 checkbox」UI 文案改为兼容性占位「(任务 AB 改造中,本 view 即将替换)」,功能仍能用但视觉提示用户「这里在改造」 — 但这显式留过渡态,违反「不留过渡」。
>
> **最终方案**: **AB.2 + AB.3 + AB.4 + AB.5 + AB.6 + AB.7 + AB.8 + AB.9 一次性合并成一个 8-9 个 sub-step 的「大 commit」**,中间不分 commit。理由:任务 AB 设计上就是「Model + View 一并 ship 不留过渡态」(design v2 § 9 + codex P1 (任务 A+B 合并))。

- [ ] **AB.2.6** (修正): **AB.2 暂不 commit**,作为「task AB 大 commit」的第 1 个 sub-step 落入工作树;继续 AB.3 同分支累积。

---

#### AB.3 — `DuplicateGroup` extension 加 helper(累积进 task AB 大 commit)

**Files**:
- Modify: `Glance/Dedup/DuplicateGroup.swift`

**改动**: 加 extension 段:

```swift
extension DuplicateGroup {
    /// 该组所有成员 (canonical + duplicates) 统一数组,D1 per-item 选择遍历用
    var allMembers: [DuplicateGroupMember] {
        [canonical] + duplicates
    }

    /// 推荐保留张 — DedupPass canonical (= earliest birth_time + 最小 id tie-breaker;
    /// **不是体积最大** — D-dedup-14 SHA256 invariant 同组成员 fileSize 完全相等);
    /// model.userKeepId 无手选时回退到这个。
    var recommendedKeepId: Int64 { canonical.id }

    /// 副本数 (= total members - 1)
    var duplicateCount: Int { duplicates.count }
}
```

**v2 注**: design v1 含 `membersSortedBySize` helper,v2 SHA256 invariant 下成员体积相等无判别价值,**不加**。

**Steps**:

- [ ] **AB.3.1**: 编辑 `Glance/Dedup/DuplicateGroup.swift` — 加 extension 段(挂在文件末尾,struct 定义后)

- [ ] **AB.3.2**: Run `make build` — 期望编译过(无新引用方,extension 不触发其它编译错)

> **AB.3 不单独 commit**,继续累积进 task AB 大 commit。

---

#### AB.4 — ContentView prune 块全量扩展 + 五态互斥 closeFocusReview 兜底(累积)

**Files**:
- Modify: `Glance/ContentView.swift`

**改动点**:

1. **L416 prune 块扩展**(design v2 § 3 codex P1 修复):
   ```swift
   .onChange(of: duplicateOverviewModel.groups) { _, newGroups in
       let validSha256s = Set(newGroups.map { $0.id })

       // skippedGroupIds (原 selectedSha256s, AB.2 改名后)
       let prunedSkipped = duplicateOverviewModel.skippedGroupIds.intersection(validSha256s)
       if prunedSkipped.count != duplicateOverviewModel.skippedGroupIds.count {
           duplicateOverviewModel.replaceSkippedGroupIds(prunedSkipped)
       }

       // userKeepIdByGroup — entry 满足 (group.id 仍在 ∧ memberId 仍在 group.allMembers) 才保留
       let validKeepIds: [String: Int64] = duplicateOverviewModel.userKeepIdByGroup.compactMapValues { _ in nil }   // placeholder
       // 实际实现: 遍历 dict, 对每 entry (groupId, memberId), 查 newGroups 中 id==groupId 的 group, 若存在且 allMembers contains memberId 则保留
       // (详细实现 AB 大 commit 内 fill in, 此处 plan 不重复 code)

       // reviewedGroupIds / expandedGroupIds — 同 skippedGroupIds 模式 prune
       // ...

       // 浮层 stale: 若 focusReviewOpen, 重算 queue + 推进/关
       // ...
   }
   ```

2. **L379-L410 五态互斥块扩展**: 每个 `.onChange(of: ...)` 入口(进 V1 folder / 进智能文件夹 / 进重复清理总览相关)末尾加 `duplicateOverviewModel.closeFocusReview()` 兜底(design v2 § 8.7 codex 修)

3. **AB.2 中遗留的字段名重命名同步**: ContentView 中所有 `selectedSha256s` / `selectedDuplicateCount` / `replaceSelectedSha256s` / `toggleSelection` 引用同时改

**Steps**:

- [ ] **AB.4.1**: grep ContentView 所有相关引用点

```bash
grep -nE "selectedSha256s|selectedDuplicateCount|replaceSelectedSha256s|toggleSelection|focusReviewOpen|closeFocusReview" Glance/ContentView.swift
```

- [ ] **AB.4.2**: 编辑 ContentView 按上述 1+2+3 项

- [ ] **AB.4.3**: Run `make build` — 期望编译过

> **AB.4 不单独 commit**,累积进 AB 大 commit。

---

#### AB.5 — `DS.Dedup` 段扩展(累积)

**Files**:
- Modify: `Glance/DesignSystem.swift`

**改动点**: `enum Dedup` 段(line 253-322 区域)末尾加新常量(保留原有,**不删**老 M4 任务 1+2 常量):

```swift
// MARK: - 重复清理 V2 重设计 — 新增常量 (任务 AB)

// 顶栏
static let topBarHeight: CGFloat = 56
static let topBarTrashIconSize: CGFloat = 26
static let topBarTrashIconCornerRadius: CGFloat = 7
static let topBarTitleFont: Font = .system(size: 16, weight: .bold)

// 汇总条
static let summaryCardCornerRadius: CGFloat = 14
static let summaryCardPaddingH: CGFloat = 20
static let summaryCardPaddingV: CGFloat = 16
static let summaryDividerWidth: CGFloat = 1
static let summaryDividerHeight: CGFloat = 48
static let summaryBigNumberFont: Font = .system(size: 23, weight: .heavy)
static let summaryLabelFont: Font = .system(size: 11.5, weight: .regular)
static let summarySubFont: Font = .system(size: 12.5, weight: .medium)
static let summaryBadgeIconSize: CGFloat = 30
static let summaryBadgeIconCornerRadius: CGFloat = 8
static let summaryReviewButtonHeight: CGFloat = 36

// 工具条
static let toolbarHeight: CGFloat = 48
static let filterPillCornerRadius: CGFloat = 20
static let filterPillPaddingH: CGFloat = 13
static let filterPillPaddingV: CGFloat = 6
static let filterPillFont: Font = .system(size: 12.5, weight: .semibold)
static let filterPillCountFont: Font = .system(size: 11, weight: .bold)
static let sortSegmentHeight: CGFloat = 32
static let sortSegmentWidth: CGFloat = 180   // v2 codex P2 DS 化, 跟 searchBoxWidth 风格一致
static let searchBoxWidth: CGFloat = 190
static let searchBoxCornerRadius: CGFloat = 8

// 列表行 (单行卡片)
static let rowHeight: CGFloat = 60
static let rowCornerRadius: CGFloat = 11
static let rowPaddingH: CGFloat = 14
static let rowPaddingV: CGFloat = 10
static let rowGap: CGFloat = 13
static let rowSkippedOpacity: Double = 0.55
static let rowTitleFont: Font = .system(size: 13.5, weight: .semibold)
static let rowSubFont: Font = .system(size: 11)
static let stackedThumbnailWidth: CGFloat = 52
static let stackedThumbnailHeight: CGFloat = 40
static let stackedThumbnailFrontWidth: CGFloat = 48
static let stackedThumbnailFrontHeight: CGFloat = 36
static let stackedThumbnailFrontCornerRadius: CGFloat = 6
static let badgeCornerRadius: CGFloat = 20
static let badgePaddingH: CGFloat = 9
static let badgePaddingV: CGFloat = 3
static let badgeFont: Font = .system(size: 11, weight: .semibold)
static let skipButtonHeight: CGFloat = 24
static let chevronSize: CGFloat = 24
static let chevronAnimationDuration: Double = 0.18

// 展开区 (90×66 缩略图横排)
static let expandedAreaPaddingH: CGFloat = 14
static let expandedAreaPaddingV: CGFloat = 12
static let expandedAreaGap: CGFloat = 11
static let expandedThumbnailWidth: CGFloat = 90
static let expandedThumbnailHeight: CGFloat = 66
static let expandedThumbnailCornerRadius: CGFloat = 8
static let expandedThumbnailMaxPixel: Int = 180
static let expandedKeepBorderWidth: CGFloat = 2
static let expandedKeepBadgeOffset: CGFloat = 4
static let expandedTrashOverlayOpacity: Double = 0.42
static let expandedTrashIconSize: CGFloat = 18
static let expandedNonKeepOpacity: Double = 0.55
static let expandedFilenameFont: Font = .system(size: 10.5)

// 浮层 (D / E 任务用,本任务先占位常量)
static let focusOverlayBackgroundOpacity: Double = 0.4
static let focusDialogWidth: CGFloat = 780
static let focusDialogCornerRadius: CGFloat = 18
static let focusDialogPaddingH: CGFloat = 22
static let focusDialogPaddingV: CGFloat = 22
static let focusHeaderPaddingV: CGFloat = 16
static let focusHeaderCloseSize: CGFloat = 28
static let focusHeaderCloseCornerRadius: CGFloat = 7
static let focusLargeImageWidth: CGFloat = 300
static let focusLargeImageHeight: CGFloat = 214
static let focusLargeImageCornerRadius: CGFloat = 12
static let focusLargeImageMaxPixel: Int = 600
static let focusKeepBorderWidth: CGFloat = 3
static let focusFooterPaddingV: CGFloat = 14
static let focusOverlayInTransitionDuration: Double = 0.18
static let focusOverlayOutTransitionDuration: Double = 0.15

// 配色 (v2 SHA256 invariant 后无 ★ 推荐角标,但仍保留 warnBg/warn 给「待确认」徽章 + reviewBg/review 给「已确认」徽章)
static let warnColor: SwiftUI.Color = .yellow
static let warnBgColor: SwiftUI.Color = .yellow.opacity(0.16)
static let reviewedColor: SwiftUI.Color = .green
static let reviewedBgColor: SwiftUI.Color = .green.opacity(0.16)
static let dangerColor: SwiftUI.Color = .red
static let dangerBgColor: SwiftUI.Color = .red.opacity(0.18)
static let dangerForegroundColor: SwiftUI.Color = SwiftUI.Color(red: 1.0, green: 0.42, blue: 0.38)
```

**Steps**:

- [ ] **AB.5.1**: 编辑 `DesignSystem.swift` 加上述常量段(挂在 `enum Dedup` 现有最后一行 `static let bannerButtonSpacing` 之后)

- [ ] **AB.5.2**: Run `make build` — 期望编译过(常量挂在 enum 内无依赖)

> **AB.5 不单独 commit**,累积进 AB 大 commit。

---

#### AB.6 — 新 `DedupCleanupV2View` 顶栏 + 汇总条骨架(累积)

**Files**:
- Create: `Glance/Dedup/DedupCleanupV2View.swift`(暂留 `DuplicateOverviewView.swift` 不删,AB.9 切换 ContentView 引用后再删)

**Steps**:

- [ ] **AB.6.1**: Write `Glance/Dedup/DedupCleanupV2View.swift`

```swift
//
//  DedupCleanupV2View.swift
//  Glance
//
//  重复清理 V2 重设计 — 主视图 (design v2 §4)
//  顶栏 + 汇总条 + 工具条 + 列表区 4 区域;浮层挂在 ContentView .overlay (任务 D)。
//  跟随全局 AppearanceMode (D4 锁定,无独立深/浅切换)。
//

import SwiftUI

struct DedupCleanupV2View: View {
    @EnvironmentObject var model: DuplicateOverviewModel
    @EnvironmentObject var migrationCoordinator: BookmarkMigrationCoordinator

    var body: some View {
        VStack(spacing: DS.Spacing.zero) {
            topBar
            mainContent
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let err = model.errorMessage {
            errorState(message: err)
        } else if case .rescanning = migrationCoordinator.phase {
            rescanningState
        } else if model.groupCount == 0 && !model.isLoading {
            emptyState
        } else {
            VStack(spacing: DS.Spacing.zero) {
                summaryStrip       // AB.6 这一 commit 实装
                // toolbar         // AB.7 实装
                // groupsList      // AB.8 实装
                Spacer()
            }
        }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "trash.fill")
                    .frame(width: DS.Dedup.topBarTrashIconSize, height: DS.Dedup.topBarTrashIconSize)
                    .background(DS.Dedup.dangerBgColor)
                    .foregroundStyle(DS.Dedup.dangerColor)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.topBarTrashIconCornerRadius))
                Text("重复清理")
                    .font(DS.Dedup.topBarTitleFont)
            }
            Spacer()
            trashAction
        }
        .frame(height: DS.Dedup.topBarHeight)
        .padding(.horizontal, DS.Spacing.lg)
        .background(SwiftUI.Color.secondary.opacity(0.05))
        .overlay(alignment: .bottom) {
            Rectangle().fill(SwiftUI.Color.secondary.opacity(0.1)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var trashAction: some View {
        switch model.trashState {
        case .idle, .completed:
            Button {
                Task { await model.trashPending() }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: DS.Icon.trash)
                    Text("移入废纸篓 (\(model.pendingTrashCount))")
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.Dedup.dangerColor)
            .disabled(!model.trashEnabled)
            .opacity(model.trashEnabled ? 1.0 : 0.45)
        case .trashing(let done, let total):
            HStack(spacing: DS.Spacing.sm) {
                ProgressView(value: Double(done), total: Double(total))
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                Text("\(done)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("取消") { Task { await model.cancelTrash() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - 汇总条 (AB.6)
    private var summaryStrip: some View {
        HStack(spacing: DS.Spacing.lg) {
            // 左块: 扫描结果 + 大数字 + 可释放
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("扫描结果")
                    .font(DS.Dedup.summaryLabelFont)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                    Text("\(model.groupCount) 组重复")
                        .font(DS.Dedup.summaryBigNumberFont)
                    Text("·")
                        .foregroundStyle(.secondary)
                }
                Text("可释放约 \(formattedReclaimable)")
                    .font(DS.Dedup.summarySubFont)
                    .foregroundStyle(DS.Dedup.reviewedColor)   // keep 绿
            }
            // 竖分隔
            Rectangle()
                .fill(SwiftUI.Color.secondary.opacity(0.2))
                .frame(width: DS.Dedup.summaryDividerWidth, height: DS.Dedup.summaryDividerHeight)
            // 中块: 双徽标 (autoCount / reviewCount, 任务 C 实装真值)
            HStack(spacing: DS.Spacing.lg) {
                summaryBadge(icon: "checkmark.seal.fill",
                            iconColor: DS.Dedup.reviewedColor,
                            iconBgColor: DS.Dedup.reviewedBgColor,
                            count: model.autoCount,
                            label: "已自动留最优")
                summaryBadge(icon: "exclamationmark.triangle.fill",
                            iconColor: DS.Dedup.warnColor,
                            iconBgColor: DS.Dedup.warnBgColor,
                            count: model.reviewCount,
                            label: "建议你确认")
            }
            Spacer()
            // 右块: 「逐组审阅 ›」按钮 (任务 D 实装 onClick → model.openFocusReview)
            reviewButton
        }
        .padding(.horizontal, DS.Dedup.summaryCardPaddingH)
        .padding(.vertical, DS.Dedup.summaryCardPaddingV)
        .background(SwiftUI.Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.summaryCardCornerRadius))
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.md)
    }

    private func summaryBadge(
        icon: String,
        iconColor: SwiftUI.Color,
        iconBgColor: SwiftUI.Color,
        count: Int,
        label: String
    ) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .frame(width: DS.Dedup.summaryBadgeIconSize, height: DS.Dedup.summaryBadgeIconSize)
                .background(iconBgColor)
                .foregroundStyle(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.summaryBadgeIconCornerRadius))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count) 组")
                    .font(.body.weight(.semibold))
                Text(label)
                    .font(DS.Dedup.summaryLabelFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var reviewButton: some View {
        Button {
            // 任务 D 实装: model.openFocusReview()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text("逐组审阅")
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .padding(.horizontal, DS.Spacing.md)
            .frame(height: DS.Dedup.summaryReviewButtonHeight)
        }
        .buttonStyle(.borderedProminent)
        .tint(DS.Dedup.warnColor)
        .disabled(model.reviewCount == 0)
        .opacity(model.reviewCount == 0 ? 0.5 : 1.0)
    }

    // MARK: - 状态 view (沿用 DuplicateOverviewView 现有,后续 AB.9 整体 git mv 后保留)

    private var emptyState: some View { /* AB.9 从 DuplicateOverviewView 迁移过来 */ EmptyView() }
    private var rescanningState: some View { EmptyView() }
    private func errorState(message: String) -> some View { EmptyView() }

    private var formattedReclaimable: String {
        ByteCountFormatter.string(fromByteCount: model.pendingReclaimableBytes, countStyle: .file)
    }
}
```

- [ ] **AB.6.2**: Run `make build` — 期望编译过(新 view 无引用方,扎实 island)

> **AB.6 不单独 commit**,累积。

---

#### AB.7 — 工具条筛选 pills + 排序分段 + 搜索框(累积)

**Files**:
- Modify: `Glance/Dedup/DedupCleanupV2View.swift`(在 AB.6 基础上加 `toolbar` view + 启用 mainContent 调用)

**改动**: 加工具栏 private view(Swift 内代码符号 `toolbar`),启用 mainContent 中 `// toolbar` 占位行。具体代码模式:

```swift
private var toolbar: some View {
    HStack(spacing: DS.Spacing.sm) {
        // 左: 筛选 pills
        HStack(spacing: DS.Spacing.xs) {
            filterPill(.all, label: "全部")
            filterPill(.needsReview, label: "待确认")
            filterPill(.auto, label: "已自动")
        }
        Spacer()
        // 右: 排序分段
        HStack(spacing: DS.Spacing.xs) {
            Text("排序").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $model.sortOption) {
                Text("可省").tag(DedupSortOption.reclaimableDesc)
                Text("张数").tag(DedupSortOption.countDesc)
                Text("名称").tag(DedupSortOption.nameAsc)
            }
            .pickerStyle(.segmented)
            .frame(width: DS.Dedup.sortSegmentWidth)
        }
        // 最右: 搜索框
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("搜索文件名…", text: $model.searchQuery)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(SwiftUI.Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.searchBoxCornerRadius))
        .frame(width: DS.Dedup.searchBoxWidth)
    }
    .padding(.horizontal, DS.Spacing.lg)
    .padding(.vertical, DS.Spacing.sm)
}

private func filterPill(_ filter: DedupListFilter, label: String) -> some View {
    let count = countFor(filter)
    let isSelected = model.filter == filter
    return Button {
        model.filter = filter
    } label: {
        HStack(spacing: DS.Spacing.xs) {
            Text(label).font(DS.Dedup.filterPillFont)
            Text("\(count)").font(DS.Dedup.filterPillCountFont).opacity(0.7)
        }
        .padding(.horizontal, DS.Dedup.filterPillPaddingH)
        .padding(.vertical, DS.Dedup.filterPillPaddingV)
        .background(isSelected ? SwiftUI.Color.primary : SwiftUI.Color.secondary.opacity(0.07))
        .foregroundStyle(isSelected ? SwiftUI.Color(NSColor.windowBackgroundColor) : SwiftUI.Color.secondary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(SwiftUI.Color.secondary.opacity(0.2), lineWidth: isSelected ? 0 : 1))
    }
    .buttonStyle(.plain)
}

private func countFor(_ filter: DedupListFilter) -> Int {
    switch filter {
    case .all:         return model.groupCount
    case .needsReview: return model.reviewCount
    case .auto:        return model.autoCount
    }
}
```

**Steps**:

- [ ] **AB.7.1**: 编辑 `DedupCleanupV2View.swift` 加工具栏(`toolbar`)段 + 启用 mainContent

- [ ] **AB.7.2**: Run `make build` — 期望编译过

> 累积。

---

#### AB.8 — 列表行卡片 + 展开区 + per-item 点击切保留张(累积)

**Files**:
- Modify: `Glance/Dedup/DedupCleanupV2View.swift`

**改动**: 加 `groupsList` + 私有 `DedupGroupRow` view + 私有 `DedupMemberCell`(展开区缩略图);启用 mainContent 中 `// groupsList` 占位行。

**关键设计**:
- `DedupGroupRow` 渲染单行卡片:叠放缩略图(`StackedThumbnail`)+ 中间信息(标题 + 「保留 {filename}」+ 「可省 {static}」)+「删 N」徽 / 「已跳过」徽 + 跳过/恢复按钮 + chevron
- `DedupMemberCell` 渲染展开区每张 90×66 缩略图:渐变占位 → loadThumbnail → 保留态绿描边 + 「✓ 保留」徽 / 待删态暗罩 + 右上 ✕ 角标 / **不显示 ★ 推荐**(SHA256 invariant 后砍)
- 列表行展开态由 model.expandedGroupIds 控制;点击 chevron / 叠放缩略图 调 model.toggleExpand
- 点击展开区缩略图 调 model.setUserKeep(groupId:memberId:) → 该图变保留态,该组若 skip 则取消 + 视觉立即更新(SwiftUI @Published 自动 redraw)

完整代码 ~150 行,本任务实施时按既有 `DuplicateMemberCell.loadThumb` 模式(`DuplicateOverviewView.swift:265-302`)实装。

**Steps**:

- [ ] **AB.8.1**: 编辑 `DedupCleanupV2View.swift` 加 `groupsList` + `DedupGroupRow` + `DedupMemberCell` 三段 + 启用 mainContent

- [ ] **AB.8.2**: Run `make build` — 期望编译过

> 累积。

---

#### AB.9 — ContentView 替换 view 引用 + `git rm` 旧 view + 单一 commit ship

**Files**:
- Modify: `Glance/ContentView.swift`(主区分支 `DuplicateOverviewView()` → `DedupCleanupV2View()`)
- Delete: `Glance/Dedup/DuplicateOverviewView.swift`(整文件删除,内容已迁移到 `DedupCleanupV2View`;空态/错态/重扫中态 view 也迁过去)

**改动**:
1. ContentView mainContent 分支 `DuplicateOverviewView()` 改为 `DedupCleanupV2View()`(单一 callsite)
2. `git rm Glance/Dedup/DuplicateOverviewView.swift`(**先报告军哥**,按 CLAUDE.md「文件操作底线 — 删文件前先报告」)

**等等 — 删文件硬规则**:CLAUDE.md「文件操作底线」明示「禁止删除任何文件,需要删除先报告给我」。即使在 plan 已经定义删 `DuplicateOverviewView.swift`,实施时也必须先报告军哥 → 等明示同意才执行。

**修正方案**: AB.9 实施前主 agent 主动汇报「准备删 `DuplicateOverviewView.swift`(内容已迁 `DedupCleanupV2View`,verify 已通过)」+ 等军哥说「删」才执行 `git rm`。

**Steps**:

- [ ] **AB.9.1**: 编辑 `ContentView.swift` mainContent 分支引用 `DedupCleanupV2View()`

- [ ] **AB.9.2**: Run `make build` — 期望编译过(`DuplicateOverviewView.swift` 还在,无引用方 SwiftUI 编译跳过即可)

- [ ] **AB.9.3**: **subagent-driven-development 流程内的删文件交接协议(v2 codex P1 修补全)**:
  - **subagent 在完成 AB.9.2(`make build` 编译过)后停手**,**不要自己执行 `git rm`**;subagent 的 final 输出必须显式说明:「AB.9.2 完成,准备删旧 view `DuplicateOverviewView.swift`,等 main agent 仲裁」
  - **main agent 收到 subagent 完成信号后**,向军哥请求确认:「AB 任务实施到 AB.9.2,新 view `DedupCleanupV2View` 已 ship + verify 过,准备 `git rm Glance/Dedup/DuplicateOverviewView.swift`(旧 view,无引用方,内容已迁移)。同意删除?」
  - **军哥说「删 / go / 同意」等明示后**,main agent 自己执行 `git rm`(不再 dispatch subagent — 单一原子操作)+ 继续 AB.9.5+ 步骤

- [ ] **AB.9.4**: 军哥同意后 → `git rm Glance/Dedup/DuplicateOverviewView.swift`(main agent 执行)

- [ ] **AB.9.5**: Run `make verify` — 期望 14/14 pass + build 0 error 0 warning

- [ ] **AB.9.6**: 一次性 commit 整任务 AB

```
git add Glance/Dedup/DedupListFilter.swift \
        Glance/Dedup/DedupSortOption.swift \
        Glance/Dedup/DuplicateOverviewModel.swift \
        Glance/Dedup/DuplicateGroup.swift \
        Glance/Dedup/DedupCleanupV2View.swift \
        Glance/DesignSystem.swift \
        Glance/ContentView.swift
git rm Glance/Dedup/DuplicateOverviewView.swift

git commit -m "feat(重复清理 V2): Model 重构 + 新 View 主体 ship (任务 AB)

· enum DedupListFilter / DedupSortOption 新建
· DuplicateOverviewModel 字段重构 (selectedSha256s → skippedGroupIds; 新增 userKeepIdByGroup / reviewedGroupIds / filter / sortOption / searchQuery / expandedGroupIds / focusReview*)
· trashSelected → trashPending (用 userKeepId 而非 SQL dedup_canonical=1; v2 SHA256 invariant 同组同体积语义)
· DuplicateGroup extension 加 allMembers / recommendedKeepId / duplicateCount helper
· ContentView prune 块全量扩展 (skippedGroupIds + userKeepIdByGroup + reviewedGroupIds + expandedGroupIds + focusReviewQueue/Index) + 五态互斥 closeFocusReview 兜底
· DS.Dedup 段扩展 ~50 个新常量 (顶栏 / 汇总条 / 工具条 / 列表行 / 展开区 / 浮层占位)
· 新 DedupCleanupV2View 主视图 (顶栏 + 汇总条 + 工具条 + 列表 + 展开区 + per-item 点击切保留张)
· 旧 DuplicateOverviewView git rm (经军哥同意)

verify.sh 三段全过 (14 pass 0 failed; 0 error 0 warning)。

任务 C 待实施: needsReview 算法 + 待确认徽章实装。"
```

- [ ] **AB.9.7**: `git push`

**验收标准**:
- 端到端: `make run` 启动后侧边栏点「重复清理」,新 UI 全部渲染,顶栏 + 汇总条 + 工具条 + 列表 + 展开区 + per-item 选择全部可点
- 用户感知: 视觉完全新设计,跟 design v2 截图 01 对得上;旧整组 checkbox UI 消失
- 独立 ship: `git checkout v2/dev` 后 `make build` + `make run` 一切正常,无任何中间过渡态

**风险点**:
- AB.2 model 改动大,字段重命名跨多文件 → 风险:编译失败遗漏某处引用 → 缓解:AB.2.1 grep 列出待改清单严格按清单改
- AB.5 DS.Dedup 段扩展 ~50 常量 → 风险:常量命名跟其它 view 冲突 → 缓解:新常量都加在 `// MARK: - 重复清理 V2 重设计 — 新增常量` 段内,不动现有 M4 常量
- AB.6-AB.8 view 实装大 → 风险:某个 modifier 链 bug 导致编译过但视觉错 → 缓解:任务 F 真机验时军哥 PENDING 项严验

**回滚方式**:
- 若 AB 大 commit 后 verify 红 → `git reset --hard HEAD^` 回 b3dc510(design v2 commit 之前)
- 若 AB 大 commit 后真机用发现严重 bug → 报告军哥 → 走 bug-fix 路径(在 v2/dev 上 incremental fix,不 reset)

**PENDING 项**(任务 F 收尾时统一加):
- 1.png 真机:进重复清理总览,看顶栏 + 汇总条 + 工具条 + 列表 4 区域是否对得上设计稿
- 2.png 真机:点叠放缩略图或 chevron,展开区显示 90×66 缩略图横排;点任一缩略图,该图变保留态
- 3.png 真机:点跳过按钮,整行 opacity 0.55 + 「删 N」变「已跳过」
- 4.png 真机:筛选 pill「全部 / 待确认 / 已自动」切换,列表正确过滤
- 5.png 真机:排序「可省 / 张数 / 名称」切换,列表正确排序
- 6.png 真机:搜索文件名,输入「card」过滤出含 card 文件名的组
- 7.png 真机:点「移入废纸篓 (N)」,既有 banner + undo 流程不变

---

### 任务 C — needsReview 算法 + 待确认徽章

> **总体**: 1 commit。实装 D3 算法(`duplicateCount >= 3`)+ 列表行徽章 + 汇总条双徽标真值 + 筛选 pills 联动。

#### C.1 — needsReview 算法实装 + 视觉徽章

**Files**:
- Modify: `Glance/Dedup/DuplicateOverviewModel.swift`(实装 `needsReview(group:)` 算法 + `autoCount` / `reviewCount` 真值)
- Modify: `Glance/Dedup/DedupCleanupV2View.swift`(列表行加「待确认」/「已确认」徽章)

**改动点**:

1. `DuplicateOverviewModel` 加方法(替换任务 AB 暂时返回 `false` 的占位):

```swift
/// design v2 §5.1 needsReview 算法 (v2 codex P0 修, SHA256 invariant)
/// 阈值: duplicateCount >= 3 (组共 ≥ 4 张, 用户值得手动审一遍挑保留 path/folder)
func needsReview(group: DuplicateGroup) -> Bool {
    return group.duplicateCount >= 3
}
```

2. accessor `autoCount` / `reviewCount` 改为真值:

```swift
var reviewCount: Int {
    groups.filter { needsReview(group: $0) && !isReviewed(groupId: $0.id) }.count
}

var autoCount: Int {
    groups.filter { !needsReview(group: $0) || isReviewed(groupId: $0.id) }.count
}
```

3. `filteredSortedGroups` filter 逻辑修正:

```swift
var filteredSortedGroups: [DuplicateGroup] {
    let q = searchQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    var list = groups.filter { group in
        // filter 联动
        switch filter {
        case .all:         break
        case .needsReview: if !(needsReview(group: group) && !isReviewed(groupId: group.id)) { return false }
        case .auto:        if needsReview(group: group) && !isReviewed(groupId: group.id) { return false }
        }
        // search 联动 (canonical filename + 任一 member relativePath)
        if !q.isEmpty {
            let inTitle = group.canonical.relativePath.lowercased().contains(q)
            let inMember = group.allMembers.contains { $0.relativePath.lowercased().contains(q) }
            if !(inTitle || inMember) { return false }
        }
        return true
    }
    // sort
    switch sortOption {
    case .reclaimableDesc: list.sort { $0.reclaimableBytes > $1.reclaimableBytes }
    case .countDesc:       list.sort { $0.duplicateCount > $1.duplicateCount }
    case .nameAsc:         list.sort { $0.canonical.relativePath.localizedCompare($1.canonical.relativePath) == .orderedAscending }
    }
    return list
}
```

4. `DedupCleanupV2View.DedupGroupRow` 内中间信息加徽章渲染(在标题旁):

```swift
private var statusBadge: some View {
    Group {
        if model.needsReview(group: group) && !model.isReviewed(groupId: group.id) {
            Text("待确认")
                .font(DS.Dedup.badgeFont)
                .padding(.horizontal, DS.Dedup.badgePaddingH)
                .padding(.vertical, DS.Dedup.badgePaddingV)
                .background(DS.Dedup.warnBgColor)
                .foregroundStyle(DS.Dedup.warnColor)
                .clipShape(Capsule())
        } else if model.isReviewed(groupId: group.id) {
            Text("已确认")
                .font(DS.Dedup.badgeFont)
                .padding(.horizontal, DS.Dedup.badgePaddingH)
                .padding(.vertical, DS.Dedup.badgePaddingV)
                .background(DS.Dedup.reviewedBgColor)
                .foregroundStyle(DS.Dedup.reviewedColor)
                .clipShape(Capsule())
        }
    }
}
```

**Steps**:

- [ ] **C.1.1**: 编辑 `DuplicateOverviewModel.swift` 按 1+2+3 项

- [ ] **C.1.2**: 编辑 `DedupCleanupV2View.swift` 按 4 项

- [ ] **C.1.3**: Run `make verify` — 期望 14/14 pass

- [ ] **C.1.4**: Commit

```
git add Glance/Dedup/DuplicateOverviewModel.swift Glance/Dedup/DedupCleanupV2View.swift
git commit -m "feat(重复清理 V2): needsReview 算法 + 待确认徽章 (任务 C)

· needsReview = duplicateCount >= 3 (v2 SHA256 invariant)
· autoCount / reviewCount 切真值 (汇总条双徽标)
· filteredSortedGroups filter + search 联动逻辑
· 列表行加「待确认」/「已确认」徽章

verify.sh 三段全过。"
```

- [ ] **C.1.5**: `git push`

**验收标准**:
- 端到端: 跑 `make run`, 进总览, 副本数 ≥ 3 的组显示「待确认」徽章
- 用户感知: 汇总条左 ✓ X 组 + 右 ⚠ Y 组 数字真值;筛选「待确认」只显示 needsReview 组;筛选「已自动」只显示 auto 组
- 独立 ship: ✅

**风险点**:
- `localizedCompare` 中文排序结果可能跟用户预期不一致 → followup 真机验定调,本任务先用此 API
- needsReview 阈值 3 经验值 → 真机验觉得太敏感/宽松时 followup 调

**PENDING**(任务 F 加):
- 副本数 4+ 组进「待确认」;3 张组(2 副本)进「已自动」
- 筛选 pill 切换列表正确过滤
- 排序「可省 / 张数 / 名称」三档结果对应预期

---

### 任务 D — 逐组审阅浮层

> **总体**: 4 commit。浮层 ZStack overlay + ultraThinMaterial + 大图对比 + 键盘 ← → Enter Esc + click-outside dismiss + focus chain 接入既有 `focusTarget` 仲裁链。

#### D.1 — ContentView `AppFocus` enum 加 `.dedupOverlay` + 仲裁切换(1 commit)

**Files**:
- Modify: `Glance/ContentView.swift`

**v2 codex P1 修**: 之前 plan v1 写「FocusTarget enum」是错的 — 实际项目 enum 名是 `AppFocus`(`Glance/ContentView.swift:14-21`),现有 cases `grid / preview / ephemeral / search`(`search` case 是 M3 任务 M 加的,历史 commit 用旧名 `Slice M`);ContentView `@FocusState focusTarget: AppFocus?` line 158。本任务 D.1 直接给现有 `AppFocus` 加 `case dedupOverlay`,**不需要 enum 重构小任务**。

**改动**:

1. `AppFocus` enum 加 `case dedupOverlay`(line 14-21 区域)
2. `ContentView` 加 `@State private var previousAppFocus: AppFocus? = nil`
3. `.onChange(of: duplicateOverviewModel.focusReviewOpen)` 仲裁:

```swift
.onChange(of: duplicateOverviewModel.focusReviewOpen) { _, isOpen in
    if isOpen {
        previousAppFocus = focusTarget
        focusTarget = .dedupOverlay
    } else {
        focusTarget = previousAppFocus ?? .grid
        previousAppFocus = nil
    }
}
```

**Steps**:

- [ ] **D.1.1**: grep 确认 `AppFocus` enum 现状(已核实 v2 plan,本步骤是 sanity check)

```bash
grep -n "enum AppFocus\|@FocusState.*AppFocus" Glance/ContentView.swift Glance/Search/SearchOverlayView.swift
```

  期望:`Glance/ContentView.swift:14 enum AppFocus: Hashable` + `Glance/ContentView.swift:158 @FocusState private var focusTarget: AppFocus?` + `Glance/Search/SearchOverlayView.swift:15 @FocusState.Binding var focusTarget: AppFocus?`

- [ ] **D.1.2**: 编辑 `Glance/ContentView.swift`:line 14-21 区域 enum AppFocus 加 `case dedupOverlay`(注释:design v2 D-dedup-15);body 内加 `@State private var previousAppFocus: AppFocus?`;现有 `.onChange` 块或新加块插入仲裁逻辑

- [ ] **D.1.3**: Run `make verify` — 期望 14/14 pass(focusReviewOpen 还无 true 路径,但 enum 扩展无副作用)

- [ ] **D.1.4**: Commit

```
git add Glance/ContentView.swift
git commit -m "feat(重复清理 V2): AppFocus 加 .dedupOverlay + 仲裁切换 (任务 D.1)

· 接入既有 ContentView.@FocusState focusTarget: AppFocus? 仲裁链 (D-dedup-15 锁定)
· AppFocus enum 加 case dedupOverlay (mirror SearchOverlayView .search 模式)
· 新增 previousAppFocus @State 保存浮层打开前焦点
· onChange(of: focusReviewOpen) 仲裁切换 + 归还

verify.sh 三段全过。"
```

- [ ] **D.1.5**: `git push`

---

#### D.2 — `DedupFocusReviewOverlay` 新 view(1 commit)

**Files**:
- Create: `Glance/Dedup/DedupFocusReviewOverlay.swift`

**改动**: 新 view(~200 行),按 design v2 §4.5 + §6 实装:

- ZStack 外层: `.ultraThinMaterial` 模糊层 + `SwiftUI.Color.black.opacity(0.4)` 加深 + `.ignoresSafeArea()` + `.onTapGesture { model.closeFocusReview() }` (D-dedup-7)
- 内层对话框: 780pt 宽 + `.thickMaterial` 实色底 + 圆角 18pt + 阴影 + `.contentShape(Rectangle())` 拦截点击不冒泡到背景层
  - 头部 HStack:「逐组审阅」标签(warnBg/warn 胶囊)+ 组标题 + Spacer +「{i+1}/{N}」+ ✕ 关闭按钮
  - 主体 ScrollView: 提示文字 + HStack flex-wrap 大图对比 cell(每张 300×214 + 文件名 + 文件夹路径)
  - 底部 HStack: 「上一组」+ Spacer +「跳过此组」+「确认并继续 ›」(最后一组文案变「确认并完成」)

每张大图 cell:
- 300×214 缩略图(loadThumbnail maxPixel 600)
- 保留态: 3pt keep 描边 + 右下「✓ 保留」徽
- 待删态: rgba(10,10,12,0.4) 暗罩 + 右下「待删」徽 + opacity 0.55
- **无 ★ 推荐**(D-dedup-12 + SHA256 invariant)
- 图下: 文件名 + folder 路径

完整代码 ~200 行,本任务实施时按既有 `DuplicateMemberCell.loadThumb` 模式 + 设计稿 02-focus-review.png 视觉。

**Steps**:

- [ ] **D.2.1**: Write `Glance/Dedup/DedupFocusReviewOverlay.swift`(完整 view,但 onClick / 键盘事件留 stub 待 D.3 实装)

- [ ] **D.2.2**: 编辑 `ContentView.swift` mainContent ZStack 外层加 `.overlay(alignment: .center)`:

```swift
.overlay(alignment: .center) {
    if duplicateOverviewModel.focusReviewOpen {
        DedupFocusReviewOverlay()
            .environmentObject(duplicateOverviewModel)
    }
}
```

- [ ] **D.2.3**: Run `make verify` — 14/14 pass(浮层因 focusReviewOpen 还无路径 set true 故不可见,但编译过)

- [ ] **D.2.4**: Commit

```
git add Glance/Dedup/DedupFocusReviewOverlay.swift Glance/ContentView.swift
git commit -m "feat(重复清理 V2): 逐组审阅浮层 view 框架 (任务 D.2)

· DedupFocusReviewOverlay 新 view (ZStack .overlay + .ultraThinMaterial)
· 头部 + 主体大图对比 + 底部操作条三层布局
· 对话框 .contentShape(Rectangle()) 拦截点击不冒泡 (D-dedup-7)
· ContentView ZStack 外层挂 .overlay 渲染 (D6 锁定: 不是 .sheet, 不是独立 NSWindow)
· onClick / 键盘 stub 留 D.3 实装

verify.sh 三段全过。"
```

- [ ] **D.2.5**: `git push`

---

#### D.3 — 键盘 ← → Enter Esc + model openFocusReview / closeFocusReview / Next/Prev/Confirm/Skip 实装(1 commit)

**Files**:
- Modify: `Glance/Dedup/DuplicateOverviewModel.swift`(实装 6 个 focusReview 方法 + markReviewed)
- Modify: `Glance/Dedup/DedupFocusReviewOverlay.swift`(挂 `.focused($focusTarget, equals: .dedupOverlay)` + `.onKeyPress` ← → Enter Esc + onClick 实装)

**改动**:

1. `DuplicateOverviewModel` 实装 6 方法:

```swift
func openFocusReview() {
    let queue = groups
        .filter { needsReview(group: $0) && !isReviewed(groupId: $0.id) && !isSkipped(groupId: $0.id) }
        .map { $0.id }
    guard !queue.isEmpty else { return }
    focusReviewQueue = queue
    focusReviewIndex = 0
    focusReviewOpen = true
}

func closeFocusReview() {
    focusReviewOpen = false
    focusReviewQueue = []
    focusReviewIndex = 0
}

func focusReviewNext() {
    guard focusReviewIndex < focusReviewQueue.count - 1 else { return }
    focusReviewIndex += 1
}

func focusReviewPrev() {
    guard focusReviewIndex > 0 else { return }
    focusReviewIndex -= 1
}

func focusReviewConfirm() {
    let currentId = focusReviewQueue[focusReviewIndex]
    markReviewed(groupId: currentId)
    if focusReviewIndex >= focusReviewQueue.count - 1 {
        closeFocusReview()
    } else {
        focusReviewIndex += 1
    }
}

func focusReviewSkip() {
    let currentId = focusReviewQueue[focusReviewIndex]
    markReviewed(groupId: currentId)
    // skip 与 reviewed 共存: 该组进 skippedGroupIds + reviewedGroupIds
    if !isSkipped(groupId: currentId) {
        toggleSkip(groupId: currentId)
    }
    if focusReviewIndex >= focusReviewQueue.count - 1 {
        closeFocusReview()
    } else {
        focusReviewIndex += 1
    }
}

func markReviewed(groupId: String) {
    reviewedGroupIds.insert(groupId)
}
```

2. `DedupFocusReviewOverlay` 挂键盘 + focus:

```swift
DedupFocusReviewOverlay()
    .focusable()
    .focused($focusTarget, equals: .dedupOverlay)
    .onKeyPress(.leftArrow)  { model.focusReviewPrev();    return .handled }
    .onKeyPress(.rightArrow) { model.focusReviewNext();    return .handled }
    .onKeyPress(.return)     { model.focusReviewConfirm(); return .handled }
    .onKeyPress(.escape)     { model.closeFocusReview();   return .handled }
```

3. 浮层底部按钮 onClick 接 model.focusReviewPrev / focusReviewSkip / focusReviewConfirm
4. ✕ 关闭按钮 onClick 接 model.closeFocusReview
5. 大图对比 cell onClick 接 model.setUserKeep(currentGroup.id, member.id)
6. 汇总条「逐组审阅 ›」按钮 onClick 改为接 `model.openFocusReview()`(任务 AB.6 时是 stub)

**Steps**:

- [ ] **D.3.1**: 编辑 `DuplicateOverviewModel.swift` 实装 6 方法

- [ ] **D.3.2**: 编辑 `DedupFocusReviewOverlay.swift` 挂键盘 + onClick

- [ ] **D.3.3**: 编辑 `DedupCleanupV2View.swift` 汇总条「逐组审阅 ›」按钮 onClick 接通

- [ ] **D.3.4**: Run `make verify` — 14/14 pass

- [ ] **D.3.5**: Commit

```
git add Glance/Dedup/DuplicateOverviewModel.swift \
        Glance/Dedup/DedupFocusReviewOverlay.swift \
        Glance/Dedup/DedupCleanupV2View.swift
git commit -m "feat(重复清理 V2): 浮层键盘 + model focusReview 方法实装 (任务 D.3)

· model.openFocusReview / closeFocusReview / Next / Prev / Confirm / Skip 6 方法
· markReviewed 加入 reviewedGroupIds 集合
· 浮层挂 .focused(\$focusTarget, equals: .dedupOverlay) (D-dedup-15)
· 键盘 ← → Enter Esc 路由到 model 方法
· 浮层底部按钮 onClick 接通
· 大图对比 cell onClick 接 setUserKeep
· 汇总条「逐组审阅 ›」按钮 onClick 接 model.openFocusReview

verify.sh 三段全过。"
```

- [ ] **D.3.6**: `git push`

---

#### D.4 — 浮层端到端真机验 + commit polish 收尾(1 commit)

**Files**: 无新文件;仅可能微调 D.2/D.3 中 cell 视觉细节(根据 `make run` 真机验时发现的 modifier 链 bug)。

**Steps**:

- [ ] **D.4.1**: `make run` 启动 → 进总览 → 验:
  1. 点汇总条「逐组审阅 ›」(reviewCount > 0 时) → 浮层 fade in
  2. 浮层标题、进度「i/N」、大图 2 列对比可见
  3. 键盘 → 切下一组,← 切上一组(边界 disabled)
  4. Enter 确认 + 推进;最后一组 Enter 关闭
  5. Esc 关闭浮层
  6. 点击对话框外部背景 → 浮层关闭(D-dedup-7)
  7. 点击大图 cell → 该图变保留态
  8. 浮层关闭后 ⌘F 仍能打开搜索 overlay(focusTarget 归还正确)

- [ ] **D.4.2**: 若有视觉/交互 bug 微调

- [ ] **D.4.3**: Run `make verify` — 14/14 pass

- [ ] **D.4.4**: Commit(若有微调)/ skip commit(若无微调 — D.3 已是 D 任务 ship 状态)

```
git commit -m "polish(重复清理 V2): 浮层真机验微调 (任务 D.4)
· ... 实际微调点 ...
"
```

(若 D.4 无需微调 → 跳过 commit 直接 D 任务收尾)

- [ ] **D.4.5**: `git push`(如有 D.4 commit)

**验收标准**(D 任务整体):
- 端到端: 浮层完整工作流可用(打开 → 审阅 → 确认/跳过/上一组/下一组 → 关闭 → 焦点归还)
- 用户感知: 模态全屏 + 大图对比 + 键盘流畅
- 独立 ship: ✅

---

### 任务 E — 进出动画 + 浮层边界细节

> **总体**: 1 commit。`.transition` + `.animation` + trashing 期 disabled + 浮层 reload 自动推进/关。

#### E.1 — 综合 polish(1 commit)

**Files**:
- Modify: `Glance/ContentView.swift`(浮层 transition + reload onChange 浮层 stale 处理)
- Modify: `Glance/Dedup/DuplicateOverviewModel.swift`(若 trashing 期 disabled 需要新 accessor)
- Modify: `Glance/Dedup/DedupCleanupV2View.swift`(「逐组审阅 ›」按钮 disabled when trashing)

**改动**:

1. ContentView 浮层 `.overlay` 加 transition + animation:

```swift
.overlay(alignment: .center) {
    if duplicateOverviewModel.focusReviewOpen {
        DedupFocusReviewOverlay()
            .environmentObject(duplicateOverviewModel)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
.animation(.easeOut(duration: DS.Dedup.focusOverlayInTransitionDuration), value: duplicateOverviewModel.focusReviewOpen)
```

2. ContentView L416 prune 块扩展 — 浮层 reload stale 处理(design v2 §3 + codex P1 修):

```swift
.onChange(of: duplicateOverviewModel.groups) { _, newGroups in
    // ... 现有 prune 逻辑 ...

    // 浮层 stale: 若打开, 重算 queue + 推进/关
    if duplicateOverviewModel.focusReviewOpen {
        duplicateOverviewModel.recomputeFocusReviewAfterReload()
    }
}
```

3. `DuplicateOverviewModel` 加方法 `recomputeFocusReviewAfterReload()`:

```swift
func recomputeFocusReviewAfterReload() {
    guard focusReviewOpen else { return }
    let validQueue = focusReviewQueue.filter { id in
        groups.contains(where: { $0.id == id }) &&
        needsReview(group: groups.first(where: { $0.id == id })!) &&
        !isReviewed(groupId: id) &&
        !isSkipped(groupId: id)
    }
    if validQueue.isEmpty {
        closeFocusReview()
        return
    }
    // 当前组若已不在新 queue → 推进到第一个仍有效的
    let currentId = focusReviewIndex < focusReviewQueue.count ? focusReviewQueue[focusReviewIndex] : nil
    let newIndex: Int = {
        if let cid = currentId, let idx = validQueue.firstIndex(of: cid) { return idx }
        return 0
    }()
    focusReviewQueue = validQueue
    focusReviewIndex = newIndex
}
```

4. `DedupCleanupV2View.reviewButton` 加 disabled when trashing:

```swift
.disabled(model.reviewCount == 0 || isTrashingNow)
.opacity(...)

private var isTrashingNow: Bool {
    if case .trashing = model.trashState { return true }
    return false
}
```

**Steps**:

- [ ] **E.1.1**: 编辑 4 处

- [ ] **E.1.2**: Run `make verify` — 14/14 pass

- [ ] **E.1.3**: `make run` 真机验:
  - 浮层打开 / 关闭 fade in/out 顺滑
  - trashing 期间「逐组审阅 ›」按钮 disabled
  - 浮层打开期 FSEvents 触发 reload(可制造场景: 外部 finder 删某组某张) → 浮层 currentGroup 不在新 groups → 自动推进或关

- [ ] **E.1.4**: Commit

```
git add Glance/ContentView.swift \
        Glance/Dedup/DuplicateOverviewModel.swift \
        Glance/Dedup/DedupCleanupV2View.swift
git commit -m "polish(重复清理 V2): 浮层动画 + 边界处理 (任务 E)

· 浮层 .transition(.opacity.combined(with: .scale)) + .animation(.easeOut)
· trashing 期间「逐组审阅 ›」disabled
· 浮层打开期 FSEvents reload 自动推进 / 关 (codex P2 修)
· recomputeFocusReviewAfterReload() 新方法实装

verify.sh 三段全过。"
```

- [ ] **E.1.5**: `git push`

**验收标准**:
- 端到端: 浮层动画顺滑;trashing 期禁用正确;reload stale 不闪屏不 crash
- 用户感知: 视觉打磨完成
- 独立 ship: ✅

---

### 任务 F — 文档同步 + verify + PENDING 收尾

> **总体**: 1 commit `[docs-only]`。重复清理 V2 整子系统 ship 收尾。

#### F.1 — 文档同步 + PENDING 加 + 决策段落地

**Files**:
- Modify: `specs/Roadmap.md`(加「重复清理 V2」段 + 各任务 commit hash 记录 + 行为变更明示)
- Modify: `CLAUDE.md`(项目段「## 项目文件结构」同步新文件)
- Modify: `specs/PENDING-USER-ACTIONS.md`(加 19 项真机验,见 design v2 §10)

**改动**:

1. `specs/Roadmap.md`:
   - 顶部「当前进度」段加新行「**2026-06-19**:重复清理 V2 重设计 ship — 5 任务 ~15 commit 落地;Claude Design 高保真原型实装」
   - 「Bug Fix 记录」表加重复清理 V2 行(commit hash 列出)
   - 「关键架构决策」段加 D-dedup-1~15 锁定记录

2. `CLAUDE.md` 「项目文件结构」段:
   - 新建文件:`DedupCleanupV2View.swift` / `DedupFocusReviewOverlay.swift` / `DedupListFilter.swift` / `DedupSortOption.swift`
   - 删除文件:`DuplicateOverviewView.swift`(已 `git rm`)
   - 更新文件:`DuplicateOverviewModel.swift` / `DuplicateGroup.swift` / `ContentView.swift` / `DesignSystem.swift` 的简介

3. `specs/PENDING-USER-ACTIONS.md` 加 19 项真机验(design v2 §10 列表 + 任务 AB/C/D/E 验项)

**Steps**:

- [ ] **F.1.1**: 编辑 3 文档

- [ ] **F.1.2**: Run `make verify` — 14/14 pass(术语字典 + Roadmap referenced specs exist 全过)

- [ ] **F.1.3**: Commit

```
git add specs/Roadmap.md CLAUDE.md specs/PENDING-USER-ACTIONS.md
git commit -m "docs(重复清理 V2): 整子系统 ship 文档同步 + PENDING 19 项军哥真机验 [docs-only]

· specs/Roadmap.md 加重复清理 V2 段 + Bug Fix 记录 + 关键架构决策 D-dedup-1~15
· CLAUDE.md 项目文件结构同步 (新 4 文件 + 删 1 文件 + 改 4 文件简介)
· specs/PENDING-USER-ACTIONS.md 加 19 项 (任务 AB/C/D/E 真机验, design v2 §10)

重复清理 V2 整子系统 ship 完成. 等军哥真机验全过后 closeout."
```

- [ ] **F.1.4**: `git push`

**验收标准**:
- 端到端: 三文档同步,verify.sh 过
- 用户感知: ⏭️ 文档不可视
- 独立 ship: ✅(纯文档 commit)

---

## §3 文档同步表

各任务 ship 后**必须**同步的文档(对照 CLAUDE.md「⚠️ 文档同步强制规则」段):

| 任务 | `specs/Roadmap.md` | `CLAUDE.md` 文件结构 | `specs/PENDING-USER-ACTIONS.md` |
|------|-------------------|---------------------|-------------------------------|
| AB | Bug Fix 表加行 + 关键架构决策段加 D-dedup-1/2 | 新 4 文件 + 删 1 文件 + 改 4 简介 | 任务 F 统一加(暂跳) |
| C | (不单独同步,F 统一) | (不单独同步,F 统一) | F 统一 |
| D | (F 统一) | (F 统一) | F 统一 |
| E | (F 统一) | (F 统一) | F 统一 |
| **F** | **全量同步 + 关键架构决策 D-dedup-3/4/5/6/7/14/15** | **全量同步** | **19 项统一加** |

> **注**: 中间任务(AB/C/D/E)的 commit message 本身就含 commit hash + 改动摘要(verify.sh Stage 1d「Roadmap 已完成 rows have commit hashes」),所以中间 commit 不强求同步 Roadmap.md;**只在 F 收尾时统一同步**(节省 commit 噪音)。但若任务 AB 完成后军哥真机验提了高优 P1 bug 需立刻沉淀,**可破例在 fix 同 commit 内同步 Roadmap**(参考 2026-06-18 删图 bug 处理路径)。

---

## §4 Code reality check 表(强制)

实施期任何新引用代码符号必须先 grep + Read 实际文件再写。**深度要求**(跨项目沉淀「reality check 必须深到函数签名 / 字段类型 / 类继承链 / 装配点」):

| 符号 / 引用点 | 核对项 | 当前实际值(design v2 §2 已核对,2026-06-19) | 引用任务 |
|--------------|-------|-------------------------------------------|---------|
| `IndexStore.fetchDuplicateGroups()` | 函数签名 + 返回类型 | `throws -> [DuplicateGroupRow]`(`Glance/IndexStore/IndexedImage.swift:643`) | AB(model 内调) |
| `IndexStore.fetchDuplicateGroupMembers(sha256:)` | 函数签名 | `throws -> [DuplicateGroupMemberRow]`(line 678) | AB |
| `IndexStore.deleteImage(folderId:relativePath:)` | 签名 | `(Int64, String) throws`(line 109) | AB(trashPending 内调) |
| `IndexStore.restoreImageFromSnapshot(_:)` | 签名 | `throws -> Int64`(line 850) | (undo 用,任务 AB 中保留既有 undo 路径,不动 — 无需 reality check) |
| `IndexStore.fetchSnapshotForRestore(folderId:relativePath:)` | 签名 | `throws -> IndexedImageSnapshot?`(line 768) | AB |
| `IndexStore.promoteOrphanDuplicates()` | 签名 | `throws`(line 391) | AB(trashPending 内调,既有保留) |
| `TrashService.trashItems(_:cancellation:progress:)` | 签名 + 内嵌 TrashInput 类型 | `static func trashItems([TrashService.TrashInput], TrashCancellationToken, @Sendable @escaping (Int, Int) -> Void) async -> TrashOutcome`(`Glance/Dedup/TrashService.swift:37`) | AB |
| `TrashService.TrashInput` | 字段 | `struct TrashInput { let snapshot: IndexedImageSnapshot; let groupKey: GroupKey }`(line 23) | AB |
| `TrashService.restoreItems(_:cancellation:)` | 签名 | `async -> RestoreOutcome`(line 139) | (undo 保留既有) |
| `FolderStoreIndexBridge.addIndexChangedObserver(_:)` | 签名 | `(@escaping () -> Void) -> UUID`(`Glance/IndexStore/FolderStoreIndexBridge.swift:45`) | (model attach 内既有调) |
| `FolderStoreIndexBridge.removeIndexChangedObserver(_:)` | 签名 | `(UUID)`(line 52) | (现有) |
| `FolderStoreIndexBridge.triggerIndexChanged()` | 签名 | `Void`(line 69) | AB(trashPending 内既有调) |
| `FolderStoreIndexBridge.requestRescan(folderId:relativePath:)` | 签名 | `async throws -> Int64`(line 380) | (undo 既有) |
| `AppearanceMode` | enum 定义 | `case dark / light / system`(`Glance/FullScreen/AppState.swift:9`) | (D4 锁定跟随,不引用) |
| `AppState.appearanceMode` | 类型 | `@Published var appearanceMode: AppearanceMode`(line 51) | (不引用) |
| `loadThumbnail(url:maxPixelSize:)` | 签名 | `nonisolated func loadThumbnail(url: URL, maxPixelSize: Int) async -> NSImage?`(`Glance/FolderBrowser/ImageGridView.swift:284`) | AB.8 / D.2(展开区 cell + 浮层 cell load 缩略图) |
| `ContentView.FocusTarget` enum | 是否已存在 + 现有 cases | **本任务 D.1 实施时必须 grep 确认** — 若已存在加 `.dedupOverlay`;若不存在新建 + 改 `@FocusState` 为 enum-based | D.1 |
| `ContentView.duplicateOverviewModel` | @StateObject 类型 | `@StateObject private var duplicateOverviewModel`(line 121) | AB(不动) |
| `ContentView.showDuplicateOverview` | @State 类型 | `@State private var showDuplicateOverview: Bool`(line 128) | AB(不动) |
| `ContentView` line 416 prune 块 | 现状 | `.onChange(of: duplicateOverviewModel.groups) { _, newGroups in ... }` 内 prune `selectedSha256s` | AB.4 扩展 |
| `ContentView` 五态互斥 line 379-410 | 现状 | 3 个 `.onChange` 块各清其它 4 态 | AB.4 加 closeFocusReview 兜底 |
| `DS.Spacing.zero/xs/sm/md/lg/xl` | 既有值 | `0/4/8/16/24/32`(line 13-22) | 全任务 |
| `DS.Icon.trash` | 既有 systemImage | (待 grep `grep -n "Icon.trash\|trash =" DesignSystem.swift`,本任务 AB 实施前核对) | AB.6 |
| `DS.Dedup.bannerXxx` | 既有 commit 已加 | 所有 banner 常量(任务 2 收尾 commit `562484a`)保留不动 | (banner 既有保留) |
| `DuplicateOverviewModel.attach(...)` | 签名 5 参数 | `(indexStore: IndexStore, bridge: FolderStoreIndexBridge, bookmarkManager: BookmarkManager, folderStore: FolderStore, migrationCoordinator: BookmarkMigrationCoordinator)`(line 66-78) | (不动) |
| `BookmarkMigrationCoordinator.start(...)` | 签名(4 参数,**v2 codex P1 修补全**) | `func start(model: DuplicateOverviewModel, bookmarkManager: BookmarkManager, folderStore: FolderStore, bridge: FolderStoreIndexBridge)`(`Glance/Migration/BookmarkMigrationCoordinator.swift:42-47`) | (AB.2 不动 trashPending 内既有 V1 引导路径调用) |
| `DuplicateGroupMember.id/folderId/urlBookmark/relativePath/fileSize/fullPath/isCanonical` | 字段 | 7 字段(`Glance/Dedup/DuplicateGroup.swift:28-45`) | AB.3 |
| `SearchOverlayView` `.focused` 用法 | 既有模式 | `.focused($focusTarget, equals: .search)`(line 56;原 plan 写 line 52 已核更新) | D.1 / D.2 |
| `TrashOutcomeEvent` | 字段 (banner 接口,**v2 codex P1 修补全**) | `struct TrashOutcomeEvent: Identifiable { let id: UUID; let trash: TrashOutcome; let undoResult: RestoreOutcome? }`(`Glance/Dedup/DuplicateOverviewModel.swift:446-451`) | (AB.2 model 不动 lastTrashOutcome 字段类型, banner 接口保留) |
| `AppFocus` enum cases | 既有 cases | `case grid / preview / ephemeral / search`(`Glance/ContentView.swift:14-21`);**任务 D.1 加 `case dedupOverlay`** | D.1 |
| `SearchOverlayState` / `InspectorState` | 既有菜单栏增补类 | (`Glance/MenuBar/SearchOverlayState.swift` / `InspectorState.swift`) | (不动) |

**reality check 触发点**: 每个任务实施前 dispatch subagent 时 prompt 必含「先 grep + Read 上表对应符号实际值再动手,任一不符上表 → 报告军哥 + 停手,**绝不脑补**」。

---

## §5 提交前 checklist

每个任务 commit 前必须过的检查项(对照 CLAUDE.md「## 完成标准」+ /go 五步):

- [ ] **Stage 1**: `make verify` 三段全过(14 pass 0 failed)
  - 静态规则:no `try!` / `as!` / TODO 格式 / `.spring` / 硬编码颜色 / Roadmap commit hash / Roadmap referenced specs exist / hooks
  - **术语字典**: 0 弃用词(违反则 hook 阻塞)
  - **xcodebuild build**: 0 error 0 warning
  - 单测占位 skip(SwiftUI 无 XCTest target)
- [ ] **Stage 2**: 改动文件 git diff self-review
  - 无硬编码颜色 / 魔法数字(全走 `DS.*`)
  - 无 `try!` / `as!` / `!` force unwrap
  - 注释格式 `// TODO: [YYYY-MM-DD]`
  - 仅 1 个 public 类型 per file(CLAUDE.md 全局)
- [ ] **Stage 3**: 文档同步
  - 若新增 / 删除文件 → 同 commit 内改 `CLAUDE.md` 文件结构
  - 若 Bug fix → 同 commit 内加 `Roadmap.md` Bug Fix 行
  - 若任务 ship → F 任务收尾时统一同步
- [ ] **Stage 4**: commit message
  - 代码改动:`<type>(<scope>): <change> (任务 X.N)`
  - 纯文档:末尾加 `[docs-only]`
  - co-author + claude-session 标签
- [ ] **Stage 5**: `git push` 触发 pre-push hook
  - 拦疑似凭据 + 拦 `.env` / `.env.local` / `.env.production`(2026-06-17 重建后仅这两道安全网)
  - 通过 → push 成功

---

## §6 失败兜底 + 下一步

### 实施期失败兜底(CLAUDE.md「## 处理 issue 流程」5)

- **同一问题失败 2 次**: 停下,报告军哥:现象 / 已尝试方案 / 当前假设 / 需要的信息
- **同一问题失败 3 次**: 强制走 `codex:rescue` skill,read-only 投递新方案给 codex,获 second opinion;主 agent 不准在 codex 拍板前继续盲改

### 任务 AB 中重大风险点

- AB.2 model 字段重命名跨多文件 → 编译失败时:严格 grep 漏点 + 重新编辑 + 重跑 verify;不超过 3 轮 self-fix 必走 codex:rescue
- AB.5 DS.Dedup 段扩展常量 ~50 个 → 命名冲突时:rename 加 `_v2_` 后缀或归一到 `enum DedupV2` 子段(不污染既有 `enum Dedup`)
- AB.9 删旧 view:**必须先报告军哥**,等明示同意才 `git rm`

### 本 plan 完成后下一步

按 CLAUDE.md「## 处理 issue 流程」step 3:

1. ✅ design v2 已 commit (`f92e07d`)
2. ⏳ plan v1 本文件写完 + spec self-review 过 + verify.sh 过
3. ⏳ **本主 agent 主动启 codex review plan**(不询问要不要 — CLAUDE.md 硬约束)
4. ⏳ codex verdict 报告军哥(分清哪段我说的、哪段 codex 提的)
5. ⏳ 军哥拍板消化 P0/P1/P2 → 折入 plan v2(若需)
6. ⏳ commit plan v2 → 进 `superpowers:subagent-driven-development` 实施

---

## Self-Review(skill 要求,2026-06-19)

按 writing-plans skill 末尾「Self-Review」节走:

### 1. Spec coverage

design v2 § 1-§ 11 各段对照本 plan:

- ✅ § 1 用户故事 + 范围 → 任务 AB-F 覆盖范围内所有「做」项;「不做」项一律不实施
- ✅ § 2 真实 API 表 → § 4 Code reality check 表逐项核对
- ✅ § 3 数据模型变更(零 SQL migration)→ AB 任务不动 SQL
- ✅ § 4 UI 状态机 6 区域 → AB.6/7/8 实装顶栏 + 汇总条 + 工具条 + 列表 + 展开区;D.2 实装浮层
- ✅ § 5 needsReview 算法 → 任务 C.1
- ✅ § 6 浮层细节 → 任务 D.1-D.4
- ✅ § 7 D-dedup-1~15 决策 → Global Constraints 段 + § 4 reality check
- ✅ § 8 风险段 → 各任务「风险点」段
- ✅ § 9 任务粒度初拟 → § 1 任务总览表细化到具体 commit
- ✅ § 10 PENDING → 任务 F.1 统一加(19 项)
- ✅ § 11 下一步 → § 6 失败兜底 + 下一步

### 2. Placeholder scan

- ✅ 无 「TBD」「TODO」「implement later」「fill in details」
- ✅ AB.6/AB.7/AB.8 view 代码块给了 sample 完整结构(非 stub);AB.5 DS 常量段给了完整字段列表
- ✅ D.2 浮层 view 代码块给了完整布局;D.3 model 6 方法给了完整实装
- ✅ AB.9 / D.4 / F.1 「视情况微调」类描述只在确实需要灵活的步骤(真机验调样式)

### 3. Type consistency

- ✅ `userKeepIdByGroup: [String: Int64]` 全文一致(model 字段 + accessor `userKeepId(for:)` 返回 Int64)
- ✅ `skippedGroupIds: Set<String>` 全文一致(原 selectedSha256s 改名)
- ✅ `DedupListFilter` / `DedupSortOption` enum 名一致(AB.1 创建 + AB.7 使用 + C.1 filter 联动)
- ✅ `focusReviewQueue: [String]` / `focusReviewIndex: Int` 类型一致
- ✅ `FocusTarget.dedupOverlay` case D.1 加 + D.2 用,前后一致

### 4. 术语字典 self-review

本 plan 文档需通过 verify.sh Stage 1d 字典检查。写完后跑 verify 实测确认。
