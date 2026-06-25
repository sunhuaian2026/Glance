//
//  DedupPass.swift
//  Glance
//
//  Slice H — 内容去重 cheap-first 算法（D3 / spec v2-design 5.2）。
//
//  策略：
//   1. fetchCandidateGroups()：找所有 (file_size, format) 撞的 group（数据库一次 SQL）
//   2. 对每组：fetchImagesInGroup → 没 SHA256 的 ContentHasher.sha256 算上 → 按 SHA256
//      子分组 → 同 SHA256 多于一个时取 earliest birth_time（tie: 最小 id）为 canonical=1，
//      其余 canonical=0；同 SHA256 仅一个则保留 NULL（视作 canonical 但不显式 set）
//   3. 不在任何 candidate group 的 image（file_size+format unique）→ NULL，placeholder
//      `(dedup_canonical IS NULL OR dedup_canonical = 1)` 视作 canonical
//
//  线程：所有调用必须在 detached task 跑（IO + CPU 重）；IndexStore mutations 走自己的
//  serial queue，不会跟 main actor 抢。
//

import Foundation

// DedupPass 必须 nonisolated：所有调用都在 Task.detached 内（FolderStoreIndexBridge
// triggerDedupFullPass / triggerDedupGroup），避免编译器把 static method 推断成
// MainActor isolated 导致 detached task 调用 warning。
nonisolated enum DedupPass {

    /// 全候选 dedup pass：扫所有 (file_size, format) candidate group，计算 SHA256 +
    /// 决议 canonical。FolderScanner 完成后调一次（或 root 删除后）。
    /// 重入安全：增量 reEvaluateGroup 也走同 IndexStore serial queue，不会冲突。
    static func runFullPass(store: IndexStore) {
        do {
            let groups = try store.fetchCandidateGroups()
            for group in groups {
                reEvaluateGroup(store: store, fileSize: group.fileSize, format: group.format)
            }
            // Orphan cleanup：删 root / handleRemoved 后留下的孤儿 duplicate（canonical=0
            // 但同 SHA256 row 已没了）→ promote 回 canonical=1
            try store.promoteOrphanDuplicates()
            print("[Dedup] full pass done — evaluated \(groups.count) candidate group(s)")
        } catch {
            print("[Dedup] full pass FAILED: \(error)")
        }
    }

    /// 单 group 重新决议 canonical。FSEvents 增量 created/modified/removed 命中该 group
    /// 后调（caller 知道 fileSize+format 时直接喂入）。
    static func reEvaluateGroup(store: IndexStore, fileSize: Int64, format: String) {
        do {
            let rows = try store.fetchImagesInGroup(fileSize: fileSize, format: format)
            guard rows.count > 1 else {
                // group 只剩 1 行：清 dedup_canonical 让它回归 NULL（视作 canonical）
                if let only = rows.first {
                    try store.setDedupCanonical(imageId: only.id, canonical: true)
                }
                return
            }
            // 给没 SHA256 的算 SHA256
            var hashed: [DedupImageRow] = []
            hashed.reserveCapacity(rows.count)
            for row in rows {
                if let existing = row.contentSha256 {
                    hashed.append(row)
                    _ = existing
                    continue
                }
                if let sha = computeSha(for: row) {
                    try store.setContentSHA256(imageId: row.id, sha256: sha)
                    hashed.append(DedupImageRow(
                        id: row.id, birthTime: row.birthTime,
                        fileSize: row.fileSize, format: row.format,
                        relativePath: row.relativePath, urlBookmark: row.urlBookmark,
                        contentSha256: sha
                    ))
                } else {
                    // SHA256 失败（文件不可读） — 跳过此 row，不参与 dedup 决议
                    print("[Dedup] sha256 FAILED for image id=\(row.id) path=\(row.relativePath)")
                }
            }

            // 按 SHA256 分组决议 canonical
            let bySha = Dictionary(grouping: hashed, by: { $0.contentSha256 ?? "" })
            for (sha, sameSha) in bySha {
                guard !sha.isEmpty else { continue }
                if sameSha.count == 1 {
                    // 唯一 SHA256 — 设 canonical=1 显式标记
                    try store.setDedupCanonical(imageId: sameSha[0].id, canonical: true)
                } else {
                    // 多 row 同 SHA256：earliest birth_time + 最小 id tie-breaker
                    let sorted = sameSha.sorted { lhs, rhs in
                        if lhs.birthTime != rhs.birthTime { return lhs.birthTime < rhs.birthTime }
                        return lhs.id < rhs.id
                    }
                    if let canonical = sorted.first {
                        try store.setDedupCanonical(imageId: canonical.id, canonical: true)
                    }
                    for dup in sorted.dropFirst() {
                        try store.setDedupCanonical(imageId: dup.id, canonical: false)
                    }
                }
            }
        } catch {
            print("[Dedup] reEvaluateGroup(fileSize=\(fileSize), format=\(format)) FAILED: \(error)")
        }
    }

    /// 解析 root bookmark + 拼 relative_path 得 child URL → SHA256。
    /// urlBookmark 是 root bookmark（Slice A 决策 — sandbox 不允许子文件 .withSecurityScope）。
    private static func computeSha(for row: DedupImageRow) -> String? {
        var stale = false
        guard let rootURL = try? URL(
            resolvingBookmarkData: row.urlBookmark,
            options: [.withSecurityScope],
            bookmarkDataIsStale: &stale
        ) else { return nil }
        let didStart = rootURL.startAccessingSecurityScopedResource()
        defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }
        let fileURL = rootURL.appendingPathComponent(row.relativePath)
        return ContentHasher.sha256(of: fileURL)
    }
}
