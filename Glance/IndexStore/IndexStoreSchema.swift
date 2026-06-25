import Foundation
import SQLite3

/// Schema version applied incrementally. M1 ships v1 with all M1+M2+M3 columns
/// (M2/M3 columns NULLable until populated). Future versions add columns via
/// ALTER TABLE in a new migration block.
nonisolated enum IndexStoreSchema {

    static let currentVersion: Int = 2

    /// Apply migrations from `current` (db's PRAGMA user_version) up to currentVersion.
    static func migrate(_ db: IndexDatabase, currentDbVersion: Int) throws {
        if currentDbVersion < 1 {
            try applyV1(db)
        }
        if currentDbVersion < 2 {
            try applyV2(db)
        }
        try db.execute("PRAGMA user_version = \(currentVersion);")
    }

    static func readDbVersion(_ db: IndexDatabase) throws -> Int {
        let stmt = try db.prepare("PRAGMA user_version;")
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    // MARK: V1 (M1+M2+M3 forward-looking)

    private static func applyV1(_ db: IndexDatabase) throws {
        // folders 表：稀疏存储 root + explicitly-set subfolder。
        // parent_root_id NULLable —— root 行 NULL（自身就是 root，无父）；
        // subfolder 行非 NULL（指向所属 root）。FK NULL 不触发约束（SQLite 标准行为）。
        // 这避免了"root 自链 insert 时 parent_root_id=0 触发 FK fail"的死锁。
        // root_path：root 行的标准化绝对路径（去重 unique 用），subfolder 行 NULL。
        try db.execute("""
            CREATE TABLE folders (
                id                  INTEGER PRIMARY KEY AUTOINCREMENT,
                root_url_bookmark   BLOB,                                -- 仅 root 行非 NULL
                root_path           TEXT,                                -- 仅 root 行非 NULL（标准化绝对路径，幂等用）
                relative_path       TEXT NOT NULL DEFAULT '',            -- '' 即 root
                parent_root_id      INTEGER,                             -- root 行 NULL；subfolder 行 → 所属 root
                hide_in_smart_view  INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (parent_root_id) REFERENCES folders(id) ON DELETE CASCADE
            );
        """)
        try db.execute("CREATE UNIQUE INDEX idx_folders_root_path ON folders(root_path) WHERE root_path IS NOT NULL;")
        try db.execute("CREATE UNIQUE INDEX idx_folders_subpath ON folders(parent_root_id, relative_path) WHERE parent_root_id IS NOT NULL;")
        try db.execute("CREATE INDEX idx_folders_parent ON folders(parent_root_id);")

        // images 表：UNIQUE(folder_id, relative_path) 让 INSERT OR IGNORE 幂等。
        // content_sha256 / dedup_canonical M1 nullable，Slice H 启用。
        try db.execute("""
            CREATE TABLE images (
                id                       INTEGER PRIMARY KEY AUTOINCREMENT,
                url_bookmark             BLOB NOT NULL,
                birth_time               REAL NOT NULL,
                file_size                INTEGER NOT NULL,
                format                   TEXT NOT NULL,
                filename                 TEXT NOT NULL,
                relative_path            TEXT NOT NULL,
                folder_id                INTEGER NOT NULL,
                dimensions_width         INTEGER,
                dimensions_height        INTEGER,
                content_sha256           TEXT,                            -- M1 nullable（Slice H 用）
                dedup_canonical          INTEGER,                          -- M1 nullable（Slice H 用）
                feature_print            BLOB,                             -- M2
                feature_print_revision   INTEGER,                          -- M2
                supports_feature_print   INTEGER NOT NULL DEFAULT 1,       -- M2
                exif_capture_date        REAL,                             -- M3
                FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE,
                UNIQUE(folder_id, relative_path)
            );
        """)
        try db.execute("CREATE INDEX idx_images_birth ON images(birth_time DESC);")
        try db.execute("CREATE INDEX idx_images_folder ON images(folder_id);")
        try db.execute("CREATE INDEX idx_images_dedup ON images(content_sha256) WHERE content_sha256 IS NOT NULL;")
    }

    // MARK: V2 (Slice I — 进度持久化)

    /// folders 表加 last_processed_path 字段（V2 GA Slice I）：
    /// 首次扫描中途用户关 Glance → 重启后从该 cursor resume，不重头扫。
    /// FolderScanner 每 100 张写一次（粒度折中：太频繁影响 SQLite，太稀疏 resume 跨度大）。
    /// NULL = 该 root 未启动扫描或已扫完；非 NULL = scan 中途断点。
    private static func applyV2(_ db: IndexDatabase) throws {
        try db.execute("ALTER TABLE folders ADD COLUMN last_processed_path TEXT;")
    }
}
