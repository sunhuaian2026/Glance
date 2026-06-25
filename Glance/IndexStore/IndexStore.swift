import Foundation

/// High-level IndexStore. Owns IndexDatabase + serializes access via internal queue.
/// Subsequent tasks add typed CRUD methods (Image / ManagedFolder).
/// `@unchecked Sendable`：所有 DB 访问内部走 DispatchQueue.sync 串行，跨 actor 共享安全。
nonisolated final class IndexStore: @unchecked Sendable {

    private let db: IndexDatabase
    private let queue: DispatchQueue
    let storageURL: URL

    /// Opens or creates the IndexStore at the canonical path:
    /// `~/Library/Application Support/Glance/index.sqlite` (sandboxed → redirected to
    /// app container's Application Support). Runs pending migrations.
    init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let glanceDir = appSupport.appendingPathComponent("Glance", isDirectory: true)
        try FileManager.default.createDirectory(at: glanceDir, withIntermediateDirectories: true)
        let url = glanceDir.appendingPathComponent("index.sqlite")
        self.storageURL = url
        self.db = try IndexDatabase(at: url)
        self.queue = DispatchQueue(label: "com.sunhongjun.glance.indexstore", qos: .utility)

        try queue.sync {
            let current = try IndexStoreSchema.readDbVersion(db)
            try IndexStoreSchema.migrate(db, currentDbVersion: current)
        }
    }

    /// Run a synchronous block on the IndexStore queue.
    func sync<T>(_ block: (IndexDatabase) throws -> T) throws -> T {
        try queue.sync {
            try block(db)
        }
    }
}
