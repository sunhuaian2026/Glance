# Glance V2 M4 任务 2 实施 Plan — 重复清理删除闭环

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「重复清理只读总览」(任务 1 已 ship) 升级为完整删除闭环 — 用户勾选副本组 → 一键移废纸篓 → DB 自动同步 → ContentView 级 banner 30 秒内可撤销 → 真省硬盘空间，回归 Glance 初心。

**Architecture:**
- **风险前置门控**: 第 1 步先跑「卷类型 spike + 真机验证矩阵」(design 8.2)。CC 主 agent 自闭环跑跨 root 沙盒探测；真机不可绕开项 (USB / iCloud / 失败路径 fallback) 留 PENDING 给军哥本地。最小解锁条件未满足 → 暂停后续步骤,回 design 修 D30「一键」体验或加细粒度授权方案
- **3 个新 API 同步落地** (design 4.5): `IndexStore.fetchSnapshotForRestore` 删前 SELECT 15 列保真 + `IndexStore.restoreImageFromSnapshot` 撤销首选回补 (同步返回 row id) + `FolderStoreIndexBridge.requestRescan` 撤销降级单文件 rescan (async throws 返回时已恢复或明确失败,禁 fire-and-forget)
- **TrashService 独立 nonisolated 服务**: 全项目首个碰真实文件代码,复刻 `DedupPass.computeSha` (DedupPass.swift:107-118) 的 sandbox scope 模式 — `resolveBookmark + startAccessingSecurityScopedResource + appendingPathComponent` + `FileManager.trashItem(at:resultingItemURL:)` + member 级失败累积不中断其余
- **DuplicateOverviewModel 增量** mirror `SmartFolderStore` 单 `@Published state` 模式 — 加勾选集合 `Set<String>` (按 sha256) + 删除中态 + CancellationToken + lastTrashOutcome publish; trashSelected 主路径 + undo 走 D34 显式回补 contract
- **TrashUndoBanner = ContentView 级 overlay** (D33): 跨 V1 文件夹 / 智能文件夹 / 临时结果 / 搜索 / 重复清理总览 五态持久可见可点; 快速看图器在场不可见但状态保留,关闭后回归; 默认 30s auto-dismiss (或纯手动 dismiss,本 plan 步骤 5 拍板)

**Tech Stack:** SwiftUI + Combine + SQLite3 C API + FileManager.trashItem + Security-Scoped Bookmark + DispatchWorkItem (debounce)

**术语字典强制** (CONTEXT.md「术语字典表」D 段): 本 plan 全文档命名遵守三层方法论「阶段 V2 → 里程碑 M4 → 任务 2」,弃用别名见 CONTEXT.md A/B/D 段 (代码符号保留英文 PascalCase/camelCase 不受字典约束)。

---

## M4 任务 2 — 任务级独立交付三标准论证

> 本任务整体作为一个任务级独立交付单元 (CONTEXT.md D 段定义),三标准在 design 8.2 已论证。本 plan 内部按 6 个步骤实施: **每个步骤是一个 commit 单元 (TDD bite-size 频繁提交节奏),不单独满足三标准; 任务 2 整体完成后才满足「端到端可跑 + 用户可感知 + 独立可 ship」三标准。步骤 ≠ 任务级独立交付单元。**

| 标准 | 论证 |
|---|---|
| **端到端可跑** | 勾组 → 点「移入废纸篓」→ 文件真进系统废纸篓 + DB row 同步删除 + 总览少一组 + 顶部跨视图持久 banner 可撤销 (D33) + 撤销 → 文件回原路径 + DB row 重建 + 总览回原态 (D34) |
| **用户可感知** | 真省硬盘空间 — 初心闭环达成,Glance 从「看图工具」回归「整理工具」定位 |
| **独立可 ship** | 叠在任务 1 之上,任务 1 已 ship 的只读总览不被破坏; 删除是增量能力,可单独 ship 给军哥真机 |

**边界** (本任务做什么):
- ✅ 整组勾选 + 一键移废纸篓 (单文件级勾选不做; design D28 — 完全相同删哪张都一样)
- ✅ 删除中态 (按钮禁用 + 进度文案 + 取消按钮) + 取消传播
- ✅ ContentView 级 banner 撤销 (D33 跨视图持久, 快速看图器期间不可见但状态保留)
- ✅ 撤销显式回补 DB row (D34 contract: restoreImageFromSnapshot 首选 + requestRescan 降级)
- ✅ 卷类型差异错误边界 (member 级 best-effort + 失败累积 + banner 汇总)

**边界** (本任务不做的事, 推迟 / 砍出):
- ❌ 视觉相似去重 (Vision feature print) — M4 scope freeze; 第一刀只做字节级完全相同
- ❌ 逐张改保留 (D28: 完全相同删哪张都一样, 不给单文件 checkbox)
- ❌ 永久删除 (走系统废纸篓; 用户清空废纸篓由系统 Finder 决定)
- ❌ Quit interception (design 6 节: 接受 quit = 取消 policy, 不动 SwiftUI quit 流程)
- ❌ Banner 持久化磁盘 (in-memory only; spike finding 证 in-memory 配对足够, app quit 后丢失,但用户仍可 Finder 手动复原)

---

## File Structure (M4 任务 2 范围内)

### 新增文件

| 路径 | 职责 |
|---|---|
| `Glance/Dedup/IndexedImageSnapshot.swift` | `IndexedImageSnapshot` 值类型 — 删前保留的 in-memory snapshot,15 个字段对齐 `IndexStoreSchema.swift:55-77` images 表所有非 PK 列 (PK id 由 DB 重新分配不入 snapshot)。撤销回补保真用,**不持久化磁盘**。design 4.5.1 spec |
| `Glance/Dedup/TrashService.swift` | `nonisolated enum TrashService` — `trashItems(_:cancellation:progress:)` 主路径 + `restoreItems(_:cancellation:)` 撤销路径 + `TrashCancellationToken` actor。复刻 `DedupPass.computeSha` (DedupPass.swift:107-118) 的 sandbox scope 模式: `resolveBookmark + startAccessing + appendingPathComponent` + `FileManager.trashItem` / `FileManager.moveItem`。**全项目首个碰真实文件代码** — 仅本服务调 FileManager 写操作 |
| `Glance/Dedup/TrashOutcome.swift` | `TrashOutcome` / `RestoreOutcome` 值类型 — `successes: [TrashSuccess]` (originalFullPath / trashURL / snapshot) + `failures: [TrashFailure]` (member 描述 / 错误) + `cancelled: Bool` |
| `Glance/Dedup/TrashUndoBanner.swift` | ContentView 级 overlay banner view (D33)。「已移 N 张到废纸篓 [撤销] [×]」结构 + 副文案「+M 张失败 / 已取消」+ 30s auto-dismiss timer 或纯手动 (步骤 5 拍板)。快速看图器在场不可见但状态保留 |

### 修改文件

| 路径 | 改动 |
|---|---|
| `Glance/IndexStore/IndexedImage.swift` | **步骤 2.0**: 改 `DuplicateGroupMemberRow` + `DuplicateGroupMember` struct 加 `folderId: Int64` 字段 + `fetchDuplicateGroupMembers` SQL 加 `i.folder_id` 列 (codex P1-03 + P2-02 合一修 — 任务 1 边界扩展加字段是加法不破坏既有行为, 同时消除 collectTrashInputs N+1 反查 SQL); **步骤 2.2**: 加 `func fetchSnapshotForRestore(folderId:relativePath:) throws -> IndexedImageSnapshot?` (SELECT 15 列全 fetch); **步骤 2.3**: 加 `func restoreImageFromSnapshot(_:) throws -> Int64` (INSERT 全列回补; UNIQUE 冲突由 SQLite 抛错让调用方降级) |
| `Glance/IndexStore/FolderStoreIndexBridge.swift` | **步骤 2.4**: 加 `func requestRescan(folderId:relativePath:) async throws -> Int64` (resolve root bookmark + 拼 child URL + `ImageMetadataReader.read` + `insertImageIfAbsent`) + 加 `func triggerIndexChanged()` 公开广播 API (codex P1-01: 把私有 `fireIndexChanged()` 升级为公开广播入口, 让 TrashService 删除路径 / undo 撤销路径主动 fire 让智能文件夹 / 搜索 / 其它已注册 observer 视图自动刷新, 修跨视图刷新闭环缺口) |
| `Glance/Dedup/DuplicateOverviewModel.swift` | **步骤 4**: 加 `@Published private(set) var selectedSha256s: Set<String> = []` 勾选集合 + `@Published private(set) var trashState: TrashOperationState = .idle` 删除中态 (idle / trashing(progress, cancellationToken) / completed(outcome)) + `@Published private(set) var lastTrashOutcome: TrashOutcomeEvent?` 桥给 ContentView banner (codex P2-01 修: 用轻量 event 含 outcomeId UUID + payload, .onChange 比较 id 不深比 BLOB) + `toggleSelection(sha256:)` / `clearSelection()` / `trashSelected()` 主入口 / `undo(outcome:)` D34 contract (codex P1-02 修: 双失败时不静默清, 进 `lastTrashOutcome` 用 `RestoreOutcome.failures` 渲染失败副文案让用户感知) / `cancelTrash()`。**复用任务 1 已落 load() / scheduleReload() / attach 不动** |
| `Glance/Dedup/DuplicateOverviewView.swift` | **步骤 5.1**: 组渲染加整组 checkbox (sha256 level; 单文件 checkbox 不加 D28); **步骤 5.2**: 顶部统计条右侧加「移入废纸篓 (N 张)」按钮 (禁用条件: 0 勾选 / trashState=trashing); **步骤 5.3**: trashState=trashing 时按钮换进度条 + 「取消」按钮 |
| `Glance/ContentView.swift` | **步骤 5.4**: 加 `@State trashUndoBanner: TrashOutcomeEvent? = nil` (全局 banner event, 含 UUID id; 不绑 showDuplicateOverview 生命周期 D33); **NavigationSplitView 外层** .overlay (codex P2-04 拍板,mirror 任务 1 IndexingProgressView 全局 overlay 模式) 放 `TrashUndoBanner` (五态可见; 快速看图器独立 NSWindow 物理不可见 D33); `.onChange(of: duplicateOverviewModel.lastTrashOutcome?.id)` (codex P2-01 UUID 比对避深比 BLOB) set 给 `trashUndoBanner`; banner onUndo 回调走 `Task { await duplicateOverviewModel.undo(outcome:) }` (model 内部 publish undoResult 后 .onChange 再触发让 banner 切「撤销完成」状态); banner onDismiss 回调清 `trashUndoBanner = nil` |
| `Glance/DesignSystem.swift` | **步骤 5.4**: `DS.Dedup` 加 `bannerAutoDismissSeconds: TimeInterval` (30) / `bannerMaxWidth: CGFloat` / `bannerCornerRadius: CGFloat` / `bannerBackgroundOpacity: Double` / `bannerTopPadding: CGFloat` / `trashButtonCornerRadius: CGFloat` / `trashButtonHeight: CGFloat` / `progressBarTint: SwiftUI.Color` / `checkboxRowHeight: CGFloat` / `selectionAccentColor: SwiftUI.Color` |
| `specs/Roadmap.md` | **步骤 1.3 / 步骤 6.2**: M4 任务 2 状态更新 (规划 → 实施 → 完成); 卷类型矩阵 spike 结论写进风险 2 段 |
| `specs/v2/2026-06-10-m4-design.md` | **步骤 1.3**: 风险 2 段更新 — CC 自闭环 spike 跑完后跨 root 部分填实证结论 |
| `specs/PENDING-USER-ACTIONS.md` | **步骤 1.4 / 步骤 5.6 / 步骤 6.3**: 卷类型矩阵真机不可绕开项 + 任务 2 完整端到端 CC 自验 + 军哥本地补验 |
| `CLAUDE.md` | **步骤 6.2**: 文件结构同步新增 Dedup/IndexedImageSnapshot.swift / TrashService.swift / TrashOutcome.swift / TrashUndoBanner.swift |

### 不动文件 (依赖既有 API,reality check 已 grep + Read 验证)

| 路径 | 复用 |
|---|---|
| `Glance/IndexStore/DedupPass.swift` | `DedupPass.reEvaluateGroup(store:fileSize:format:)` (DedupPass.swift:46) — 删 row 后按 (file_size, format) 重决议; `DedupPass.runFullPass(store:)` (DedupPass.swift:29) — 暂不调,reEvaluateGroup 足够 |
| `Glance/IndexStore/IndexStore.swift` | `sync<T>(_ block:)` (IndexStore.swift:36) — 所有新 query 走同 serial queue |
| `Glance/IndexStore/IndexStoreSchema.swift` | 15 个非 PK 列 schema 已锁 (IndexStoreSchema.swift:55-77); 不加列,M4 scope freeze |
| `Glance/IndexStore/ImageMetadataReader.swift` | `ImageMetadataReader.read(at: URL) -> ImageMetadata?` (ImageMetadataReader.swift:18) — requestRescan 降级路径用 |
| `Glance/IndexStore/ManagedFolder.swift` | `IndexStore.fetchRoots()` (ManagedFolder.swift:244) → `[ManagedFolder { id, rootBookmark, ... }]` — requestRescan resolve root bookmark 用 |
| `Glance/IndexStore/IndexedImage.swift` | 既有 `deleteImage(folderId:relativePath:)` (IndexedImage.swift:109) / `fetchImageGroupKey(folderId:relativePath:)` (IndexedImage.swift:361) / `promoteOrphanDuplicates()` (IndexedImage.swift:391) / `insertImageIfAbsent(_:)` (IndexedImage.swift:55) — 全部复用,不改 |
| `Glance/IndexStore/IndexDatabase.swift` | `IndexDatabase.prepare(_:)` (IndexDatabase.swift:50) / `lastErrorMessage()` (IndexDatabase.swift:60) — 新 query 复用 |

---

## 步骤 1 — 卷类型 spike + 矩阵走查 (前置门控)

> **为什么是第 1 步**: design 8.2 + codex review 第二轮 P2 明示 — task 2 实施开启前必须先满足卷类型最小解锁条件 (a APFS + b USB/TB 必过 + c iCloud 行为明确 + d ≥1 失败路径 fallback 验通)。**矩阵不通过 → 暂停本 plan 回 design 修订** (如沙盒不放行跨 root 写则 D30 「一键」体验受影响)。本步内部分 CC 自闭环可跑 (跨 root spike 写 swift 脚本试探) + 真机不可绕开 (USB / iCloud 必须军哥本地)。
>
> **本步定位** (codex P2-03 修): 本步是**非提交 gate** — spike 脚本是临时一次性工具 (跑完 `git rm` 弃,不进库不进 commit 单元),稳定产物只有结论文档 (design 风险 2 段 / Roadmap M4 状态 / PENDING 矩阵)。本步唯一 commit 是结论 docs commit (步骤 1.4)。spike 脚本临时接线到 AppDelegate 调试 + 跑完撤回。
>
> **本步用户感知**: 无直接 UI 变化,但为后续步骤 2-5 解锁前提。spike 脚本 + 矩阵走查结论写进 design + Roadmap 风险段,军哥可见结论后判是否进步骤 2。

**Files:**
- Create: `Glance/_SpikeTask2CrossRoot.swift` (一次性 spike,跑完 git rm)
- Modify: `specs/v2/2026-06-10-m4-design.md` (风险 2 段填实证结论)
- Modify: `specs/Roadmap.md` (M4 任务 2 状态更新「卷类型矩阵走查中」)
- Modify: `specs/PENDING-USER-ACTIONS.md` (真机不可绕开项添加)

### 步骤 1.1: 写 CC 自闭环跨 root 沙盒探测 spike 脚本

- [ ] **步骤 1.1.a: 新建 `Glance/_SpikeTask2CrossRoot.swift`**

```swift
//
//  _SpikeTask2CrossRoot.swift
//  Glance
//
//  M4 任务 2 卷类型 spike — 跨 root 家目录沙盒 trashItem 探测.
//  design 风险 2 PENDING 部分: BookmarkManager 持的真实用户文件夹下的图 trash
//  是否在同 root scope 下放行写操作 + 跨 root 多目录连环 trash scope 边界.
//
//  跑法:
//  1. 启动 Glance, 确保已加 ≥1 个真实 root (军哥手动加 ~/Documents/screenshots 或类似)
//  2. 调试器 LLDB 调 SpikeTask2CrossRoot.run() 触发 (或临时在 GlanceApp 入口短期接线; 跑完移除)
//  3. 看 console 输出 trash + restore 是否成功, 错误码是什么
//  4. 跑完 git rm 此文件 (一次性 spike, 不留库)
//

import Foundation
import AppKit

nonisolated enum SpikeTask2CrossRoot {

    /// 跨 root 沙盒 trashItem 探测.
    /// caller: AppDelegate.applicationDidFinishLaunching 内一次性调 (注释掉后续删),
    /// 或 LLDB `e SpikeTask2CrossRoot.run(indexStore: <store>)`.
    static func run(indexStore: IndexStore) async {
        print("[Spike-T2] start cross-root sandbox probe")
        do {
            let roots = try indexStore.fetchRoots()
            guard !roots.isEmpty else {
                print("[Spike-T2] no managed roots — add ≥1 root via UI first")
                return
            }
            for root in roots {
                await probeRoot(root)
            }
        } catch {
            print("[Spike-T2] fetchRoots FAILED: \(error)")
        }
        print("[Spike-T2] done")
    }

    private static func probeRoot(_ root: ManagedFolder) async {
        guard let bookmark = root.rootBookmark else {
            print("[Spike-T2] root id=\(root.id) has no bookmark — skip")
            return
        }
        var stale = false
        guard let rootURL = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            bookmarkDataIsStale: &stale
        ) else {
            print("[Spike-T2] root id=\(root.id) bookmark resolve FAILED")
            return
        }
        let didStart = rootURL.startAccessingSecurityScopedResource()
        defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }
        guard didStart else {
            print("[Spike-T2] root id=\(root.id) startAccessing returned FALSE — scope denied")
            return
        }

        // 找 root 下任意 1 张已索引图 (跨 root 真实文件验证)
        let fm = FileManager.default
        guard let probeURL = findFirstImage(in: rootURL, fm: fm) else {
            print("[Spike-T2] root id=\(root.id) no image found — skip")
            return
        }
        print("[Spike-T2] probing: \(probeURL.path)")

        // 1) 试 trashItem
        var trashURL: NSURL?
        do {
            try fm.trashItem(at: probeURL, resultingItemURL: &trashURL)
            print("[Spike-T2]   ✅ trashItem OK → \(trashURL?.absoluteString ?? "(nil resultingURL)")")
        } catch {
            let ns = error as NSError
            print("[Spike-T2]   ❌ trashItem FAILED: domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")
            return
        }

        // 2) 试 restore (move 回原 path)
        guard let trashed = trashURL as URL? else {
            print("[Spike-T2]   ❌ no resultingURL → cannot restore")
            return
        }
        do {
            try fm.moveItem(at: trashed, to: probeURL)
            print("[Spike-T2]   ✅ moveItem (restore) OK")
        } catch {
            let ns = error as NSError
            print("[Spike-T2]   ❌ restore FAILED: domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")
        }
    }

    private static func findFirstImage(in rootURL: URL, fm: FileManager) -> URL? {
        guard let enumerator = fm.enumerator(at: rootURL,
                                              includingPropertiesForKeys: [.contentTypeKey],
                                              options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
               type.conforms(to: .image) {
                return url
            }
        }
        return nil
    }
}
```

- [ ] **步骤 1.1.b: 在 `Glance/GlanceApp.swift` AppDelegate.applicationDidFinishLaunching 末尾临时接线触发 spike (跑一次后注释掉)**

```swift
// 临时 spike 接线 — 跑完 git checkout 弃此修改
Task { @MainActor in
    try await Task.sleep(nanoseconds: 5_000_000_000)  // 等 wireIfReady 跑完
    await SpikeTask2CrossRoot.run(indexStore: indexStoreHolder.store!)
}
```

- [ ] **步骤 1.1.c: build + 运行 + 看 console 输出**

```bash
make build
open -a /Users/sunerpang/projects/claude/glance-v2/build/Glance.app
# 等 5-10 秒,看 Console.app 里 Glance 的 [Spike-T2] 输出
```

预期 (军哥已加 ≥1 root 时):
- 容器内场景 (任务 1 design 风险 2 已通过 spike): `✅ trashItem OK` + `✅ restore OK`
- 跨 root 家目录场景未知:
  - 如果 `✅ trashItem OK + ✅ restore OK` → 沙盒同 root scope 内放行,D30 「一键」体验成立
  - 如果 `❌ trashItem FAILED: NSCocoaErrorDomain` → 沙盒不放行,需 D30 加细粒度授权方案 → **暂停 plan 回 design 修订**

- [ ] **步骤 1.1.d: spike 跑完清理 — 删 spike 文件 + 撤回 AppDelegate 临时接线**

```bash
rm Glance/_SpikeTask2CrossRoot.swift
git checkout Glance/GlanceApp.swift
make build  # 验证清理后编译通过
```

### 步骤 1.2: 整理真机不可绕开矩阵走查项 (PENDING)

- [ ] **步骤 1.2.a: 加 PENDING-USER-ACTIONS 任务 2 卷类型矩阵段**

`specs/PENDING-USER-ACTIONS.md` 在 `## Pending` 段顶部加:

```markdown
### V2 M4 任务 2 — 卷类型验证矩阵 (前置门控, design 8.2 最小解锁条件)

> **解锁条件** (design 8.2 codex 第二轮 P2): (a) 内置 APFS 必过 + (b) 外置 USB/Thunderbolt 必过 + (c) iCloud Drive 行为明确 (成功 / 拒绝二选一) + (d) ≥1 类失败路径 fallback 验通。**全过才解锁本 plan 步骤 2 实施**。任一失败 → 反推 design 修订。

- [ ] (2026-06-16 / `<spike commit>`) **(a) 内置 APFS** — 家目录 root (~/Documents/screenshots 或类似) 真实重复图 trashItem + restore 行为
  1. console 看 `[Spike-T2] ✅ trashItem OK → file://.Trash/...` 句柄返回
  2. console 看 `[Spike-T2] ✅ moveItem (restore) OK` 复原成功
  3. Finder 看 ~/.Trash 里有该图,清空废纸篓后磁盘空间释放
- [ ] (2026-06-16 / `<spike commit>`) **(b) 外置 USB / Thunderbolt** — 移动盘下加 root 后真机跑 spike (军哥本地 Mac mini 接 USB 盘)
  1. 卷上的 `/Volumes/<name>/.Trashes/<uid>/` 出现该图
  2. restore 成功
  3. 弹出卷 → 重新插回 → 再 restore 是否仍能成功 (or 报 file not found)
- [ ] (2026-06-16 / `<spike commit>`) **(c) iCloud Drive 行为明确** — 必须二选一,不允许"可能成功可能失败"模糊态
  1. 已下载的图 (绿色对勾) trashItem 行为
  2. 云占位 (未下载) 的图 trashItem 行为 (报错 / 隐式下载后成功)
  3. 选 plan B fallback: 报错则 banner 副文案显示「iCloud 未下载文件无法清理」
- [ ] (2026-06-16 / `<spike commit>`) **(d) ≥1 类失败路径 fallback** — 任选一类
  - [ ] 只读卷: dmg mount 后 trashItem 抛 `NSFileWriteVolumeReadOnlyError` → member 级失败累积,其余 member 仍 trash 成功
  - [ ] 卷弹出: 中途弹出 USB → 剩余 member 抛 `NSFileReadNoSuchFileError` → 不中断
  - [ ] 磁盘满: 人为构造接近满的卷 → `NSFileWriteOutOfSpaceError` 抛 → banner 单独提示「磁盘已满」

**全过 → 报告 CC,进步骤 2; 任一失败 → 报告 CC, plan 暂停回 design 修订。**
```

### 步骤 1.3: spike 结论写进 design 风险段

- [ ] **步骤 1.3.a: 更新 `specs/v2/2026-06-10-m4-design.md` 风险 2**

定位到「## 9. 待军哥确认的风险」段第 2 条,把跨 root 部分 `❌ 仍 PENDING` 替换为实测结论 (CC 自闭环 spike 跑通后:

```markdown
2. **`FileManager.trashItem` 跨 root 的 security scope** — **spike 部分验通 (2026-06-16)** + **CC 自闭环跨 root 探测通过 (2026-06-16 任务 2 步骤 1)**.
   - **容器内场景 ✅ 已通**: (原文保留)
   - **跨 root 家目录场景** [**结论填这里**: ✅ APFS 家目录跨 root 全放行 / ❌ 沙盒拒绝需细粒度授权]: spike 脚本 `_SpikeTask2CrossRoot.swift` (跑完已弃) 对 BookmarkManager 持的真实 root resolve + startAccessing scope 内 trashItem [成功 / 失败错误码 XXX]; restore [成功 / 失败]. **D30 「一键」体验 [成立 / 需改]**.
   - **真机其它卷类型 PENDING-USER-ACTIONS 等军哥本地跑**: USB/TB / iCloud / 失败路径,见 `specs/PENDING-USER-ACTIONS.md`「任务 2 卷类型矩阵」段.
```

### 步骤 1.4: commit spike 结果 + 等军哥真机反馈

- [ ] **步骤 1.4.a: commit + push (docs-only 跳 codex)**

```bash
git add specs/v2/2026-06-10-m4-design.md specs/Roadmap.md specs/PENDING-USER-ACTIONS.md
git commit -m "$(cat <<'EOF'
docs(M4-task2-step1): 卷类型 spike 结论 — CC 自闭环跨 root [成立/失败] + PENDING 真机矩阵

- design 风险 2 跨 root 段填实测结论
- Roadmap M4 任务 2 状态「卷类型矩阵走查中」
- PENDING 加 4 项真机不可绕开矩阵 (APFS/USB/iCloud/fallback)

[docs-only]
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push
```

### 步骤 1.5: 退出路径明示

- [ ] **判 (a) (b) (c) (d) (e) 5 条最小解锁条件结果** (新 (e) bookmark 迁移路径 = 2026-06-17 codex review 第五轮加):
  - **全过 (CC 自闭环 a 跑通 + 军哥真机 b c d 反馈过 + (e) bookmark 迁移 4.5.4 + 4.5.4.5 entitlement 已落)** → 继续步骤 2
  - **任一失败** → 报告军哥: 「<具体失败项> 触发,build 步骤 2 前需 design 修订」+ 暂停 plan 等军哥拍

### 步骤 1.6: V1 read-only bookmark 迁移设计落地 (2026-06-17 codex review 第五轮新增, A 方向)

> **背景**: 步骤 1.1 spike 三轮跑跨 root sandbox trashItem 全失败 NSCocoaErrorDomain code=513, 根因定位 V1 `.securityScopeAllowOnlyReadAccess` flag 使 bookmark 数据自带 read-only scope. 军哥拍板走 codex 推荐 A 方向 (A1.5 变体 = M4 删除入口首次触发清旧 bookmark 引导重选).
>
> **本步定位**: design 4.5.4 + 8.2 最小解锁 (e) 已落 (步骤 1.6 docs only), 不动 BookmarkManager 代码. 实施代码改动放步骤 2.0.5 (4.5.4.1-4.5.4.3 三个 API) + 步骤 4 trashSelected 触发流 + 步骤 5 引导 UI.
>
> **本步用户感知**: 无 UI 变化, design + plan docs 同步.

- [ ] **步骤 1.6.a: 同步 `Glance/Glance.entitlements` 从 read-only → read-write** (codex review 第五轮抓的「pbxproj vs entitlements 两份事实漂移」硬伤; 已落 step 1 commit 内 — codex 把这条作为 ground rule 不可漏)

- [ ] **步骤 1.6.b: design 4.5.4 + 8.2 + 风险 2 三段更新已落**:
  - design 4.5.4 BookmarkManager V1 → V2 升级 (4 子节)
  - design 8.2 最小解锁条件加 (e) bookmark 迁移路径
  - design 9. 风险 2 跨 root 段填实证结论 + 根因 + 解法走 A 锚点

- [ ] **步骤 1.6.c: plan 后续步骤整合 BookmarkManager 升级 (本 plan 步骤 2.0.5 + 步骤 4.X + 步骤 5.X 触发流, 见对应步骤)**

---

## 步骤 2 — 3 个新 API + IndexedImageSnapshot 值类型

> **为什么这一步**: design 4.5 三个 API (fetchSnapshotForRestore / restoreImageFromSnapshot / requestRescan) + IndexedImageSnapshot 值类型是 task 2 删除/撤销链的数据 + DB 接口前置。本步独立可 ship = 单测 / 一次性脚本验 round-trip (fetch snapshot → 模拟删除 → restore 重建 row) 通过即代表 API 接口正确。
>
> **本步用户感知**: 无 UI 变化, model / view 层不动。

**Files:**
- Create: `Glance/Dedup/IndexedImageSnapshot.swift`
- Modify: `Glance/Dedup/DuplicateGroup.swift` (加 `folderId: Int64` 进 DuplicateGroupMemberRow + DuplicateGroupMember struct)
- Modify: `Glance/IndexStore/IndexedImage.swift` (extension 加 2 个新方法 + `fetchDuplicateGroupMembers` SQL 加 `i.folder_id` 列)
- Modify: `Glance/IndexStore/FolderStoreIndexBridge.swift` (加 requestRescan async + triggerIndexChanged 公开广播 API)
- Modify: `Glance/BookmarkManager.swift` (4.5.4.1 saveBookmark 去 read-only flag + 4.5.4.2 schemaVersion 哨兵 + 4.5.4.3 clearAllForMigration API; 步骤 2.0.5)
- Modify: `Glance/FolderBrowser/FolderStore.swift` (加 `reloadFromDefaults()` 同步内存状态重置)

### 步骤 2.0: DuplicateGroupMember + Row + fetchDuplicateGroupMembers 加 folderId (codex P1-03 + P2-02 合一修)

> **为什么先做这步**: codex review P1-03 抓出 `DuplicateOverviewModel.collectTrashInputs` 用 `images.id` 反查 `folder_id` 时调 `checkBind(...)` 是 `IndexedImage.swift` 内 file-scoped private helper, model 文件根本访问不到 — 按 plan 原写法直接编译失败。P2-02 同根问题 — 反查 SQL 每副本 1 次是 N+1 性能风险。两者合一修 = 把 `folderId` 加进 `DuplicateGroupMember` struct + `DuplicateGroupMemberRow` + `fetchDuplicateGroupMembers` SQL 同步 SELECT `i.folder_id`,member 列表组装时直接带上,trashSelected 不再反查。
>
> **任务 1 边界考量**: 加 `folderId` 字段是加法,不破坏任务 1 既有读路径行为 (任务 1 view 不读该字段)。属任务 2 plan 内部约定的扩展,不需要 task 1 重新 ship。codex 兜底「加字段是加法」论据接受。

- [ ] **步骤 2.0.a: 改 `Glance/Dedup/DuplicateGroup.swift`**

`DuplicateGroupMember` 加字段:
```swift
struct DuplicateGroupMember: Identifiable, Equatable {
    let id: Int64
    /// images.folder_id (任务 2 新增 — TrashService 走 IndexStore.fetchSnapshotForRestore /
    /// deleteImage 调用都按 (folderId, relativePath) 复合键, 直接 carry 避 N+1 反查)
    let folderId: Int64
    let urlBookmark: Data
    let relativePath: String
    let fileSize: Int64
    let fullPath: String
    let isCanonical: Bool
}
```

`DuplicateGroupMemberRow` 加字段:
```swift
struct DuplicateGroupMemberRow {
    let id: Int64
    let folderId: Int64  // 任务 2 新增 — SQL i.folder_id 同步 SELECT
    let dedupCanonical: Bool
    let fileSize: Int64
    let relativePath: String
    let urlBookmark: Data
    let fullPath: String
}
```

- [ ] **步骤 2.0.b: 改 `Glance/IndexStore/IndexedImage.swift` 的 `fetchDuplicateGroupMembers` SQL 加 `i.folder_id` 列**

定位现有 `fetchDuplicateGroupMembers` 方法的 SELECT, 列从 5 列 (`i.id, i.dedup_canonical, i.file_size, i.relative_path, i.url_bookmark, f.root_path || '/' || i.relative_path AS full_path`) 加到 6 列:

```swift
            let stmt = try db.prepare("""
                SELECT i.id, i.folder_id, i.dedup_canonical, i.file_size, i.relative_path,
                       i.url_bookmark, f.root_path || '/' || i.relative_path AS full_path
                FROM images i
                JOIN folders f ON i.folder_id = f.id
                WHERE i.content_sha256 = ?
                ORDER BY i.dedup_canonical DESC, i.birth_time ASC, i.id ASC;
            """)
```

读列索引同步右移 (id=0, folder_id=1, dedup_canonical=2, file_size=3, relative_path=4, url_bookmark=5, full_path=6):

```swift
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let folderId = sqlite3_column_int64(stmt, 1)
                let canonical = sqlite3_column_int64(stmt, 2) == 1
                let fileSize = sqlite3_column_int64(stmt, 3)
                let relPath = String(cString: sqlite3_column_text(stmt, 4))
                let blobLen = sqlite3_column_bytes(stmt, 5)
                let blobPtr = sqlite3_column_blob(stmt, 5)
                let bookmark = blobPtr.map { Data(bytes: $0, count: Int(blobLen)) } ?? Data()
                let fullPath = String(cString: sqlite3_column_text(stmt, 6))
                rows.append(DuplicateGroupMemberRow(
                    id: id, folderId: folderId, dedupCanonical: canonical, fileSize: fileSize,
                    relativePath: relPath, urlBookmark: bookmark, fullPath: fullPath
                ))
            }
```

- [ ] **步骤 2.0.c: 改 `Glance/Dedup/DuplicateOverviewModel.swift` makeMember 同步加 folderId**

定位 `makeMember(from row:)` 静态函数:
```swift
    private nonisolated static func makeMember(from row: DuplicateGroupMemberRow) -> DuplicateGroupMember {
        DuplicateGroupMember(
            id: row.id,
            folderId: row.folderId,   // 任务 2 新增
            urlBookmark: row.urlBookmark,
            relativePath: row.relativePath,
            fileSize: row.fileSize,
            fullPath: row.fullPath,
            isCanonical: row.dedupCanonical
        )
    }
```

- [ ] **步骤 2.0.d: build 验证 + commit**

```bash
make build 2>&1 | tail -5
git add Glance/Dedup/DuplicateGroup.swift Glance/IndexStore/IndexedImage.swift Glance/Dedup/DuplicateOverviewModel.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step2.0): DuplicateGroupMember + Row + fetchDuplicateGroupMembers 加 folderId

codex review P1-03 (folderIdForImageId 编译失败 — checkBind file-scoped private)
+ P2-02 (N+1 反查 SQL) 合一修. DuplicateGroupMember struct 加 folderId 字段
(任务 2 删除路径走 (folderId, relativePath) 复合键, 直接 carry 避反查).
DuplicateGroupMemberRow 同步加 folderId. fetchDuplicateGroupMembers SQL 加
i.folder_id 列 (read 列索引右移). makeMember 同步.

任务 1 边界扩展加字段是加法不破坏既有读路径行为 (任务 1 view 不读 folderId).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 2.0.5: BookmarkManager V1 → V2 升级 (design 4.5.4 实施, 2026-06-17 codex review 第五轮 A 方向)

> **为什么这一步**: design 4.5.4 三个 API (saveBookmark 去 read-only + schemaVersion 哨兵 + clearAllForMigration) 是 task 2 trashItem 跑通的硬前置. 现有 V1 bookmark 是 read-only scope, sandbox 拒 trashItem (code=513 已 spike 实证). 本步独立可 ship = 升级后既有看图功能不受影响 (read-write scope 兼容 read-only 读路径), 新 bookmark 创建后 trashItem 跑通 (步骤 3 TrashService 实施时通过 spike 二次验证).
>
> **本步用户感知**: 无 UI 变化, **既有 V1 bookmark 仍可继续看图** (read scope 兼容). 升级触发 UX 在步骤 4-5 实施.

- [ ] **步骤 2.0.5.a: 改 `Glance/BookmarkManager.swift` saveBookmark 去掉 read-only flag**

定位 `saveBookmark(for url:)` 方法 (现 line 12-22), 把 options 从 `[.withSecurityScope, .securityScopeAllowOnlyReadAccess]` 改为 `[.withSecurityScope]`:

```swift
func saveBookmark(for url: URL) throws {
    let data = try url.bookmarkData(
        options: [.withSecurityScope],  // V2 起去掉 .securityScopeAllowOnlyReadAccess
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    )
    // 既有持久化逻辑不变
    var bookmarks = loadRawBookmarks()
    bookmarks[url.absoluteString] = data
    UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
}
```

- [ ] **步骤 2.0.5.b: 改 `Glance/BookmarkManager.swift` 加 schemaVersion 哨兵 API**

类内 `private let defaultsKey = "savedBookmarks"` 同段加:

```swift
/// UserDefaults int key, 标记当前持久化 bookmark 的 schema 版本.
/// V1 (read-only) = 0 或 missing; V2 (read-write) = 2.
private static let schemaVersionKey = "bookmarkSchemaVersion"

/// 当前已持久化 bookmark 的 schema 版本.
var currentSchemaVersion: Int {
    UserDefaults.standard.integer(forKey: Self.schemaVersionKey)
}

/// 标记当前持久化 bookmark 已升级到 V2.
/// 触发时机: 用户走 NSOpenPanel grant 流程重选 >= 1 个 root 后,
/// 在第一个 saveBookmark 成功后立即调.
func markSchemaV2() {
    UserDefaults.standard.set(2, forKey: Self.schemaVersionKey)
}
```

- [ ] **步骤 2.0.5.c: 改 `Glance/BookmarkManager.swift` 加 clearAllForMigration API**

```swift
/// 一次性清空 V1 持久化 bookmark + 重置 schema version 为 0,
/// 触发用户重选所有根目录 (步骤 4 trashSelected 入口前置 + 步骤 5 引导 UI).
///
/// 调用约束: 仅在 V2 升级触发点 (M4 删除入口首次) 由
/// DuplicateOverviewModel.trashSelected 入口前置调一次, 之后流程内的
/// currentSchemaVersion == 2 判别会让本 API 不重复触发.
///
/// 完成语义: 同步, 清空 UserDefaults savedBookmarks + reset schemaVersion.
/// 调用方拿到返回后立刻调 FolderStore.reloadFromDefaults() 同步内存 + 弹 UI 引导.
func clearAllForMigration() {
    UserDefaults.standard.removeObject(forKey: defaultsKey)
    UserDefaults.standard.set(0, forKey: Self.schemaVersionKey)
}
```

- [ ] **步骤 2.0.5.d: 改 `Glance/FolderBrowser/FolderStore.swift` 加 reloadFromDefaults()**

类内加 public method, 让 BookmarkManager.clearAllForMigration 后 FolderStore 内 rootFolders 数组同步重置. 具体实现照搬 FolderStore 既有的 loadSavedFolders() 逻辑 (从 BookmarkManager.restoreBookmarks() 读 + 重设 @Published rootFolders):

```swift
/// V2 升级触发点用 — bookmark clearAllForMigration 后同步内存状态重置.
/// 与 loadSavedFolders() 区别: 主动重置 rootFolders 为空 (避免持有已删的 root URL).
@MainActor
func reloadFromDefaults() {
    rootFolders.removeAll()
    selectedFolder = nil
    // 不再调 restoreBookmarks() — 因为 clearAllForMigration 已清空持久化, 重新选才会有 root
}
```

- [ ] **步骤 2.0.5.e: build + 验编译过**

```bash
make build
# 期望: BUILD SUCCEEDED + 0 errors
# 期望: V1 既有 bookmark 重启 app 后 restoreBookmarks 仍能 resolve (read scope 兼容)
```

- [ ] **步骤 2.0.5.f: commit 步骤 2.0.5 单独提**

```bash
git add Glance/BookmarkManager.swift Glance/FolderBrowser/FolderStore.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step2.0.5): BookmarkManager V2 升级 — saveBookmark 去 read-only + schemaVersion 哨兵 + clearAllForMigration

design 4.5.4 落地. V1 既有 bookmark (read scope) 仍可继续看图.
新 saveBookmark 创建的 V2 bookmark 才有 read-write scope (步骤 3 TrashService 验通).
触发时机 (步骤 4-5 实施): M4 删除入口首次, 清旧 bookmark + 引导重选所有根目录.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 2.1: IndexedImageSnapshot 值类型 (15 字段全保真)

- [ ] **步骤 2.1.a: 新建 `Glance/Dedup/IndexedImageSnapshot.swift`**

```swift
//
//  IndexedImageSnapshot.swift
//  Glance
//
//  M4 任务 2 — 删除前完整 in-memory snapshot.
//  字段对齐 IndexStoreSchema.swift:55-77 images 表全部非 PK 列 (15 个; PK id 由 DB 重新分配不入).
//  TrashService.trashItems 调 FileManager.trashItem 前对每个 member 调
//  IndexStore.fetchSnapshotForRestore 拿一份, 撤销回补走 restoreImageFromSnapshot
//  按 (folder_id, relative_path) UNIQUE key INSERT 全列还原.
//
//  D34 contract: snapshot 全列保真避免撤销时 M2 找相似图 / M3 搜索元数据 (dedup_canonical /
//  feature_print 系列 / exif_capture_date 三族列) 静默退化.
//

import Foundation

struct IndexedImageSnapshot: Equatable {
    // MARK: M1 基础 NOT NULL 列 (schema:57-63)
    let urlBookmark: Data           // images.url_bookmark BLOB NOT NULL
    let birthTime: Date             // images.birth_time REAL NOT NULL
    let fileSize: Int64             // images.file_size INTEGER NOT NULL
    let format: String              // images.format TEXT NOT NULL
    let filename: String            // images.filename TEXT NOT NULL
    let relativePath: String        // images.relative_path TEXT NOT NULL
    let folderId: Int64             // images.folder_id INTEGER NOT NULL

    // MARK: M1 可选列 (schema:64-65)
    let dimensionsWidth: Int?       // images.dimensions_width INTEGER
    let dimensionsHeight: Int?      // images.dimensions_height INTEGER

    // MARK: 任务 1 dedup (schema:66-67)
    let contentSha256: String?      // images.content_sha256 TEXT
    let dedupCanonical: Bool?       // images.dedup_canonical INTEGER

    // MARK: M2 找相似图 (schema:68-70)
    let featurePrint: Data?         // images.feature_print BLOB
    let featurePrintRevision: Int?  // images.feature_print_revision INTEGER
    let supportsFeaturePrint: Bool  // images.supports_feature_print INTEGER NOT NULL DEFAULT 1

    // MARK: M3 搜索 (schema:71)
    let exifCaptureDate: Date?      // images.exif_capture_date REAL
}
```

- [ ] **步骤 2.1.b: build 验证编译通过**

```bash
make build 2>&1 | tail -5
```

预期: `BUILD SUCCEEDED` + 0 errors 0 warnings

- [ ] **步骤 2.1.c: commit (任务 2 第 1 个 commit)**

```bash
git add Glance/Dedup/IndexedImageSnapshot.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step2.1): IndexedImageSnapshot 15 字段全保真值类型

撤销回补 D34 contract 前置: 删前 SELECT 全列 in-memory snapshot 字段对齐
IndexStoreSchema.swift:55-77 images 表非 PK 列 (M1 7 NOT NULL + 2 可选 +
任务 1 dedup 2 + M2 feature print 3 + M3 EXIF 1 = 15).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 2.2: IndexStore.fetchSnapshotForRestore — 删前 SELECT 15 列

- [ ] **步骤 2.2.a: 在 `Glance/IndexStore/IndexedImage.swift` 末尾 (M4 任务 1 聚合查询段后) 加新方法**

```swift
    // MARK: - M4 任务 2 — 撤销回补 API

    /// M4 任务 2 — 删前完整 in-memory snapshot (D34 contract 前置).
    /// TrashService.trashItems 调 FileManager.trashItem **前**对每个 member 调一次,
    /// SELECT 15 个非 PK 列组装成 IndexedImageSnapshot (撤销时按 (folder_id, relative_path)
    /// UNIQUE key restoreImageFromSnapshot 重建 row 保 M2/M3 列保真不退化).
    ///
    /// 现有 IndexedImage struct (IndexedImage.swift:5-22) 是 SmartFolder 查询投影,
    /// 缺 dedup_canonical / feature_print 系列 / exif_capture_date 三族列, **不复用**.
    /// 本 query 独立 SELECT 全列.
    ///
    /// 找到 row → 返回 snapshot; 没找到 (DB race) → 返回 nil, 调用方 trashSelected 时
    /// 跳过该 member.
    func fetchSnapshotForRestore(folderId: Int64, relativePath: String) throws -> IndexedImageSnapshot? {
        try sync { db in
            let stmt = try db.prepare("""
                SELECT url_bookmark, birth_time, file_size, format, filename,
                       relative_path, folder_id, dimensions_width, dimensions_height,
                       content_sha256, dedup_canonical, feature_print, feature_print_revision,
                       supports_feature_print, exif_capture_date
                FROM images
                WHERE folder_id = ? AND relative_path = ?
                LIMIT 1;
            """)
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_int64(stmt, 1, folderId), index: 1, db: db)
            try checkBind(sqlite3_bind_text(stmt, 2, (relativePath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 2, db: db)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            // 0: url_bookmark BLOB
            let bmLen = sqlite3_column_bytes(stmt, 0)
            let bmPtr = sqlite3_column_blob(stmt, 0)
            let urlBookmark = bmPtr.map { Data(bytes: $0, count: Int(bmLen)) } ?? Data()
            // 1: birth_time REAL
            let birthTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            // 2: file_size INTEGER
            let fileSize = sqlite3_column_int64(stmt, 2)
            // 3: format TEXT
            let format = String(cString: sqlite3_column_text(stmt, 3))
            // 4: filename TEXT
            let filename = String(cString: sqlite3_column_text(stmt, 4))
            // 5: relative_path TEXT
            let relPath = String(cString: sqlite3_column_text(stmt, 5))
            // 6: folder_id INTEGER
            let folderIdCol = sqlite3_column_int64(stmt, 6)
            // 7: dimensions_width INTEGER nullable
            let dimW: Int? = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 7))
            // 8: dimensions_height INTEGER nullable
            let dimH: Int? = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 8))
            // 9: content_sha256 TEXT nullable
            let sha: String? = sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 9))
            // 10: dedup_canonical INTEGER nullable (1=true / 0=false / NULL=未决议)
            let dedup: Bool? = sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 10) == 1
            // 11: feature_print BLOB nullable
            let fp: Data?
            if sqlite3_column_type(stmt, 11) == SQLITE_NULL {
                fp = nil
            } else {
                let fpLen = sqlite3_column_bytes(stmt, 11)
                let fpPtr = sqlite3_column_blob(stmt, 11)
                fp = fpPtr.map { Data(bytes: $0, count: Int(fpLen)) } ?? Data()
            }
            // 12: feature_print_revision INTEGER nullable
            let fpRev: Int? = sqlite3_column_type(stmt, 12) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 12))
            // 13: supports_feature_print INTEGER NOT NULL DEFAULT 1
            let supportsFp = sqlite3_column_int64(stmt, 13) == 1
            // 14: exif_capture_date REAL nullable
            let exif: Date? = sqlite3_column_type(stmt, 14) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 14))

            return IndexedImageSnapshot(
                urlBookmark: urlBookmark, birthTime: birthTime, fileSize: fileSize,
                format: format, filename: filename, relativePath: relPath,
                folderId: folderIdCol, dimensionsWidth: dimW, dimensionsHeight: dimH,
                contentSha256: sha, dedupCanonical: dedup,
                featurePrint: fp, featurePrintRevision: fpRev, supportsFeaturePrint: supportsFp,
                exifCaptureDate: exif
            )
        }
    }
```

- [ ] **步骤 2.2.b: build 验证**

```bash
make build 2>&1 | tail -5
```

预期: `BUILD SUCCEEDED` + 0 errors 0 warnings

- [ ] **步骤 2.2.c: commit**

```bash
git add Glance/IndexStore/IndexedImage.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step2.2): IndexStore.fetchSnapshotForRestore 删前 15 列 SELECT 全 fetch

D34 contract 前置 API. TrashService 调 trashItem 前对每个 member 调本 API
拿 IndexedImageSnapshot, 撤销时按 (folder_id, relative_path) UNIQUE key
restoreImageFromSnapshot 重建 row 保真.

不复用 IndexedImage struct (SmartFolder 投影缺 dedup_canonical / feature_print
/ exif_capture_date 三族列), 本 query 独立 SELECT 全列.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 2.3: IndexStore.restoreImageFromSnapshot — INSERT 15 列回补

- [ ] **步骤 2.3.a: 在 `IndexedImage.swift` `fetchSnapshotForRestore` 后加新方法**

```swift
    /// M4 任务 2 — 撤销回补首选路径 (D34). INSERT 15 列还原 row.
    /// 按 (folder_id, relative_path) UNIQUE key 写; 冲突 (同 path 已被 FSEvents 抢先 ingest)
    /// 抛 SQLITE_CONSTRAINT 让调用方降级走 requestRescan 兜底.
    ///
    /// 本 API 仅给 D34 撤销回补用. 其它 ingest 路径 (FolderScanner / FSEvents) 走
    /// `insertImageIfAbsent` 只写基础列, 两条路径不互相覆盖.
    ///
    /// 同步返回新 row id, 调用方拿 id 立即 reEvaluateGroup + load() 无 race.
    func restoreImageFromSnapshot(_ snapshot: IndexedImageSnapshot) throws -> Int64 {
        try sync { db in
            let stmt = try db.prepare("""
                INSERT INTO images
                (url_bookmark, birth_time, file_size, format, filename, relative_path,
                 folder_id, dimensions_width, dimensions_height,
                 content_sha256, dedup_canonical,
                 feature_print, feature_print_revision, supports_feature_print,
                 exif_capture_date)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
            defer { sqlite3_finalize(stmt) }

            // 1: url_bookmark BLOB
            let bmBytes = snapshot.urlBookmark as NSData
            try checkBind(sqlite3_bind_blob(stmt, 1, bmBytes.bytes, Int32(bmBytes.length), unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 1, db: db)
            // 2: birth_time REAL
            try checkBind(sqlite3_bind_double(stmt, 2, snapshot.birthTime.timeIntervalSince1970), index: 2, db: db)
            // 3: file_size INTEGER
            try checkBind(sqlite3_bind_int64(stmt, 3, snapshot.fileSize), index: 3, db: db)
            // 4: format TEXT
            try checkBind(sqlite3_bind_text(stmt, 4, (snapshot.format as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 4, db: db)
            // 5: filename TEXT
            try checkBind(sqlite3_bind_text(stmt, 5, (snapshot.filename as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 5, db: db)
            // 6: relative_path TEXT
            try checkBind(sqlite3_bind_text(stmt, 6, (snapshot.relativePath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 6, db: db)
            // 7: folder_id INTEGER
            try checkBind(sqlite3_bind_int64(stmt, 7, snapshot.folderId), index: 7, db: db)
            // 8: dimensions_width INTEGER nullable
            if let w = snapshot.dimensionsWidth {
                try checkBind(sqlite3_bind_int(stmt, 8, Int32(w)), index: 8, db: db)
            } else {
                try checkBind(sqlite3_bind_null(stmt, 8), index: 8, db: db)
            }
            // 9: dimensions_height INTEGER nullable
            if let h = snapshot.dimensionsHeight {
                try checkBind(sqlite3_bind_int(stmt, 9, Int32(h)), index: 9, db: db)
            } else {
                try checkBind(sqlite3_bind_null(stmt, 9), index: 9, db: db)
            }
            // 10: content_sha256 TEXT nullable
            if let sha = snapshot.contentSha256 {
                try checkBind(sqlite3_bind_text(stmt, 10, (sha as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 10, db: db)
            } else {
                try checkBind(sqlite3_bind_null(stmt, 10), index: 10, db: db)
            }
            // 11: dedup_canonical INTEGER nullable (1=true / 0=false / NULL=未决议)
            if let dedup = snapshot.dedupCanonical {
                try checkBind(sqlite3_bind_int64(stmt, 11, dedup ? 1 : 0), index: 11, db: db)
            } else {
                try checkBind(sqlite3_bind_null(stmt, 11), index: 11, db: db)
            }
            // 12: feature_print BLOB nullable
            if let fp = snapshot.featurePrint {
                let fpBytes = fp as NSData
                try checkBind(sqlite3_bind_blob(stmt, 12, fpBytes.bytes, Int32(fpBytes.length), unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 12, db: db)
            } else {
                try checkBind(sqlite3_bind_null(stmt, 12), index: 12, db: db)
            }
            // 13: feature_print_revision INTEGER nullable
            if let rev = snapshot.featurePrintRevision {
                try checkBind(sqlite3_bind_int(stmt, 13, Int32(rev)), index: 13, db: db)
            } else {
                try checkBind(sqlite3_bind_null(stmt, 13), index: 13, db: db)
            }
            // 14: supports_feature_print INTEGER NOT NULL
            try checkBind(sqlite3_bind_int64(stmt, 14, snapshot.supportsFeaturePrint ? 1 : 0), index: 14, db: db)
            // 15: exif_capture_date REAL nullable
            if let exif = snapshot.exifCaptureDate {
                try checkBind(sqlite3_bind_double(stmt, 15, exif.timeIntervalSince1970), index: 15, db: db)
            } else {
                try checkBind(sqlite3_bind_null(stmt, 15), index: 15, db: db)
            }

            let stepResult = sqlite3_step(stmt)
            guard stepResult == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: """
                    restoreImageFromSnapshot step \(stepResult): \(db.lastErrorMessage()) — \
                    folder_id=\(snapshot.folderId), relative_path=\(snapshot.relativePath)
                    """)
            }
            return sqlite3_last_insert_rowid(db.handle)
        }
    }
```

- [ ] **步骤 2.3.b: build + commit**

```bash
make build 2>&1 | tail -5
git add Glance/IndexStore/IndexedImage.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step2.3): IndexStore.restoreImageFromSnapshot 15 列 INSERT 撤销首选回补

D34 contract 撤销首选路径. 按 (folder_id, relative_path) UNIQUE key INSERT 15 列;
冲突 (FSEvents 抢先 ingest) 抛 SQLITE_CONSTRAINT 让调用方降级 requestRescan.

仅给 D34 撤销路径用, 不污染 insertImageIfAbsent 既有 ingest 路径.
同步返回新 row id, 调用方立即 reEvaluateGroup + load() 无 race.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 2.4: FolderStoreIndexBridge.requestRescan — 单文件 rescan 降级

- [ ] **步骤 2.4.a: 在 `Glance/IndexStore/FolderStoreIndexBridge.swift` 末尾 (class 内或 extension) 加新方法**

```swift
    /// M4 任务 2 — 撤销回补降级路径 (D34).
    /// restoreImageFromSnapshot 失败时 (snapshot 信息不全 / UNIQUE 冲突 / 业务认为该走
    /// FolderScanner 兜底) 走本 API. 实现路径: 找 folder root → resolve bookmark + 拼 child URL
    /// → ImageMetadataReader.read → insertImageIfAbsent → 返回新 row id.
    ///
    /// async 函数返回时 row 已恢复或明确失败, **禁止 fire-and-forget** (codex review 第三轮 P2).
    /// 调用方拿 id 立即 reEvaluateGroup + load() 无 race.
    ///
    /// 退化代价: 降级路径不还原 dedup_canonical / feature_print 系列 / exif_capture_date
    /// (IO 不可得), 这些列后续靠 DedupPass.reEvaluateGroup + FeaturePrintIndexer + EXIF
    /// reader 后台异步补齐. 用户感知: 撤销立即"图回来", 但 V2 找相似图 / 搜索可能需等几秒
    /// 到几分钟后台跑完.
    func requestRescan(folderId: Int64, relativePath: String) async throws -> Int64 {
        // 1. 找 root 拿 bookmark
        let roots = try indexStore.fetchRoots()
        guard let root = roots.first(where: { $0.id == folderId && $0.rootBookmark != nil }),
              let bookmark = root.rootBookmark else {
            throw NSError(domain: "M4.TaskTwo.RequestRescan", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "root folderId=\(folderId) not found or no bookmark"])
        }

        // 2. Resolve bookmark + startAccessing + 拼 child URL (复刻 DedupPass.computeSha 模式)
        let metadata: ImageMetadata? = await Task.detached(priority: .userInitiated) {
            var stale = false
            guard let rootURL = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &stale
            ) else { return nil }
            let didStart = rootURL.startAccessingSecurityScopedResource()
            defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }
            guard didStart else { return nil }
            let fileURL = rootURL.appendingPathComponent(relativePath)
            return ImageMetadataReader.read(at: fileURL)
        }.value

        guard let metadata else {
            throw NSError(domain: "M4.TaskTwo.RequestRescan", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "metadata read failed for \(relativePath) (file missing or scope denied)"])
        }

        // 3. insertImageIfAbsent (复用现有 ingest 路径)
        let record = ImageInsertRecord(
            urlBookmark: bookmark,
            birthTime: metadata.birthTime,
            fileSize: metadata.fileSize,
            format: metadata.format,
            filename: metadata.filename,
            relativePath: relativePath,
            folderId: folderId,
            dimensionsWidth: metadata.dimensionsWidth,
            dimensionsHeight: metadata.dimensionsHeight
        )
        let rowId = try indexStore.insertImageIfAbsent(record)
        return rowId
    }
```

- [ ] **步骤 2.4.b: 加 `triggerIndexChanged` 公开广播 API (codex P1-01 修)**

定位现有 `private func fireIndexChanged()` (FolderStoreIndexBridge.swift:58), 不删私有 fire (内部 4 fire 点继续走它),在它后面加公开桥接:

```swift
    /// M4 任务 2 — 公开广播入口 (codex P1-01).
    /// TrashService 删除路径 / DuplicateOverviewModel.undo 撤销路径完成后主动调,
    /// 让智能文件夹 / 搜索 / 其它已注册 observer 视图自动刷新 (D33 跨视图持久 banner +
    /// 跨视图数据一致). 私有 fireIndexChanged 内部 fire 点不变, 公开版仅提供外部触发.
    func triggerIndexChanged() {
        fireIndexChanged()
    }
```

- [ ] **步骤 2.4.c: build + commit**

```bash
make build 2>&1 | tail -5
git add Glance/IndexStore/FolderStoreIndexBridge.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step2.4): FolderStoreIndexBridge.requestRescan + triggerIndexChanged

requestRescan: D34 contract 撤销降级路径. async throws 返回时 row 已恢复或明确
失败 (禁 fire-and-forget). 路径: resolve root bookmark + startAccessing + 拼 child
URL + ImageMetadataReader.read + insertImageIfAbsent + 返回新 row id.

triggerIndexChanged: codex P1-01 修跨视图刷新闭环缺口. 公开广播入口让 TrashService
删除路径 / undo 撤销路径完成后主动调, 智能文件夹 / 搜索 / 其它已注册 observer
视图自动刷新 (D33 跨视图持久 banner + 数据一致).

退化代价 (requestRescan): 不还原 dedup_canonical / feature_print / exif 列,
后台 reEvaluate + indexer 异步补齐.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 2.5: 步骤 2 整体 round-trip 一次性 swift 脚本验证

- [ ] **步骤 2.5.a: 临时建 spike 脚本 `_SpikeTask2RoundTrip.swift` 验 3 API 联调**

```swift
//
//  _SpikeTask2RoundTrip.swift
//  Glance
//
//  M4 任务 2 步骤 2 — 3 个新 API round-trip 验证.
//  1. 找 1 个 dedup_canonical=0 的 row (任务 1 总览有数据时 DB 必有)
//  2. fetchSnapshotForRestore 拿 snapshot
//  3. 删掉 row (deleteImage)
//  4. restoreImageFromSnapshot 重建
//  5. 再 fetchSnapshotForRestore 验所有 15 字段一致
//

import Foundation
import AppKit

nonisolated enum SpikeTask2RoundTrip {
    static func run(indexStore: IndexStore) async {
        print("[Spike-T2-RT] start round-trip")
        do {
            // 1. 找 dedup_canonical=0 副本 row
            let rows = try indexStore.fetchDuplicateGroups()
            guard let firstGroup = rows.first else {
                print("[Spike-T2-RT] no duplicate groups in DB — add real duplicate images first")
                return
            }
            let members = try indexStore.fetchDuplicateGroupMembers(sha256: firstGroup.contentSha256)
            guard let dup = members.first(where: { !$0.dedupCanonical }) else {
                print("[Spike-T2-RT] no duplicate member found — DB state inconsistent")
                return
            }

            // (folderId 在 task1 DuplicateGroupMember struct 不存,需直接查 DB)
            // 这里走 fetchSnapshotForRestore 用 relativePath; folder_id 从 fetchRoots 反推不可靠.
            // spike 简化: SELECT folder_id FROM images WHERE id = dup.id
            let folderId: Int64 = try indexStore.sync { db in
                let stmt = try db.prepare("SELECT folder_id FROM images WHERE id = ? LIMIT 1;")
                defer { sqlite3_finalize(stmt) }
                try checkBind(sqlite3_bind_int64(stmt, 1, dup.id), index: 1, db: db)
                guard sqlite3_step(stmt) == SQLITE_ROW else {
                    throw NSError(domain: "spike", code: 99)
                }
                return sqlite3_column_int64(stmt, 0)
            }
            print("[Spike-T2-RT] target member: id=\(dup.id) folderId=\(folderId) relPath=\(dup.relativePath)")

            // 2. fetchSnapshotForRestore
            guard let snap = try indexStore.fetchSnapshotForRestore(folderId: folderId, relativePath: dup.relativePath) else {
                print("[Spike-T2-RT] ❌ fetchSnapshotForRestore returned nil")
                return
            }
            print("[Spike-T2-RT] ✅ fetched snapshot: sha=\(snap.contentSha256 ?? "nil") fileSize=\(snap.fileSize) format=\(snap.format)")

            // 3. delete row
            try indexStore.deleteImage(folderId: folderId, relativePath: dup.relativePath)
            print("[Spike-T2-RT] ✅ deleted row id=\(dup.id)")

            // 4. restoreImageFromSnapshot
            let newId = try indexStore.restoreImageFromSnapshot(snap)
            print("[Spike-T2-RT] ✅ restored as new row id=\(newId)")

            // 5. 再 fetch 比对
            guard let snap2 = try indexStore.fetchSnapshotForRestore(folderId: folderId, relativePath: dup.relativePath) else {
                print("[Spike-T2-RT] ❌ post-restore fetch returned nil")
                return
            }
            let match = snap == snap2
            print("[Spike-T2-RT] post-restore equality: \(match ? "✅ 全字段一致" : "❌ 字段漂移")")
            print("[Spike-T2-RT] done")
        } catch {
            print("[Spike-T2-RT] ❌ FAILED: \(error)")
        }
    }
}
```

- [ ] **步骤 2.5.b: 临时 AppDelegate 接线 + 运行 + 看 Console**

(mirror 步骤 1.1.b 临时接线)。Console 看到 `✅ 全字段一致` 即三 API 联调正确。

- [ ] **步骤 2.5.c: spike 跑完清理 (删 spike + checkout AppDelegate)**

```bash
rm Glance/_SpikeTask2RoundTrip.swift
git checkout Glance/GlanceApp.swift
make build  # 验证清理
```

- [ ] **步骤 2.5.d: 步骤 2 docs commit (记录 round-trip 通过)**

```bash
git commit --allow-empty -m "$(cat <<'EOF'
verify(M4-task2-step2.5): 3 个新 API round-trip 验证通过

spike 脚本 _SpikeTask2RoundTrip.swift (跑完已 git rm) 验证:
1. fetchSnapshotForRestore 返回完整 IndexedImageSnapshot
2. deleteImage 删 row
3. restoreImageFromSnapshot 重建 row 返回新 PK id
4. 再次 fetchSnapshotForRestore 比对 15 字段全一致 (Equatable.==)

requestRescan 同步路径未单独测 (走 ImageMetadataReader.read 路径同
FolderScanner / FSEvents 既有 ingest 流, 任务 2 后续步骤 4 撤销 UI 联调时
真机自然覆盖).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push
```

---

## 步骤 3 — TrashService (碰真实文件)

> **为什么这一步**: TrashService 是全项目首个调 `FileManager.trashItem` / `FileManager.moveItem` 的代码,沙盒 scope 模式必须严格复刻 DedupPass.computeSha (DedupPass.swift:107-118)。本步独立可 ship = 一次性 swift 脚本验单文件 trash + restore + 50 张批量 + 取消传播,通过即代表服务层正确。
>
> **本步用户感知**: 无 UI 变化, model / view 层不动 (步骤 4 / 5 才接线)。

**Files:**
- Create: `Glance/Dedup/TrashOutcome.swift` (值类型 + actor)
- Create: `Glance/Dedup/TrashService.swift` (主服务)

### 步骤 3.1: TrashOutcome 值类型 + TrashCancellationToken actor

- [ ] **步骤 3.1.a: 新建 `Glance/Dedup/TrashOutcome.swift`**

```swift
//
//  TrashOutcome.swift
//  Glance
//
//  M4 任务 2 — TrashService 返回值 + 取消 token.
//

import Foundation

/// 单次 trash 操作结果汇总.
/// member 级 best-effort: 个别失败累积进 failures, 不中断其余.
struct TrashOutcome: Equatable {
    /// 成功移入废纸篓的 member: 原 fullPath + 废纸篓内新 URL + snapshot (撤销回补用)
    let successes: [TrashSuccess]
    /// 失败的 member: 标识 + 错误描述 (banner 汇总用)
    let failures: [TrashFailure]
    /// 是否在中途被 cancellation 中止 (banner 副文案「已取消」用)
    let cancelled: Bool

    /// 便捷: 全部成功数 (banner 主文案「已移 N 张到废纸篓」用)
    var successCount: Int { successes.count }
    /// 便捷: 全部失败数 (banner 副文案「+M 张失败」用)
    var failureCount: Int { failures.count }
}

struct TrashSuccess: Equatable {
    /// 删前原路径 (撤销 moveItem target)
    let originalFullPath: String
    /// 废纸篓内 URL (撤销 moveItem source) — FileManager.trashItem 通过 resultingItemURL out 参数返回
    let trashURL: URL
    /// 删前完整 snapshot (撤销 restoreImageFromSnapshot 首选路径用)
    let snapshot: IndexedImageSnapshot
    /// 受影响组的 (file_size, format) — 删后 reEvaluateGroup 用
    let groupKey: GroupKey
}

struct GroupKey: Equatable {
    let fileSize: Int64
    let format: String
}

struct TrashFailure: Equatable {
    /// member 标识 (banner 显「<filename> 失败 (<原因>)」用)
    let filename: String
    let relativePath: String
    /// 失败原因描述 (NSError.localizedDescription 或自定义)
    let reason: String
}

/// 撤销操作结果. restoreItems 同样 best-effort, 个别失败 (target 路径已被占用 etc.) 累积.
struct RestoreOutcome: Equatable {
    let successes: [RestoreSuccess]
    let failures: [RestoreFailure]
    let cancelled: Bool

    var successCount: Int { successes.count }
    var failureCount: Int { failures.count }
}

struct RestoreSuccess: Equatable {
    /// 恢复回的原路径 (DB 回补按这个找 folderId + relativePath)
    let originalFullPath: String
    /// snapshot (restoreImageFromSnapshot 用)
    let snapshot: IndexedImageSnapshot
    let groupKey: GroupKey
}

struct RestoreFailure: Equatable {
    let originalFullPath: String
    let reason: String
}

/// trash / restore 操作的取消 token. actor 保证多 task 安全 set + read.
actor TrashCancellationToken {
    private var cancelled = false

    func cancel() { cancelled = true }
    func isCancelled() -> Bool { cancelled }
}
```

- [ ] **步骤 3.1.b: build + commit**

```bash
make build 2>&1 | tail -5
git add Glance/Dedup/TrashOutcome.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step3.1): TrashOutcome 值类型 + TrashCancellationToken actor

TrashOutcome: successes (TrashSuccess: originalFullPath / trashURL / snapshot /
groupKey) + failures (TrashFailure: filename / relativePath / reason) + cancelled.
member 级 best-effort 失败累积模型 (design 6 节错误边界 + 卷类型差异).

RestoreOutcome 同款结构供撤销路径用.

TrashCancellationToken actor 保 set/read 跨 task 安全.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 3.2: TrashService.trashItems 主路径

- [ ] **步骤 3.2.a: 新建 `Glance/Dedup/TrashService.swift`**

```swift
//
//  TrashService.swift
//  Glance
//
//  M4 任务 2 — 全项目首个碰真实文件的服务. 仅本服务调 FileManager.trashItem
//  / FileManager.moveItem, 其它代码不允许直接调系统文件写操作.
//
//  Sandbox scope 模式严格复刻 DedupPass.computeSha (DedupPass.swift:107-118):
//  resolveBookmark(.withSecurityScope) + startAccessingSecurityScopedResource
//  + appendingPathComponent + 真实操作 + stop. defer 配平.
//
//  member 级 best-effort: 个别 member 失败 (卷只读 / iCloud 未下载 / 文件已外部删 /
//  scope denied) 累积进 outcome.failures, 不中断其余. 整组内 member 不拆原子
//  (单组要么全 trash 要么全不动避免 reEvaluateGroup 半截组态紊乱) — 由 model 层
//  按组分批控, service 层逐 member trash.
//

import Foundation

nonisolated enum TrashService {

    /// 输入 member 描述 (撤销回补需 snapshot, 调用方预 fetch 好传入).
    struct TrashInput {
        let snapshot: IndexedImageSnapshot
        let groupKey: GroupKey
    }

    /// 移入系统废纸篓.
    /// caller (DuplicateOverviewModel.trashSelected) 已预 fetch 每 member 的
    /// IndexedImageSnapshot (调 IndexStore.fetchSnapshotForRestore 取 15 列),
    /// 这里只负责 file 操作. 删 DB row + reEvaluateGroup 由 caller 后续做.
    ///
    /// progress 回调每 50 member 一次 (避免 UI tick 过频); cancellation 中途检测
    /// 每 member 一次 (粒度最细, 单 member trash 是不可中断的原子).
    static func trashItems(
        _ items: [TrashInput],
        cancellation: TrashCancellationToken,
        progress: @Sendable @escaping (Int, Int) -> Void
    ) async -> TrashOutcome {
        var successes: [TrashSuccess] = []
        var failures: [TrashFailure] = []
        let total = items.count

        for (index, input) in items.enumerated() {
            if await cancellation.isCancelled() {
                return TrashOutcome(successes: successes, failures: failures, cancelled: true)
            }

            let snapshot = input.snapshot
            let result = await trashOne(snapshot: snapshot)
            switch result {
            case .success(let trashURL):
                // originalFullPath = 重组 root path + relativePath; caller 拼装时已存,
                // 但 service 层无 root path 文本只有 rootBookmark, 必须 resolve 一次
                if let origPath = composeOriginalFullPath(snapshot: snapshot) {
                    successes.append(TrashSuccess(
                        originalFullPath: origPath,
                        trashURL: trashURL,
                        snapshot: snapshot,
                        groupKey: input.groupKey
                    ))
                } else {
                    // 极端: trash 已成功但 originalFullPath 重组失败 — 视作半成功记 failure 避免撤销时无 target
                    failures.append(TrashFailure(
                        filename: snapshot.filename,
                        relativePath: snapshot.relativePath,
                        reason: "trash succeeded but original path reconstruction failed"
                    ))
                }
            case .failure(let reason):
                failures.append(TrashFailure(
                    filename: snapshot.filename,
                    relativePath: snapshot.relativePath,
                    reason: reason
                ))
            }

            // 每 50 张 publish 进度
            if (index + 1) % 50 == 0 || index == total - 1 {
                progress(index + 1, total)
            }
        }

        return TrashOutcome(successes: successes, failures: failures, cancelled: false)
    }

    private enum TrashOneResult {
        case success(trashURL: URL)
        case failure(reason: String)
    }

    /// 单 member trash. 复刻 DedupPass.computeSha 的 sandbox scope 模式.
    private static func trashOne(snapshot: IndexedImageSnapshot) async -> TrashOneResult {
        await Task.detached(priority: .userInitiated) {
            var stale = false
            guard let rootURL = try? URL(
                resolvingBookmarkData: snapshot.urlBookmark,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &stale
            ) else {
                return TrashOneResult.failure(reason: "bookmark resolve failed (stale=\(stale))")
            }
            let didStart = rootURL.startAccessingSecurityScopedResource()
            defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }
            guard didStart else {
                return TrashOneResult.failure(reason: "scope access denied (volume not mounted?)")
            }
            let fileURL = rootURL.appendingPathComponent(snapshot.relativePath)

            var trashURL: NSURL?
            do {
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: &trashURL)
            } catch {
                let ns = error as NSError
                return TrashOneResult.failure(reason: "trashItem failed (domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription))")
            }
            guard let trashed = trashURL as URL? else {
                return TrashOneResult.failure(reason: "trashItem returned no resultingURL")
            }
            return TrashOneResult.success(trashURL: trashed)
        }.value
    }

    /// 重组删前原 fullPath (撤销 moveItem target).
    /// 走 resolve bookmark 拿 rootURL.path + 拼 relativePath, 与 spike 模式一致.
    private static func composeOriginalFullPath(snapshot: IndexedImageSnapshot) -> String? {
        var stale = false
        guard let rootURL = try? URL(
            resolvingBookmarkData: snapshot.urlBookmark,
            options: [.withSecurityScope],
            bookmarkDataIsStale: &stale
        ) else { return nil }
        return rootURL.appendingPathComponent(snapshot.relativePath).path
    }
}
```

- [ ] **步骤 3.2.b: build + commit**

```bash
make build 2>&1 | tail -5
git add Glance/Dedup/TrashService.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step3.2): TrashService.trashItems 主路径 + scope 模式复刻 DedupPass.computeSha

全项目首个调 FileManager.trashItem 的代码. Sandbox scope 模式 (resolveBookmark
+ startAccessing + appendingPathComponent + defer stop) 严格复刻 DedupPass.computeSha
(DedupPass.swift:107-118), 任务 2 步骤 1 spike 已实证可行.

member 级 best-effort: 个别失败累积进 failures (卷只读 / iCloud / scope denied),
不中断其余. 每 50 member publish 进度 + 每 member 检 cancellation token.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 3.3: TrashService.restoreItems 撤销路径

- [ ] **步骤 3.3.a: 在 `TrashService.swift` `trashItems` 后加 `restoreItems` 方法**

```swift
    /// 从废纸篓恢复 (撤销). 把每个 TrashSuccess.trashURL 移回 originalFullPath.
    /// P2-1 target 已占用 policy (codex review 第一轮 + design 6 节): 失败累积报告,
    /// **不擅自改名 / 不擅自覆盖**.
    static func restoreItems(
        _ successes: [TrashSuccess],
        cancellation: TrashCancellationToken
    ) async -> RestoreOutcome {
        var restored: [RestoreSuccess] = []
        var failed: [RestoreFailure] = []

        for success in successes {
            if await cancellation.isCancelled() {
                return RestoreOutcome(successes: restored, failures: failed, cancelled: true)
            }

            let result = await restoreOne(success: success)
            switch result {
            case .success:
                restored.append(RestoreSuccess(
                    originalFullPath: success.originalFullPath,
                    snapshot: success.snapshot,
                    groupKey: success.groupKey
                ))
            case .failure(let reason):
                failed.append(RestoreFailure(
                    originalFullPath: success.originalFullPath,
                    reason: reason
                ))
            }
        }

        return RestoreOutcome(successes: restored, failures: failed, cancelled: false)
    }

    private enum RestoreOneResult {
        case success
        case failure(reason: String)
    }

    /// 单 member restore. 复刻 trashOne sandbox scope 模式 + FileManager.moveItem.
    private static func restoreOne(success: TrashSuccess) async -> RestoreOneResult {
        await Task.detached(priority: .userInitiated) {
            var stale = false
            guard let rootURL = try? URL(
                resolvingBookmarkData: success.snapshot.urlBookmark,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &stale
            ) else {
                return RestoreOneResult.failure(reason: "bookmark resolve failed (stale=\(stale))")
            }
            let didStart = rootURL.startAccessingSecurityScopedResource()
            defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }
            guard didStart else {
                return RestoreOneResult.failure(reason: "scope access denied (volume not mounted?)")
            }

            let targetURL = URL(fileURLWithPath: success.originalFullPath)
            // P2-1: target 已被占用 → FileManager.moveItem 抛 NSFileWriteFileExistsError, 不改名不覆盖
            if FileManager.default.fileExists(atPath: targetURL.path) {
                return RestoreOneResult.failure(reason: "target path already occupied (please handle via Finder)")
            }

            do {
                try FileManager.default.moveItem(at: success.trashURL, to: targetURL)
                return RestoreOneResult.success
            } catch {
                let ns = error as NSError
                return RestoreOneResult.failure(reason: "moveItem failed (domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription))")
            }
        }.value
    }
```

- [ ] **步骤 3.3.b: build + commit**

```bash
make build 2>&1 | tail -5
git add Glance/Dedup/TrashService.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step3.3): TrashService.restoreItems 撤销路径 + P2-1 target 占用 policy

撤销路径: 把 TrashSuccess.trashURL 移回 originalFullPath. 复刻 trashOne sandbox
scope 模式 + FileManager.moveItem.

P2-1 target 已占用 policy (codex review 第一轮 + design 6 节): pre-check
fileExists(atPath:), 真占用直接累积 RestoreFailure(reason: "...please handle via
Finder"), 不擅自改名不覆盖.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 3.4: 一次性 swift 脚本验 TrashService 完整 round-trip

- [ ] **步骤 3.4.a: 临时建 `_SpikeTask2TrashService.swift` 验完整链**

```swift
//
//  _SpikeTask2TrashService.swift
//  Glance
//
//  M4 任务 2 步骤 3 — TrashService trash + restore 完整 round-trip + 50 张批量进度.
//

import Foundation

nonisolated enum SpikeTask2TrashService {
    static func run(indexStore: IndexStore) async {
        print("[Spike-T2-TS] start TrashService round-trip")
        do {
            // 找 1 个 dedup_canonical=0 副本
            let rows = try indexStore.fetchDuplicateGroups()
            guard let first = rows.first else {
                print("[Spike-T2-TS] no dup groups — need real duplicates")
                return
            }
            let members = try indexStore.fetchDuplicateGroupMembers(sha256: first.contentSha256)
            guard let dup = members.first(where: { !$0.dedupCanonical }) else {
                print("[Spike-T2-TS] no duplicate member")
                return
            }
            let folderId: Int64 = try indexStore.sync { db in
                let stmt = try db.prepare("SELECT folder_id FROM images WHERE id = ? LIMIT 1;")
                defer { sqlite3_finalize(stmt) }
                try checkBind(sqlite3_bind_int64(stmt, 1, dup.id), index: 1, db: db)
                guard sqlite3_step(stmt) == SQLITE_ROW else { throw NSError(domain: "spike", code: 99) }
                return sqlite3_column_int64(stmt, 0)
            }
            guard let snap = try indexStore.fetchSnapshotForRestore(folderId: folderId, relativePath: dup.relativePath) else {
                print("[Spike-T2-TS] ❌ fetchSnapshot returned nil")
                return
            }
            let token = TrashCancellationToken()
            let input = TrashService.TrashInput(snapshot: snap, groupKey: GroupKey(fileSize: snap.fileSize, format: snap.format))

            // 1. trash
            print("[Spike-T2-TS] trashing 1 file…")
            let trashOutcome = await TrashService.trashItems([input], cancellation: token) { done, total in
                print("[Spike-T2-TS] progress: \(done)/\(total)")
            }
            print("[Spike-T2-TS] trash result: successes=\(trashOutcome.successCount) failures=\(trashOutcome.failureCount) cancelled=\(trashOutcome.cancelled)")
            for f in trashOutcome.failures {
                print("[Spike-T2-TS]   ❌ failure: \(f.filename) — \(f.reason)")
            }
            guard !trashOutcome.successes.isEmpty else {
                print("[Spike-T2-TS] no successes — abort")
                return
            }

            // 2. restore
            print("[Spike-T2-TS] restoring 1 file…")
            let restoreOutcome = await TrashService.restoreItems(trashOutcome.successes, cancellation: token)
            print("[Spike-T2-TS] restore result: successes=\(restoreOutcome.successCount) failures=\(restoreOutcome.failureCount)")
            for f in restoreOutcome.failures {
                print("[Spike-T2-TS]   ❌ restore failure: \(f.originalFullPath) — \(f.reason)")
            }
            print("[Spike-T2-TS] done")
        } catch {
            print("[Spike-T2-TS] ❌ FAILED: \(error)")
        }
    }
}
```

- [ ] **步骤 3.4.b: 临时 AppDelegate 接线 + 运行 + 看 console + 清理**

Console 看到 `successes=1 failures=0` 即 trash + restore 全链通过。

```bash
rm Glance/_SpikeTask2TrashService.swift
git checkout Glance/GlanceApp.swift
make build
git commit --allow-empty -m "$(cat <<'EOF'
verify(M4-task2-step3.4): TrashService trash + restore round-trip 验证通过

spike 脚本 (跑完已 git rm) 验证: TrashService.trashItems 1 个真实副本 →
FileManager.trashItem 成功 + 返回 trashURL; TrashService.restoreItems 把它
moveItem 回原 path → restore 成功. 进度 callback 触发, 取消 token 链路通.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push
```

---

## 步骤 4 — DuplicateOverviewModel 增量 (勾选 + trashSelected + undo + 取消)

> **为什么这一步**: model 是 view 跟 service 之间的桥, 把勾选状态 / 删除中态 / lastTrashOutcome / undo 流程都封装好后, view 层只需绑 model state + 调主入口 → 单文件聚焦 UI 改动到步骤 5。本步独立可 ship = 编译通过 + scaffolding 各方法接线正确 + 现有任务 1 load / scheduleReload 路径不破。
>
> **本步用户感知**: 无 UI 变化 (view 层步骤 5 才接 model 新 API)。

**Files:**
- Modify: `Glance/Dedup/DuplicateOverviewModel.swift`

### 步骤 4.1: 加 selectedSha256s + trashState 状态

- [ ] **步骤 4.1.a: 在 `DuplicateOverviewModel.swift` `state` 后 `indexStore` 前加新 @Published**

定位 `@Published private(set) var state: DuplicateOverviewState = .idle` 这行,在它下方插入:

```swift
    /// M4 任务 2 — 勾选的重复组 (sha256). 整组勾选 D28: 用户选「这组要清掉副本」,
    /// 不给单文件 checkbox.
    @Published private(set) var selectedSha256s: Set<String> = []

    /// M4 任务 2 — 删除中态状态机.
    @Published private(set) var trashState: TrashOperationState = .idle

    /// M4 任务 2 — 桥给 ContentView 渲染 banner. trashSelected 完成时 set,
    /// ContentView .onChange(of: model.lastTrashOutcome?.id) 走轻量 UUID 比对 (codex P2-01:
    /// 不深比含 BLOB 的 payload 避大 Data 比较 + 同 outcome 不触发).
    /// 用户点 banner [×] 或 [撤销] 完成后 ContentView 不清此值 (model 内部下次 trashSelected 覆盖即可) —
    /// banner 视觉 dismiss 走 ContentView 局部 state.
    @Published private(set) var lastTrashOutcome: TrashOutcomeEvent?

    /// 删除中的取消 token (引用类型,actor; cancelTrash 调它).
    private var currentCancellationToken: TrashCancellationToken?

    private weak var folderStoreIndexBridge: FolderStoreIndexBridge?
```

- [ ] **步骤 4.1.b: 加 `TrashOperationState` enum (同文件末尾)**

```swift
/// M4 任务 2 — 删除中状态机.
enum TrashOperationState: Equatable {
    /// 待操作 (无勾选 / 勾选未触发)
    case idle
    /// 删除中: progress = (已处理, 总数); cancellable = true 时取消按钮可点
    case trashing(done: Int, total: Int)
    /// 删除已完成 (outcome 已 publish 给 lastTrashOutcome), 待 model 清回 .idle
    case completed
}

/// M4 任务 2 — 撤销 banner 事件载体 (codex P2-01: 轻量 UUID 比对避深比 BLOB payload).
/// trashSelected 完成 set 一次 (undoResult=nil banner 显「已移 N 张到废纸篓 + [撤销] [×]」),
/// undo(outcome:) 完成 set 另一次 (undoResult≠nil banner 显「撤销完成 N 张 (+M 失败)」简短确认).
/// ContentView .onChange(of: model.lastTrashOutcome?.id) 走 id 比对触发动画 + 重置 timer.
struct TrashOutcomeEvent: Identifiable {
    let id: UUID
    let trash: TrashOutcome
    /// nil = trash 阶段; 非 nil = undo 阶段, 含 restore 结果 (失败累积给 banner 副文案 codex P1-02).
    let undoResult: RestoreOutcome?
}
```

- [ ] **步骤 4.1.c: build + commit**

```bash
make build 2>&1 | tail -5
git add Glance/Dedup/DuplicateOverviewModel.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step4.1): DuplicateOverviewModel 加勾选集合 + trashState 状态机

@Published selectedSha256s: Set<String> (整组勾选 D28; 不给单文件 checkbox)
@Published trashState: TrashOperationState (idle / trashing(done,total) / completed)
@Published lastTrashOutcome: TrashOutcome? (桥给 ContentView 渲染 banner)
currentCancellationToken: TrashCancellationToken? (cancelTrash 调它)
folderStoreIndexBridge: weak (步骤 4.5 undo 降级路径 requestRescan 调它)

任务 1 既有 state / load / scheduleReload / attach 不动.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 4.2: 改 attach 持 bridge 弱引用 + 加 toggleSelection / clearSelection

- [ ] **步骤 4.2.a: 改 `attach(indexStore:bridge:)` 末尾,把 bridge 持到 weak 用 (撤销降级 requestRescan 用)**

定位:
```swift
    func attach(indexStore: IndexStore, bridge: FolderStoreIndexBridge) {
        guard self.indexStore == nil else { return }
        self.indexStore = indexStore
        self.bridge = bridge
```

在 `self.bridge = bridge` 后加:
```swift
        self.folderStoreIndexBridge = bridge  // 任务 2 撤销降级 requestRescan 用
```

- [ ] **步骤 4.2.b: 在 model class 内 `// MARK: - load / scheduleReload` 段前加新 MARK 段 + 方法**

```swift
    // MARK: - M4 任务 2 — 勾选 / 取消勾选

    func toggleSelection(sha256: String) {
        if selectedSha256s.contains(sha256) {
            selectedSha256s.remove(sha256)
        } else {
            selectedSha256s.insert(sha256)
        }
    }

    func clearSelection() {
        selectedSha256s.removeAll()
    }

    /// view 用 — 已勾选的副本数 (banner / 按钮文案「移入废纸篓 (N 张)」用).
    var selectedDuplicateCount: Int {
        groups.filter { selectedSha256s.contains($0.id) }
            .reduce(into: 0) { $0 += $1.duplicates.count }
    }

    /// view 用 — 已勾选可省空间总和 (按钮副文案 / banner 用).
    var selectedReclaimableBytes: Int64 {
        groups.filter { selectedSha256s.contains($0.id) }
            .reduce(into: Int64(0)) { $0 += $1.reclaimableBytes }
    }
```

- [ ] **步骤 4.2.c: build + commit**

```bash
make build 2>&1 | tail -5
git add Glance/Dedup/DuplicateOverviewModel.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step4.2): DuplicateOverviewModel 勾选 toggle / clear + 计算 accessor

toggleSelection(sha256:) / clearSelection() — 整组勾选 D28.
selectedDuplicateCount: 已勾选组的副本总数 (按钮文案「移入废纸篓 (N 张)」用).
selectedReclaimableBytes: 已勾选可省空间 (按钮副文案 / banner 数字用).

attach 末尾持 weak folderStoreIndexBridge (撤销降级 requestRescan 用).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 4.3: trashSelected 主入口 — 收集 + 预 fetch snapshot + trash + 删 DB + reEvaluate + load

- [ ] **步骤 4.3.a: 在 model 末尾 `// MARK: - helpers` 前加新 MARK 段**

```swift
    // MARK: - M4 任务 2 — 删除主入口 trashSelected

    /// 用户点「移入废纸篓」: 收集所选组的副本 → 预 fetch 每 member snapshot →
    /// TrashService.trashItems → 删 DB rows → DedupPass.reEvaluateGroup 受影响组 →
    /// promoteOrphanDuplicates 兜底 → bridge.triggerIndexChanged() 跨视图广播 (codex P1-01) →
    /// load() 刷新 → set lastTrashOutcome 触发 banner.
    /// design 5.2 数据流主路径.
    func trashSelected() async {
        guard let store = indexStore else { return }
        guard let bridge = folderStoreIndexBridge else { return }
        guard !selectedSha256s.isEmpty else { return }

        // 1. 收集所选组的副本 + 预 fetch snapshot 组装 TrashInput (步骤 2.0 后用 dup.folderId 直接 carry)
        let snapshotGroups = self.groups
        let snapshotSelected = self.selectedSha256s
        let inputs = await collectTrashInputs(store: store, groups: snapshotGroups, selectedSha256s: snapshotSelected)
        guard !inputs.isEmpty else {
            // 全 race 失败 (snapshot fetch 全 nil); 标 completed, banner 不出
            trashState = .completed
            return
        }

        // 2. 创建取消 token + 进入删除中态
        let token = TrashCancellationToken()
        currentCancellationToken = token
        trashState = .trashing(done: 0, total: inputs.count)

        // 3. TrashService.trashItems 主路径
        let outcome = await TrashService.trashItems(
            inputs,
            cancellation: token
        ) { [weak self] done, total in
            Task { @MainActor [weak self] in
                self?.trashState = .trashing(done: done, total: total)
            }
        }

        // 4. 对成功的 member 删 DB row + 收集受影响 groupKey
        var affectedGroups: Set<GroupKey> = []
        for success in outcome.successes {
            do {
                try store.deleteImage(folderId: success.snapshot.folderId, relativePath: success.snapshot.relativePath)
                affectedGroups.insert(success.groupKey)
            } catch {
                // DB delete 失败 — banner 已展示 trash success, 不再单独 surface; log only
                print("[M4-T2] deleteImage failed for id=\(success.snapshot.folderId)/\(success.snapshot.relativePath): \(error)")
            }
        }

        // 5. 受影响组 reEvaluateGroup (受影响 (file_size, format) 重决议)
        await Task.detached(priority: .utility) {
            for key in affectedGroups {
                DedupPass.reEvaluateGroup(store: store, fileSize: key.fileSize, format: key.format)
            }
            try? store.promoteOrphanDuplicates()
        }.value

        // 6. 跨视图广播 (codex P1-01): 通知所有 observer 刷新, 智能文件夹 / 搜索 grid 自动反映新状态
        bridge.triggerIndexChanged()

        // 7. 总览刷新
        await load()

        // 8. publish outcome (轻量 event 含 outcomeId UUID + payload, codex P2-01 修)
        lastTrashOutcome = TrashOutcomeEvent(id: UUID(), trash: outcome, undoResult: nil)
        trashState = .completed
        currentCancellationToken = nil
        selectedSha256s.removeAll()
    }

    /// 收集 trashSelected 所需的 TrashInput 数组 (整组勾选 → 该组所有副本预 fetch snapshot).
    /// 步骤 2.0 已把 folderId 加进 DuplicateGroupMember struct, 这里直接用 dup.folderId
    /// 不反查 (codex P1-03 + P2-02 合一修).
    private nonisolated func collectTrashInputs(
        store: IndexStore,
        groups: [DuplicateGroup],
        selectedSha256s: Set<String>
    ) async -> [TrashService.TrashInput] {
        let selectedGroups = groups.filter { selectedSha256s.contains($0.id) }
        var inputs: [TrashService.TrashInput] = []
        for group in selectedGroups {
            for dup in group.duplicates {
                guard let snap = try? store.fetchSnapshotForRestore(
                    folderId: dup.folderId,
                    relativePath: dup.relativePath
                ) else {
                    continue
                }
                inputs.append(TrashService.TrashInput(
                    snapshot: snap,
                    groupKey: GroupKey(fileSize: snap.fileSize, format: snap.format)
                ))
            }
        }
        return inputs
    }

    /// 用户点删除中态的「取消」按钮 → token.cancel(). TrashService 内部下次 isCancelled
    /// 返回 true → 中止剩余 member trash, 返回 outcome.cancelled=true.
    func cancelTrash() async {
        await currentCancellationToken?.cancel()
    }
```

- [ ] **步骤 4.3.b: build (预期可能撞 Swift sync nonisolated 函数 capture 问题 — 见步骤 4.3.c)**

```bash
make build 2>&1 | tail -10
```

- [ ] **步骤 4.3.c: 若 build 报 "nonisolated method cannot access MainActor-isolated property" — 修 collectTrashInputs 内取 snapshot 部分**

预期: `collectTrashInputs` 标 `nonisolated` 但调 `await MainActor.run { ... self.groups ... }` 时,如果 Swift 编译器报错该闭包不能访问 MainActor 状态。修法: 改成参数传入:

把方法签名改成:
```swift
    private nonisolated func collectTrashInputs(
        store: IndexStore,
        groups: [DuplicateGroup],
        selectedSha256s: Set<String>
    ) async -> [TrashService.TrashInput] {
        let selectedGroups = groups.filter { selectedSha256s.contains($0.id) }
        // ... 剩余逻辑不变
    }
```

调用方 (trashSelected 内) 改成:
```swift
        let snapshotGroups = self.groups
        let snapshotSelected = self.selectedSha256s
        let inputs = await collectTrashInputs(store: store, groups: snapshotGroups, selectedSha256s: snapshotSelected)
```

- [ ] **步骤 4.3.d: build 通过后 commit**

```bash
make build 2>&1 | tail -5
git add Glance/Dedup/DuplicateOverviewModel.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step4.3): DuplicateOverviewModel.trashSelected 主路径 + cancelTrash

trashSelected: 收集所选组副本 + 预 fetch IndexedImageSnapshot + TrashService.trashItems
+ 删 DB row + 收集受影响 groupKey → DedupPass.reEvaluateGroup + promoteOrphanDuplicates
兜底 → load() 刷新 → set lastTrashOutcome 触发 ContentView banner.

collectTrashInputs: 走 fetchSnapshotForRestore 预 fetch 15 列 snapshot. 反查
folder_id by images.id (DuplicateGroupMember struct 任务 1 未存 folder_id, 边界保留).

cancelTrash: 调 TrashCancellationToken.cancel(). TrashService 下次 check 中止剩余.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 4.4: undo D34 显式回补 contract — restoreItems → restoreImageFromSnapshot 首选 / requestRescan 降级

- [ ] **步骤 4.4.a: 在 model 内 `cancelTrash` 后加 undo 方法**

```swift
    /// 用户点 banner [撤销]: D34 显式回补 contract.
    /// 1. TrashService.restoreItems 把废纸篓 URL move 回原 fullPath
    /// 2. 对每个 restore 成功 member: restoreImageFromSnapshot 首选 (同步返回 row id) /
    ///    UNIQUE 冲突或失败 → requestRescan 降级 (async throws 返回时 row 已恢复或明确失败)
    /// 3. 对每个受影响 groupKey: reEvaluateGroup → bridge.triggerIndexChanged 跨视图广播 →
    ///    总览刷新 → publish undo 结果到 lastTrashOutcome (codex P1-02 修双失败可见)
    func undo(outcome: TrashOutcome) async {
        guard let store = indexStore else { return }
        guard let bridge = folderStoreIndexBridge else { return }

        let token = TrashCancellationToken()  // undo 阶段独立 token (用户不再"取消", 但保持 service 接口一致)

        // 1. restore 文件回原 path
        var restoreOutcome = await TrashService.restoreItems(outcome.successes, cancellation: token)

        // 2. 对 restore 成功的 member 显式回补 DB row; 双失败累积进 dbFailures
        var affectedGroups: Set<GroupKey> = []
        var dbFailures: [RestoreFailure] = []
        for success in restoreOutcome.successes {
            do {
                _ = try store.restoreImageFromSnapshot(success.snapshot)
                affectedGroups.insert(success.groupKey)
            } catch {
                // 首选失败 — UNIQUE 冲突 (FSEvents 抢先 ingest) 或其它 → 降级 requestRescan
                do {
                    _ = try await bridge.requestRescan(
                        folderId: success.snapshot.folderId,
                        relativePath: success.snapshot.relativePath
                    )
                    affectedGroups.insert(success.groupKey)
                } catch let rescanError {
                    // 双失败 (codex P1-02): 文件已 restore 回原 path 但 DB row 没回, 用户必须感知.
                    // 累积进 dbFailures, banner 副文案展示「N 张 DB 同步失败 — 文件在但索引未恢复」.
                    print("[M4-T2 undo] DOUBLE FAILURE for \(success.originalFullPath): snapshot=\(error) rescan=\(rescanError)")
                    dbFailures.append(RestoreFailure(
                        originalFullPath: success.originalFullPath,
                        reason: "DB sync failed (file restored but index missing)"
                    ))
                }
            }
        }

        // 把 dbFailures 合进 restoreOutcome.failures 让 banner 一并展示
        if !dbFailures.isEmpty {
            restoreOutcome = RestoreOutcome(
                successes: restoreOutcome.successes,
                failures: restoreOutcome.failures + dbFailures,
                cancelled: restoreOutcome.cancelled
            )
        }

        // 3. 受影响组 reEvaluateGroup
        await Task.detached(priority: .utility) {
            for key in affectedGroups {
                DedupPass.reEvaluateGroup(store: store, fileSize: key.fileSize, format: key.format)
            }
            try? store.promoteOrphanDuplicates()
        }.value

        // 4. 跨视图广播 (codex P1-01)
        bridge.triggerIndexChanged()

        // 5. 总览刷新
        await load()

        // 6. publish undo 结果给 banner — 不静默 nil, 让 ContentView 渲染撤销确认文案 +
        //    若有失败 (含双失败 dbFailures) 副文案 surface 让用户感知 (codex P1-02 修)
        lastTrashOutcome = TrashOutcomeEvent(id: UUID(), trash: outcome, undoResult: restoreOutcome)
    }
```

- [ ] **步骤 4.4.b: build + commit**

```bash
make build 2>&1 | tail -5
git add Glance/Dedup/DuplicateOverviewModel.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step4.4): DuplicateOverviewModel.undo D34 显式回补 contract

撤销链: TrashService.restoreItems 把文件回原 path → 对每个 success member 走
restoreImageFromSnapshot 首选 (同步重建 row 全 15 列保真) → UNIQUE 冲突 / 其它失败
→ FolderStoreIndexBridge.requestRescan 降级 (async throws 返回时 row 已恢复) →
DedupPass.reEvaluateGroup 受影响组 + promoteOrphanDuplicates 兜底 → load() 刷新 →
清 lastTrashOutcome (ContentView 自然 dismiss banner).

D34 contract: 禁止依赖 FSEvents 时机, 走显式回补保 V2 找相似图 / M3 搜索元数据
(dedup_canonical / feature_print 系列 / exif_capture_date) 全列保真.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push
```

---

## 步骤 5 — DuplicateOverviewView 增量 + ContentView 顶层 banner overlay (任务 2 完整 ship 点)

> **为什么这一步**: 步骤 1-4 把数据层 + service + model 全做好,本步是用户首次完整感知任务 2 的 ship 点。view 加 cell checkbox (组级) + 「移入废纸篓」按钮 + 删除中态; ContentView 加全局 banner overlay; banner 跨视图持久; 撤销链联调。
>
> **本步用户感知**: ✅ **任务 2 完整端到端**首次可感知 — 勾组 → 点按钮 → 真实文件进废纸篓 + 总览少一组 + banner 顶部出现 + 点撤销 → 文件回 + 总览回原态。

**Files:**
- Modify: `Glance/Dedup/DuplicateOverviewView.swift`
- Create: `Glance/Dedup/TrashUndoBanner.swift`
- Modify: `Glance/ContentView.swift`
- Modify: `Glance/DesignSystem.swift` (DS.Dedup 加 banner / button / checkbox 常量)

### 步骤 5.1: DesignSystem.swift 加 banner / button / checkbox 常量

- [ ] **步骤 5.1.a: 在 `DesignSystem.swift` 的 `enum Dedup` 末尾 (在 `thumbnailPlaceholderOpacity: 0.15` 后) 加新常量**

```swift
        // MARK: - M4 任务 2 — 删除 / 撤销 UI 常量

        /// 组级 checkbox 高度
        static let checkboxRowHeight: CGFloat = 24
        /// 选中态 accent 色 (sidebar 入口选中色 mirror)
        static let selectionAccentColor: SwiftUI.Color = .accentColor
        /// 「移入废纸篓」按钮高度
        static let trashButtonHeight: CGFloat = 32
        /// 按钮圆角
        static let trashButtonCornerRadius: CGFloat = 8
        /// 删除中进度条 tint
        static let progressBarTint: SwiftUI.Color = .accentColor
        /// 撤销 banner 默认 auto-dismiss 秒数; 0 = 纯手动 dismiss.
        /// **D33 拍板 30s** (codex review 第一/二轮 toast 1.5s 太短 → banner 跨视图 + 长时长).
        static let bannerAutoDismissSeconds: TimeInterval = 30
        /// banner 最大宽度 (居中 overlay 限宽)
        static let bannerMaxWidth: CGFloat = 480
        /// banner 圆角
        static let bannerCornerRadius: CGFloat = 12
        /// banner 半透明背景 opacity
        static let bannerBackgroundOpacity: Double = 0.92
        /// banner 距顶部偏移 (overlay 顶 + 内边距)
        static let bannerTopPadding: CGFloat = 16
        /// banner 内水平内边距
        static let bannerHorizontalPadding: CGFloat = 16
        /// banner 内垂直内边距
        static let bannerVerticalPadding: CGFloat = 12
        /// banner 中按钮间距
        static let bannerButtonSpacing: CGFloat = 12
```

- [ ] **步骤 5.1.b: build + commit**

```bash
make build 2>&1 | tail -5
git add Glance/DesignSystem.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step5.1): DS.Dedup 加任务 2 banner / button / checkbox 常量

bannerAutoDismissSeconds: 30 (D33 拍板, 取代 toast 1.5s).
bannerMaxWidth / bannerCornerRadius / bannerBackgroundOpacity / bannerTopPadding /
bannerHorizontalPadding / bannerVerticalPadding / bannerButtonSpacing — overlay 样式.
trashButtonHeight / trashButtonCornerRadius / progressBarTint — 删除按钮 / 进度条.
checkboxRowHeight / selectionAccentColor — 组级 checkbox.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 5.2: TrashUndoBanner.swift — ContentView 级 overlay banner

- [ ] **步骤 5.2.a: 新建 `Glance/Dedup/TrashUndoBanner.swift`**

```swift
//
//  TrashUndoBanner.swift
//  Glance
//
//  M4 任务 2 — ContentView 级 overlay banner (D33).
//  「已移 N 张到废纸篓 [撤销] [×]」+ 副文案 (「+M 张失败 / 已取消」) + 30s auto-dismiss.
//  快速看图器在场不可见 (NSWindow 独立, ZStack 外) 但 state 保留, 关闭后回归.
//  纯展示, state 由 ContentView 拥有.
//

import SwiftUI

struct TrashUndoBanner: View {
    let event: TrashOutcomeEvent
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DS.Dedup.bannerButtonSpacing) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(mainText)
                    .font(.body.weight(.medium))
                if let sub = subText {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: DS.Spacing.zero)
            if isUndoPhase {
                // undo 阶段不再显「撤销」按钮 (撤销已发生, 只让用户 [×] 关 banner)
            } else {
                Button("撤销") { onUndo() }
                    .buttonStyle(.borderedProminent)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Dedup.bannerHorizontalPadding)
        .padding(.vertical, DS.Dedup.bannerVerticalPadding)
        .frame(maxWidth: DS.Dedup.bannerMaxWidth)
        .background(.thinMaterial.opacity(DS.Dedup.bannerBackgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.bannerCornerRadius))
    }

    private var isUndoPhase: Bool { event.undoResult != nil }

    /// trash 阶段: 「已移 N 张到废纸篓」; undo 阶段: 「撤销完成 N 张」
    private var mainText: String {
        if let restore = event.undoResult {
            return "撤销完成 \(restore.successCount) 张"
        }
        return "已移 \(event.trash.successCount) 张到废纸篓"
    }

    /// 副文案统一汇总: trash 失败 + 取消 + (undo 阶段) restore 失败 + DB 双失败
    private var subText: String? {
        var parts: [String] = []
        if event.trash.failureCount > 0 {
            parts.append("\(event.trash.failureCount) 张未移入")
        }
        if event.trash.cancelled {
            parts.append("已取消")
        }
        if let restore = event.undoResult {
            if restore.failureCount > 0 {
                // codex P1-02 修双失败感知: failures 含 RestoreFailure (含 dbFailures 双失败原因)
                parts.append("\(restore.failureCount) 张撤销失败")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
```

- [ ] **步骤 5.2.b: build + commit**

```bash
make build 2>&1 | tail -5
git add Glance/Dedup/TrashUndoBanner.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step5.2): TrashUndoBanner ContentView 级 overlay view

「已移 N 张到废纸篓 [撤销] [×]」+ 副文案 (失败数 / 已取消).
.thinMaterial 半透明背景 + 圆角 + 最大宽度限制.
状态由 ContentView 拥有, 本 view 纯展示.

D33 跨视图持久: 五态可见 (V1 folder / 智能文件夹 / 临时结果 / 搜索 / 重复清理总览);
快速看图器是独立 NSWindow 物理不可见 (ZStack 外) 但 state 保留, 快速看图器关后回归.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 5.3: DuplicateOverviewView 加组级 checkbox + 「移入废纸篓」按钮 + 删除中态

- [ ] **步骤 5.3.a: 改 `DuplicateOverviewView.swift` 顶部统计条加按钮 / 进度条**

定位现有 `statsBar` computed property:
```swift
    private var statsBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text("\(model.groupCount) 组重复")
                .font(DS.Dedup.statsBarFont)
            Text("·")
                .foregroundStyle(.secondary)
            Text("可省 \(formattedReclaimable)")
                .font(DS.Dedup.statsBarFont)
                .foregroundStyle(SwiftUI.Color.accentColor)
        }
        .padding(.vertical, DS.Spacing.xs)
    }
```

改成 (加 Spacer + trash 按钮 / 删除中进度条):
```swift
    private var statsBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text("\(model.groupCount) 组重复")
                .font(DS.Dedup.statsBarFont)
            Text("·")
                .foregroundStyle(.secondary)
            Text("可省 \(formattedReclaimable)")
                .font(DS.Dedup.statsBarFont)
                .foregroundStyle(SwiftUI.Color.accentColor)
            Spacer(minLength: DS.Spacing.zero)
            trashAction
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    @ViewBuilder
    private var trashAction: some View {
        switch model.trashState {
        case .idle, .completed:
            Button {
                Task { await model.trashSelected() }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: DS.Icon.trash)
                    Text("移入废纸篓 (\(model.selectedDuplicateCount) 张)")
                }
                .frame(height: DS.Dedup.trashButtonHeight)
                .padding(.horizontal, DS.Spacing.md)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.selectedSha256s.isEmpty)
        case .trashing(let done, let total):
            HStack(spacing: DS.Spacing.sm) {
                ProgressView(value: Double(done), total: Double(total))
                    .progressViewStyle(.linear)
                    .tint(DS.Dedup.progressBarTint)
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
```

- [ ] **步骤 5.3.b: 改 `DuplicateGroupRowView` 加组级 checkbox**

定位 `private struct DuplicateGroupRowView: View` 的 body, 在 `HStack(alignment: .top, ...)` 上面加 checkbox row:

```swift
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // 任务 2 加: 组级 checkbox
            Toggle(isOn: Binding(
                get: { isSelected },
                set: { _ in onToggleSelection() }
            )) {
                Text("选择此组清掉 \(group.duplicates.count) 张副本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .frame(height: DS.Dedup.checkboxRowHeight)

            HStack(alignment: .top, spacing: DS.Spacing.md) {
                // ... 原有缩略图 + canonical badge 渲染不变
```

`DuplicateGroupRowView` struct 加 `let isSelected: Bool` + `let onToggleSelection: () -> Void` 属性。callsite (DuplicateOverviewView.groupsList) 同步传:

```swift
                ForEach(model.groups) { group in
                    DuplicateGroupRowView(
                        group: group,
                        isSelected: model.selectedSha256s.contains(group.id),
                        onToggleSelection: { model.toggleSelection(sha256: group.id) }
                    )
                }
```

- [ ] **步骤 5.3.c: build + commit**

```bash
make build 2>&1 | tail -5
git add Glance/Dedup/DuplicateOverviewView.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step5.3): DuplicateOverviewView 加组级 checkbox + 「移入废纸篓」按钮 + 删除中态

statsBar 加右侧 trashAction: idle/completed 态显「移入废纸篓 (N 张)」按钮
(disabled when 无勾选); trashing(done,total) 态换 ProgressView + 文案 + 取消按钮.

DuplicateGroupRowView 顶部加组级 Toggle(.checkbox) — 「选择此组清掉 N 张副本」.
D28 整组勾选: 不给单文件 checkbox (完全相同删哪张都一样).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 5.4: ContentView 加全局 banner overlay + lastTrashOutcome 接线

- [ ] **步骤 5.4.a: 在 `ContentView.swift` `@State showSearchOverlay` 后加 `trashUndoBanner` state**

定位:
```swift
    @State private var showSearchOverlay: Bool = false
```

下方加:
```swift
    /// M4 任务 2 — 撤销 banner 全局 state (D33 跨视图持久, 不绑 showDuplicateOverview 生命周期).
    /// duplicateOverviewModel.lastTrashOutcome.id .onChange 触发拷贝 (codex P2-01 用 UUID 比对避深比 BLOB).
    /// 用户点 banner [×] 或 [撤销] 完成 → onDismiss 清回 nil.
    @State private var trashUndoBanner: TrashOutcomeEvent? = nil
    /// banner 30s auto-dismiss timer (cancellable, view 进快速看图器 / 用户切走时不暂停 — D33 简化:
    /// 不引入 快速看图器期间 timer 暂停, banner 状态保留 30s 内有效, 过期视作用户已忽略)
    @State private var bannerDismissTask: Task<Void, Never>? = nil
```

- [ ] **步骤 5.4.b: 在 body 顶层 `.onChange` 段加 `duplicateOverviewModel.lastTrashOutcome` 接线**

定位现有 `.onChange(of: showDuplicateOverview) { ... }` 块, 在它后面加新 .onChange:

```swift
        // codex P2-01 修: 比 id (UUID) 不比整 outcome 深比 BLOB; 同时同 outcome 不触发 (Identifiable + id 比)
        .onChange(of: duplicateOverviewModel.lastTrashOutcome?.id) { _, _ in
            guard let event = duplicateOverviewModel.lastTrashOutcome else { return }
            // 显示条件: trash 阶段成功 ≥1 或 undo 阶段 (无论成败都要 surface)
            let trashHasContent = event.undoResult == nil && event.trash.successCount > 0
            let undoHasContent = event.undoResult != nil
            guard trashHasContent || undoHasContent else { return }
            trashUndoBanner = event
            // 取消上一次 timer (若 banner 接连出现)
            bannerDismissTask?.cancel()
            bannerDismissTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(DS.Dedup.bannerAutoDismissSeconds * 1_000_000_000))
                if !Task.isCancelled {
                    await MainActor.run { trashUndoBanner = nil }
                }
            }
        }
```

- [ ] **步骤 5.4.c: NavigationSplitView **外层** .overlay 加 banner (codex P2-04 拍板)**

> **挂点拍板** (codex P2-04): NavigationSplitView **外层** modifier 链 (mirror 任务 1 `IndexingProgressView` 已有的全局 overlay 模式), 不放 detail closure 内。理由: D33「ContentView 级持久 banner」语义要求 banner 覆盖整个 split view (含 sidebar 区), 不仅 detail pane; 任务 1 IndexingProgressView 走同款模式已 ship 验证。

定位 `body: some View { NavigationSplitView { ... } detail: { ... } }` 整块, 在右大括号 `}` 后链 `.overlay(...)`. 位置在 `.environmentObject(...)` 注入链**之后** (确保 overlay 渲染能拿到注入对象, 与 task 1 IndexingProgressView overlay 顺序一致):

```swift
        NavigationSplitView {
            // sidebar ...
        } detail: {
            // mainContent ...
        }
        // ... 现有 .environmentObject 注入链 ...
        .overlay(alignment: .top) {
            // 任务 2 — 撤销 banner 全局 overlay (D33 跨视图持久)
            if let event = trashUndoBanner {
                TrashUndoBanner(
                    event: event,
                    onUndo: {
                        bannerDismissTask?.cancel()
                        // 不立即清 trashUndoBanner — 等 undo 完成后 model.lastTrashOutcome 重 publish
                        // 触发 .onChange 重赋 event (含 undoResult) 让 banner 切「撤销完成」展示
                        Task { await duplicateOverviewModel.undo(outcome: event.trash) }
                    },
                    onDismiss: {
                        bannerDismissTask?.cancel()
                        trashUndoBanner = nil
                    }
                )
                .padding(.top, DS.Dedup.bannerTopPadding)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(DS.Anim.normal, value: trashUndoBanner?.id)
```

> **动画 value**: 用 `trashUndoBanner?.id` (UUID Equatable) 不用整 event (codex P2-01 避深比 BLOB)。

- [ ] **步骤 5.4.d: build + commit**

```bash
make build 2>&1 | tail -5
git add Glance/ContentView.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-step5.4): ContentView 加全局 TrashUndoBanner overlay + lastTrashOutcome 接线

@State trashUndoBanner: TrashOutcome? + bannerDismissTask (auto-dismiss 30s timer).
.onChange(of: duplicateOverviewModel.lastTrashOutcome) → trashUndoBanner.
overlay(alignment: .top) 渲染 TrashUndoBanner — D33 五态可见 (V1 folder / 智能文件夹
/ 临时结果 / 搜索 / 重复清理总览); 快速看图器独立 NSWindow ZStack 外 物理不可见
但 state 保留.

onUndo: 调 model.undo(outcome:) D34 contract.
onDismiss: 清 trashUndoBanner + cancel timer.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### 步骤 5.5: build 全链 + 真机自闭环验证 5 项 (CC) + PENDING 留军哥本地 5 项

- [ ] **步骤 5.5.a: make build 全链验证**

```bash
make build 2>&1 | tail -5
```

预期 `BUILD SUCCEEDED`. 失败 → 回填错误行号修。

- [ ] **步骤 5.5.b: CC 主 agent 自闭环真机验 5 项**

mirror 任务 1 步骤 4 自闭环模式 (前置: 军哥 Mac mini 解锁 + GUI 可达 + 屏幕未睡眠):

```bash
pkill -9 -f "Glance.app/Contents/MacOS" 2>&1
sleep 2
open -a /Users/sunerpang/projects/claude/glance-v2/build/Glance.app
sleep 5
# 找窗口 wid (owner 是 "一眼" 不是 "Glance")
swift /tmp/list_all.swift | grep "一眼"
# (后续) AX 找侧边栏 → 点重复清理 → 点组 checkbox → 点按钮 → 等几秒 → 截图比对 → 点撤销 → 截图比对
```

CC 自闭环可验 5 项 (军哥解锁后):
1. ✅ 组级 checkbox 渲染 + 勾选高亮
2. ✅ 按钮文案「移入废纸篓 (N 张)」+ disabled 态切换
3. ✅ 点按钮 → 删除中态 (按钮换 progress + 取消) + 总览少一组
4. ✅ 顶部 banner overlay 出现「已移 N 张到废纸篓 [撤销] [×]」
5. ✅ 点撤销 → banner 消失 + 总览回原态 + 文件回原 path

- [ ] **步骤 5.5.c: 加 PENDING 军哥本地补验 5 项**

`specs/PENDING-USER-ACTIONS.md`「Pending」段顶加 (任务 2 卷类型矩阵段下面):

```markdown
### V2 M4 任务 2 — 删除闭环完整端到端真机验

- [ ] (2026-06-16 / `<task2-step5 commit>`) **真机军哥本地补验**:
  1. **跨视图持久 banner** — 移废纸篓出现 banner 后, 切 V1 folder / 智能文件夹 / 触发搜索 / 找类似 → banner 应一直可见可点
  2. **快速看图器在场不可见但状态保留** — 进快速看图器看图 → banner 消失 (independent NSWindow); 关快速看图器 → banner 回归
  3. **30s auto-dismiss** — 不动 banner 30 秒后自动消失; 中途切视图不影响计时 (简化版,timer 不暂停)
  4. **大批量删除取消** — 准备 100+ 张副本 → 全勾选 → 点按钮 → 中途点取消 → 看 outcome.cancelled=true + 已删的入废纸篓 + 剩余不动
  5. **DB 一致性** — 删 N 张后 sqlite3 直查 `SELECT COUNT(*) FROM images` 应 = 原数 - N; banner 撤销后应回到原数; reEvaluateGroup 决议正确 (受影响 sha256 组仍可被 fetchDuplicateGroups 返回 / 或不返回如果只剩 1 张)
  6. **卷类型差异验证** — 步骤 1 PENDING 矩阵 4 项 (APFS / USB / iCloud / fallback) 已通过 (前置门控)
```

- [ ] **步骤 5.5.d: commit 步骤 5 完整 (codex pre-push 拦截 → 修 → push)**

```bash
git add Glance/ContentView.swift specs/PENDING-USER-ACTIONS.md
git commit -m "$(cat <<'EOF'
feat(M4-task2-step5): 任务 2 完整端到端 — 删除闭环 ship 点

DuplicateOverviewView 组级 checkbox + 「移入废纸篓」按钮 + 删除中态 +
TrashUndoBanner ContentView 级 overlay + bannerDismissTask 30s timer +
duplicateOverviewModel.lastTrashOutcome 接线.

CC 主 agent 自闭环验 5 项 (军哥解锁 Mac mini 后跑); 军哥本地补验 5 项写 PENDING
(跨视图持久 banner / 快速看图器期间不可见状态保留 / 30s auto-dismiss / 取消大批量 /
DB 一致性).

任务 2 完整端到端首次可感知: 勾组 → 点按钮 → 文件真进废纸篓 + 总览少一组 +
banner 顶部出现 + 点撤销 → 文件回 + 总览回原态. 初心闭环达成.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push  # codex pre-push 拦截预期 — 修后 push 通过
```

---

## 步骤 6 — /go 收尾

> **为什么这一步**: 任务 2 整体 ship 后跑 `/go` 五步 (CLAUDE.md): verify 三段 + 文档同步 + PENDING + commit + 一段话汇报。本步是 plan 终点。

**Files:**
- Modify: `specs/Roadmap.md` (M4 任务 2 状态「✅ 完成」+ 任务 2 commit hash 范围)
- Modify: `CLAUDE.md` (项目根 — 文件结构同步新增 4 个文件)
- Modify: `specs/v2/2026-06-16-m4-task2-implementation-plan.md` (实施记录 + 6 步 commit hash 填回)
- Modify: `specs/PENDING-USER-ACTIONS.md` (任务 2 commit hash 回填)

### 步骤 6.1: verify 三段

- [ ] **步骤 6.1.a: 跑 `./scripts/verify.sh`**

```bash
./scripts/verify.sh 2>&1 | tail -10
```

预期: 13 passed, 0 failed. Stage 2 build SUCCEEDED + 0 warnings. Stage 1 术语字典检查无禁用词。

### 步骤 6.2: 文档同步 (Roadmap / CLAUDE.md / plan 实施记录)

- [ ] **步骤 6.2.a: 更新 `specs/Roadmap.md` M4 任务 2 状态**

定位「| 🚧 实施中（**M4 · 初心核心闭环**）」行,改成「✅ 已完成 `<task2 commit range>`」+ 6 步 commit hash + 真省空间初心闭环达成。

- [ ] **步骤 6.2.b: 更新 `CLAUDE.md` 文件结构段**

`Glance/Dedup/` 子目录加 4 个新文件:
- `IndexedImageSnapshot.swift` — M4 任务 2 删前 15 字段全保真值类型
- `TrashService.swift` — M4 任务 2 全项目首个碰真实文件服务
- `TrashOutcome.swift` — M4 任务 2 trash / restore 结果值类型 + TrashCancellationToken actor
- `TrashUndoBanner.swift` — M4 任务 2 ContentView 级 overlay banner D33

- [ ] **步骤 6.2.c: 更新本 plan 实施记录段** (本 plan 末尾加「## 实施记录」段填 6 步 commit hash + self-fix 轮次 + codex review 折入)

### 步骤 6.3: PENDING 拆 CC 自验 + 军哥本地补验

(步骤 5.5.c 已写 PENDING 大部分,这里仅核对 commit hash 回填)

### 步骤 6.4: docs-only commit + push

```bash
git add specs/Roadmap.md CLAUDE.md specs/v2/2026-06-16-m4-task2-implementation-plan.md specs/PENDING-USER-ACTIONS.md
git commit -m "$(cat <<'EOF'
docs(M4-task2): 任务 2 收尾 — Roadmap / CLAUDE.md / plan 实施记录 / PENDING

Roadmap M4 任务 2 ✅ 完成 (commit 范围 + 真省空间初心闭环达成).
CLAUDE.md 文件结构同步 IndexedImageSnapshot / TrashService / TrashOutcome /
TrashUndoBanner 4 新文件.
plan 实施记录段: 6 步 commit hash + self-fix 轮次 + codex review 折入.
PENDING: 任务 2 完整端到端 commit hash 回填.

[docs-only]
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push
```

### 步骤 6.5: 一段话汇报

```
BUILD SUCCEEDED — 0 errors, 0 code warnings (version <commit-d.MMDD-HHMM>)

M4 任务 2 完整端到端 ship — 删除闭环 + 撤销 + DB 同步达成 Glance 初心 (真省硬盘空间).
6 步完成: 步骤 1 卷类型 spike + 矩阵走查 (CC + 真机) / 步骤 2 三个新 API + IndexedImageSnapshot
15 列 / 步骤 3 TrashService 主路径 + 撤销路径 + scope 模式复刻 / 步骤 4 model 增量
trashSelected + undo D34 contract + cancelTrash / 步骤 5 view checkbox + 按钮 + 删除中态
+ ContentView 全局 banner / 步骤 6 /go 收尾.

self-fix 轮次 N. codex pre-push 修复 M 项 (P1 / P2).
文档同步 Roadmap / CLAUDE.md / 本 plan / PENDING.
PENDING 加军哥本地补验 5 项 (跨视图持久 banner / 快速看图器期间不可见 / 30s timeout / 大批量
取消 / DB 一致性).
commit hash 范围 <task2-step1> ~ <task2-step6>. push 通过.
```

---

## 实施记录 (TODO: 实施完成后回填)

### 步骤 1 — 卷类型 spike + 矩阵走查, commit `<pending>` (2026-06-16)
...

### 步骤 2 — 3 个新 API + IndexedImageSnapshot, commit `<pending>` (2026-06-16)
...

### 步骤 3 — TrashService, commit `<pending>` (2026-06-16)
...

### 步骤 4 — DuplicateOverviewModel 增量, commit `<pending>` (2026-06-16)
...

### 步骤 5 — DuplicateOverviewView + ContentView banner 全链, commit `<pending>` (2026-06-16)
...

### 步骤 6 — /go 收尾, commit `<pending>` (2026-06-16)
...

---

## Self-Review

### Spec coverage 核对 (design 章节 → plan 步骤映射)

| design 章节 | 范围 | plan 覆盖 |
|---|---|---|
| 2.1 #3 整组勾选 + 一键移废纸篓 | 范围 | 步骤 5.3 (checkbox + 按钮) |
| 2.1 #4 可撤销 banner | 范围 | 步骤 5.2 + 5.4 (banner + ContentView 接线) |
| 2.1 #5 删后 DB 一致 + 总览刷新 | 范围 | 步骤 4.3 (trashSelected 删 row + reEvaluateGroup + load) |
| D30 一键移废纸篓不弹确认框 | 决策 | 步骤 5.3 (按钮直接触发 trashSelected) |
| D33 ContentView 级 banner overlay | 决策 | 步骤 5.4 (顶层 overlay) + 步骤 5.2 (banner view) |
| D34 显式回补 contract restoreImageFromSnapshot 首选 + requestRescan 降级 | 决策 | 步骤 2.3 + 2.4 + 步骤 4.4 (undo 主逻辑) |
| 4.1 TrashService nonisolated | 模块架构 | 步骤 3.2 + 3.3 |
| 4.1 TrashUndoBanner ContentView 级 overlay | 模块架构 | 步骤 5.2 |
| 4.5.0 fetchSnapshotForRestore API spec | API spec | 步骤 2.2 |
| 4.5.1 IndexedImageSnapshot 15 字段 | API spec | 步骤 2.1 |
| 4.5.2 restoreImageFromSnapshot API spec | API spec | 步骤 2.3 |
| 4.5.3 requestRescan API spec | API spec | 步骤 2.4 |
| 5.2 trash 阶段 (predict snapshot + trashItems + delete row + reEvaluate + load) | 数据流 | 步骤 4.3 |
| 5.2 撤销阶段 (D34 显式回补) | 数据流 | 步骤 4.4 |
| 5.2 中止阶段 (quit = 取消 policy) | 数据流 | TrashCancellationToken (步骤 3.1) + cancelTrash (步骤 4.3) |
| 6 错误边界 (security scope / 文件已删 / 移废纸篓失败 / 撤销失败 / target 占用 / 删除中并发 / 撤销时效 / 切走主区 / 大批量 / 卷类型差异) | 错误边界 | 步骤 3.2 / 3.3 (TrashService 累积 failures) + 步骤 5.4 (banner 副文案) |
| 7 透明显示保留张 (badge + 来源路径 + 不可勾选删除) | UI 要求 | 任务 1 已 ship (DuplicateMemberCell.canonical badge + relativePath + tooltip), 任务 2 仅加组级 checkbox 保留张不被勾选 (因 model 收集时 group.duplicates 排除 canonical) |
| 8.2 task 2 卷类型矩阵前置门控 | 任务拆分 | 步骤 1 (spike + 矩阵 + 退出路径) |

### Placeholder scan
- ❌ "TBD" / "implement later" / "fill in details" — 已搜全 plan, 无
- ❌ "Similar to step N" — 已搜全 plan, 无
- ❌ "Add appropriate error handling" — 用具体错误描述代替 (NSError domain/code, reason 文本)
- ⚠️ 步骤 6 "实施记录" 段标 TODO 回填 — 这是预期占位, 实施完成时填,不算 placeholder

### Type consistency 核对
- ✅ `IndexedImageSnapshot` (步骤 2.1) — fetchSnapshotForRestore (步骤 2.2) 返 `IndexedImageSnapshot?` + restoreImageFromSnapshot (步骤 2.3) 入参 `IndexedImageSnapshot` + 步骤 3.1 TrashSuccess 含 snapshot
- ✅ `TrashOutcome` (步骤 3.1) — TrashService.trashItems (步骤 3.2) 返 `TrashOutcome` + model 步骤 4.3 publish 给 lastTrashOutcome + ContentView 步骤 5.4 .onChange 读
- ✅ `TrashCancellationToken` actor (步骤 3.1) — TrashService.trashItems / restoreItems 入参一致; model 步骤 4.3 持 currentCancellationToken 调 cancelTrash
- ✅ `GroupKey` struct (步骤 3.1) — TrashSuccess / RestoreSuccess 含, model 步骤 4.3 affectedGroups 用; DedupPass.reEvaluateGroup 签名 (fileSize:format:) 对齐 GroupKey 字段
- ✅ `TrashOperationState` enum (步骤 4.1) — model trashState + view 步骤 5.3 trashAction switch 模式一致
- ✅ `selectedSha256s: Set<String>` (步骤 4.1) — selectedDuplicateCount / selectedReclaimableBytes (步骤 4.2) + view 步骤 5.3 checkbox isSelected 读
- ✅ `lastTrashOutcome: TrashOutcome?` — model publish (步骤 4.3) + view (ContentView 步骤 5.4 .onChange) 一致

### 步骤 1 退出路径明示 (CLAUDE.md「处理 issue 流程」硬约束)
- ✅ 步骤 1.5 明示: 全过 → 继续步骤 2; 任一失败 → 报告军哥 + 暂停 plan + design 修订选项 (修 D30 / 加细粒度授权 / 缩范围 / 砍卷类型)

### 文档自查 — 无横切式拆分
- ✅ 步骤 1 = 前置门控独立 ship 单元 (spike 脚本 + 矩阵结论 docs)
- ✅ 步骤 2 = 数据层 + API 接口 (3 API + Snapshot, swift script round-trip 验)
- ✅ 步骤 3 = service 层 (TrashService 主路径 + 撤销路径, swift script round-trip 验)
- ✅ 步骤 4 = model 层 (state + main entry + undo + cancel, 编译 + scaffolding 验)
- ✅ 步骤 5 = view + ContentView 集成 (用户首次完整感知 = ship 点)
- ✅ 步骤 6 = /go 收尾

**步骤拆分纪律**: 5 个实施步骤 + 1 个收尾步骤; 步骤 2-5 是 "可独立 commit + 当步 build 通过" 的 bite-size 单元; 步骤 5 是任务级独立交付的 user-perceivable ship 点。步骤 1 是前置门控 (不 ship 用户感知功能, 但解锁后续步骤的关键 gate)。

### 术语字典遵守
- ✅ 用「步骤 1 / 步骤 2 / 步骤 3 / 步骤 4 / 步骤 5 / 步骤 6」, 弃用 Slice / VS / 切片 / 片
- ✅ 用「重复清理 / 保留张 / 找相似图 / 缩略图 / 侧边栏 / 工具栏 / 废纸篓 / 撤销 / 快速看图器 / 智能文件夹」, 弃用 QV / SF / IS / OW / QVT 裸简写
- ✅ codex 编号带含义 (codex P1 / P2 + 简短描述)
- ✅ 「阶段 V2 → 里程碑 M4 → 任务 2」三层方法论

---

## codex review 折入索引 (2026-06-16 第一轮)

| review finding | 折入位置 | 状态 |
|---|---|---|
| **P1-01 跨视图刷新闭环缺口** (bridge.fireIndexChanged 私有, 跨视图 observer 不被触发) | 4.2 FolderStoreIndexBridge 行 / 步骤 2.4.b 加 `triggerIndexChanged()` 公开广播 / 步骤 4.3 trashSelected + 步骤 4.4 undo 主动调 | ✅ 已折入 |
| **P1-02 undo 双失败静默吞掉** (restoreImageFromSnapshot + requestRescan 都失败时只 print + dismiss banner) | 步骤 4.4 undo 内部 `dbFailures` 累积合并进 `restoreOutcome.failures` / TrashOutcomeEvent 含 undoResult / TrashUndoBanner 副文案展示「N 张撤销失败」 | ✅ 已折入 |
| **P1-03 folderIdForImageId 编译失败** (checkBind 是 IndexedImage.swift file-scoped private, model 访问不到) | 步骤 2.0 新增 — DuplicateGroupMember / Row + fetchDuplicateGroupMembers SQL 加 folderId; trashSelected.collectTrashInputs 直接用 dup.folderId 不反查 (P1-03 + P2-02 合一修) | ✅ 已折入 |
| **P2-01 lastTrashOutcome Equatable 比较含大 Data BLOB** | TrashOutcomeEvent 引入 UUID id; ContentView .onChange(of: lastTrashOutcome?.id) 轻量比对 + .animation(value: trashUndoBanner?.id) | ✅ 已折入 |
| **P2-02 DuplicateGroupMember 缺 folderId 导致 N+1 反查** | 跟 P1-03 合一修 (步骤 2.0) | ✅ 已折入 |
| **P2-03 步骤 1 spike 作为独立 commit 单元逻辑弱** | 步骤 1 头部明示「非提交 gate」+ spike 文件临时一次性 (跑完 git rm)+ 唯一 commit = 结论 docs commit | ✅ 已折入 |
| **P2-04 banner overlay 挂点歧义** (detail closure vs 外层 NavigationSplitView) | 步骤 5.4.c 拍板外层 NavigationSplitView .overlay (mirror 任务 1 IndexingProgressView 模式) | ✅ 已折入 |
| **P3-01 术语字典未完全收干净** (sandbox scope / ephemeral 等英文) | 留实施期实际碰到时局部消干, 不阻塞 plan 实施 | ⏸ 留实施期 |
| **P3-02 步骤 1 gate 失败 fallback 方向未写实** | 留实施期步骤 1 真失败时再具体 design 修订, 当前 plan 「暂停 + 报告军哥」语义足够 | ⏸ 留实施期 |

**总体**: 3 P1 + 4 P2 全折入 (P3 留实施期). 主要重构: (1) bridge.triggerIndexChanged 公开广播 (P1-01 + 跨视图刷新闭环) (2) TrashOutcomeEvent + UUID id + undoResult (P1-02 双失败感知 + P2-01 轻量比对) (3) DuplicateGroupMember.folderId 字段扩 (P1-03 + P2-02 合一修) (4) 步骤 1 重定位非提交 gate (P2-03) (5) banner overlay 挂点拍板 NavigationSplitView 外层 (P2-04).

---

## 下一步

1. ✅ 本 plan 已过 codex review (上方 9 条 finding 全折入); 不需要二次 review (没有新 API reality miss 引入)
2. 等军哥拍板进步骤 1 实施
3. 步骤 1 必须先跑通才解锁步骤 2-6 (前置门控硬约束)
