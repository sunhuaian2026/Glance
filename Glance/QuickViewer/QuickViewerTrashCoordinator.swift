//
//  QuickViewerTrashCoordinator.swift
//  Glance
//
//  快速看图器增强 任务 C — 单张删除适配层.
//
//  与 DuplicateOverviewModel.trashSelected (M4 任务 2 批量删除入口) 共用 TrashService 底层,
//  但单张删除场景下不持选中 set / 不持总览 state, 只走 "URL → snapshot → trash → DB
//  prune → reEvaluateGroup → triggerIndexChanged" 极简流程.
//
//  D34 contract: 删前必须 fetchSnapshotForRestore 拿 15 字段保真 snapshot, 撤销 (任务 C 后续
//  toast [撤销] 按钮) 时 restoreImageFromSnapshot 全列回补避 M2/M3 退化.
//
//  Schema gate (D-M4-1 + design 4.5.4): currentSchemaVersion < 2 (V1 read-only bookmark)
//  时 trash 直接返 nil — V1 bookmark 无 trashItem 写权限, 触 V2 升级引导走 DuplicateOverviewModel
//  路径 (本 Coordinator 不弹引导, 由调用方 ContentView 处理).
//

import Foundation
import Combine

@MainActor
final class QuickViewerTrashCoordinator: ObservableObject {

    /// 显式 publisher — Coordinator 当前无 @Published 状态 (trash/restore 返 outcome 给调用方
    /// 渲染 toast, 不在本身持状态), 但保 ObservableObject 接口让 ContentView @StateObject 持.
    let objectWillChange = ObservableObjectPublisher()

    weak var indexStore: IndexStore?
    weak var bridge: FolderStoreIndexBridge?
    weak var bookmarkManager: BookmarkManager?

    init() {}

    /// 装配依赖. ContentView wireIfReady 阶段调一次.
    func attach(
        indexStore: IndexStore,
        bridge: FolderStoreIndexBridge,
        bookmarkManager: BookmarkManager
    ) {
        self.indexStore = indexStore
        self.bridge = bridge
        self.bookmarkManager = bookmarkManager
    }

    // MARK: - 主 API: 单张移入废纸篓

    /// 把 URL 对应的图片移入系统废纸篓 + 同步删 DB row + reEvaluateGroup + 跨视图广播.
    /// 返回 outcome (撤销用); nil 表示 schema gate 未过 / 索引未装配 / 路径未索引.
    func trash(url: URL) async -> TrashOutcome? {
        // (a) schema gate — V1 read-only bookmark 无 trashItem 写权限
        guard (bookmarkManager?.currentSchemaVersion ?? 0) >= 2 else { return nil }
        guard let store = indexStore else { return nil }
        guard let bridgeRef = bridge else { return nil }

        // (b) 反查 snapshot (15 字段保真); 路径未索引 / DB race → 跳过
        guard let snapshot = try? store.fetchSnapshotForRestore(byFullPath: url.path) else {
            return nil
        }

        // (c)/(d) 构造 TrashInput; GroupKey = (fileSize, format) — 删后 reEvaluateGroup 用
        let input = TrashService.TrashInput(
            snapshot: snapshot,
            groupKey: GroupKey(fileSize: snapshot.fileSize, format: snapshot.format)
        )

        // (e) 走 TrashService 主路径 (单 member 不发 progress; 单张无需取消但保持接口一致)
        let token = TrashCancellationToken()
        let outcome = await TrashService.trashItems(
            [input],
            cancellation: token,
            progress: { _, _ in }
        )

        // (f) 成功 → 删 DB row + reEvaluateGroup + promoteOrphanDuplicates + 广播
        if outcome.successCount == 1 {
            do {
                try store.deleteImage(folderId: snapshot.folderId, relativePath: snapshot.relativePath)
            } catch {
                NSLog("[QV-Trash-C] deleteImage failed for folder=%lld path=%@: %@",
                      snapshot.folderId, snapshot.relativePath, String(describing: error))
            }

            await Task.detached(priority: .utility) {
                DedupPass.reEvaluateGroup(store: store, fileSize: snapshot.fileSize, format: snapshot.format)
                try? store.promoteOrphanDuplicates()
            }.value

            bridgeRef.triggerIndexChanged()
        }

        // (g) 返回 outcome 让调用方 (Overlay toast) 渲染并提供 [撤销] 按钮
        return outcome
    }

    // MARK: - 撤销 API

    /// 撤销单张 trash 的 outcome. 把废纸篓内 URL 移回原路径 + restoreImageFromSnapshot 回补
    /// DB row + reEvaluateGroup + 广播.
    /// mirror DuplicateOverviewModel.undo(outcome:) 但简化为 single member 场景.
    func restore(outcome: TrashOutcome) async -> RestoreOutcome? {
        guard let store = indexStore else { return nil }
        guard let bridgeRef = bridge else { return nil }

        let token = TrashCancellationToken()

        // 1. restore 文件回原路径
        var restoreOutcome = await TrashService.restoreItems(outcome.successes, cancellation: token)

        // 2. 对 restore 成功的 member 显式回补 DB row; 双失败累积进 dbFailures
        var affectedGroups: Set<GroupKey> = []
        var dbFailures: [RestoreFailure] = []
        for success in restoreOutcome.successes {
            do {
                _ = try store.restoreImageFromSnapshot(success.snapshot)
                affectedGroups.insert(success.groupKey)
            } catch {
                // 首选失败 → 降级 requestRescan (mirror DuplicateOverviewModel:300 双失败兜底)
                do {
                    _ = try await bridgeRef.requestRescan(
                        folderId: success.snapshot.folderId,
                        relativePath: success.snapshot.relativePath
                    )
                    affectedGroups.insert(success.groupKey)
                } catch let rescanError {
                    NSLog("[QV-Trash-C undo] DOUBLE FAILURE for %@: snapshot=%@ rescan=%@",
                          success.originalFullPath,
                          String(describing: error),
                          String(describing: rescanError))
                    dbFailures.append(RestoreFailure(
                        originalFullPath: success.originalFullPath,
                        reason: "DB sync failed (file restored but index missing)"
                    ))
                }
            }
        }

        // 把 dbFailures 合进 restoreOutcome.failures 让 banner 一并展示
        if !dbFailures.isEmpty {
            restoreOutcome = RestoreOutcome(
                successes: restoreOutcome.successes,
                failures: restoreOutcome.failures + dbFailures,
                cancelled: restoreOutcome.cancelled
            )
        }

        // 3. 受影响组 reEvaluateGroup + 4. 广播
        await Task.detached(priority: .utility) {
            for key in affectedGroups {
                DedupPass.reEvaluateGroup(store: store, fileSize: key.fileSize, format: key.format)
            }
            try? store.promoteOrphanDuplicates()
        }.value

        bridgeRef.triggerIndexChanged()

        return restoreOutcome
    }
}
