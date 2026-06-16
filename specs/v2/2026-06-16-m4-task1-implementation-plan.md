# Glance V2 M4 任务 1 实施 Plan — 重复清理只读总览

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把后台已经算好的「字节级完全相同」重复结果搬到台前 — 侧边栏 加「重复清理」入口、主区主区一张只读总览，量化「你有 X 组重复 · 可省 Y GB」、透明标注每组保留张，零删除代码先建立信任。

**Architecture:**
- `FolderStoreIndexBridge.onIndexChanged` 单播变量一次性升级为多播 observer 容器（D35 prerequisite），ContentView.swift:584 既有 smartFolder 调用方同步迁移
- 新增 `Glance/Dedup/` 模块（`DuplicateGroup` record / `DuplicateOverviewModel` state 机 / `DuplicateOverviewView`），mirror `SmartFolderStore` placeholder/attach 模式 + mirror `SmartFolderGridView` 渲染骨架
- 侧边栏 在 `SmartFolderListView` 既有 `ForEach(availableSmartFolders)` 下方加独立 `DuplicateCleanupRow`（不混进 SmartFolder 列表），ContentView 持 `@StateObject duplicateOverviewModel` + `@State showDuplicateOverview`，主区 ZStack swap，五态互斥沿用现有 `.onChange` 模式（V1 folder / 智能文件夹 / 临时结果 / 搜索 overlay / 重复清理总览，进入总览时全清）

**Tech Stack:** SwiftUI + Combine + SQLite3 C API + DispatchWorkItem（debounce）

**术语字典强制**（CONTEXT.md「术语字典表」D 段）：本 plan 全文档命名遵守三层方法论「阶段 V2 → 里程碑 M4 → 任务 1」，弃用别名见 CONTEXT.md A/B/D 段（代码符号保留英文 PascalCase/camelCase 不受字典约束）。

---

## M4 任务 1 — 任务级独立交付三标准论证

> 本任务整体作为一个任务级独立交付单元（CONTEXT.md D 段定义），三标准在 design 8.1 已论证（codex review 第一轮 P3 兜底 — 任务 1 是合格独立交付），本 plan 内部按 5 个步骤实施：**每个步骤是一个 commit 单元（TDD bite-size 频繁提交节奏），不单独满足三标准；任务 1 整体完成后才满足「端到端可跑 + 用户可感知 + 独立可 ship」三标准。步骤 ≠ 任务级独立交付单元。**

| 标准 | 论证 |
|---|---|
| **端到端可跑** | 侧边栏 点「重复清理」入口 → 主区出现真实重复组列表 + 真实可省空间数字（直读真 DB 现成 dedup 结果） |
| **用户可感知** | 第一次量化「我有 X 组重复 · 可省 Y GB」 — Glance 初心 awareness 时刻 |
| **独立可 ship** | 无删除能力也有完整价值 — 军哥真机先验证 dedup 结果分组准不准（保留张选对没、组聚得对没），**建立信任后再放开删除（任务 2）** = 风险前置策略 |

**边界**（任务 1 不做的事，task 2 才装）：
- 不装 checkbox / 「移入废纸篓」按钮 / 删除中态
- 不装 `TrashService` / `TrashOutcome` / `TrashUndoBanner`
- 不装 `IndexStore.fetchSnapshotForRestore` / `IndexStore.restoreImageFromSnapshot` / `FolderStoreIndexBridge.requestRescan` 三个撤销前置 API（task 2 第 1-2 步实施，见 design 4.5 节）
- 不装 `IndexedImageSnapshot` 值类型（task 2 配 fetchSnapshotForRestore 一起加）
- `DuplicateOverviewModel` 不持勾选集合 / 删除中状态 / CancellationToken / `lastTrashOutcome`

---

## File Structure（M4 任务 1 范围内）

### 新增文件

| 路径 | 职责 |
|---|---|
| `Glance/Dedup/DuplicateGroup.swift` | `DuplicateGroup` 值类型（id = sha256 / canonical: DuplicateGroupMember / duplicates: [DuplicateGroupMember] / reclaimableBytes）+ `DuplicateGroupMember` 值类型（id / urlBookmark / relativePath / fileSize / fullPath / isCanonical — **不含 folderId**，codex P2-3 修：任务 2 删除路径再扩） |
| `Glance/Dedup/DuplicateOverviewState.swift` | `enum DuplicateOverviewState` 状态机（idle / loading / loaded / error），mirror `SmartFolderState` |
| `Glance/Dedup/DuplicateOverviewModel.swift` | `@MainActor ObservableObject` 单一 `@Published state` + computed accessors + `placeholder()` / `attach(indexStore:bridge:)` + `load()` + `scheduleReload()`（DispatchWorkItem debounce）+ bridge multicast observer token，mirror `SmartFolderStore`。**不持 `detach()`**（codex P2-4 修：ContentView @StateObject 寿命 = app 寿命，无销毁路径调用 detach；observer token 寿命跟 model 一致，bridge 重建场景由 wireIfReady didWire 保护一次 attach） |
| `Glance/Dedup/DuplicateOverviewView.swift` | 只读总览 view：顶部统计条 + 组列表（每组保留张 + 副本 + reclaimableBytes）+ 空态 + 错误态 + 跟随全局外观；mirror `SmartFolderGridView` ScrollView + LazyVStack 骨架；cell 渲染复用 `ThumbnailCell`。**不持索引 chip**（ContentView.mainContent 已全局 overlay `IndexingProgressView`，避免双渲染 — codex P2-2 修）。**不持 `.onAppear` load 触发**（load 单一 owner 在 ContentView `.onChange(showDuplicateOverview)`，避免与 model.scheduleReload 并发触发 stale-write race — codex P1-2 修） |

### 修改文件

| 路径 | 改动 |
|---|---|
| `Glance/IndexStore/FolderStoreIndexBridge.swift` | **步骤 1 D35 prerequisite**：删 `var onIndexChanged: (() -> Void)? = nil`（:37）→ 加 `private var indexChangedObservers: [UUID: () -> Void] = [:]` + `func addIndexChangedObserver(_:) -> UUID` + `func removeIndexChangedObserver(_:)`；4 个 fire 点（:87 / :192 / :202 / :245）改为 `for observer in indexChangedObservers.values { observer() }` |
| `Glance/ContentView.swift` | **步骤 1**：L584 `bridge.onIndexChanged = { ... }` 改为 `let smartFolderObserverToken = bridge.addIndexChangedObserver { ... }`，token 持到 wireIfReady 域局部变量。**步骤 4**：加 `@StateObject duplicateOverviewModel = DuplicateOverviewModel.placeholder()` + `@State showDuplicateOverview: Bool = false`；`.environmentObject(duplicateOverviewModel)` 注入主区（DuplicateOverviewView 用 `@EnvironmentObject` 读 model）；侧边栏 `SmartFolderListView` 传 `isDuplicateOverviewSelected: showDuplicateOverview` + `onSelectDuplicates` callback；`mainContent` ZStack 加 `showDuplicateOverview` 分支 swap `DuplicateOverviewView`；五态互斥（`.onChange(of: showDuplicateOverview)` 是 load 唯一 owner + 进入临时结果/搜索 overlay 时清 `showDuplicateOverview`）；`wireIfReady` 内调 `duplicateOverviewModel.attach(indexStore:bridge:)` |
| `Glance/IndexStore/IndexedImage.swift` | **步骤 2**：extension 加 `fetchDuplicateGroups() throws -> [DuplicateGroupRow]`（聚合查询，4.4 节 SQL）+ `fetchDuplicateGroupMembers(sha256:) throws -> [DuplicateGroupMemberRow]`（成员明细查询） |
| `Glance/DesignSystem.swift` | **步骤 2**：`enum DS` 加 `enum Dedup`（`reloadDebounceMillis: Int = 500` / `groupRowSpacing: CGFloat` / `groupCellThumbnailSize: CGFloat` / `groupCellThumbnailMaxPixel: Int`（对齐 `loadThumbnail(maxPixelSize: Int)` 签名）/ `canonicalBadgeColor: Color` / `statsBarFont: Font` / `emptyStateFont: Font`） |
| `Glance/FolderBrowser/SmartFolderListView.swift` | **步骤 4**：L17 `ForEach(...)` 下方加独立 `DuplicateCleanupRow`（不混进 `availableSmartFolders`，它不是 SmartFolder）；view 接受 `isDuplicateOverviewSelected: Bool` 参数 + `onSelectDuplicates: () -> Void` callback，**不读 model 状态**（codex P2-1 状态漂移修：选中态唯一权威在 ContentView） |

### 不动文件（依赖既有 API）

| 路径 | 复用 |
|---|---|
| `Glance/IndexStore/DedupPass.swift` | 不改，任务 1 不删 row 无需调 reEvaluateGroup |
| `Glance/IndexStore/IndexStore.swift` | 不改，复用 serial queue + 现有 prepare/step pattern |
| `Glance/IndexStore/IndexStoreHolder.swift` | 不改，`@Published progress` 任务 1 只读用于 chip |
| `Glance/IndexStore/IndexingProgressView.swift` | 不改，复用 chip pattern |
| `Glance/FolderBrowser/ImageGridView.swift` | 不改，DuplicateOverviewView 复用 `ThumbnailCell` + 顶层 `loadThumbnail` 函数 |
| `Glance/SmartFolder/SmartFolderStore.swift` | 不改，mirror 其 state 机 + placeholder/attach 模式 |
| `Glance/IndexStore/IndexStoreSchema.swift` | 不改，复用 v2 schema 已有列 |

---

## 步骤 1：bridge 多播架构升级（D35 prerequisite，纯 refactor 零功能变化）

> **为什么是第 1 步**：design D35 + codex review 第三轮 P1 拍板 — `FolderStoreIndexBridge.onIndexChanged` 是单播 `var`，ContentView.swift:584 已绑给 `smartFolderStore.refreshSelected`；DuplicateOverviewModel 若直接覆盖会断 V2 主线 smartFolder 流量。capture-old-callback 链式调用在 `@StateObject` 模型下不成立（model 长寿不 deinit → 永久覆盖）。一次性架构升级 bridge → 多播容器是正解，**必须在新 observer（DuplicateOverviewModel）注册之前完成**。
>
> **本步用户感知**：智能文件夹缩略图网格自动刷新功能行为完全等价（FSEvents 增量 / dedup 完成 / 孤儿清扫 4 路触发不变）。纯 refactor 步骤 prerequisite，不引入新功能也不破坏现有功能。

**Files:**
- Modify: `Glance/IndexStore/FolderStoreIndexBridge.swift`（删 :37 单播变量 + 4 fire 点改 :87 / :192 / :202 / :245 + 新增 add/removeIndexChangedObserver API）
- Modify: `Glance/ContentView.swift`（L584 唯一 caller 同步迁移）

- [ ] **步骤 1.1: 改 FolderStoreIndexBridge 添加多播 observer 容器 + API**

打开 `Glance/IndexStore/FolderStoreIndexBridge.swift`，删 L37 单播变量声明：

```swift
// 删除：
var onIndexChanged: (() -> Void)? = nil
```

替换为多播容器 + add/remove API（放回原 L37 位置，注释解释 D35 原因）：

```swift
/// D35 — 多播 observer 容器（M4 任务 1 prerequisite，原 onIndexChanged 单播变量升级）。
/// 注册多个观察者 fan-out：FSEvents 派发的索引更新（add/remove/modify）/ dedup 完成 / 孤儿清扫
/// 触发后遍历 dict 调每个 observer。caller 用 `addIndexChangedObserver` 注册时拿 UUID token，
/// 销毁时显式 `removeIndexChangedObserver(token)` 清理（@StateObject model 长寿不 deinit，
/// 不依赖自动释放）。
private var indexChangedObservers: [UUID: () -> Void] = [:]

func addIndexChangedObserver(_ closure: @escaping () -> Void) -> UUID {
    let token = UUID()
    indexChangedObservers[token] = closure
    return token
}

func removeIndexChangedObserver(_ id: UUID) {
    indexChangedObservers.removeValue(forKey: id)
}
```

- [ ] **步骤 1.2: 4 个 fire 点遍历 dict**

L87（孤儿清扫后）：

```swift
// 原：onIndexChanged?()
for observer in indexChangedObservers.values { observer() }
```

L192（triggerDedupFullPass 完成回主线程）：

```swift
// 原：self?.onIndexChanged?()
guard let self else { return }
for observer in self.indexChangedObservers.values { observer() }
```

L202（triggerDedupGroup 完成回主线程）：

```swift
// 原：self?.onIndexChanged?()
guard let self else { return }
for observer in self.indexChangedObservers.values { observer() }
```

L245（handleEvents batch 处理完）：

```swift
// 原：if changed { onIndexChanged?() }
if changed {
    for observer in indexChangedObservers.values { observer() }
}
```

- [ ] **步骤 1.3: ContentView.swift:584 唯一 caller 同步迁移**

打开 `Glance/ContentView.swift`，定位 L583-586：

```swift
// 原：
let storeRef = smartFolderStore  // class 引用 capture 安全
bridge.onIndexChanged = {
    Task { await storeRef.refreshSelected() }
}
```

改为：

```swift
let storeRef = smartFolderStore  // class 引用 capture 安全
// D35 — 注册多播 observer，token 局部变量持到本 async func 退出（caller 不再 cleanup
// 因为 bridge 寿命由 indexBridge @State 持有；smartFolder 永远在线即一次注册即可）
let smartFolderObserverToken = bridge.addIndexChangedObserver {
    Task { await storeRef.refreshSelected() }
}
_ = smartFolderObserverToken  // 暂 ignore；如未来需要 detach 路径再改回主线程持 token
```

> **理由**：当前 `wireIfReady` 在 `.onAppear` + `.onChange(of: indexStoreHolder.isReady)` 调（ContentView.swift:273 / :275），`didWire` 标志保证只 wire 一次。bridge 由 `@State indexBridge` 持有寿命跟 ContentView 一致，smartFolder observer 永远在线即合理。未来若 ContentView 重建场景出现需要 detach，再加 token 持久化。

- [ ] **步骤 1.4: 编译验证 + smartFolder 行为等价**

跑：

```bash
make build
```

期望：`BUILD SUCCEEDED` + 0 errors + 0 warnings。

启 app 真机验证智能文件夹缩略图网格自动刷新（手动验证 4 路 fire 点等价）：

1. 添加根目录 → 等首次扫描完 → 期望缩略图网格出现新图（fire 点 L192 dedup full pass 完成）
2. 文件夹外部 Finder 新增 / 删除 / 改名图 → 期望缩略图网格自动反映（fire 点 L245 FSEvents handleEvents）
3. 删根目录 → 期望孤儿 image 被清（fire 点 L87 孤儿清扫）
4. 编辑某图（变 file_size 或 sha256）→ 期望缩略图网格自动刷新（fire 点 L202 dedup group 重决议）

若上述 4 路行为退化 → 回查 fire 点遍历 dict 实现。

- [ ] **步骤 1.5: commit**

```bash
git add Glance/IndexStore/FolderStoreIndexBridge.swift Glance/ContentView.swift
git commit -m "refactor(M4): bridge 多播架构升级 — D35 task 1 prerequisite

- onIndexChanged 单播 var 升级为 indexChangedObservers UUID dict 多播容器
- 新增 addIndexChangedObserver(_:) -> UUID / removeIndexChangedObserver(_:)
- 4 fire 点（:87 / :192 / :202 / :245）改为遍历 dict 调每个 observer
- ContentView.swift:584 既有 smartFolder caller 同步迁移 addIndexChangedObserver

理由：design D35 拍板 — capture-old-callback 链式调用在 @StateObject 模型下不成立，
DuplicateOverviewModel 若直接覆盖会断 V2 主线 smartFolder 流量。一次性升级正解。

未来观察者（M4 DuplicateOverviewModel）注册前置完成，行为完全等价不引入新功能。
真机验证 4 路 fire 等价（首次 scan / FSEvents 增量 / 孤儿清扫 / dedup 重决议）。"
```

---

## 步骤 2：fetchDuplicateGroups 聚合查询 + DuplicateGroup record + DS.Dedup 常量

> **本步用户感知**：DB 层准备，本步独立无 UI 感知。**本步 commit 作为步骤 4 集成前的 atom**（plan 内部技术栈层级拆分，非任务级独立交付违反 — 任务 1 整体作为一个任务级独立交付已论证）。

**Files:**
- Create: `Glance/Dedup/DuplicateGroup.swift`
- Modify: `Glance/IndexStore/IndexedImage.swift`（extension 加 2 个 fetch 方法）
- Modify: `Glance/DesignSystem.swift`（加 `enum Dedup`）

- [ ] **步骤 2.1: 创建 Glance/Dedup/ 目录 + 新建 DuplicateGroup.swift**

```bash
mkdir -p Glance/Dedup
```

新文件 `Glance/Dedup/DuplicateGroup.swift`：

```swift
//
//  DuplicateGroup.swift
//  Glance
//
//  M4 任务 1 — 重复清理总览的值类型 record。
//  每个 group 代表 SQL 聚合后的一组「content_sha256 相同 + 含 dedup_canonical=0 副本」的图，
//  含保留张（canonical）+ 待清理副本（duplicates）+ 可省空间（reclaimableBytes）。
//

import Foundation

/// 总览 view 渲染一组重复图的最小数据单位。
/// canonical 保留张 + duplicates 副本数组分开，UI 透明显示「保留这张」（D28 硬约束）。
struct DuplicateGroup: Identifiable, Equatable {
    /// SHA256 hex 字符串作为组的稳定 ID（同 sha256 即同组）
    let id: String
    /// 保留张（dedup_canonical = 1）的成员
    let canonical: DuplicateGroupMember
    /// 待清理副本（dedup_canonical = 0）的成员，按 birth_time ASC 排（与 SQL 一致）
    let duplicates: [DuplicateGroupMember]
    /// 副本可省空间总和（duplicates 的 fileSize 之和；保留张不计）
    let reclaimableBytes: Int64
}

/// 重复组内单张图的最小数据（任务 1 只读用）。
/// 任务 2 删除路径所需的额外字段（如 folderId）届时扩展，本 struct 不预装
/// （codex P2-3 修：避免 task 2 边界泄漏进 task 1 审查面）。
struct DuplicateGroupMember: Identifiable, Equatable {
    /// images.id（Identifiable 满足 UI ForEach 用；任务 1 不通过 id 删 row）
    let id: Int64
    /// images.url_bookmark（root bookmark，UI 渲染缩略图 resolve scope 用）
    let urlBookmark: Data
    /// images.relative_path（cell 显示用 + 缩略图 resolve 拼 child URL 用）
    let relativePath: String
    /// images.file_size（保留张 / 副本同 sha256 必然同 file_size，UI 显示和 reclaimable 计算用）
    let fileSize: Int64
    /// folders.root_path / relative_path 拼接的展示路径（cell tooltip 用，D28 透明显示来源路径）
    let fullPath: String
    /// dedup_canonical = 1（保留张）or 0（副本）— UI 渲染 badge / 弱化用
    let isCanonical: Bool
}

/// IndexStore.fetchDuplicateGroups 聚合查询返回行（每组一行：sha256 + 成员数 + reclaimable）。
/// Model 拿这行后调 fetchDuplicateGroupMembers 拉成员明细组装成 DuplicateGroup。
struct DuplicateGroupRow {
    let contentSha256: String
    let memberCount: Int64
    let reclaimableBytes: Int64
}

/// IndexStore.fetchDuplicateGroupMembers 成员明细查询返回行（每行一个 member）。
/// 任务 1 只读必需字段；任务 2 删除路径所需的 folder_id 届时扩展。
struct DuplicateGroupMemberRow {
    let id: Int64
    let dedupCanonical: Bool
    let fileSize: Int64
    let relativePath: String
    let urlBookmark: Data
    let fullPath: String
}
```

- [ ] **步骤 2.2: IndexedImage.swift 加 fetchDuplicateGroups 聚合查询**

打开 `Glance/IndexStore/IndexedImage.swift`，在文件末尾（L641 `private func checkBind` 私有 helper 之前的 extension 闭合 `}` 内）追加。**真实 API 模式**：`try sync { db in ... }`（IndexStore.swift:36）+ 裸 `sqlite3_*` C API + `try checkBind(...)` 包裹 bind 调用（mirror `fetchCandidateGroups` IndexedImage.swift:310 + `fetchImagesInGroup` :327）：

```swift
// MARK: - M4 任务 1 — 重复清理总览聚合查询

    /// M4 任务 1 — 总览主查询。
    /// 列出所有「真有待清理副本」的重复组（HAVING SUM(dedup_canonical=0) > 0 保证：
    /// 只列含至少一个副本的组，单张组 / 全 NULL 组 / 仅保留张的组都不进总览）。
    /// content_sha256 IS NOT NULL 自动排除尚未算 SHA256 的图（4.4 节 dedup_canonical 口径）。
    /// 按 reclaimable_bytes DESC 排，可省空间最大的组在最前面。
    func fetchDuplicateGroups() throws -> [DuplicateGroupRow] {
        try sync { db in
            let stmt = try db.prepare("""
                SELECT content_sha256,
                       COUNT(*) AS member_count,
                       SUM(CASE WHEN dedup_canonical = 0 THEN file_size ELSE 0 END) AS reclaimable_bytes
                FROM images
                WHERE content_sha256 IS NOT NULL
                GROUP BY content_sha256
                HAVING SUM(CASE WHEN dedup_canonical = 0 THEN 1 ELSE 0 END) > 0
                ORDER BY reclaimable_bytes DESC;
            """)
            defer { sqlite3_finalize(stmt) }
            var rows: [DuplicateGroupRow] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let sha = String(cString: sqlite3_column_text(stmt, 0))
                let count = sqlite3_column_int64(stmt, 1)
                let reclaimable = sqlite3_column_int64(stmt, 2)
                rows.append(DuplicateGroupRow(
                    contentSha256: sha,
                    memberCount: count,
                    reclaimableBytes: reclaimable
                ))
            }
            return rows
        }
    }

    /// M4 任务 1 — 成员明细查询（点开组 / 任务 2 删除时用）。
    /// 按 dedup_canonical DESC 排把保留张排第一（UI 透明显示「保留这张」D28）；
    /// 同 dedup_canonical 内按 birth_time ASC 排（与 DedupPass.reEvaluateGroup canonical 决议
    /// earliest birth_time + 最小 id tie-break 一致）。
    /// JOIN folders 拿 root_path 拼 full_path 给 cell tooltip 用。
    func fetchDuplicateGroupMembers(sha256: String) throws -> [DuplicateGroupMemberRow] {
        try sync { db in
            // 注：SELECT 不取 i.folder_id（任务 1 只读不需要；任务 2 删除路径再扩 — codex P2-3 修）。
            // JOIN ON i.folder_id = f.id 仍保留（拼 full_path 需要）。
            let stmt = try db.prepare("""
                SELECT i.id, i.dedup_canonical, i.file_size, i.relative_path,
                       i.url_bookmark, f.root_path || '/' || i.relative_path AS full_path
                FROM images i
                JOIN folders f ON i.folder_id = f.id
                WHERE i.content_sha256 = ?
                ORDER BY i.dedup_canonical DESC, i.birth_time ASC, i.id ASC;
            """)
            defer { sqlite3_finalize(stmt) }
            try checkBind(
                sqlite3_bind_text(
                    stmt, 1,
                    (sha256 as NSString).utf8String, -1,
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                ),
                index: 1, db: db
            )
            var rows: [DuplicateGroupMemberRow] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let canonical = sqlite3_column_int64(stmt, 1) == 1
                let fileSize = sqlite3_column_int64(stmt, 2)
                let relPath = String(cString: sqlite3_column_text(stmt, 3))
                let blobLen = sqlite3_column_bytes(stmt, 4)
                let blobPtr = sqlite3_column_blob(stmt, 4)
                let bookmark = blobPtr.map { Data(bytes: $0, count: Int(blobLen)) } ?? Data()
                let fullPath = String(cString: sqlite3_column_text(stmt, 5))
                rows.append(DuplicateGroupMemberRow(
                    id: id,
                    dedupCanonical: canonical,
                    fileSize: fileSize,
                    relativePath: relPath,
                    urlBookmark: bookmark,
                    fullPath: fullPath
                ))
            }
            return rows
        }
    }
```

> **实现细节实证**（写代码前已 grep verify）：
>
> - `try sync { db in ... }` 是 `IndexStore.sync<T>(_ block: (IndexDatabase) throws -> T) throws -> T`（IndexStore.swift:36）— 所有 IndexStore extension fetch/CRUD 都走此模式串行化访问
> - `db.prepare("...")` 返回裸 `OpaquePointer`（IndexDatabase.swift:50）— **不是** 自定义 `Statement` 类型，没有 `.columnText` / `.step` 包装方法
> - `sqlite3_step(stmt) == SQLITE_ROW` 循环 / `sqlite3_finalize(stmt)` 收尾 / `sqlite3_column_int64(stmt, idx)` / `sqlite3_column_text(stmt, idx)` 取列 / `String(cString:)` 转 Swift String — 裸 sqlite3 C API
> - `sqlite3_column_blob` + `sqlite3_column_bytes` 组合取 BLOB（url_bookmark）+ `Data(bytes:count:)` 包装 — mirror `fetchImagesInGroup` 取 bookmark 的写法（IndexedImage.swift:345-347）
> - `checkBind(_:index:db:)` private helper 包裹 bind 检查（IndexedImage.swift:636）
> - bind TEXT 的 `unsafeBitCast(-1, to: sqlite3_destructor_type.self)` = `SQLITE_TRANSIENT` 让 SQLite 自己复制字符串 — mirror `fetchImagesInGroup` :336 + `fetchImageGroupKey` :366 已落写法

- [ ] **步骤 2.3: 写聚合查询的单元手测脚本**

无 XCTest target，按项目惯例（CLAUDE.md 完成标准 + AppState.md 已落）人工验：

在 `DuplicateOverviewModel` 完成（步骤 3）前，无法直接通过 UI 验，**先验编译**：

```bash
make build
```

期望：`BUILD SUCCEEDED` + 0 errors + 0 warnings。

- [ ] **步骤 2.4: DesignSystem.swift 加 enum Dedup**

打开 `Glance/DesignSystem.swift`，定位 `enum DS` 内部（L11-285），在 `enum Icon`（L248）前插：

```swift
/// M4 — 重复清理总览专属常量（任务 1 只读 UI 用；任务 2 加删除按钮 / 进度配色再补）。
enum Dedup {
    /// model bridge observer debounce — 后台索引活动激增（FSEvents batch / dedup full pass 完成）
    /// 时频繁 fire，500ms debounce 后 reload 避免抖动；UI 实际感知接近实时。
    static let reloadDebounceMillis: Int = 500
    /// 组与组之间的垂直间距（LazyVStack spacing）
    static let groupRowSpacing: CGFloat = DS.Spacing.lg
    /// 组内缩略图渲染尺寸（保留张 + 副本展示位）
    static let groupCellThumbnailSize: CGFloat = 96
    /// loadThumbnail 请求的最大像素（高 DPI 屏 Retina 缩放）；类型 Int 对齐 loadThumbnail(maxPixelSize: Int) 签名
    static let groupCellThumbnailMaxPixel: Int = 192
    /// 保留张 badge 文字 / 边框配色（绿系，accent 提示「这张留下」D28）
    static let canonicalBadgeColor: Color = .green
    /// 顶部统计条字号（mirror IndexingProgressView caption 风格）
    static let statsBarFont: Font = .body.weight(.semibold)
    /// 空态字号
    static let emptyStateFont: Font = .body
    /// 副本相对保留张的视觉弱化 opacity
    static let duplicateThumbnailOpacity: Double = 0.7
}
```

> **理由**：DS.Spacing.lg 是已有常量（DesignSystem.swift:15-25 `enum Spacing`，grep 确认 `lg` case 存在；若不存在则用 `xl` / `md` 现有最接近的）。`reloadDebounceMillis` 命名表达单位（避免魔法数字）。

- [ ] **步骤 2.5: commit**

```bash
git add Glance/Dedup/DuplicateGroup.swift Glance/IndexStore/IndexedImage.swift Glance/DesignSystem.swift
git commit -m "feat(M4): fetchDuplicateGroups 聚合查询 + DuplicateGroup record + DS.Dedup 常量

- 新建 Glance/Dedup/ 目录 + DuplicateGroup.swift（DuplicateGroup / DuplicateGroupMember
  / DuplicateGroupRow / DuplicateGroupMemberRow 4 个值类型）
- IndexedImage.swift extension 加 fetchDuplicateGroups + fetchDuplicateGroupMembers 两查询
  - fetchDuplicateGroups: HAVING SUM(dedup_canonical=0) > 0 只列真有副本的组
  - fetchDuplicateGroupMembers: dedup_canonical DESC 保证保留张排第一（D28 透明显示）
- DesignSystem.swift 加 enum Dedup（reloadDebounceMillis 500 / 缩略图尺寸 / 保留张 badge 配色
  / 副本弱化 opacity）
- DB 层 + 设计常量准备完毕，步骤 3 写 Model 调用"
```

---

## 步骤 3：DuplicateOverviewModel 状态机 + bridge observer 订阅 + load 路径

> **本步用户感知**：业务 model 准备，无 UI 集成，独立可单元验。**任务 1 硬边界**：本 model 只 expose `state` / `load()` / `attach()`，不放 task 2 的 `trashSelected` / `undo` / 勾选集合任何字段（CLAUDE.md 改动 scope 锁死 + design 4.1 model 描述）。**不持 `detach()`**（codex P2-4 修：dead code 删除）。

**Files:**
- Create: `Glance/Dedup/DuplicateOverviewState.swift`
- Create: `Glance/Dedup/DuplicateOverviewModel.swift`

- [ ] **步骤 3.1: 新建 DuplicateOverviewState.swift（状态机 enum）**

新文件 `Glance/Dedup/DuplicateOverviewState.swift`：

```swift
//
//  DuplicateOverviewState.swift
//  Glance
//
//  M4 任务 1 — 总览状态机。mirror SmartFolderState（SmartFolder/SmartFolderState.swift）：
//  单一 @Published state 替代多独立字段，无效组合从结构上不可表达。
//

import Foundation

enum DuplicateOverviewState: Equatable {
    /// 初始 / 入口未激活
    case idle
    /// 加载中（staleGroups 在 reload 时 carry 旧数据避免清空闪屏）
    case loading(staleGroups: [DuplicateGroup])
    /// 已加载（含空数组 = 真无重复 → view 走空态）
    case loaded(groups: [DuplicateGroup])
    /// load 出错（SQL fail / IndexStore 异常）
    case error(message: String)
}
```

- [ ] **步骤 3.2: 新建 DuplicateOverviewModel.swift**

新文件 `Glance/Dedup/DuplicateOverviewModel.swift`：

```swift
//
//  DuplicateOverviewModel.swift
//  Glance
//
//  M4 任务 1 — 总览业务 model。@MainActor ObservableObject，mirror SmartFolderStore：
//  placeholder() / attach(indexStore:bridge:) 异步装配；单一 @Published state 状态机。
//
//  D35 — 注册 bridge.addIndexChangedObserver 多播 observer 跟踪后台索引活动，
//  debounce 500ms 后 reload。observerToken 寿命跟 model 一致（@StateObject 长寿，
//  app 寿命内不销毁）。
//
//  任务 1 硬边界：本 model 仅 expose state + load + attach。不持 detach（codex P2-4 修：
//  现有架构无销毁路径调用，避免假 API；未来 ContentView 重建场景出现再加）。
//  任务 2 加：勾选集合 / 删除中状态 / CancellationToken / trashSelected / undo / lastTrashOutcome。
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class DuplicateOverviewModel: ObservableObject {

    @Published private(set) var state: DuplicateOverviewState = .idle

    private var indexStore: IndexStore?
    private weak var bridge: FolderStoreIndexBridge?
    private var observerToken: UUID?
    private var pendingReload: DispatchWorkItem?
    // stale-write guard：每次 load() 自增，后续 await 回来核对；不一致说明更新的 load 已启动，旧结果丢弃
    private var loadGeneration: Int = 0

    // 注：入口激活态不放 model（codex P2-1 状态漂移修） —— ContentView.@State showDuplicateOverview
    // 是唯一权威，SmartFolderListView 通过 isDuplicateOverviewSelected: Bool 参数接收，
    // 不读 model 状态。这与现有三态互斥（V1 folder / 智能文件夹 / 临时结果视图）全在
    // ContentView 持有的模式一致（ContentView.swift:145-149 / :287-299）。

    // MARK: - placeholder / attach（mirror SmartFolderStore.placeholder / attach）

    static func placeholder() -> DuplicateOverviewModel {
        DuplicateOverviewModel()
    }

    private init() {}

    /// ContentView wireIfReady 调，IndexStore ready 后装配 + 注册 bridge observer。
    /// 幂等：重复调忽略（已 attach 过则不重复注册 observer）。
    func attach(indexStore: IndexStore, bridge: FolderStoreIndexBridge) {
        guard self.indexStore == nil else { return }
        self.indexStore = indexStore
        self.bridge = bridge
        let token = bridge.addIndexChangedObserver { [weak self] in
            // bridge fire 在 MainActor 上（FolderStoreIndexBridge 已 @MainActor）；
            // 这里直接调 scheduleReload 同 actor 不需切线程
            Task { @MainActor [weak self] in
                self?.scheduleReload()
            }
        }
        self.observerToken = token
    }

    // 注：不持 detach() (codex P2-4 修)。ContentView @StateObject 寿命 = app 寿命，
    // 现有架构无销毁路径调用 detach；observerToken 寿命跟 model 一致即合理。
    // 若未来 ContentView 重建场景出现，再加 detach() 接线，目前避免假 API。

    // MARK: - load / scheduleReload

    /// 立即 load — 入口激活时（ContentView showDuplicateOverview 由 false → true）调一次。
    func load() async {
        guard let store = indexStore else {
            state = .error(message: "IndexStore 未装配")
            return
        }
        loadGeneration &+= 1
        let myGeneration = loadGeneration
        let staleGroups = currentGroups()
        state = .loading(staleGroups: staleGroups)
        do {
            let groups = try await Task.detached(priority: .userInitiated) {
                try Self.fetchGroups(store: store)
            }.value
            // Stale-write guard：generation 不一致说明后续 load 已启动，旧结果丢弃
            // 注：不用 `if case .loading = state` —— 两次并发 load 都满足 .loading 条件，generation 才是唯一 ID
            guard loadGeneration == myGeneration else { return }
            state = .loaded(groups: groups)
        } catch {
            guard loadGeneration == myGeneration else { return }
            state = .error(message: "\(error)")
        }
    }

    /// bridge observer fire 时调，500ms debounce 后 load。
    /// DispatchWorkItem cancel + 重置实现 trailing debounce（同 SwiftUI Search.swift debounce 套路）。
    func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                await self?.load()
            }
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(DS.Dedup.reloadDebounceMillis),
            execute: work
        )
    }

    // MARK: - helpers

    /// 取当前 state 的 groups 数组（reload 时作为 stale carry）
    private func currentGroups() -> [DuplicateGroup] {
        switch state {
        case .loaded(let groups): return groups
        case .loading(let stale): return stale
        case .idle, .error: return []
        }
    }

    /// 后台 Task 跑的拉数据 + 组装函数。nonisolated static，所有依赖通过参数传入。
    private static func fetchGroups(store: IndexStore) throws -> [DuplicateGroup] {
        let rows = try store.fetchDuplicateGroups()
        var groups: [DuplicateGroup] = []
        groups.reserveCapacity(rows.count)
        for row in rows {
            let members = try store.fetchDuplicateGroupMembers(sha256: row.contentSha256)
            guard let canonical = members.first(where: { $0.dedupCanonical }) else {
                // 异常组（无 canonical）— DedupPass 不应产出此状态；跳过
                continue
            }
            let duplicates = members.filter { !$0.dedupCanonical }
            let group = DuplicateGroup(
                id: row.contentSha256,
                canonical: makeMember(from: canonical),
                duplicates: duplicates.map(makeMember(from:)),
                reclaimableBytes: row.reclaimableBytes
            )
            groups.append(group)
        }
        return groups
    }

    private static func makeMember(from row: DuplicateGroupMemberRow) -> DuplicateGroupMember {
        DuplicateGroupMember(
            id: row.id,
            urlBookmark: row.urlBookmark,
            relativePath: row.relativePath,
            fileSize: row.fileSize,
            fullPath: row.fullPath,
            isCanonical: row.dedupCanonical
        )
    }
}

// MARK: - computed accessors（view 直接读，mirror SmartFolderStore computed accessors）

extension DuplicateOverviewModel {

    /// view 用 — 当前总览的组列表（.loaded 时真实数据，.loading 时 stale 防闪屏，其它空数组）。
    var groups: [DuplicateGroup] {
        currentGroups()
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let msg) = state { return msg }
        return nil
    }

    /// 总组数（顶部统计条用）
    var groupCount: Int { groups.count }

    /// 总可省空间（顶部统计条用，所有组 reclaimableBytes 之和）
    var totalReclaimableBytes: Int64 {
        groups.reduce(into: Int64(0)) { $0 += $1.reclaimableBytes }
    }
}
```

> **实现细节实证**：
>
> - `FolderStoreIndexBridge` 是 `@MainActor` class（grep `FolderStoreIndexBridge.swift` 顶部确认 `@MainActor final class FolderStoreIndexBridge: ObservableObject` 注解 — 若实际不是 @MainActor，则 `addIndexChangedObserver` closure 可能在任意线程被调，model 内 closure 必须用 `Task { @MainActor in ... }` 显式 hop）
> - 实际：本 plan closure 已用 `Task { @MainActor [weak self] in ... }` 包裹 → 即使 bridge 不是 @MainActor 也兼容；保守做法
> - `IndexStore` 是 class 通过参数传 `Task.detached` 安全（`nonisolated`）
> - `DispatchQueue.main.asyncAfter` + `DispatchWorkItem.cancel` 是 SwiftUI 项目通用 debounce 模式（无 Combine debounce subject 引入避免增加依赖面）

- [ ] **步骤 3.3: 编译验证**

```bash
make build
```

期望：`BUILD SUCCEEDED` + 0 errors + 0 warnings。

- [ ] **步骤 3.4: commit**

```bash
git add Glance/Dedup/DuplicateOverviewState.swift Glance/Dedup/DuplicateOverviewModel.swift
git commit -m "feat(M4): DuplicateOverviewModel 状态机 + bridge multicast observer 订阅

- DuplicateOverviewState enum (idle / loading[stale] / loaded / error) mirror SmartFolderState
- DuplicateOverviewModel @MainActor ObservableObject placeholder/attach 模式 mirror SmartFolderStore
- attach(indexStore:bridge:) 注册 bridge.addIndexChangedObserver 拿 token（寿命跟 model 一致，不持 detach）
- scheduleReload() DispatchWorkItem debounce DS.Dedup.reloadDebounceMillis (500ms) → load()
- load() Task.detached fetchGroups + generation counter stale-write guard（两次并发 load 时丢弃旧结果）
- computed accessors（groups / isLoading / errorMessage / groupCount / totalReclaimableBytes）

任务 1 硬边界：本 commit 不放 task 2 的勾选集合 / trashSelected / undo / lastTrashOutcome 任何字段。
任务 2 实施时增量扩展本 model（design 8.2 范围）。"
```

---

## 步骤 4：DuplicateOverviewView 只读 UI + 侧边栏「重复清理」入口 + ContentView 四态互斥

> **本步用户感知**：✅ 完整任务 1 价值兑现 — 侧边栏 点入口 → 主区出现真实重复组列表 + 真实可省空间数字 + 保留张透明标注。本步是任务 1 的 user-facing 集成步，软件功能整体在本 commit 后用户首次能完整体验。

**Files:**
- Create: `Glance/Dedup/DuplicateOverviewView.swift`
- Modify: `Glance/FolderBrowser/SmartFolderListView.swift`
- Modify: `Glance/ContentView.swift`

- [ ] **步骤 4.1: 新建 DuplicateOverviewView.swift**

新文件 `Glance/Dedup/DuplicateOverviewView.swift`：

```swift
//
//  DuplicateOverviewView.swift
//  Glance
//
//  M4 任务 1 — 重复清理总览只读 view。
//  顶部统计条「X 组重复 · 可省 Y」+ 组列表（每组保留张 badge + 副本展示 + reclaimableBytes）
//  + 空态 + 错误态。跟随全局外观（非快速看图器场景不强制深色）。
//  注：不渲染索引 chip —— ContentView.mainContent 已全局 overlay IndexingProgressView（codex P2-2 修）。
//

import SwiftUI

struct DuplicateOverviewView: View {
    @EnvironmentObject var model: DuplicateOverviewModel

    var body: some View {
        mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
    }
    // 注：本 view 不持 .onAppear 触发 load —— load 单一 owner = ContentView
    // .onChange(of: showDuplicateOverview)（codex P1-2 race 修：双触发会让先返回的旧结果
    // 反向覆盖后返回的新结果，stale-write guard 无 generation token 防不住）。
    // 注：本 view 不渲染索引 chip —— ContentView.mainContent 已全局 overlay
    // IndexingProgressView（ContentView.swift:358-365），本 view 渲染会双层（codex P2-2 修）。

    @ViewBuilder
    private var mainContent: some View {
        if let err = model.errorMessage {
            errorState(message: err)
        } else if model.groupCount == 0 && !model.isLoading {
            emptyState
        } else {
            groupsList
        }
    }

    private var groupsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Dedup.groupRowSpacing) {
                statsBar
                ForEach(model.groups) { group in
                    DuplicateGroupRow(group: group)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
        }
    }

    private var statsBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text("\(model.groupCount) 组重复")
                .font(DS.Dedup.statsBarFont)
            Text("·")
                .foregroundStyle(.secondary)
            Text("可省 \(formattedReclaimable)")
                .font(DS.Dedup.statsBarFont)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("没找到重复图")
                .font(DS.Dedup.emptyStateFont)
                .foregroundStyle(.secondary)
            Text("Glance 会在后台持续监控，发现重复立即显示。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("加载失败")
                .font(DS.Dedup.emptyStateFont)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DS.Spacing.lg)
    }

    // indexingChip 不在本 view 渲染 —— ContentView.mainContent 已全局 overlay
    // IndexingProgressView (ContentView.swift:358-365)，本 view 无需重复
    // (codex P2-2 双渲染修)。

    private var formattedReclaimable: String {
        ByteCountFormatter.string(
            fromByteCount: model.totalReclaimableBytes,
            countStyle: .file
        )
    }
}

/// 单一组渲染：保留张缩略图（badge「保留」）+ 副本缩略图 + 路径信息 + 组可省空间。
private struct DuplicateGroupRow: View {
    let group: DuplicateGroup

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                DuplicateMemberCell(member: group.canonical, isCanonical: true)
                ForEach(group.duplicates) { dup in
                    DuplicateMemberCell(member: dup, isCanonical: false)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "scalemass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("组可省 \(formattedReclaimable)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.md)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var formattedReclaimable: String {
        ByteCountFormatter.string(
            fromByteCount: group.reclaimableBytes,
            countStyle: .file
        )
    }
}

/// 单张图缩略图渲染。保留张加「保留」badge + 不弱化；副本 opacity 0.7 视觉弱化（无 badge）。
/// hover 显完整路径 tooltip（mirror SmartFolderGridView 做法）。
private struct DuplicateMemberCell: View {
    let member: DuplicateGroupMember
    let isCanonical: Bool

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            ZStack(alignment: .topTrailing) {
                thumbnailContent
                    .frame(
                        width: DS.Dedup.groupCellThumbnailSize,
                        height: DS.Dedup.groupCellThumbnailSize
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .opacity(isCanonical ? 1.0 : DS.Dedup.duplicateThumbnailOpacity)
                if isCanonical {
                    Text("保留")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.Dedup.canonicalBadgeColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(4)
                }
            }
            Text(member.relativePath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: DS.Dedup.groupCellThumbnailSize, alignment: .leading)
        }
        .help(member.fullPath)
        .task(id: member.id) {
            await loadThumb()
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let img = thumbnail {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.15))
        }
    }

    /// resolve root bookmark + 拼 child URL + loadThumbnail（顶层 nonisolated 函数）。
    /// mirror DedupPass.computeSha 的 scope 模式。
    private func loadThumb() async {
        let urlBookmark = member.urlBookmark
        let relativePath = member.relativePath
        let maxPixel = DS.Dedup.groupCellThumbnailMaxPixel
        let img: NSImage? = await Task.detached(priority: .utility) {
            var stale = false
            guard let rootURL = try? URL(
                resolvingBookmarkData: urlBookmark,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &stale
            ) else { return nil }
            let didStart = rootURL.startAccessingSecurityScopedResource()
            defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }
            let fileURL = rootURL.appendingPathComponent(relativePath)
            return await loadThumbnail(url: fileURL, maxPixelSize: maxPixel)
        }.value
        await MainActor.run {
            self.thumbnail = img
        }
    }
}
```

> **实现细节实证**：
>
> - `loadThumbnail(url:maxPixelSize:)` 顶层 nonisolated 函数：grep `Glance/FolderBrowser/ImageGridView.swift` 确认存在 — 若签名不一致（如返回类型 / 参数名）调整
> - `IndexingProgressView(progress:onCancel:)` 签名：见 IndexingProgressView.swift L14-18 ✅
> - `indexStoreHolder.cancelCurrentScan` 是 closure 类型 `(() -> Void)?`：grep IndexStoreHolder.swift L30 ✅
> - `NSColor.windowBackgroundColor`：Cocoa 系统色 ✅

- [ ] **步骤 4.2: SmartFolderListView 加「重复清理」入口 row**

打开 `Glance/FolderBrowser/SmartFolderListView.swift`，在 L29 `}` 之后、`}` 结尾之前（VStack body 内部 ForEach 之后）追加独立 row：

整体 body 改为：

```swift
struct SmartFolderListView: View {

    @EnvironmentObject var smartFolderStore: SmartFolderStore
    /// M4 任务 1 — 重复清理入口选中态（ContentView 持 showDuplicateOverview 是唯一权威，
    /// codex P2-1 修：选中态不放 model 避免状态漂移）。
    let isDuplicateOverviewSelected: Bool
    /// M4 任务 1 — 入口点击 callback。ContentView 持 showDuplicateOverview 控制实际切换。
    let onSelectDuplicates: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(smartFolderStore.availableSmartFolders) { folder in
                SmartFolderRow(
                    folder: folder,
                    isSelected: smartFolderStore.selected?.id == folder.id
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await smartFolderStore.select(folder) }
                }
            }
            DuplicateCleanupRow(
                isSelected: isDuplicateOverviewSelected
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onSelectDuplicates()
            }
        }
    }
}

private struct DuplicateCleanupRow: View {
    let isSelected: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: DS.Icon.trash)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Text("重复清理")
                .font(.body)
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
    }
}
```

- [ ] **步骤 4.3: ContentView 集成 @StateObject + @State + mainContent swap + 四态互斥**

打开 `Glance/ContentView.swift`，定位 L113-127 加状态声明（在 `@StateObject smartFolderStore` 后追加）：

```swift
@StateObject private var smartFolderStore = SmartFolderStore.placeholder()
/// M4 任务 1 — 重复清理总览 model（mirror smartFolderStore placeholder/attach 模式）
@StateObject private var duplicateOverviewModel = DuplicateOverviewModel.placeholder()
/// M4 任务 1 — 是否切换到重复清理总览（四态互斥的第四态）
@State private var showDuplicateOverview: Bool = false
```

定位 L229 `.environmentObject(smartFolderStore)`（主区注入，DuplicateOverviewView 用 `@EnvironmentObject` 读 model），在其后追加：

```swift
.environmentObject(smartFolderStore)
.environmentObject(duplicateOverviewModel)
```

> 注：原 ContentView 有 2 处 `.environmentObject(smartFolderStore)` 调用（L179 侧边栏 + L229 主区）。**侧边栏那处不注入 duplicateOverviewModel**（codex P2-1 修：SmartFolderListView 改成接 `isDuplicateOverviewSelected: Bool` 参数不读 model 状态，无须注入）；**只在主区注入**让 `DuplicateOverviewView` 拿到。

定位 SmartFolderListView 调用处（在 侧边栏 VStack 内），传入选中态 + onSelectDuplicates callback：

```swift
SmartFolderListView(
    isDuplicateOverviewSelected: showDuplicateOverview,
    onSelectDuplicates: {
        showDuplicateOverview = true
    }
)
```

> 注：实际位置见原 ContentView 侧边栏段（搜索 `SmartFolderListView()` 定位）；本 plan 不预设具体行号避 stale，实施时按真实位置改。

定位 L313-341 `mainContent` 内 `ZStack(alignment: .top)`，加 `showDuplicateOverview` 分支（与 `currentEphemeral` 同层互斥）：

```swift
ZStack(alignment: .top) {
    if showDuplicateOverview {
        DuplicateOverviewView()
    } else if let req = currentEphemeral {
        EphemeralResultView(...)
    } else {
        // 原 baseGrid 分支保持
    }
    // previewOverlay 等其它分支保持
}
```

> 注：实际 ZStack 已有 `currentEphemeral` 与 baseGrid 互斥逻辑，M4 加 `showDuplicateOverview` 作为最优先分支（mirror search overlay 模式，被切到 dup 视图时临时结果也让位）。

定位 L287-299 互斥 `.onChange` 段，扩展到四态互斥：

```swift
.onChange(of: folderStore.selectedFolder) { _, newFolder in
    if newFolder != nil {
        if smartFolderStore.selected != nil {
            Task { await smartFolderStore.select(nil) }
        }
        showDuplicateOverview = false  // M4
    }
}
.onChange(of: smartFolderStore.selected) { _, newSF in
    if newSF != nil {
        if folderStore.selectedFolder != nil {
            folderStore.selectedFolder = nil
            folderStore.images = []
            folderStore.selectedImageIndex = nil
        }
        showDuplicateOverview = false  // M4
    }
}
.onChange(of: showDuplicateOverview) { _, newValue in
    if newValue {
        // 进入总览：清其它四态（V1 folder / 智能文件夹 / 临时结果 / 搜索 overlay）
        if smartFolderStore.selected != nil {
            Task { await smartFolderStore.select(nil) }
        }
        folderStore.selectedFolder = nil
        folderStore.images = []
        folderStore.selectedImageIndex = nil
        currentEphemeral = nil
        showSearchOverlay = false  // M4：搜索 overlay 与总览互斥（ContentView.swift:127 @State showSearchOverlay）
        // 主动 trigger load —— 这里是 load 的**唯一 owner**（codex P1-2 race 修：
        // 删 DuplicateOverviewView.onAppear 触发，避免与 model.scheduleReload
        // 并发 stale-write）。
        Task { await duplicateOverviewModel.load() }
    }
}
```

> **五态互斥补全**：进入临时结果 / 搜索两态时也要清 `showDuplicateOverview`。定位以下两个调用点各加一行：

**1. `handleFindSimilar(sourceUrl:)` 尾部（L689，设 `currentEphemeral = .similar(...)`）**：

```swift
self.currentEphemeral = .similar(sourceUrl: sourceUrl, results: urls, banner: banner)
showDuplicateOverview = false  // M4：进入临时结果（找相似）时清重复清理总览态
```

**2. `openSearch()` 内（L738，设 `showSearchOverlay = true` 前后）**：

```swift
showSearchOverlay = true
showDuplicateOverview = false  // M4：开搜索 overlay 时清重复清理总览态
currentEphemeral = .search(query: "", images: [], urls: [])
```

定位 `wireIfReady()`（L575-608），在 `smartFolderStore.attach(engine: engine)` 后 + bridge 创建后追加 duplicateOverviewModel attach：

```swift
smartFolderStore.attach(engine: engine)
let bridge = FolderStoreIndexBridge(indexStore: store)
// M4 任务 1 — 把 indexStore + bridge 装配给 dup overview model（mirror smartFolderStore.attach）
duplicateOverviewModel.attach(indexStore: store, bridge: bridge)
// 既有 smartFolder observer 注册
let storeRef = smartFolderStore
let smartFolderObserverToken = bridge.addIndexChangedObserver {
    Task { await storeRef.refreshSelected() }
}
_ = smartFolderObserverToken
// ... 其余 wireIfReady 原逻辑不变
```

> 注：duplicateOverviewModel.attach 必须**先于** smartFolder observer 注册前 / 后都可（多播容器无顺序依赖），但 design D35 写「ContentView wireIfReady 域同步迁移」 — 顺序按本 plan 写为 dup.attach 在 smartFolder observer 注册之前，方便阅读。

- [ ] **步骤 4.4: 编译验证 + 真机集成验**

```bash
make build
```

期望：`BUILD SUCCEEDED` + 0 errors + 0 warnings。

启 app：
1. 侧边栏 看到「重复清理」入口（trash icon + secondary 灰色）
2. 点入口 → 主区切到总览
3. 若 DB 有重复组 → 看到顶部统计「X 组重复 · 可省 Y」+ 每组保留张 badge「保留」（绿）+ 副本弱化
4. 若 DB 无重复 → 看到空态「没找到重复图」
5. 点 V1 folder / 智能文件夹 / 触发搜索 → showDuplicateOverview 自动清零，主区切走
6. 后台索引活动（添加根目录触发 scan）→ 等 500ms debounce → 总览自动刷新

- [ ] **步骤 4.5: commit**

```bash
git add Glance/Dedup/DuplicateOverviewView.swift \
        Glance/FolderBrowser/SmartFolderListView.swift \
        Glance/ContentView.swift
git commit -m "feat(M4): DuplicateOverviewView 只读 UI + 侧边栏「重复清理」入口 + ContentView 五态互斥

- DuplicateOverviewView 顶部统计条 + ScrollView+LazyVStack 组列表 + 空态 + 错误态 + 跟随全局外观
  （索引 chip 由 ContentView.mainContent 全局 overlay IndexingProgressView 持有，本 view 不重复渲染）
- DuplicateGroupRow 渲染单组：保留张 + 副本展示位 + 组可省空间
- DuplicateMemberCell loadThumb mirror DedupPass.computeSha scope 模式（resolve root +
  startAccessing + 拼 child URL）+ 保留张「保留」绿色 badge + 副本 opacity 0.7 弱化
- SmartFolderListView ForEach 下方加独立 DuplicateCleanupRow（不混进 availableSmartFolders）
- ContentView @StateObject duplicateOverviewModel.placeholder() + @State showDuplicateOverview
  + .environmentObject 注入 + SmartFolderListView onSelectDuplicates callback
- mainContent ZStack showDuplicateOverview 分支 swap DuplicateOverviewView，与临时结果/baseGrid
  互斥
- 四态互斥 .onChange 扩展（V1 folder / 智能文件夹 / 临时结果 / 重复清理总览）
- wireIfReady 调 duplicateOverviewModel.attach(indexStore:bridge:)

M4 任务 1 完整端到端：点入口 → 看到真实重复组 + 真实可省空间数字 + 保留张透明显示。"
```

---

## 步骤 5：/go 收尾 — verify.sh 三段 + 文档同步 + PENDING + commit + push

> **本步用户感知**：无新功能，是任务 1 ship 前的质量与文档闭环。

**Files:**
- Modify: `specs/Roadmap.md`（M4 段进度 + D33-D35 决策段补全）
- Modify: `CLAUDE.md`（文件结构 `Glance/Dedup/` 目录新增）
- Append: `specs/v2/2026-06-16-m4-task1-implementation-plan.md`（末尾「步骤 X 完成详细」表）
- Append: `specs/PENDING-USER-ACTIONS.md`（M4 任务 1 真机验项）

- [ ] **步骤 5.1: 跑 verify.sh 三段**

```bash
./scripts/verify.sh
```

期望：
- Stage 1 静态规则全过（含 Stage 1d 术语字典禁用词扫描）
- Stage 2 编译 `BUILD SUCCEEDED` + 0 errors + 0 warnings
- Stage 3 单测 skip（项目无 XCTest target）

红 → 修 → 重跑，最多 5 轮（CLAUDE.md /go Step 1 硬约束）。

- [ ] **步骤 5.2: 更新 specs/Roadmap.md**

「关键架构决策」段补 D33 / D34 / D35（如 design 落 D 时未自动同步则补，design 4.5 节内容引用即可）。

「M4 进度」段标注：
- 任务 1（只读总览）✅ 已完成 — commit hash 待 push 后回填
- 任务 2（删除闭环）⏸ 等卷类型验证矩阵（design 8.2 节最小解锁条件 4 条）

- [ ] **步骤 5.3: 更新 CLAUDE.md 文件结构**

在「## 项目文件结构」段 `Glance/Search/` 段后插：

```
    ├── Dedup/                       ← V2 M4 重复清理（去重省空间）
    │   ├── DuplicateGroup.swift              ← DuplicateGroup / DuplicateGroupMember 值类型
    │   ├── DuplicateOverviewState.swift      ← 状态机 enum (idle/loading[stale]/loaded/error)
    │   ├── DuplicateOverviewModel.swift      ← @MainActor 业务 model + bridge multicast observer 订阅 + 500ms debounce reload
    │   └── DuplicateOverviewView.swift       ← 只读总览 UI（统计条 + 组列表 + 保留张 badge；索引 chip 由 ContentView 全局持有）
```

ContentView 段补一句：「**M4 任务 1**：加 `@StateObject duplicateOverviewModel` + `@State showDuplicateOverview` 四态互斥 + `SmartFolderListView` onSelectDuplicates callback + `mainContent` ZStack `showDuplicateOverview` 分支 swap」。

FolderStoreIndexBridge 段更新：「**M4 任务 1 D35 prerequisite**：`onIndexChanged` 单播变量升级为 `indexChangedObservers` 多播 UUID dict，新增 `addIndexChangedObserver(_:) -> UUID` / `removeIndexChangedObserver(_:)` API」。

SmartFolderListView 段补一句：「**M4 任务 1**：ForEach 下方加独立 `DuplicateCleanupRow` 入口（不混进 availableSmartFolders）」。

DesignSystem 段补一句：「**M4 任务 1**：加 `enum Dedup`（reloadDebounceMillis / 缩略图尺寸 / 保留张 badge 配色 / 副本弱化 opacity）」。

- [ ] **步骤 5.4: 追加本 plan 末尾「步骤 X 完成详细」表**

mirror M2 任务 J 实施记录段 pattern，在本 plan 末尾追加段：

```markdown
## 步骤完成详细（任务 1 实施记录）

### 步骤 1 — bridge 多播架构升级（commit <hash>）
- 改动：FolderStoreIndexBridge.swift onIndexChanged 单播 → indexChangedObservers 多播 dict + 4 fire 点遍历 + ContentView.swift smartFolder caller 迁移
- 验证：编译 0 error/warning + 真机 4 路 fire 行为等价

### 步骤 2 — fetchDuplicateGroups + DuplicateGroup record + DS.Dedup（commit <hash>）
- 改动：新建 Glance/Dedup/DuplicateGroup.swift + IndexedImage.swift extension 2 个 fetch 方法 + DesignSystem.swift enum Dedup
- 验证：编译 0 error/warning

### 步骤 3 — DuplicateOverviewModel 状态机 + bridge observer 订阅（commit <hash>）
- 改动：新建 DuplicateOverviewState.swift + DuplicateOverviewModel.swift（placeholder/attach + state 机 + scheduleReload debounce + load + computed accessors）
- 验证：编译 0 error/warning

### 步骤 4 — DuplicateOverviewView + 侧边栏入口 + ContentView 四态互斥（commit <hash>）
- 改动：新建 DuplicateOverviewView.swift + SmartFolderListView.swift 加 DuplicateCleanupRow + ContentView.swift 四态集成
- 验证：编译 0 error/warning + 真机点入口看到真实重复组 + 空态 + 互斥行为正常

### 步骤 5 — /go 收尾（commit <hash>）
- 改动：specs/Roadmap.md / CLAUDE.md / 本 plan 末尾 / specs/PENDING-USER-ACTIONS.md
- 验证：verify.sh 全段过 + pre-push hook codex 通过
```

- [ ] **步骤 5.5: 追加 specs/PENDING-USER-ACTIONS.md M4 任务 1 真机验项**

```markdown
### M4 任务 1 真机验项（2026-06-16）

- [ ] 侧边栏「重复清理」入口 — trash icon 显示正常 + secondary 灰色态 + accent 选中态切换
- [ ] 点入口 → 主区切总览 + 其它三态自动清零（V1 folder / 智能文件夹 / 临时结果 都让位）
- [ ] 顶部统计「X 组重复 · 可省 Y」数字与 DB 内 dedup_canonical=0 的 file_size 之和一致（抽样人工核对 1-2 组）
- [ ] 每组保留张「保留」绿色 badge 显示正常 + 副本无 badge + 副本 opacity 0.7 视觉弱化
- [ ] 每组缩略图 hover 显完整路径 tooltip（cell .help(member.fullPath)）
- [ ] 空态：清空 DB 后总览显「没找到重复图」+ checkmark.seal icon
- [ ] 后台索引活动（添加根目录触发首次扫描）→ 看顶部索引 chip 实时刷新 + 扫完总览自动 reload（500ms debounce）
- [ ] 切走总览（点 V1 folder）→ 切回 → 总览数据应正确（observer 在后台已 reload）
- [ ] dedup 分组准确性核对（军哥真机）：保留张选对（earliest birth_time 的）+ 组聚得对（同 sha256 必同组，跨格式不进同组）+ 可省空间数字与 macOS Finder 真实文件大小一致
- [ ] 跟随全局外观：浅色 / 深色模式切换无残留
```

- [ ] **步骤 5.6: commit + push（触发 pre-push hook codex review）**

```bash
git add specs/Roadmap.md CLAUDE.md specs/v2/2026-06-16-m4-task1-implementation-plan.md specs/PENDING-USER-ACTIONS.md
git commit -m "docs(M4): 任务 1 收尾 — Roadmap / CLAUDE.md / plan / PENDING 同步

- specs/Roadmap.md：M4 段任务 1 标 ✅ + D33/D34/D35 决策段补全
- CLAUDE.md：Glance/Dedup/ 目录登记 + ContentView/FolderStoreIndexBridge/SmartFolderListView/
  DesignSystem 模块说明同步 M4 任务 1 改动
- 本 plan 末尾追加「步骤完成详细」表（mirror M2 任务 J pattern）
- specs/PENDING-USER-ACTIONS.md 追加 M4 任务 1 真机验 10 项

任务 1 ship 后军哥真机验证 dedup 分组准确性 / 保留张选对没 / 组聚得对没；
建立信任后再进入任务 2 卷类型验证矩阵 → 删除闭环。"

git push origin v2/dev
```

> pre-push hook 触发 codex 自动 review 待推 `.swift + .md` diff。[P1] 阻塞 push，[P2] 仅告警。报 [P1] → 修 → 重跑 verify.sh → 重 push。

---

## 完成判定（M4 任务 1 ship 条件）

- ✅ 编译 0 error + 0 warning
- ✅ verify.sh 三段全过
- ✅ specs/Roadmap.md / CLAUDE.md / 本 plan / PENDING 全同步
- ✅ pre-push codex review [P1] 无（[P2] 可带 follow-up）
- ✅ 真机 PENDING 10 项军哥眼审（无 GUI Mac mini 无法跑，留军哥真机会话验）
- ✅ 任务 1 任务级独立交付三标准全兑现：端到端可跑 + 用户可感知（X 组 · Y GB 量化）+ 独立可 ship

任务 1 ship 后：进入任务 2 解锁条件 = 卷类型验证矩阵跑通 4 条最小门槛（design 8.2 节）。

---

## Self-Review

写完本 plan 后 fresh-eye 检查（writing-plans skill 强制 step）：

### 1. Spec coverage

| design 8.1 任务 1 范围条目 | 对应步骤 |
|---|---|
| 聚合查询 (`fetchDuplicateGroups`) | 步骤 2 |
| 侧边栏入口 (`SmartFolderListView` 加 `DuplicateCleanupRow`) | 步骤 4 |
| 主区只读总览 (`DuplicateOverviewView`) | 步骤 4 |
| bridge 多播架构升级（D35 prerequisite） | 步骤 1 |
| `onIndexChanged` hook 订阅（`bridge.addIndexChangedObserver`） | 步骤 3（model attach 内注册） |
| `DuplicateGroup` record | 步骤 2 |
| `DuplicateOverviewModel`（仅 load，task 1 边界） | 步骤 3 |
| `ContentView` 挂载 + 互斥 | 步骤 4 |
| 文档同步 + PENDING | 步骤 5 |

✅ design 8.1 任务 1 范围全覆盖。

### 2. Placeholder scan

grep TODO / TBD / "implement later" / "add appropriate" / "similar to" 关键词：

- ✅ 本 plan 无 TODO / TBD / "implement later"
- ⚠️ 步骤 2.4 末尾「若 DS.Spacing.lg 不存在则用 `xl` / `md` 现有最接近的」 — 是 reality fallback 语义而非 placeholder，实施时按真实存在的常量名调整即可

### 3. 类型一致性

| 符号 | 步骤定义处 | 步骤引用处 |
|---|---|---|
| `DuplicateGroup` | 步骤 2.1 | 步骤 3.2 model state + 步骤 4.1 view |
| `DuplicateGroupMember` | 步骤 2.1 | 步骤 3.2 model + 步骤 4.1 view cell |
| `DuplicateGroupRow` | 步骤 2.1 | 步骤 2.2 fetchDuplicateGroups 返回 + 步骤 3.2 fetchGroups 用 |
| `DuplicateGroupMemberRow` | 步骤 2.1 | 步骤 2.2 fetchDuplicateGroupMembers 返回 + 步骤 3.2 makeMember 转换 |
| `DuplicateOverviewState` | 步骤 3.1 | 步骤 3.2 model @Published state |
| `DuplicateOverviewModel` | 步骤 3.2 | 步骤 4.3 ContentView @StateObject + 步骤 4.2 SmartFolderListView EnvironmentObject |
| `fetchDuplicateGroups` / `fetchDuplicateGroupMembers` | 步骤 2.2 | 步骤 3.2 fetchGroups |
| `addIndexChangedObserver` / `removeIndexChangedObserver` | 步骤 1.1 | 步骤 1.3 ContentView smartFolder + 步骤 3.2 model attach（observer token 寿命跟 model 一致，不持 detach） |
| `DS.Dedup.reloadDebounceMillis` | 步骤 2.4 | 步骤 3.2 model scheduleReload |
| `DS.Dedup.groupCellThumbnailSize` / `groupCellThumbnailMaxPixel` / `canonicalBadgeColor` / `duplicateThumbnailOpacity` | 步骤 2.4 | 步骤 4.1 view cell |

✅ 类型 / 方法名 / 属性名前后一致。

### 4. 术语字典禁用词扫描

本 plan grep 自检（人工 + verify.sh Stage 1d 自动）：

见 `scripts/verify.sh` Stage 1d 实际禁用词 regex（CONTEXT.md「术语字典表」执行端唯一权威）。预期本 plan 通过（写作过程已避开弃用别名）。

期望：空（除「步骤」「任务」「重复清理」「保留张」「快速看图器」「侧边栏」等规范用词）。

写作过程已避开弃用别名，commit message + plan 正文全用三层方法论命名。

---

## Execution Handoff

Plan 已保存到 `specs/v2/2026-06-16-m4-task1-implementation-plan.md`。

按军哥规则：**plan 定稿后先过 codex review，再交军哥拍板**。本 plan 暂不执行实施，下一步走 codex:rescue 独立 review 找架构 / 步骤拆分 / API reality 盲点（吸取前 3 轮 design review reality miss 教训）。

军哥拍板后再选执行路径（superpowers:subagent-driven-development 推荐 / superpowers:executing-plans）。

---

## 实施记录（commit 落地后追加，mirror Slice J 完成详细 pattern）

### 步骤 1 — bridge 多播架构升级（D35 prerequisite），commit `5b77249`（2026-06-16）

**改动文件**：`Glance/IndexStore/FolderStoreIndexBridge.swift` + `Glance/ContentView.swift` + `CLAUDE.md` + `specs/Roadmap.md` + `specs/PENDING-USER-ACTIONS.md`

**实施摘要**：
- bridge `var onIndexChanged: (() -> Void)?` 单播变量删除 → `indexChangedObservers: [UUID: () -> Void]` 多播 dict + `addIndexChangedObserver(_:) -> UUID` / `removeIndexChangedObserver(_:)` / 私有 `fireIndexChanged()`（snapshot before fan-out 防御）三 API
- 4 个 fire 点（孤儿清扫 :87 → :111 / dedup full pass :192 → :216 / dedup group :202 → :226 / FSEvents handleEvents :245 → :269）统一改 `fireIndexChanged()`
- ContentView.swift L584 唯一 caller 迁移到 `addIndexChangedObserver`，token 寿命依赖说明落注释

**Self-fix 轮次**：0（首次 build 即 SUCCEEDED）

**codex pre-push 折入**：第一轮 P1 (Roadmap 未同步) → 补 M4 决策段 D33/D34/D35（commit `0c8f561`）；第二轮 P2 (fan-out snapshot) → 顺手折入（commit `5b77249`）；第三轮 docs-only skip

**真机验项**（PENDING 已加）：4 路 fire 点等价回归（加 root / FSEvents 增删改 / 删 root / 编辑图 → 智能文件夹 grid 自动刷新）

### 步骤 2 — fetchDuplicateGroups 聚合查询 + DuplicateGroup record + DS.Dedup 常量，commit `2abe08d`（2026-06-16）

**改动文件**：`Glance/Dedup/DuplicateGroup.swift`（新增）+ `Glance/IndexStore/IndexedImage.swift` + `Glance/DesignSystem.swift` + `CLAUDE.md` + `specs/PENDING-USER-ACTIONS.md`

**实施摘要**：
- 新建 `Glance/Dedup/` 目录 + `DuplicateGroup.swift`：4 个值类型 record（DuplicateGroup / DuplicateGroupMember / DuplicateGroupRow / DuplicateGroupMemberRow），任务 1 边界严格遵守不含 `folderId`
- IndexedImage.swift extension 加 2 个查询方法（mirror `fetchCandidateGroups:310` + `fetchImagesInGroup:327` 裸 sqlite3 C API + `try sync { db in ... }` + `try checkBind` 模式）：
  - `fetchDuplicateGroups()`: HAVING SUM(dedup_canonical=0)>0 + ORDER BY reclaimable_bytes DESC
  - `fetchDuplicateGroupMembers(sha256:)`: dedup_canonical DESC 保留张排第一 + JOIN folders 拼 full_path
- DesignSystem.swift 加 `enum Dedup`：8 个常量（reloadDebounceMillis=500 / groupRowSpacing=DS.Spacing.lg / groupCellThumbnailSize=96 / groupCellThumbnailMaxPixel: Int = 192 对齐 loadThumbnail / canonicalBadgeColor: SwiftUI.Color = .green / statsBarFont / emptyStateFont / duplicateThumbnailOpacity=0.7）

**Self-fix 轮次**：1（首次 build error: `DS.Color` no member `green` — enum DS 内嵌套 `enum Color` 截胡 `.green` 解析，加 `SwiftUI.Color` 全限定修复）

**真机验项**：编译通过即代表本步落地；聚合查询正确性在步骤 3/4 UI 跑通后验

### 步骤 3 — DuplicateOverviewModel 状态机 + bridge multicast observer 订阅，commit `<pending>`（2026-06-16）

**改动文件**：`Glance/Dedup/DuplicateOverviewState.swift`（新增）+ `Glance/Dedup/DuplicateOverviewModel.swift`（新增）+ `CLAUDE.md`

**实施摘要**：
- DuplicateOverviewState enum（idle / loading[staleGroups] / loaded[groups] / error[message]）mirror SmartFolderState
- DuplicateOverviewModel `@MainActor ObservableObject` 单一 `@Published private(set) var state` + placeholder/attach 装配模式
- attach(indexStore:bridge:) 注册 bridge.addIndexChangedObserver token + observer closure 走 `Task { @MainActor in scheduleReload() }`（bridge `@MainActor` 已验证，保守 hop 防未来 bridge 去 @MainActor 化）
- scheduleReload() DispatchWorkItem cancel + 重置实现 trailing debounce 500ms（DS.Dedup.reloadDebounceMillis）→ load()
- load() loadGeneration counter 自增 → Task.detached fetchGroups → guard generation 一致才回写（两次并发 load 时旧结果丢弃，比 `if case .loading = state` 更精确）
- fetchGroups / makeMember 显式 `nonisolated static`（@MainActor class 内 static 默认继承隔离会让 detached Task 调失败）
- computed accessors（groups / isLoading / errorMessage / groupCount / totalReclaimableBytes）给 view 用，view 不直接 pattern match state

**Self-fix 轮次**：1（首次 build error: "main actor-isolated static method 'fetchGroups(store:)' cannot be called from outside of the actor" → 给 fetchGroups + makeMember 加 `nonisolated` 修复）

**真机验项**：本 commit 后 model 完整可调但无 UI 集成 — 编译通过即代表本步落地，model 行为验证延后到步骤 4 UI 集成后 4 路 fire 点（加 root / FSEvents / 删 root / 编辑图）→ debounce 500ms → grid 自动 reload 真机验
