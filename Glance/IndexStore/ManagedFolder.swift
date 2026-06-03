import Foundation
import SQLite3

struct ManagedFolder: Identifiable, Equatable {
    let id: Int64
    let rootBookmark: Data?              // non-nil only for root rows
    let relativePath: String              // "" for root
    let parentRootId: Int64?              // root 行 NULL（自身就是 root），subfolder 行 → 所属 root id
    let hideInSmartView: Bool

    var isRoot: Bool { relativePath.isEmpty && rootBookmark != nil }
}

nonisolated extension IndexStore {

    /// Register a root managed folder; **幂等**：同一 path 重复调用返回已有 id，不新建行。
    /// `path` = rootURL.standardizedFileURL.path，作为 unique 键。
    /// caller（FolderStoreIndexBridge）传 path + bookmark，bookmark 在重启可能 stale 但 path 稳定。
    func registerRoot(path: String, bookmark: Data) throws -> Int64 {
        try sync { db in
            let selStmt = try db.prepare("SELECT id FROM folders WHERE root_path = ? LIMIT 1;")
            defer { sqlite3_finalize(selStmt) }
            sqlite3_bind_text(selStmt, 1, (path as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(selStmt) == SQLITE_ROW {
                return sqlite3_column_int64(selStmt, 0)
            }

            // 新 root：parent_root_id = NULL（root 行无父），FK 不触发
            let insStmt = try db.prepare("""
                INSERT INTO folders (root_url_bookmark, root_path, relative_path, parent_root_id, hide_in_smart_view)
                VALUES (?, ?, '', NULL, 0)
                RETURNING id;
            """)
            defer { sqlite3_finalize(insStmt) }

            let bytes = bookmark as NSData
            sqlite3_bind_blob(insStmt, 1, bytes.bytes, Int32(bytes.length), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(insStmt, 2, (path as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            guard sqlite3_step(insStmt) == SQLITE_ROW else {
                throw IndexDatabaseError.stepFailed(message: db.lastErrorMessage())
            }
            return sqlite3_column_int64(insStmt, 0)
        }
    }

    /// 查 root_path → folder id（V2 sidebar contextMenu 用 V1 URL 反推 IndexStore id）。
    /// 路径走标准化绝对（caller 通常传 url.standardizedFileURL.path）。
    func folderIdForRootPath(_ path: String) throws -> Int64? {
        try sync { db in
            let stmt = try db.prepare("SELECT id FROM folders WHERE root_path = ? LIMIT 1;")
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int64(stmt, 0)
            }
            return nil
        }
    }

    /// Slice D — root 行 hide 切换。直接 UPDATE 已存在的 root row（registerRoot 时 hide=0 默认）。
    func setRootHidden(rootId: Int64, hidden: Bool) throws {
        try sync { db in
            let stmt = try db.prepare("UPDATE folders SET hide_in_smart_view = ? WHERE id = ? AND parent_root_id IS NULL;")
            defer { sqlite3_finalize(stmt) }
            try checkBindBool(sqlite3_bind_int(stmt, 1, hidden ? 1 : 0), index: 1, db: db)
            try checkBindBool(sqlite3_bind_int64(stmt, 2, rootId), index: 2, db: db)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "setRootHidden: \(db.lastErrorMessage())")
            }
        }
    }

    /// Slice D — subfolder hide 状态写入（稀疏 explicit 模型）。
    /// 首次右键子目录 → INSERT new row；已 explicit set 过 → UPDATE 该行。
    /// ON CONFLICT 目标 **必须含 WHERE 子句** 匹配 schema 的 *partial* unique idx
    /// `idx_folders_subpath ... WHERE parent_root_id IS NOT NULL`，否则 SQLite 拒绝 prepare（codex P1）。
    func upsertSubfolderHide(rootId: Int64, relativePath: String, hidden: Bool) throws {
        try sync { db in
            let stmt = try db.prepare("""
                INSERT INTO folders (root_url_bookmark, root_path, relative_path, parent_root_id, hide_in_smart_view)
                VALUES (NULL, NULL, ?, ?, ?)
                ON CONFLICT (parent_root_id, relative_path) WHERE parent_root_id IS NOT NULL
                DO UPDATE SET hide_in_smart_view = excluded.hide_in_smart_view;
            """)
            defer { sqlite3_finalize(stmt) }
            try checkBindBool(sqlite3_bind_text(stmt, 1, (relativePath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 1, db: db)
            try checkBindBool(sqlite3_bind_int64(stmt, 2, rootId), index: 2, db: db)
            try checkBindBool(sqlite3_bind_int(stmt, 3, hidden ? 1 : 0), index: 3, db: db)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "upsertSubfolderHide: \(db.lastErrorMessage())")
            }
        }
    }

    /// Slice I.2 — 进度持久化：每 100 张写一次扫描 cursor，让重启 resume from cursor。
    func setLastProcessedPath(rootId: Int64, path: String) throws {
        try sync { db in
            let stmt = try db.prepare("UPDATE folders SET last_processed_path = ? WHERE id = ? AND parent_root_id IS NULL;")
            defer { sqlite3_finalize(stmt) }
            try checkBindBool(sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 1, db: db)
            try checkBindBool(sqlite3_bind_int64(stmt, 2, rootId), index: 2, db: db)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "setLastProcessedPath: \(db.lastErrorMessage())")
            }
        }
    }

    /// Slice I.2 — 扫完一个 root 清除 cursor（NULL = 已扫完，下次启动不需 resume）。
    func clearLastProcessedPath(rootId: Int64) throws {
        try sync { db in
            let stmt = try db.prepare("UPDATE folders SET last_processed_path = NULL WHERE id = ? AND parent_root_id IS NULL;")
            defer { sqlite3_finalize(stmt) }
            try checkBindBool(sqlite3_bind_int64(stmt, 1, rootId), index: 1, db: db)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "clearLastProcessedPath: \(db.lastErrorMessage())")
            }
        }
    }

    /// Slice I.2 — 启动 root scan 前读 cursor，决定是否 resume。
    /// nil = 全新扫 / 上次完整扫完；非 nil = 中断断点 → FolderScanner skipWhile 跳过。
    func fetchLastProcessedPath(rootId: Int64) throws -> String? {
        try sync { db in
            let stmt = try db.prepare("SELECT last_processed_path FROM folders WHERE id = ? AND parent_root_id IS NULL LIMIT 1;")
            defer { sqlite3_finalize(stmt) }
            try checkBindBool(sqlite3_bind_int64(stmt, 1, rootId), index: 1, db: db)
            if sqlite3_step(stmt) == SQLITE_ROW {
                if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return nil }
                return String(cString: sqlite3_column_text(stmt, 0))
            }
            return nil
        }
    }

    /// Slice G.1 — 删除 root folder（V1 sidebar 移除 root 时触发）。
    /// FK CASCADE 自动连删：images 表 (folder_id REFERENCES folders.id) + subfolder hide rows
    /// (parent_root_id REFERENCES folders.id)。
    /// 仅删 root 行（parent_root_id IS NULL 守卫，防误删 subfolder hide row）。
    func deleteRoot(rootId: Int64) throws {
        try sync { db in
            let stmt = try db.prepare("DELETE FROM folders WHERE id = ? AND parent_root_id IS NULL;")
            defer { sqlite3_finalize(stmt) }
            try checkBindBool(sqlite3_bind_int64(stmt, 1, rootId), index: 1, db: db)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "deleteRoot: \(db.lastErrorMessage())")
            }
        }
    }

    /// 对账用：取 DB 里所有 root 的 (id, root_path)。仅 root 行（parent_root_id IS NULL）+
    /// root_path NOT NULL 守卫（防 malformed 行）。FolderStoreIndexBridge.sync 拿它跟
    /// BookmarkManager 的受管根集对账，删掉 DB 里已不在受管集的 root（FK CASCADE 连删 images）。
    func fetchRootPaths() throws -> [(id: Int64, path: String)] {
        try sync { db in
            let stmt = try db.prepare("SELECT id, root_path FROM folders WHERE parent_root_id IS NULL AND root_path IS NOT NULL;")
            defer { sqlite3_finalize(stmt) }
            var results: [(id: Int64, path: String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let path = String(cString: sqlite3_column_text(stmt, 1))
                results.append((id: id, path: path))
            }
            return results
        }
    }

    /// 防御性孤儿清扫：删 folder_id 指向已不存在 folders 行的 image（历史上 FK 曾关 / 旧 DB 遗留产生）。
    /// 现行 PRAGMA foreign_keys=ON 下正常操作不会产生孤儿，此为一次性完整性修复。返回删除行数。
    /// 用 NOT EXISTS 而非 NOT IN（NULL-safe）。
    @discardableResult
    func deleteOrphanImages() throws -> Int {
        try sync { db in
            let stmt = try db.prepare("DELETE FROM images WHERE NOT EXISTS (SELECT 1 FROM folders WHERE folders.id = images.folder_id);")
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "deleteOrphanImages: \(db.lastErrorMessage())")
            }
            return db.handle.map { Int(sqlite3_changes($0)) } ?? 0
        }
    }

    /// Slice D — 计算给定 (rootId, relativePath) 路径上的 effective hidden 状态。
    /// 走"path 上溯找最具体 explicit hide row"算法（稀疏 explicit 模型）：
    /// 1. 检查 (parent_root_id=rootId AND relative_path 是 path 前缀) 的所有 row
    /// 2. 加上 root 自身 (id=rootId AND parent_root_id IS NULL)
    /// 3. 按 LENGTH(relative_path) DESC 取第一个 → 最具体 explicit
    /// 4. 没有匹配则 default false（未 explicit 设过的目录视作 visible）
    /// `relativePath = ""` 表示查 root 自身的 effective state（== root row 的 hide_in_smart_view）。
    func effectiveHidden(rootId: Int64, relativePath: String) throws -> Bool {
        try sync { db in
            let stmt = try db.prepare("""
                SELECT hide_in_smart_view FROM folders
                WHERE (id = ? AND parent_root_id IS NULL)
                   OR (parent_root_id = ? AND (relative_path = ? OR ? LIKE relative_path || '/%'))
                ORDER BY LENGTH(relative_path) DESC
                LIMIT 1;
            """)
            defer { sqlite3_finalize(stmt) }
            try checkBindBool(sqlite3_bind_int64(stmt, 1, rootId), index: 1, db: db)
            try checkBindBool(sqlite3_bind_int64(stmt, 2, rootId), index: 2, db: db)
            try checkBindBool(sqlite3_bind_text(stmt, 3, (relativePath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 3, db: db)
            try checkBindBool(sqlite3_bind_text(stmt, 4, (relativePath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 4, db: db)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int(stmt, 0) != 0
            }
            return false
        }
    }

    /// Slice D follow-up — 是否**显式**设过 hide=1（不走 effectiveHidden 的 path-walk 继承），
    /// 给 sidebar 决定是否显 eye.slash 图标（仅 explicit set 才显，避免 root hide 整树时
    /// 所有 subfolder 都顶图标的视觉爆炸）。
    /// `relativePath = ""` 查 root row；否则查 (parent_root_id, relative_path) explicit subfolder row。
    /// 没 row 视作未 explicit set → false。
    func isExplicitlyHidden(rootId: Int64, relativePath: String) throws -> Bool {
        try sync { db in
            let sql: String
            if relativePath.isEmpty {
                sql = "SELECT hide_in_smart_view FROM folders WHERE id = ? AND parent_root_id IS NULL LIMIT 1;"
            } else {
                sql = "SELECT hide_in_smart_view FROM folders WHERE parent_root_id = ? AND relative_path = ? LIMIT 1;"
            }
            let stmt = try db.prepare(sql)
            defer { sqlite3_finalize(stmt) }
            try checkBindBool(sqlite3_bind_int64(stmt, 1, rootId), index: 1, db: db)
            if !relativePath.isEmpty {
                try checkBindBool(sqlite3_bind_text(stmt, 2, (relativePath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 2, db: db)
            }
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int(stmt, 0) != 0
            }
            return false
        }
    }

    private func checkBindBool(_ result: Int32, index: Int, db: IndexDatabase) throws {
        if result != SQLITE_OK {
            throw IndexDatabaseError.bindFailed(index: index, message: "bind result \(result): \(db.lastErrorMessage())")
        }
    }

    /// Fetch all root managed folders.
    func fetchRoots() throws -> [ManagedFolder] {
        try sync { db in
            let stmt = try db.prepare("""
                SELECT id, root_url_bookmark, relative_path, parent_root_id, hide_in_smart_view
                FROM folders
                WHERE root_url_bookmark IS NOT NULL
                ORDER BY id ASC;
            """)
            defer { sqlite3_finalize(stmt) }

            var results: [ManagedFolder] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let blobLen = sqlite3_column_bytes(stmt, 1)
                let blobPtr = sqlite3_column_blob(stmt, 1)
                let bookmark = blobPtr.map { Data(bytes: $0, count: Int(blobLen)) }
                let relPath = String(cString: sqlite3_column_text(stmt, 2))
                let parentId: Int64?
                if sqlite3_column_type(stmt, 3) == SQLITE_NULL {
                    parentId = nil
                } else {
                    parentId = sqlite3_column_int64(stmt, 3)
                }
                let hide = sqlite3_column_int(stmt, 4) != 0

                results.append(ManagedFolder(
                    id: id,
                    rootBookmark: bookmark,
                    relativePath: relPath,
                    parentRootId: parentId,
                    hideInSmartView: hide
                ))
            }
            return results
        }
    }
}
