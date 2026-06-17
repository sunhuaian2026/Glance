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
//  任务 1 硬边界：本 model 仅 expose state + load + attach。不持 detach
//  （现有架构无销毁路径调用，避免假 API；未来 ContentView 重建场景出现再加）。
//  任务 2 加：勾选集合 / 删除中状态 / CancellationToken / trashSelected / undo / lastTrashOutcome。
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class DuplicateOverviewModel: ObservableObject {

    @Published private(set) var state: DuplicateOverviewState = .idle

    /// M4 任务 2 — 勾选的重复组 (sha256). 整组勾选 D28: 用户选「这组要清掉副本」,
    /// 不给单文件 checkbox.
    @Published private(set) var selectedSha256s: Set<String> = []

    /// M4 任务 2 — 删除中态状态机.
    @Published private(set) var trashState: TrashOperationState = .idle

    /// M4 任务 2 — 桥给 ContentView 渲染 banner. trashSelected 完成时 set,
    /// ContentView .onChange(of: model.lastTrashOutcome?.id) 走轻量 UUID 比对
    /// (codex review P2(大 BLOB Equatable) 修: 不深比含 BLOB 的 payload 避大 Data 比较 + 同 outcome 不触发).
    @Published private(set) var lastTrashOutcome: TrashOutcomeEvent?

    private var indexStore: IndexStore?
    private weak var bridge: FolderStoreIndexBridge?
    // M4 任务 2 收尾 — V1→V2 bookmark 升级引导 UI 依赖 (步骤 A.4 加).
    private weak var bookmarkManager: BookmarkManager?
    private weak var folderStore: FolderStore?
    private weak var migrationCoordinator: BookmarkMigrationCoordinator?
    private var observerToken: UUID?
    private var pendingReload: DispatchWorkItem?
    // stale-write guard：每次 load() 自增，后续 await 回来核对；不一致说明更新的 load 已启动，旧结果丢弃
    private var loadGeneration: Int = 0

    /// M4 任务 2 — 删除中的取消 token (actor; cancelTrash 调它).
    private var currentCancellationToken: TrashCancellationToken?

    // 注：入口激活态不放 model —— ContentView.@State showDuplicateOverview 是唯一权威，
    // SmartFolderListView 通过 isDuplicateOverviewSelected: Bool 参数接收，不读 model 状态。
    // 这与现有三态互斥（V1 folder / 智能文件夹 / 临时结果视图）全在 ContentView 持有的模式一致。

    // MARK: - placeholder / attach（mirror SmartFolderStore.placeholder / attach）

    static func placeholder() -> DuplicateOverviewModel {
        DuplicateOverviewModel()
    }

    private init() {}

    /// ContentView wireIfReady 调，IndexStore ready 后装配 + 注册 bridge observer。
    /// 幂等：重复调忽略（已 attach 过则不重复注册 observer）。
    func attach(
        indexStore: IndexStore,
        bridge: FolderStoreIndexBridge,
        bookmarkManager: BookmarkManager,
        folderStore: FolderStore,
        migrationCoordinator: BookmarkMigrationCoordinator
    ) {
        guard self.indexStore == nil else { return }
        self.indexStore = indexStore
        self.bridge = bridge
        self.bookmarkManager = bookmarkManager
        self.folderStore = folderStore
        self.migrationCoordinator = migrationCoordinator
        let token = bridge.addIndexChangedObserver { [weak self] in
            // bridge fire 在 MainActor 上（FolderStoreIndexBridge.swift:14 @MainActor 确认）；
            // 这里直接调 scheduleReload 同 actor 不需切线程。
            // 保守包 Task @MainActor 防 bridge 未来去 @MainActor 化场景。
            Task { @MainActor [weak self] in
                self?.scheduleReload()
            }
        }
        self.observerToken = token
    }

    // 注：不持 detach()。ContentView @StateObject 寿命 = app 寿命，
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

    /// M4 任务 2 收尾 — D5-bm-ui prune 用. 一次性替换勾选集合 (避免 toggleSelection N 次调用).
    /// ContentView .onChange(of: groups) prune 后调.
    func replaceSelectedSha256s(_ newValue: Set<String>) {
        selectedSha256s = newValue
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

    // MARK: - M4 任务 2 — 删除主入口 trashSelected

    /// 用户点「移入废纸篓」: 收集所选组的副本 → 预 fetch 每 member snapshot →
    /// TrashService.trashItems → 删 DB rows → DedupPass.reEvaluateGroup 受影响组 →
    /// promoteOrphanDuplicates 兜底 → bridge.triggerIndexChanged() 跨视图广播 (codex 第一轮 P1(跨视图刷新)) →
    /// load() 刷新 → set lastTrashOutcome 触发 banner.
    /// design 5.2 数据流主路径.
    func trashSelected() async {
        guard let store = indexStore else { return }
        guard let bridgeRef = bridge else { return }
        guard !selectedSha256s.isEmpty else { return }

        // M4 任务 2 收尾 — V1→V2 bookmark 升级引导 UI 入口 (步骤 A.4).
        // schemaVersion < 2 = V1 时代 bookmark, trashItem 必失败 (NSCocoa 513). 触发引导.
        guard let bookmarkManager else { return }
        guard let folderStore else { return }
        guard let migrationCoordinator else { return }
        guard bookmarkManager.currentSchemaVersion >= 2 else {
            migrationCoordinator.start(
                model: self,
                bookmarkManager: bookmarkManager,
                folderStore: folderStore,
                bridge: bridgeRef
            )
            return   // V1 路径: 引导触发, trashSelected 本次不执行, 等用户走完引导回来再点按钮
        }
        // V2 路径: 既有 trash 主流程不变 (下面代码)

        let snapshotGroups = self.groups
        let snapshotSelected = self.selectedSha256s
        let inputs = await collectTrashInputs(store: store, groups: snapshotGroups, selectedSha256s: snapshotSelected)
        guard !inputs.isEmpty else {
            trashState = .completed
            return
        }

        let token = TrashCancellationToken()
        currentCancellationToken = token
        trashState = .trashing(done: 0, total: inputs.count)

        let outcome = await TrashService.trashItems(
            inputs,
            cancellation: token
        ) { [weak self] done, total in
            Task { @MainActor [weak self] in
                self?.trashState = .trashing(done: done, total: total)
            }
        }

        var affectedGroups: Set<GroupKey> = []
        for success in outcome.successes {
            do {
                try store.deleteImage(folderId: success.snapshot.folderId, relativePath: success.snapshot.relativePath)
                affectedGroups.insert(success.groupKey)
            } catch {
                NSLog("[M4-T2] deleteImage failed for id=%lld/%@: %@",
                      success.snapshot.folderId, success.snapshot.relativePath, String(describing: error))
            }
        }

        await Task.detached(priority: .utility) {
            for key in affectedGroups {
                DedupPass.reEvaluateGroup(store: store, fileSize: key.fileSize, format: key.format)
            }
            try? store.promoteOrphanDuplicates()
        }.value

        bridgeRef.triggerIndexChanged()

        await load()

        lastTrashOutcome = TrashOutcomeEvent(id: UUID(), trash: outcome, undoResult: nil)
        trashState = .completed
        currentCancellationToken = nil
        selectedSha256s.removeAll()
    }

    /// 收集 trashSelected 所需的 TrashInput 数组 (整组勾选 → 该组所有副本预 fetch snapshot).
    /// 步骤 2.0 已把 folderId 加进 DuplicateGroupMember struct, 这里直接用 dup.folderId
    /// 不反查 (codex 第三轮 P1(checkBind file-scoped 编译失败) + P2(N+1 反查) 合一修).
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

    // MARK: - M4 任务 2 — 撤销主入口 undo (D34 显式回补 contract)

    /// 用户点 banner [撤销]: D34 显式回补 contract.
    /// 1. TrashService.restoreItems 把废纸篓 URL move 回原 fullPath
    /// 2. 对每个 restore 成功 member: restoreImageFromSnapshot 首选 (同步返回 row id) /
    ///    UNIQUE 冲突或失败 → requestRescan 降级 (async throws 返回时 row 已恢复或明确失败)
    /// 3. 对每个受影响 groupKey: reEvaluateGroup → bridge.triggerIndexChanged 跨视图广播 →
    ///    总览刷新 → publish undo 结果到 lastTrashOutcome (codex 第一轮 P1(undo 双失败静默吞掉) 修)
    func undo(outcome: TrashOutcome) async {
        guard let store = indexStore else { return }
        guard let bridgeRef = bridge else { return }

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
                    _ = try await bridgeRef.requestRescan(
                        folderId: success.snapshot.folderId,
                        relativePath: success.snapshot.relativePath
                    )
                    affectedGroups.insert(success.groupKey)
                } catch let rescanError {
                    // 双失败: 文件已 restore 回原 path 但 DB row 没回, 用户必须感知.
                    // 累积进 dbFailures, banner 副文案展示「N 张 DB 同步失败 — 文件在但索引未恢复」.
                    NSLog("[M4-T2 undo] DOUBLE FAILURE for %@: snapshot=%@ rescan=%@",
                          success.originalFullPath,
                          String(describing: error),
                          String(describing: rescanError))
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

        // 4. 跨视图广播 (codex 第一轮 P1(跨视图刷新) 修)
        bridgeRef.triggerIndexChanged()

        // 5. 总览刷新
        await load()

        // 6. publish undo 结果给 banner — 不静默 nil, 让 ContentView 渲染撤销确认文案 +
        //    若有失败 (含双失败 dbFailures) 副文案 surface 让用户感知
        lastTrashOutcome = TrashOutcomeEvent(id: UUID(), trash: outcome, undoResult: restoreOutcome)
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
    /// nonisolated 必加：@MainActor class 内 static 默认继承隔离，detached Task 无法调；
    /// IndexStore 本身非 @MainActor，从后台调 fetchDuplicateGroups 安全（参考 DedupPass.runFullPass）。
    private nonisolated static func fetchGroups(store: IndexStore) throws -> [DuplicateGroup] {
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

    private nonisolated static func makeMember(from row: DuplicateGroupMemberRow) -> DuplicateGroupMember {
        DuplicateGroupMember(
            id: row.id,
            folderId: row.folderId,   // 任务 2 加 — carry 进 member 避 trashSelected N+1 反查
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

// MARK: - M4 任务 2 — 删除中状态机 + Banner 事件载体

/// M4 任务 2 — 删除中状态机.
enum TrashOperationState: Equatable {
    /// 待操作 (无勾选 / 勾选未触发)
    case idle
    /// 删除中: progress = (已处理, 总数); cancellable = true 时取消按钮可点
    case trashing(done: Int, total: Int)
    /// 删除已完成 (outcome 已 publish 给 lastTrashOutcome), 待 model 清回 .idle
    case completed
}

/// M4 任务 2 — 撤销 banner 事件载体 (codex review P2(大 BLOB Equatable): 轻量 UUID 比对避深比 BLOB payload).
/// trashSelected 完成 set 一次 (undoResult=nil banner 显「已移 N 张到废纸篓 + [撤销] [×]」),
/// undo(outcome:) 完成 set 另一次 (undoResult≠nil banner 显「撤销完成 N 张 (+M 失败)」简短确认).
/// ContentView .onChange(of: model.lastTrashOutcome?.id) 走 id 比对触发动画 + 重置 timer.
struct TrashOutcomeEvent: Identifiable {
    let id: UUID
    let trash: TrashOutcome
    /// nil = trash 阶段; 非 nil = undo 阶段, 含 restore 结果 (失败累积给 banner 副文案 codex 第一轮 P1(undo 双失败静默吞掉)).
    let undoResult: RestoreOutcome?
}
