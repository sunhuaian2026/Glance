//
//  DuplicateOverviewModel.swift
//  Glance
//
//  M4 任务 1 — 总览业务 model。@MainActor ObservableObject，mirror SmartFolderStore：
//  placeholder() / attach(indexStore:bridge:) 异步装配；单一 @Published state 状态机。
//
//  重复清理 V2 重设计 (任务 AB) — 字段重构:
//  selectedSha256s → skippedGroupIds (语义反转: 跳过组而非整组勾选)
//  新增 userKeepIdByGroup / reviewedGroupIds / filter / sortOption / searchQuery /
//  expandedGroupIds / focusReview* 系列字段 (design v2 §2.1)
//  trashSelected → trashPending (用 userKeepId 而非 SQL dedup_canonical=1; D1)
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class DuplicateOverviewModel: ObservableObject {

    @Published private(set) var state: DuplicateOverviewState = .idle

    // MARK: - V2 临时态字段 (design v2 §2.1)

    /// D2 锁定 — 跳过组 sha256 集合 (临时态, 不写 DB).
    /// 改名自旧 selectedSha256s (语义反转: 跳过组而非整组勾选).
    @Published private(set) var skippedGroupIds: Set<String> = []

    /// D1 锁定 — per-item 选保留张临时态 (groupId → memberId). 不调 IndexStore.setDedupCanonical
    /// (D1 锁定不污染 DedupPass 的 canonical 计算).
    /// design v2 §2.1
    @Published private(set) var userKeepIdByGroup: [String: Int64] = [:]

    /// 已确认过的组 sha256 集合 (design v2 §2.1, 任务 C 实装真值联动).
    @Published private(set) var reviewedGroupIds: Set<String> = []

    /// 工具条筛选 pills 选中态 (design v2 §4.3).
    @Published var filter: DedupListFilter = .all

    /// 工具条排序分段选中态 (design v2 §4.3).
    @Published var sortOption: DedupSortOption = .reclaimableDesc

    /// 搜索框输入 (design v2 §4.3).
    @Published var searchQuery: String = ""

    /// 已展开组 sha256 集合 (design v2 §4.4).
    @Published private(set) var expandedGroupIds: Set<String> = []

    /// 浮层开关 (design v2 §6; 任务 D 实装浮层 UI).
    @Published var focusReviewOpen: Bool = false

    /// 浮层待审 queue (groupId 数组; design v2 §6).
    @Published private(set) var focusReviewQueue: [String] = []

    /// 浮层当前 index into focusReviewQueue (design v2 §6).
    @Published var focusReviewIndex: Int = 0

    // MARK: - 删除中状态 (M4 任务 2 沿用)

    @Published private(set) var trashState: TrashOperationState = .idle

    @Published private(set) var lastTrashOutcome: TrashOutcomeEvent?

    // MARK: - 弱引用依赖

    private var indexStore: IndexStore?
    private weak var bridge: FolderStoreIndexBridge?
    private weak var bookmarkManager: BookmarkManager?
    private weak var folderStore: FolderStore?
    private weak var migrationCoordinator: BookmarkMigrationCoordinator?
    private var observerToken: UUID?
    private var pendingReload: DispatchWorkItem?
    private var loadGeneration: Int = 0
    private var currentCancellationToken: TrashCancellationToken?

    // MARK: - placeholder / attach

    static func placeholder() -> DuplicateOverviewModel {
        DuplicateOverviewModel()
    }

    private init() {}

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
            Task { @MainActor [weak self] in
                self?.scheduleReload()
            }
        }
        self.observerToken = token
    }

    // MARK: - load / scheduleReload

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
            guard loadGeneration == myGeneration else { return }
            state = .loaded(groups: groups)
        } catch {
            guard loadGeneration == myGeneration else { return }
            state = .error(message: "\(error)")
        }
    }

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

    // MARK: - V2 跳过 / 跳过恢复 (design v2 §2.1, D2 锁定)

    /// 切换组跳过态 (design v2 D2 — 临时态不写 DB).
    func toggleSkip(groupId: String) {
        if skippedGroupIds.contains(groupId) {
            skippedGroupIds.remove(groupId)
        } else {
            skippedGroupIds.insert(groupId)
        }
    }

    /// 清空所有跳过态 (trashPending 完成后调).
    func clearSkips() {
        skippedGroupIds.removeAll()
    }

    /// ContentView .onChange(of: groups) prune 后调 — 一次性替换跳过集合.
    func replaceSkippedGroupIds(_ newValue: Set<String>) {
        skippedGroupIds = newValue
    }

    /// ContentView prune 块调 — 一次性替换 userKeepIdByGroup (设计 v2 §3 prune 用).
    func replaceUserKeepIds(_ newValue: [String: Int64]) {
        userKeepIdByGroup = newValue
    }

    /// ContentView prune 块调 — 一次性替换 reviewedGroupIds.
    func replaceReviewedGroupIds(_ newValue: Set<String>) {
        reviewedGroupIds = newValue
    }

    /// ContentView prune 块调 — 一次性替换 expandedGroupIds.
    func replaceExpandedGroupIds(_ newValue: Set<String>) {
        expandedGroupIds = newValue
    }

    // MARK: - V2 per-item 保留张 (design v2 §2.1, D1 锁定)

    /// 手选此组保留张 (design v2 D1 — 临时态不调 IndexStore.setDedupCanonical).
    /// 同时 unskip 该组 (选了保留张表示用户想清理这组, 不该跳过).
    func setUserKeep(groupId: String, memberId: Int64) {
        userKeepIdByGroup[groupId] = memberId
        skippedGroupIds.remove(groupId)  // 选了保留张 = 不跳过
    }

    /// 单一权威读取入口 — dict 中且 id 在 allMembers 才返回, 否则回退 group.recommendedKeepId.
    /// design v2 §2.1
    func userKeepId(for group: DuplicateGroup) -> Int64 {
        if let memberId = userKeepIdByGroup[group.id],
           group.allMembers.contains(where: { $0.id == memberId }) {
            return memberId
        }
        return group.recommendedKeepId
    }

    // MARK: - V2 展开 (design v2 §4.4)

    func toggleExpand(groupId: String) {
        if expandedGroupIds.contains(groupId) {
            expandedGroupIds.remove(groupId)
        } else {
            expandedGroupIds.insert(groupId)
        }
    }

    func isExpanded(groupId: String) -> Bool { expandedGroupIds.contains(groupId) }

    // MARK: - V2 已确认 (design v2 §2.1, 任务 C 实装真值)

    func markReviewed(groupId: String) {
        reviewedGroupIds.insert(groupId)
    }

    func isReviewed(groupId: String) -> Bool { reviewedGroupIds.contains(groupId) }

    // MARK: - V2 跳过判断

    func isSkipped(groupId: String) -> Bool { skippedGroupIds.contains(groupId) }

    // MARK: - V2 浮层 (design v2 §6; 任务 D 实装真实 UI)

    /// 打开逐组审阅浮层 — 收集 needsReview && !reviewed && !skipped 的组, init queue + index = 0.
    /// 任务 C 实装 needsReview 算法后 queue 才有真实数据; 目前 needsReview 暂返回 false.
    func openFocusReview() {
        let queue = groups
            .filter { needsReview(group: $0) && !isReviewed(groupId: $0.id) && !isSkipped(groupId: $0.id) }
            .map { $0.id }
        focusReviewQueue = queue
        focusReviewIndex = 0
        focusReviewOpen = !queue.isEmpty
    }

    func closeFocusReview() {
        focusReviewOpen = false
    }

    func focusReviewNext() {
        guard focusReviewOpen, focusReviewIndex < focusReviewQueue.count - 1 else { return }
        focusReviewIndex += 1
    }

    func focusReviewPrev() {
        guard focusReviewOpen, focusReviewIndex > 0 else { return }
        focusReviewIndex -= 1
    }

    func focusReviewConfirm() {
        guard focusReviewOpen,
              focusReviewIndex < focusReviewQueue.count else { return }
        let groupId = focusReviewQueue[focusReviewIndex]
        markReviewed(groupId: groupId)
        // 末尾组直接关浮层; 否则推进到下一组
        if focusReviewIndex >= focusReviewQueue.count - 1 {
            closeFocusReview()
        } else {
            focusReviewNext()
        }
    }

    func focusReviewSkip() {
        guard focusReviewOpen,
              focusReviewIndex < focusReviewQueue.count else { return }
        let groupId = focusReviewQueue[focusReviewIndex]
        toggleSkip(groupId: groupId)
        focusReviewNext()
    }

    /// 任务 E — reload stale 处理: groups 重算后, queue 过滤失效组并推进 / 关浮层.
    /// ContentView .onChange(of: model.groups) 内调; newGroups 作参数避免再读 self.groups (prune 顺序安全).
    func recomputeFocusReviewAfterReload(newGroups: [DuplicateGroup]) {
        guard focusReviewOpen else { return }
        let validSha256s = Set(newGroups.map { $0.id })
        let validQueue = focusReviewQueue.filter { id in
            guard validSha256s.contains(id) else { return false }
            guard let group = newGroups.first(where: { $0.id == id }) else { return false }
            return needsReview(group: group) && !isReviewed(groupId: id) && !isSkipped(groupId: id)
        }
        if validQueue.isEmpty {
            closeFocusReview()
            return
        }
        // 当前组若已不在新 queue → 推进到第一个仍有效的
        let currentId: String? = focusReviewIndex < focusReviewQueue.count
            ? focusReviewQueue[focusReviewIndex] : nil
        let newIndex: Int = {
            if let cid = currentId, let idx = validQueue.firstIndex(of: cid) { return idx }
            return 0
        }()
        focusReviewQueue = validQueue
        focusReviewIndex = newIndex
    }

    // MARK: - needsReview 算法 (design v2 §5.1, D3)

    /// design v2 §5.1 needsReview 算法 (v2 codex P0 修, SHA256 invariant)
    /// 阈值: duplicateCount >= 3 (组共 ≥ 4 张, 用户值得手动审一遍挑保留 path/folder)
    func needsReview(group: DuplicateGroup) -> Bool {
        return group.duplicateCount >= 3
    }

    // MARK: - V2 filteredSortedGroups (design v2 §2.1)

    /// 应用 filter + sort + searchQuery 后的结果集 (design v2 §2.1).
    var filteredSortedGroups: [DuplicateGroup] {
        var result = groups

        // filter pill
        switch filter {
        case .all:
            break
        case .needsReview:
            result = result.filter { needsReview(group: $0) && !isReviewed(groupId: $0.id) }
        case .auto:
            result = result.filter { !needsReview(group: $0) || isReviewed(groupId: $0.id) }
        }

        // search
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter { group in
                group.canonical.relativePath.lowercased().contains(q) ||
                group.duplicates.contains { $0.relativePath.lowercased().contains(q) }
            }
        }

        // sort
        switch sortOption {
        case .reclaimableDesc:
            result.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        case .countDesc:
            result.sort { $0.duplicateCount > $1.duplicateCount }
        case .nameAsc:
            result.sort { $0.canonical.relativePath.localizedCompare($1.canonical.relativePath) == .orderedAscending }
        }

        return result
    }

    /// 待确认组数 (needsReview && !reviewed). 任务 C 实装真值.
    var reviewCount: Int {
        groups.filter { needsReview(group: $0) && !isReviewed(groupId: $0.id) }.count
    }

    /// 已自动处理组数 (!needsReview || isReviewed). 任务 C 实装真值.
    var autoCount: Int {
        groups.filter { !needsReview(group: $0) || isReviewed(groupId: $0.id) }.count
    }

    /// 废纸篓按钮是否可用 (design v2 §2.1).
    var trashEnabled: Bool { pendingTrashCount > 0 }

    // MARK: - V2 SHA256 invariant 计算 (design v2 §2.1, D-dedup-14)

    /// v2 SHA256 invariant — 未跳过组的 duplicates.count 之和.
    /// 与 userKeepId 切换无关 (同组同体积, 切谁删几张都不变).
    var pendingTrashCount: Int {
        groups.filter { !skippedGroupIds.contains($0.id) }
            .reduce(into: 0) { $0 += $1.duplicates.count }
    }

    /// v2 SHA256 invariant — 未跳过组的 reclaimableBytes 之和 (SQL 已算好, 与 userKeepId 无关).
    var pendingReclaimableBytes: Int64 {
        groups.filter { !skippedGroupIds.contains($0.id) }
            .reduce(into: Int64(0)) { $0 += $1.reclaimableBytes }
    }

    // MARK: - V2 trashPending (改名自 trashSelected)

    /// 用户点「移入废纸篓」: 收集未跳过组的副本 (用 userKeepId 决定谁是保留张) →
    /// TrashService.trashItems → 删 DB rows → DedupPass.reEvaluateGroup →
    /// promoteOrphanDuplicates → bridge.triggerIndexChanged → load → lastTrashOutcome.
    /// D1 锁定: 用 userKeepId 而非 DB dedup_canonical=1; v2 SHA256 invariant 同组同体积语义.
    func trashPending() async {
        guard let store = indexStore else { return }
        guard let bridgeRef = bridge else { return }
        guard trashEnabled else { return }

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
            return
        }

        // Snapshot 全依赖 — D1 plan §2.8
        let snapshotKeepIds = self.userKeepIdByGroup
        let snapshotSkipped = self.skippedGroupIds
        let snapshotGroups = self.groups

        let inputs = await collectTrashInputsFromPending(
            store: store,
            groups: snapshotGroups,
            skippedGroupIds: snapshotSkipped,
            userKeepIds: snapshotKeepIds
        )
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
        clearSkips()
    }

    /// V2 trash inputs 收集 — 过滤跳过组, 用 userKeepId 决定保留张, 其余为副本 (D1).
    private nonisolated func collectTrashInputsFromPending(
        store: IndexStore,
        groups: [DuplicateGroup],
        skippedGroupIds: Set<String>,
        userKeepIds: [String: Int64]
    ) async -> [TrashService.TrashInput] {
        let pendingGroups = groups.filter { !skippedGroupIds.contains($0.id) }
        var inputs: [TrashService.TrashInput] = []
        for group in pendingGroups {
            // D1: userKeepId 而非 dedup_canonical 决定保留张
            let keepId: Int64
            if let chosen = userKeepIds[group.id],
               group.allMembers.contains(where: { $0.id == chosen }) {
                keepId = chosen
            } else {
                keepId = group.recommendedKeepId
            }
            for member in group.allMembers where member.id != keepId {
                guard let snap = try? store.fetchSnapshotForRestore(
                    folderId: member.folderId,
                    relativePath: member.relativePath
                ) else { continue }
                inputs.append(TrashService.TrashInput(
                    snapshot: snap,
                    groupKey: GroupKey(fileSize: snap.fileSize, format: snap.format)
                ))
            }
        }
        return inputs
    }

    func cancelTrash() async {
        await currentCancellationToken?.cancel()
    }

    // MARK: - Undo (M4 任务 2 沿用, 无改动)

    func undo(outcome: TrashOutcome) async {
        guard let store = indexStore else { return }
        guard let bridgeRef = bridge else { return }

        let token = TrashCancellationToken()
        var restoreOutcome = await TrashService.restoreItems(outcome.successes, cancellation: token)

        var affectedGroups: Set<GroupKey> = []
        var dbFailures: [RestoreFailure] = []
        for success in restoreOutcome.successes {
            do {
                _ = try store.restoreImageFromSnapshot(success.snapshot)
                affectedGroups.insert(success.groupKey)
            } catch {
                do {
                    _ = try await bridgeRef.requestRescan(
                        folderId: success.snapshot.folderId,
                        relativePath: success.snapshot.relativePath
                    )
                    affectedGroups.insert(success.groupKey)
                } catch let rescanError {
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

        if !dbFailures.isEmpty {
            restoreOutcome = RestoreOutcome(
                successes: restoreOutcome.successes,
                failures: restoreOutcome.failures + dbFailures,
                cancelled: restoreOutcome.cancelled
            )
        }

        await Task.detached(priority: .utility) {
            for key in affectedGroups {
                DedupPass.reEvaluateGroup(store: store, fileSize: key.fileSize, format: key.format)
            }
            try? store.promoteOrphanDuplicates()
        }.value

        bridgeRef.triggerIndexChanged()
        await load()

        lastTrashOutcome = TrashOutcomeEvent(id: UUID(), trash: outcome, undoResult: restoreOutcome)
    }

    // MARK: - V2 replaceSkippedGroupIds (prune 用, design v2 §3 ContentView prune 块)

    // replaceSkippedGroupIds 已在上方 "V2 跳过" 段定义.

    // MARK: - helpers

    private func currentGroups() -> [DuplicateGroup] {
        switch state {
        case .loaded(let groups): return groups
        case .loading(let stale): return stale
        case .idle, .error: return []
        }
    }

    private nonisolated static func fetchGroups(store: IndexStore) throws -> [DuplicateGroup] {
        let rows = try store.fetchDuplicateGroups()
        var groups: [DuplicateGroup] = []
        groups.reserveCapacity(rows.count)
        for row in rows {
            let members = try store.fetchDuplicateGroupMembers(sha256: row.contentSha256)
            guard let canonical = members.first(where: { $0.dedupCanonical }) else { continue }
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
            folderId: row.folderId,
            urlBookmark: row.urlBookmark,
            relativePath: row.relativePath,
            fileSize: row.fileSize,
            fullPath: row.fullPath,
            isCanonical: row.dedupCanonical
        )
    }
}

// MARK: - computed accessors (mirror SmartFolderStore computed accessors)

extension DuplicateOverviewModel {

    var groups: [DuplicateGroup] { currentGroups() }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let msg) = state { return msg }
        return nil
    }

    var groupCount: Int { groups.count }

    var totalReclaimableBytes: Int64 {
        groups.reduce(into: Int64(0)) { $0 += $1.reclaimableBytes }
    }
}

// MARK: - 删除中状态机 + Banner 事件载体 (M4 任务 2 沿用)

enum TrashOperationState: Equatable {
    case idle
    case trashing(done: Int, total: Int)
    case completed
}

struct TrashOutcomeEvent: Identifiable {
    let id: UUID
    let trash: TrashOutcome
    let undoResult: RestoreOutcome?
}
