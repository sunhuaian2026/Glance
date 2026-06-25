import Foundation
import SwiftUI
import Combine

@MainActor
final class SmartFolderStore: ObservableObject {

    @Published var availableSmartFolders: [SmartFolder] = BuiltInSmartFolders.all

    /// Slice I.3 — 单一状态机替代 selected/queryResult/isQuerying/lastError 四独立字段。
    /// 无效组合（如 isQuerying=true 同时 queryResult 非空）从结构上不可表达。
    @Published var state: SmartFolderState = .idle

    /// Optional engine：A.17 placeholder()/attach 模式让 ContentView 可在 IndexStore
    /// 异步 ready 之前先创建 store；ready 后调 attach(engine:) 完成 wire-up。
    var engine: SmartFolderEngine?

    init(engine: SmartFolderEngine?) {
        self.engine = engine
    }

    static func placeholder() -> SmartFolderStore {
        SmartFolderStore(engine: nil)
    }

    func attach(engine: SmartFolderEngine) {
        self.engine = engine
    }

    // MARK: - 兼容旧 API 的 computed accessors（views / ContentView 直接读不变）

    var selected: SmartFolder? {
        switch state {
        case .idle: return nil
        case .loading(let f, _), .loaded(let f, _), .error(let f, _): return f
        }
    }

    /// .loading 期间返回 staleImages 让 grid 不清空避免闪屏；.loaded 返回真实结果。
    var queryResult: [IndexedImage] {
        switch state {
        case .loaded(_, let imgs): return imgs
        case .loading(_, let stale): return stale
        case .idle, .error: return []
        }
    }

    var isQuerying: Bool {
        if case .loading = state { return true }
        return false
    }

    var lastError: String? {
        if case .error(_, let msg) = state { return msg }
        return nil
    }

    // MARK: - State transitions

    /// Select a smart folder and refresh its query result. nil → state .idle。
    /// 切到不同 SF 时不 carry stale（用户主动切，期望立刻看到新 SF 数据）；
    /// 同 SF refresh 时 carry 当前 queryResult 作为 stale，避免重复 refresh 闪屏。
    func select(_ folder: SmartFolder?) async {
        guard let folder else {
            state = .idle
            return
        }
        let stale: [IndexedImage] = (selected?.id == folder.id) ? queryResult : []
        state = .loading(folder, staleImages: stale)
        await runQuery(for: folder)
    }

    /// Re-execute the currently-selected smart folder query.
    /// Carry 当前 queryResult 作为 stale → grid 在 loading 期间继续显示旧数据。
    func refreshSelected() async {
        guard let folder = selected else { return }
        state = .loading(folder, staleImages: queryResult)
        await runQuery(for: folder)
    }

    /// 运行 query + 处理 stale-write（query 跑过程中用户已切到别的 SF / 清 selection）。
    private func runQuery(for folder: SmartFolder) async {
        guard let eng = engine else { return }
        let captured = eng
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try captured.execute(folder)
            }.value
            // Stale-write guard：仅当当前 state 仍指向同一 folder 的 .loading 才写回结果
            if case .loading(let cur, _) = state, cur.id == folder.id {
                state = .loaded(folder, result)
            }
        } catch {
            if case .loading(let cur, _) = state, cur.id == folder.id {
                state = .error(folder, "\(error)")
            }
        }
    }
}
