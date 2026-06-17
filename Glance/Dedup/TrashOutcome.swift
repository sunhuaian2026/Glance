//
//  TrashOutcome.swift
//  Glance
//
//  M4 任务 2 — TrashService 操作结果值类型 + 取消 token.
//

import Foundation

/// 整个 trash 操作的结果 (按 trashItems 一次调用为单位).
/// member 级 best-effort: 个别失败累积进 failures, 不中断其余.
///
/// nonisolated: 跨 actor 边界 (TrashService 后台 Task.detached 用; model @MainActor 也用).
struct TrashOutcome: Equatable, Sendable {
    /// 成功移入废纸篓的 member: 原 fullPath + 废纸篓内新 URL + snapshot (撤销回补用)
    let successes: [TrashSuccess]
    /// 失败的 member: 标识 + 错误描述 (banner 汇总用)
    let failures: [TrashFailure]
    /// 是否在中途被 cancellation 中止 (banner 副文案「已取消」用)
    let cancelled: Bool

    /// 便捷: 全部成功数 (banner 主文案「已移 N 张到废纸篓」用)
    var successCount: Int { successes.count }
    /// 便捷: 全部失败数 (banner 副文案「+M 张失败」用)
    var failureCount: Int { failures.count }
}

struct TrashSuccess: Equatable, Sendable {
    /// 删前原路径 (撤销 moveItem target)
    let originalFullPath: String
    /// 废纸篓内 URL (撤销 moveItem source) — FileManager.trashItem 通过 resultingItemURL out 参数返回
    let trashURL: URL
    /// 删前完整 snapshot (撤销 restoreImageFromSnapshot 首选路径用)
    let snapshot: IndexedImageSnapshot
    /// 受影响组的 (file_size, format) — 删后 reEvaluateGroup 用
    let groupKey: GroupKey
}

struct GroupKey: Equatable, Hashable, Sendable {
    let fileSize: Int64
    let format: String
}

struct TrashFailure: Equatable, Sendable {
    /// member 标识 (banner 显「<filename> 失败 (<原因>)」用)
    let filename: String
    let relativePath: String
    /// 失败原因描述 (NSError.localizedDescription 或自定义)
    let reason: String
}

/// 撤销操作结果. restoreItems 同样 best-effort, 个别失败 (target 路径已被占用 etc.) 累积.
struct RestoreOutcome: Equatable, Sendable {
    let successes: [RestoreSuccess]
    let failures: [RestoreFailure]
    let cancelled: Bool

    var successCount: Int { successes.count }
    var failureCount: Int { failures.count }
}

struct RestoreSuccess: Equatable, Sendable {
    /// 恢复回的原路径 (DB 回补按这个找 folderId + relativePath)
    let originalFullPath: String
    /// snapshot (restoreImageFromSnapshot 用)
    let snapshot: IndexedImageSnapshot
    let groupKey: GroupKey
}

struct RestoreFailure: Equatable, Sendable {
    let originalFullPath: String
    let reason: String
}

/// trash / restore 操作的取消 token. actor 保证多 task 安全 set + read.
actor TrashCancellationToken {
    private var cancelled = false

    func cancel() { cancelled = true }
    func isCancelled() -> Bool { cancelled }
}
