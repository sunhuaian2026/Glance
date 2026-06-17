import Foundation
import SQLite3

struct IndexedImage: Identifiable, Equatable {
    let id: Int64
    /// **Root** folder 的 .withSecurityScope bookmark（不是 image 自己的）。macOS sandbox
    /// 不允许给 enumerator 出来的子文件创建 .withSecurityScope bookmark，所以全部 image row
    /// 共享所属 root 的 bookmark；读图时 resolve + startAccessing 后拼 relative_path 得 child URL。
    /// Slice I rename 候选：→ rootBookmark 或者改为 folder_id → folders.root_url_bookmark lookup。
    let urlBookmark: Data
    let birthTime: Date
    let fileSize: Int64
    let format: String
    let filename: String
    let relativePath: String
    let folderId: Int64
    let dimensionsWidth: Int?
    let dimensionsHeight: Int?
    /// Slice H — 内容 SHA256 hex（小写）。NULL 表示尚未计算（candidate group 之外的图永远 NULL）；
    /// 计算后写入 + 用于 dedup_canonical 决议。
    let contentSha256: String?
}

/// Slice H — dedup 算法用的轻量 image record（只取算法需要的列，避免每张全 row fetch）。
struct DedupImageRow {
    let id: Int64
    let birthTime: Date
    let fileSize: Int64
    let format: String
    let relativePath: String
    let urlBookmark: Data
    let contentSha256: String?
}

struct ImageInsertRecord {
    /// 同 IndexedImage.urlBookmark 语义：root bookmark，不是 image 自己的
    let urlBookmark: Data
    let birthTime: Date
    let fileSize: Int64
    let format: String
    let filename: String
    let relativePath: String
    let folderId: Int64
    let dimensionsWidth: Int?
    let dimensionsHeight: Int?
}

nonisolated extension IndexStore {

    /// 幂等 insert：SELECT-first by (folder_id, relative_path)。
    /// 行存在 → 返回已有 id；不存在 → INSERT（**不用 OR IGNORE**，让 FK / NOT NULL /
    /// 其他 constraint violation 真实 surface，而不是被 OR IGNORE 静默吞成"post-IGNORE
    /// lookup 找不到行"的混淆错误）。
    /// 错误消息含 record 关键字段 dump，下次失败直接看 root cause。
    func insertImageIfAbsent(_ record: ImageInsertRecord) throws -> Int64 {
        try sync { db in
            // 1. SELECT first：行存在直接返回 id（幂等 happy path）
            let lookupStmt = try db.prepare("SELECT id FROM images WHERE folder_id = ? AND relative_path = ? LIMIT 1;")
            defer { sqlite3_finalize(lookupStmt) }
            try checkBind(sqlite3_bind_int64(lookupStmt, 1, record.folderId), index: 1, db: db)
            try checkBind(sqlite3_bind_text(lookupStmt, 2, (record.relativePath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 2, db: db)
            if sqlite3_step(lookupStmt) == SQLITE_ROW {
                return sqlite3_column_int64(lookupStmt, 0)
            }

            // 2. 不存在 → INSERT（不带 OR IGNORE，让真实错误 surface）
            let insStmt = try db.prepare("""
                INSERT INTO images
                (url_bookmark, birth_time, file_size, format, filename, relative_path,
                 folder_id, dimensions_width, dimensions_height, supports_feature_print)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1);
            """)
            defer { sqlite3_finalize(insStmt) }

            let bookmarkBytes = record.urlBookmark as NSData
            try checkBind(sqlite3_bind_blob(insStmt, 1, bookmarkBytes.bytes, Int32(bookmarkBytes.length), unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 1, db: db)
            try checkBind(sqlite3_bind_double(insStmt, 2, record.birthTime.timeIntervalSince1970), index: 2, db: db)
            try checkBind(sqlite3_bind_int64(insStmt, 3, record.fileSize), index: 3, db: db)
            try checkBind(sqlite3_bind_text(insStmt, 4, (record.format as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 4, db: db)
            try checkBind(sqlite3_bind_text(insStmt, 5, (record.filename as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 5, db: db)
            try checkBind(sqlite3_bind_text(insStmt, 6, (record.relativePath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 6, db: db)
            try checkBind(sqlite3_bind_int64(insStmt, 7, record.folderId), index: 7, db: db)
            if let w = record.dimensionsWidth {
                try checkBind(sqlite3_bind_int(insStmt, 8, Int32(w)), index: 8, db: db)
            } else {
                try checkBind(sqlite3_bind_null(insStmt, 8), index: 8, db: db)
            }
            if let h = record.dimensionsHeight {
                try checkBind(sqlite3_bind_int(insStmt, 9, Int32(h)), index: 9, db: db)
            } else {
                try checkBind(sqlite3_bind_null(insStmt, 9), index: 9, db: db)
            }

            let stepResult = sqlite3_step(insStmt)
            guard stepResult == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: """
                    insertImage step \(stepResult): \(db.lastErrorMessage()) — \
                    folder_id=\(record.folderId), relative_path=\(record.relativePath), \
                    filename=\(record.filename), format=\(record.format), \
                    file_size=\(record.fileSize), bookmark_size=\(record.urlBookmark.count)
                    """)
            }
            return sqlite3_last_insert_rowid(db.handle)
        }
    }

    /// Slice G.3 — 删除单条 image row（FSEvents ItemRemoved 触发）。
    /// 走 (folder_id, relative_path) 复合键（schema UNIQUE(folder_id, relative_path)）。
    func deleteImage(folderId: Int64, relativePath: String) throws {
        try sync { db in
            let stmt = try db.prepare("DELETE FROM images WHERE folder_id = ? AND relative_path = ?;")
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_int64(stmt, 1, folderId), index: 1, db: db)
            try checkBind(sqlite3_bind_text(stmt, 2, (relativePath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 2, db: db)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "deleteImage: \(db.lastErrorMessage())")
            }
        }
    }

    /// Cleanup pass — 拉某 folder 下所有 row 的 relative_path，给 FolderScanner 做
    /// 完整 scan 后的 garbage collection（删除文件已不存在的 stale row）。
    /// FSEvents 只在 app 运行期监听；离线移动 / 删除靠下次 scan 末尾这一步补。
    func fetchAllRelativePaths(folderId: Int64) throws -> Set<String> {
        try sync { db in
            let stmt = try db.prepare("SELECT relative_path FROM images WHERE folder_id = ?;")
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_int64(stmt, 1, folderId), index: 1, db: db)
            var result = Set<String>()
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cString = sqlite3_column_text(stmt, 0) {
                    result.insert(String(cString: cString))
                }
            }
            return result
        }
    }

    /// 批量删除（folder_id, relative_path）匹配的 row。供 FolderScanner cleanup pass 用。
    /// 单 transaction 内多次 DELETE，比循环调 deleteImage 高效。返回成功删除条数。
    @discardableResult
    func deleteImages(folderId: Int64, relativePaths: [String]) throws -> Int {
        guard !relativePaths.isEmpty else { return 0 }
        return try sync { db in
            let stmt = try db.prepare("DELETE FROM images WHERE folder_id = ? AND relative_path = ?;")
            defer { sqlite3_finalize(stmt) }
            var deleted = 0
            for path in relativePaths {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                try checkBind(sqlite3_bind_int64(stmt, 1, folderId), index: 1, db: db)
                try checkBind(sqlite3_bind_text(stmt, 2, (path as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 2, db: db)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw IndexDatabaseError.stepFailed(message: "deleteImages: \(db.lastErrorMessage())")
                }
                deleted += Int(sqlite3_changes(db.handle))
            }
            return deleted
        }
    }

    /// Slice G.3 — 更新单条 image row 元数据（FSEvents Modified 触发）。
    /// 仅 metadata 字段（birth_time / file_size / format / filename / dimensions）；
    /// content_sha256 / dedup_canonical 是 Slice H 字段，本 slice 保留 NULL 不重算。
    /// 行不存在 → 静默跳过（视作"上一帧 batch 已 DELETE 或没 INSERT 过"，FSEvents 容错）。
    func updateImageMetadata(folderId: Int64, relativePath: String, metadata: ImageMetadata) throws {
        try sync { db in
            let stmt = try db.prepare("""
                UPDATE images SET
                    birth_time = ?, file_size = ?, format = ?, filename = ?,
                    dimensions_width = ?, dimensions_height = ?
                WHERE folder_id = ? AND relative_path = ?;
            """)
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_double(stmt, 1, metadata.birthTime.timeIntervalSince1970), index: 1, db: db)
            try checkBind(sqlite3_bind_int64(stmt, 2, metadata.fileSize), index: 2, db: db)
            try checkBind(sqlite3_bind_text(stmt, 3, (metadata.format as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 3, db: db)
            try checkBind(sqlite3_bind_text(stmt, 4, (metadata.filename as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 4, db: db)
            if let w = metadata.dimensionsWidth {
                try checkBind(sqlite3_bind_int(stmt, 5, Int32(w)), index: 5, db: db)
            } else {
                try checkBind(sqlite3_bind_null(stmt, 5), index: 5, db: db)
            }
            if let h = metadata.dimensionsHeight {
                try checkBind(sqlite3_bind_int(stmt, 6, Int32(h)), index: 6, db: db)
            } else {
                try checkBind(sqlite3_bind_null(stmt, 6), index: 6, db: db)
            }
            try checkBind(sqlite3_bind_int64(stmt, 7, folderId), index: 7, db: db)
            try checkBind(sqlite3_bind_text(stmt, 8, (relativePath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 8, db: db)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "updateImageMetadata: \(db.lastErrorMessage())")
            }
        }
    }

    /// 受 SQL injection 保护的 fetch：仅接 SmartFolderQueryBuilder 编译产物。
    /// `CompiledSmartFolderQuery` 的 whereClause / orderBy 字符串由 builder 内部生成，
    /// 仅含已知 column name 和 placeholder（?），用户输入永远走 parameters 绑定。
    func fetch(_ compiled: CompiledSmartFolderQuery, limit: Int? = nil) throws -> [IndexedImage] {
        try sync { db in
            var sql = "SELECT id, url_bookmark, birth_time, file_size, format, filename, relative_path, folder_id, dimensions_width, dimensions_height, content_sha256 FROM images"
            if !compiled.whereClause.isEmpty {
                sql += " WHERE \(compiled.whereClause)"
            }
            if !compiled.orderBy.isEmpty {
                sql += " ORDER BY \(compiled.orderBy)"
            }
            if let limit {
                sql += " LIMIT \(limit)"
            }
            sql += ";"

            let stmt = try db.prepare(sql)
            defer { sqlite3_finalize(stmt) }

            for (idx, param) in compiled.parameters.enumerated() {
                let pos = Int32(idx + 1)
                let bindResult: Int32
                switch param {
                case let v as Int64: bindResult = sqlite3_bind_int64(stmt, pos, v)
                case let v as Int: bindResult = sqlite3_bind_int64(stmt, pos, Int64(v))
                case let v as Double: bindResult = sqlite3_bind_double(stmt, pos, v)
                case let v as String: bindResult = sqlite3_bind_text(stmt, pos, (v as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                case let v as Bool: bindResult = sqlite3_bind_int(stmt, pos, v ? 1 : 0)
                default:
                    throw IndexDatabaseError.bindFailed(index: idx, message: "unsupported parameter type \(type(of: param))")
                }
                if bindResult != SQLITE_OK {
                    throw IndexDatabaseError.bindFailed(index: idx, message: "bind result \(bindResult): \(db.lastErrorMessage())")
                }
            }

            var results: [IndexedImage] = []
            while true {
                let stepResult = sqlite3_step(stmt)
                if stepResult == SQLITE_DONE { break }
                if stepResult != SQLITE_ROW {
                    throw IndexDatabaseError.stepFailed(message: "fetch step \(stepResult): \(db.lastErrorMessage())")
                }
                let id = sqlite3_column_int64(stmt, 0)
                let blobLen = sqlite3_column_bytes(stmt, 1)
                let blobPtr = sqlite3_column_blob(stmt, 1)
                let bookmark = blobPtr.map { Data(bytes: $0, count: Int(blobLen)) } ?? Data()
                let birth = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                let size = sqlite3_column_int64(stmt, 3)
                let format = String(cString: sqlite3_column_text(stmt, 4))
                let filename = String(cString: sqlite3_column_text(stmt, 5))
                let relPath = String(cString: sqlite3_column_text(stmt, 6))
                let folderId = sqlite3_column_int64(stmt, 7)
                let w = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : Optional(Int(sqlite3_column_int(stmt, 8)))
                let h = sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : Optional(Int(sqlite3_column_int(stmt, 9)))
                let sha: String? = sqlite3_column_type(stmt, 10) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(stmt, 10))

                results.append(IndexedImage(
                    id: id, urlBookmark: bookmark, birthTime: birth, fileSize: size,
                    format: format, filename: filename, relativePath: relPath,
                    folderId: folderId, dimensionsWidth: w, dimensionsHeight: h,
                    contentSha256: sha
                ))
            }
            return results
        }
    }

    // MARK: - Slice H 内容去重 (SHA256 + dedup_canonical)

    /// 写入 SHA256 hex（小写）；caller 已 ContentHasher.sha256 计算完。
    func setContentSHA256(imageId: Int64, sha256: String) throws {
        try sync { db in
            let stmt = try db.prepare("UPDATE images SET content_sha256 = ? WHERE id = ?;")
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_text(stmt, 1, (sha256 as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 1, db: db)
            try checkBind(sqlite3_bind_int64(stmt, 2, imageId), index: 2, db: db)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "setContentSHA256: \(db.lastErrorMessage())")
            }
        }
    }

    /// 写入 dedup_canonical（true=canonical=1, false=duplicate=0）。
    func setDedupCanonical(imageId: Int64, canonical: Bool) throws {
        try sync { db in
            let stmt = try db.prepare("UPDATE images SET dedup_canonical = ? WHERE id = ?;")
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_int(stmt, 1, canonical ? 1 : 0), index: 1, db: db)
            try checkBind(sqlite3_bind_int64(stmt, 2, imageId), index: 2, db: db)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "setDedupCanonical: \(db.lastErrorMessage())")
            }
        }
    }

    /// FSEvents Modified 触发：reset SHA256 + dedup_canonical 到 NULL，让 DedupPass 重算。
    func resetSHA256AndCanonical(imageId: Int64) throws {
        try sync { db in
            let stmt = try db.prepare("UPDATE images SET content_sha256 = NULL, dedup_canonical = NULL WHERE id = ?;")
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_int64(stmt, 1, imageId), index: 1, db: db)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "resetSHA256AndCanonical: \(db.lastErrorMessage())")
            }
        }
    }

    /// cheap-first 第一步：找所有 (file_size, format) 相撞的候选 group。
    /// 跨所有 root（多 managed root 之间互相去重，spec 要求）。
    func fetchCandidateGroups() throws -> [(fileSize: Int64, format: String)] {
        try sync { db in
            let stmt = try db.prepare("""
                SELECT file_size, format FROM images
                GROUP BY file_size, format
                HAVING COUNT(*) > 1;
            """)
            defer { sqlite3_finalize(stmt) }
            var results: [(Int64, String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append((sqlite3_column_int64(stmt, 0), String(cString: sqlite3_column_text(stmt, 1))))
            }
            return results
        }
    }

    /// 取一个 candidate group 的所有 image rows（带必要字段计算 SHA256 + 决议 canonical）。
    func fetchImagesInGroup(fileSize: Int64, format: String) throws -> [DedupImageRow] {
        try sync { db in
            let stmt = try db.prepare("""
                SELECT id, birth_time, file_size, format, relative_path, url_bookmark, content_sha256
                FROM images
                WHERE file_size = ? AND format = ?;
            """)
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_int64(stmt, 1, fileSize), index: 1, db: db)
            try checkBind(sqlite3_bind_text(stmt, 2, (format as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 2, db: db)

            var results: [DedupImageRow] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let birth = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
                let size = sqlite3_column_int64(stmt, 2)
                let fmt = String(cString: sqlite3_column_text(stmt, 3))
                let relPath = String(cString: sqlite3_column_text(stmt, 4))
                let blobLen = sqlite3_column_bytes(stmt, 5)
                let blobPtr = sqlite3_column_blob(stmt, 5)
                let bookmark = blobPtr.map { Data(bytes: $0, count: Int(blobLen)) } ?? Data()
                let sha: String? = sqlite3_column_type(stmt, 6) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(stmt, 6))
                results.append(DedupImageRow(
                    id: id, birthTime: birth, fileSize: size, format: fmt,
                    relativePath: relPath, urlBookmark: bookmark, contentSha256: sha
                ))
            }
            return results
        }
    }

    /// 增量 handleRemoved 用：删行前 fetch (fileSize, format)，删完后 reEvaluateGroup 该 group。
    func fetchImageGroupKey(folderId: Int64, relativePath: String) throws -> (fileSize: Int64, format: String)? {
        try sync { db in
            let stmt = try db.prepare("SELECT file_size, format FROM images WHERE folder_id = ? AND relative_path = ? LIMIT 1;")
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_int64(stmt, 1, folderId), index: 1, db: db)
            try checkBind(sqlite3_bind_text(stmt, 2, (relativePath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 2, db: db)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return (sqlite3_column_int64(stmt, 0), String(cString: sqlite3_column_text(stmt, 1)))
            }
            return nil
        }
    }

    /// handleModified 后用：复合键 → image id；后续 resetSHA256AndCanonical 用 id 走 PK。
    func fetchImageIdByPath(folderId: Int64, relativePath: String) throws -> Int64? {
        try sync { db in
            let stmt = try db.prepare("SELECT id FROM images WHERE folder_id = ? AND relative_path = ? LIMIT 1;")
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_int64(stmt, 1, folderId), index: 1, db: db)
            try checkBind(sqlite3_bind_text(stmt, 2, (relativePath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 2, db: db)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int64(stmt, 0)
            }
            return nil
        }
    }

    /// 删 root / handleRemoved 之后的 orphan cleanup：还标 canonical=0 的 row 但其 SHA256
    /// 已没其他 row 共享（即同 SHA256 row 已被删了）→ promote 回 canonical=1。
    /// 防止"被删 canonical 留下的孤儿 duplicate 在 grid 永远不显示"。
    func promoteOrphanDuplicates() throws {
        try sync { db in
            let stmt = try db.prepare("""
                UPDATE images SET dedup_canonical = 1
                WHERE dedup_canonical = 0
                  AND content_sha256 IS NOT NULL
                  AND NOT EXISTS (
                      SELECT 1 FROM images dup
                      WHERE dup.content_sha256 = images.content_sha256
                        AND dup.id != images.id
                  );
            """)
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "promoteOrphanDuplicates: \(db.lastErrorMessage())")
            }
        }
    }

    /// Inspector 副本段用 — 接收 image 的 absolute fullPath，自动反查 (id, sha256) 后调
    /// fetchDuplicates 查同 SHA256 其他 row。fullPath 没匹配 row 或图未 hash → 返空 []。
    func fetchDuplicatesByFullPath(_ fullPath: String) throws -> [(id: Int64, fullPath: String)] {
        let selfData: (id: Int64, sha: String?)? = try sync { db in
            let stmt = try db.prepare("""
                SELECT i.id, i.content_sha256 FROM images i
                JOIN folders f ON i.folder_id = f.id
                WHERE f.root_path || '/' || i.relative_path = ? LIMIT 1;
            """)
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_text(stmt, 1, (fullPath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 1, db: db)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let sha: String? = sqlite3_column_type(stmt, 1) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(stmt, 1))
                return (id, sha)
            }
            return nil
        }
        guard let row = selfData, let sha = row.sha else { return [] }
        return try fetchDuplicates(imageId: row.id, sha256: sha)
    }

    /// Inspector 副本段用：找跟某 image 同 SHA256 的其他 row，返回 (id, fullPath)。
    /// fullPath 通过 JOIN folders 拼 root_path + relative_path 得到。
    func fetchDuplicates(imageId: Int64, sha256: String) throws -> [(id: Int64, fullPath: String)] {
        try sync { db in
            let stmt = try db.prepare("""
                SELECT i.id, f.root_path || '/' || i.relative_path AS full_path
                FROM images i
                JOIN folders f ON i.folder_id = f.id
                WHERE i.content_sha256 = ? AND i.id != ?
                ORDER BY i.birth_time ASC;
            """)
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_text(stmt, 1, (sha256 as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 1, db: db)
            try checkBind(sqlite3_bind_int64(stmt, 2, imageId), index: 2, db: db)

            var results: [(Int64, String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append((sqlite3_column_int64(stmt, 0), String(cString: sqlite3_column_text(stmt, 1))))
            }
            return results
        }
    }

    // MARK: - M2 Slice J 找类似（feature print CRUD）

    /// J.3 — 拉一批 supports_feature_print=1 且 feature_print IS NULL 的 row 给 indexer 抽。
    /// 按 id ASC 取，配 limit 实现 batch backfill。返回 [(id, urlBookmark, relativePath, folderId)]。
    /// 不返回 IndexedImage 整 row（只用到这 4 列，省内存 + IO）。
    func fetchImagesNeedingFeaturePrint(limit: Int) throws -> [(id: Int64, urlBookmark: Data, relativePath: String, folderId: Int64)] {
        try sync { db in
            let stmt = try db.prepare("""
                SELECT id, url_bookmark, relative_path, folder_id FROM images
                WHERE supports_feature_print = 1 AND feature_print IS NULL
                ORDER BY id ASC LIMIT ?;
            """)
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_int(stmt, 1, Int32(limit)), index: 1, db: db)

            var results: [(Int64, Data, String, Int64)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let blobLen = sqlite3_column_bytes(stmt, 1)
                let blobPtr = sqlite3_column_blob(stmt, 1)
                let bookmark = blobPtr.map { Data(bytes: $0, count: Int(blobLen)) } ?? Data()
                let relPath = String(cString: sqlite3_column_text(stmt, 2))
                let folderId = sqlite3_column_int64(stmt, 3)
                results.append((id, bookmark, relPath, folderId))
            }
            return results
        }
    }

    /// J.3 — 统计待抽 feature print 的图总数（pendingTotal 用，避免 Int.max 传给 limit 触发 Int32 trap）。
    func countImagesNeedingFeaturePrint() throws -> Int {
        try sync { db in
            let stmt = try db.prepare("""
                SELECT COUNT(*) FROM images
                WHERE supports_feature_print = 1 AND feature_print IS NULL;
            """)
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }

    /// J.3 — 写入 feature_print blob + revision；caller (indexer) 已 SimilarityService.extract 拿到。
    func setFeaturePrint(imageId: Int64, archivedData: Data, revision: Int) throws {
        try sync { db in
            let stmt = try db.prepare("""
                UPDATE images SET feature_print = ?, feature_print_revision = ?
                WHERE id = ?;
            """)
            defer { sqlite3_finalize(stmt) }
            let blobBytes = archivedData as NSData
            try checkBind(
                sqlite3_bind_blob(stmt, 1, blobBytes.bytes, Int32(blobBytes.length), unsafeBitCast(-1, to: sqlite3_destructor_type.self)),
                index: 1, db: db
            )
            try checkBind(sqlite3_bind_int(stmt, 2, Int32(revision)), index: 2, db: db)
            try checkBind(sqlite3_bind_int64(stmt, 3, imageId), index: 3, db: db)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "setFeaturePrint: \(db.lastErrorMessage())")
            }
        }
    }

    /// K.1 — 把所有 feature_print_revision 不等于 currentRevision 的 row 清回 NULL，
    /// 让 indexer 通过 fetchImagesNeedingFeaturePrint 自然重抽。返回受影响 row 数。
    /// 触发场景：macOS 升级让 VNFeaturePrintObservation 算法 revision 变化，旧 fp 不能
    /// 跟新算法的源图直接 computeDistance（行为不一致 / 距离失真）。
    func resetFeaturePrintsWithStaleRevision(currentRevision: Int) throws -> Int {
        try sync { db in
            let stmt = try db.prepare("""
                UPDATE images SET feature_print = NULL, feature_print_revision = NULL
                WHERE feature_print_revision IS NOT NULL AND feature_print_revision != ?;
            """)
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_int(stmt, 1, Int32(currentRevision)), index: 1, db: db)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "resetFeaturePrintsWithStaleRevision: \(db.lastErrorMessage())")
            }
            return Int(sqlite3_changes(db.handle))
        }
    }

    /// J.3 — Vision 抽取失败（unsupported format / corrupted file）→ 标 supports=0，
    /// 让 fetchImagesNeedingFeaturePrint 永久跳过（避免无限 retry 同一坏图）。
    func setFeaturePrintUnsupported(imageId: Int64) throws {
        try sync { db in
            let stmt = try db.prepare("""
                UPDATE images SET supports_feature_print = 0,
                                  feature_print = NULL,
                                  feature_print_revision = NULL
                WHERE id = ?;
            """)
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_int64(stmt, 1, imageId), index: 1, db: db)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw IndexDatabaseError.stepFailed(message: "setFeaturePrintUnsupported: \(db.lastErrorMessage())")
            }
        }
    }

    /// J.10 — 找类似 query：取所有有 fp 的 (id, archivedData)，加载 SimilarityService 算 distance。
    /// 1 万图 × ~6KB archive = ~60MB 内存峰值，M1 mac 可接受。
    func fetchAllFeaturePrintsForCosine() throws -> [(id: Int64, archivedData: Data)] {
        try sync { db in
            let stmt = try db.prepare("""
                SELECT id, feature_print FROM images
                WHERE supports_feature_print = 1 AND feature_print IS NOT NULL
                ORDER BY id ASC;
            """)
            defer { sqlite3_finalize(stmt) }
            var results: [(Int64, Data)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let blobLen = sqlite3_column_bytes(stmt, 1)
                let blobPtr = sqlite3_column_blob(stmt, 1)
                let archived = blobPtr.map { Data(bytes: $0, count: Int(blobLen)) } ?? Data()
                guard !archived.isEmpty else { continue }
                results.append((id, archived))
            }
            return results
        }
    }

    /// J.10 — 找类似时：按 image full URL 查 (id, archivedData)。caller 反查源图自己的 fp。
    /// 失败（行不存在 / fp 未抽 / fp 损坏）→ 返 nil（caller 提示"该图未索引/不支持"）。
    func fetchFeaturePrintByFullPath(_ fullPath: String) throws -> (id: Int64, archivedData: Data)? {
        try sync { db in
            let stmt = try db.prepare("""
                SELECT i.id, i.feature_print FROM images i
                JOIN folders f ON i.folder_id = f.id
                WHERE f.root_path || '/' || i.relative_path = ? LIMIT 1;
            """)
            defer { sqlite3_finalize(stmt) }
            try checkBind(sqlite3_bind_text(stmt, 1, (fullPath as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), index: 1, db: db)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let id = sqlite3_column_int64(stmt, 0)
            guard sqlite3_column_type(stmt, 1) != SQLITE_NULL else { return nil }
            let blobLen = sqlite3_column_bytes(stmt, 1)
            let blobPtr = sqlite3_column_blob(stmt, 1)
            let archived = blobPtr.map { Data(bytes: $0, count: Int(blobLen)) } ?? Data()
            guard !archived.isEmpty else { return nil }
            return (id, archived)
        }
    }

    /// J.10 — 已知 image id list → URL list（resolve root bookmark + 拼 relative_path）。
    /// computeV2Urls 同款 pattern；失败行 silently skip（compactMap）。
    func fetchUrlsByIds(_ ids: [Int64]) throws -> [URL] {
        guard !ids.isEmpty else { return [] }
        return try sync { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let sql = "SELECT id, url_bookmark, relative_path FROM images WHERE id IN (\(placeholders));"
            let stmt = try db.prepare(sql)
            defer { sqlite3_finalize(stmt) }
            for (idx, id) in ids.enumerated() {
                try checkBind(sqlite3_bind_int64(stmt, Int32(idx + 1), id), index: idx + 1, db: db)
            }

            // 先拉 row 进字典，再按入参 ids 顺序输出（preserve top-N 排序）
            var byId: [Int64: URL] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let rowId = sqlite3_column_int64(stmt, 0)
                let blobLen = sqlite3_column_bytes(stmt, 1)
                let blobPtr = sqlite3_column_blob(stmt, 1)
                let bookmark = blobPtr.map { Data(bytes: $0, count: Int(blobLen)) } ?? Data()
                let relPath = String(cString: sqlite3_column_text(stmt, 2))
                var stale = false
                if let rootURL = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope],
                    bookmarkDataIsStale: &stale
                ) {
                    byId[rowId] = rootURL.appendingPathComponent(relPath)
                }
            }
            return ids.compactMap { byId[$0] }
        }
    }

    // MARK: - M4 任务 1 — 重复清理总览聚合查询

    /// M4 任务 1 — 总览主查询。
    /// 列出所有「真有待清理副本」的重复组（HAVING SUM(dedup_canonical=0) > 0 保证：
    /// 只列含至少一个副本的组，单张组 / 全 NULL 组 / 仅保留张的组都不进总览）。
    /// content_sha256 IS NOT NULL 自动排除尚未算 SHA256 的图（dedup_canonical 口径一致）。
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
    /// 注：SELECT 不取 i.folder_id（任务 1 只读不需要；任务 2 删除路径再扩 — codex P2-3 修）。
    /// JOIN ON i.folder_id = f.id 仍保留（拼 full_path 需要）。
    func fetchDuplicateGroupMembers(sha256: String) throws -> [DuplicateGroupMemberRow] {
        try sync { db in
            let stmt = try db.prepare("""
                SELECT i.id, i.folder_id, i.dedup_canonical, i.file_size, i.relative_path,
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
                let folderId = sqlite3_column_int64(stmt, 1)
                let canonical = sqlite3_column_int64(stmt, 2) == 1
                let fileSize = sqlite3_column_int64(stmt, 3)
                let relPath = String(cString: sqlite3_column_text(stmt, 4))
                let blobLen = sqlite3_column_bytes(stmt, 5)
                let blobPtr = sqlite3_column_blob(stmt, 5)
                let bookmark = blobPtr.map { Data(bytes: $0, count: Int(blobLen)) } ?? Data()
                let fullPath = String(cString: sqlite3_column_text(stmt, 6))
                rows.append(DuplicateGroupMemberRow(
                    id: id,
                    folderId: folderId,
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
            try checkBind(
                sqlite3_bind_text(
                    stmt, 2,
                    (relativePath as NSString).utf8String, -1,
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                ),
                index: 2, db: db
            )
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            // 0: url_bookmark BLOB NOT NULL
            let bmLen = sqlite3_column_bytes(stmt, 0)
            let bmPtr = sqlite3_column_blob(stmt, 0)
            let urlBookmark = bmPtr.map { Data(bytes: $0, count: Int(bmLen)) } ?? Data()
            // 1: birth_time REAL NOT NULL
            let birthTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            // 2: file_size INTEGER NOT NULL
            let fileSize = sqlite3_column_int64(stmt, 2)
            // 3: format TEXT NOT NULL
            let format = String(cString: sqlite3_column_text(stmt, 3))
            // 4: filename TEXT NOT NULL
            let filename = String(cString: sqlite3_column_text(stmt, 4))
            // 5: relative_path TEXT NOT NULL
            let relPath = String(cString: sqlite3_column_text(stmt, 5))
            // 6: folder_id INTEGER NOT NULL
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

    private func checkBind(_ result: Int32, index: Int, db: IndexDatabase) throws {
        if result != SQLITE_OK {
            throw IndexDatabaseError.bindFailed(index: index, message: "bind result \(result): \(db.lastErrorMessage())")
        }
    }
}
