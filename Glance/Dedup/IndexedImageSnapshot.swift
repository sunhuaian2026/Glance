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

struct IndexedImageSnapshot: Equatable, Sendable {
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
