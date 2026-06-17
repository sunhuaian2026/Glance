//
//  TrashService.swift
//  Glance
//
//  M4 任务 2 — 全项目首个碰真实文件的服务. 仅本服务调 FileManager.trashItem
//  / FileManager.moveItem, 其它代码不允许直接调系统文件写操作.
//
//  Sandbox scope 模式严格复刻 DedupPass.computeSha:
//  resolveBookmark(.withSecurityScope) + startAccessingSecurityScopedResource
//  + appendingPathComponent + 真实操作 + defer stop. defer 配平.
//
//  member 级 best-effort: 个别 member 失败 (卷只读 / iCloud 未下载 / 文件已外部删 /
//  scope denied) 累积进 outcome.failures, 不中断其余. 整组内 member 不拆原子
//  (单组要么全 trash 要么全不动避免 reEvaluateGroup 半截组态紊乱) — 由 model 层
//  按组分批控, service 层逐 member trash.
//

import Foundation

nonisolated enum TrashService {

    /// 输入 member 描述 (撤销回补需 snapshot, 调用方预 fetch 好传入).
    struct TrashInput {
        let snapshot: IndexedImageSnapshot
        let groupKey: GroupKey
    }

    // MARK: - trashItems 主路径

    /// 移入系统废纸篓.
    /// caller (DuplicateOverviewModel.trashSelected) 已预 fetch 每 member 的
    /// IndexedImageSnapshot (调 IndexStore.fetchSnapshotForRestore 取 15 列),
    /// 这里只负责 file 操作. 删 DB row + reEvaluateGroup 由 caller 后续做.
    ///
    /// progress 回调每 50 member 一次 (避免 UI tick 过频); cancellation 中途检测
    /// 每 member 一次 (粒度最细, 单 member trash 是不可中断的原子).
    static func trashItems(
        _ items: [TrashInput],
        cancellation: TrashCancellationToken,
        progress: @Sendable @escaping (Int, Int) -> Void
    ) async -> TrashOutcome {
        var successes: [TrashSuccess] = []
        var failures: [TrashFailure] = []
        let total = items.count

        for (index, input) in items.enumerated() {
            if await cancellation.isCancelled() {
                return TrashOutcome(successes: successes, failures: failures, cancelled: true)
            }

            let snapshot = input.snapshot
            let result = await trashOne(snapshot: snapshot)
            switch result {
            case .success(let trashURL):
                if let origPath = composeOriginalFullPath(snapshot: snapshot) {
                    successes.append(TrashSuccess(
                        originalFullPath: origPath,
                        trashURL: trashURL,
                        snapshot: snapshot,
                        groupKey: input.groupKey
                    ))
                } else {
                    failures.append(TrashFailure(
                        filename: snapshot.filename,
                        relativePath: snapshot.relativePath,
                        reason: "trash succeeded but original path reconstruction failed"
                    ))
                }
            case .failure(let reason):
                failures.append(TrashFailure(
                    filename: snapshot.filename,
                    relativePath: snapshot.relativePath,
                    reason: reason
                ))
            }

            if (index + 1) % 50 == 0 || index == total - 1 {
                progress(index + 1, total)
            }
        }

        return TrashOutcome(successes: successes, failures: failures, cancelled: false)
    }

    private enum TrashOneResult {
        case success(trashURL: URL)
        case failure(reason: String)
    }

    /// 单 member trash. 复刻 DedupPass.computeSha 的 sandbox scope 模式.
    private static func trashOne(snapshot: IndexedImageSnapshot) async -> TrashOneResult {
        await Task.detached(priority: .userInitiated) {
            var stale = false
            guard let rootURL = try? URL(
                resolvingBookmarkData: snapshot.urlBookmark,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &stale
            ) else {
                return TrashOneResult.failure(reason: "bookmark resolve failed (stale=\(stale))")
            }
            let didStart = rootURL.startAccessingSecurityScopedResource()
            defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }
            guard didStart else {
                return TrashOneResult.failure(reason: "scope access denied (volume not mounted?)")
            }
            let fileURL = rootURL.appendingPathComponent(snapshot.relativePath)

            var trashURL: NSURL?
            do {
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: &trashURL)
            } catch {
                let ns = error as NSError
                return TrashOneResult.failure(reason: "trashItem failed (domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription))")
            }
            guard let trashed = trashURL as URL? else {
                return TrashOneResult.failure(reason: "trashItem returned no resultingURL")
            }
            return TrashOneResult.success(trashURL: trashed)
        }.value
    }

    /// 重组删前原 fullPath (撤销 moveItem target).
    /// 走 resolve bookmark 拿 rootURL.path + 拼 relativePath, 与 spike 模式一致.
    private static func composeOriginalFullPath(snapshot: IndexedImageSnapshot) -> String? {
        var stale = false
        guard let rootURL = try? URL(
            resolvingBookmarkData: snapshot.urlBookmark,
            options: [.withSecurityScope],
            bookmarkDataIsStale: &stale
        ) else { return nil }
        return rootURL.appendingPathComponent(snapshot.relativePath).path
    }

    // MARK: - restoreItems 撤销路径

    /// 从废纸篓恢复 (撤销). 把每个 TrashSuccess.trashURL 移回 originalFullPath.
    /// codex review P2(target 已占用) policy (第一轮 + design 6 节): 失败累积报告,
    /// **不擅自改名 / 不擅自覆盖**.
    static func restoreItems(
        _ successes: [TrashSuccess],
        cancellation: TrashCancellationToken
    ) async -> RestoreOutcome {
        var restored: [RestoreSuccess] = []
        var failed: [RestoreFailure] = []

        for success in successes {
            if await cancellation.isCancelled() {
                return RestoreOutcome(successes: restored, failures: failed, cancelled: true)
            }

            let result = await restoreOne(success: success)
            switch result {
            case .success:
                restored.append(RestoreSuccess(
                    originalFullPath: success.originalFullPath,
                    snapshot: success.snapshot,
                    groupKey: success.groupKey
                ))
            case .failure(let reason):
                failed.append(RestoreFailure(
                    originalFullPath: success.originalFullPath,
                    reason: reason
                ))
            }
        }

        return RestoreOutcome(successes: restored, failures: failed, cancelled: false)
    }

    private enum RestoreOneResult {
        case success
        case failure(reason: String)
    }

    /// 单 member restore. 复刻 trashOne sandbox scope 模式 + FileManager.moveItem.
    private static func restoreOne(success: TrashSuccess) async -> RestoreOneResult {
        await Task.detached(priority: .userInitiated) {
            var stale = false
            guard let rootURL = try? URL(
                resolvingBookmarkData: success.snapshot.urlBookmark,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &stale
            ) else {
                return RestoreOneResult.failure(reason: "bookmark resolve failed (stale=\(stale))")
            }
            let didStart = rootURL.startAccessingSecurityScopedResource()
            defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }
            guard didStart else {
                return RestoreOneResult.failure(reason: "scope access denied (volume not mounted?)")
            }

            let targetURL = URL(fileURLWithPath: success.originalFullPath)
            // codex review P2(target 占用): pre-check fileExists, 真占用直接累积 failure 不改名不覆盖
            if FileManager.default.fileExists(atPath: targetURL.path) {
                return RestoreOneResult.failure(reason: "target path already occupied (please handle via Finder)")
            }

            do {
                try FileManager.default.moveItem(at: success.trashURL, to: targetURL)
                return RestoreOneResult.success
            } catch {
                let ns = error as NSError
                return RestoreOneResult.failure(reason: "moveItem failed (domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription))")
            }
        }.value
    }
}
