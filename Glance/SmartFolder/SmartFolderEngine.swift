import Foundation

/// `@unchecked Sendable`：仅持只读 IndexStore 引用，IndexStore 自身串行，跨 actor 共享安全。
nonisolated final class SmartFolderEngine: @unchecked Sendable {

    let store: IndexStore

    init(store: IndexStore) {
        self.store = store
    }

    func execute(_ folder: SmartFolder, now: Date = Date(), limit: Int? = nil) throws -> [IndexedImage] {
        let compiled = try SmartFolderQueryBuilder.compile(folder, now: now)
        return try store.fetch(compiled, limit: limit)
    }
}
