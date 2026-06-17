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

    private var indexStore: IndexStore?
    private weak var bridge: FolderStoreIndexBridge?
    private var observerToken: UUID?
    private var pendingReload: DispatchWorkItem?
    // stale-write guard：每次 load() 自增，后续 await 回来核对；不一致说明更新的 load 已启动，旧结果丢弃
    private var loadGeneration: Int = 0

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
    func attach(indexStore: IndexStore, bridge: FolderStoreIndexBridge) {
        guard self.indexStore == nil else { return }
        self.indexStore = indexStore
        self.bridge = bridge
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
