//
//  DuplicateGroup.swift
//  Glance
//
//  M4 任务 1 — 重复清理总览的值类型 record。
//  每个 group 代表 SQL 聚合后的一组「content_sha256 相同 + 含 dedup_canonical=0 副本」的图，
//  含保留张（canonical）+ 待清理副本（duplicates）+ 可省空间（reclaimableBytes）。
//

import Foundation

/// 总览 view 渲染一组重复图的最小数据单位。
/// canonical 保留张 + duplicates 副本数组分开，UI 透明显示「保留这张」（D28 硬约束）。
struct DuplicateGroup: Identifiable, Equatable {
    /// SHA256 hex 字符串作为组的稳定 ID（同 sha256 即同组）
    let id: String
    /// 保留张（dedup_canonical = 1）的成员
    let canonical: DuplicateGroupMember
    /// 待清理副本（dedup_canonical = 0）的成员，按 birth_time ASC 排（与 SQL 一致）
    let duplicates: [DuplicateGroupMember]
    /// 副本可省空间总和（duplicates 的 fileSize 之和；保留张不计）
    let reclaimableBytes: Int64
}

/// 重复组内单张图的最小数据（任务 1 只读用）。
/// 任务 2 删除路径所需的额外字段（如 folderId）届时扩展，本 struct 不预装
/// （codex P2-3 修：避免任务 2 边界泄漏进任务 1 审查面）。
struct DuplicateGroupMember: Identifiable, Equatable {
    /// images.id（Identifiable 满足 UI ForEach 用；任务 1 不通过 id 删 row）
    let id: Int64
    /// images.folder_id（任务 2 加 — TrashService 走 IndexStore.fetchSnapshotForRestore /
    /// deleteImage 调用都按 (folderId, relativePath) 复合键, 直接 carry 避 N+1 反查;
    /// codex review P1-03 + P2-02 合一修, plan 步骤 2.0）
    let folderId: Int64
    /// images.url_bookmark（root bookmark，UI 渲染缩略图 resolve scope 用）
    let urlBookmark: Data
    /// images.relative_path（cell 显示用 + 缩略图 resolve 拼 child URL 用）
    let relativePath: String
    /// images.file_size（保留张 / 副本同 sha256 必然同 file_size，UI 显示和 reclaimable 计算用）
    let fileSize: Int64
    /// folders.root_path / relative_path 拼接的展示路径（cell tooltip 用，D28 透明显示来源路径）
    let fullPath: String
    /// dedup_canonical = 1（保留张）or 0（副本）— UI 渲染 badge / 弱化用
    let isCanonical: Bool
}

// MARK: - V2 helpers (任务 AB)

extension DuplicateGroup {
    /// 该组所有成员 (canonical + duplicates) 统一数组,D1 per-item 选择遍历用
    nonisolated var allMembers: [DuplicateGroupMember] {
        [canonical] + duplicates
    }

    /// 推荐保留张 — DedupPass canonical (= earliest birth_time + 最小 id tie-breaker;
    /// **不是体积最大** — D-dedup-14 SHA256 invariant 同组成员 fileSize 完全相等);
    /// model.userKeepId 无手选时回退到这个。
    nonisolated var recommendedKeepId: Int64 { canonical.id }

    /// 副本数 (= total members - 1)
    nonisolated var duplicateCount: Int { duplicates.count }
}

/// IndexStore.fetchDuplicateGroups 聚合查询返回行（每组一行：sha256 + 成员数 + reclaimable）。
/// Model 拿这行后调 fetchDuplicateGroupMembers 拉成员明细组装成 DuplicateGroup。
struct DuplicateGroupRow {
    let contentSha256: String
    let memberCount: Int64
    let reclaimableBytes: Int64
}

/// IndexStore.fetchDuplicateGroupMembers 成员明细查询返回行（每行一个 member）。
/// 任务 1 只读必需字段；任务 2 删除路径所需的 folder_id 届时扩展。
struct DuplicateGroupMemberRow {
    let id: Int64
    /// images.folder_id（任务 2 加 — SQL 同步 SELECT i.folder_id, model 组 member 时直接 carry）
    let folderId: Int64
    let dedupCanonical: Bool
    let fileSize: Int64
    let relativePath: String
    let urlBookmark: Data
    let fullPath: String
}
