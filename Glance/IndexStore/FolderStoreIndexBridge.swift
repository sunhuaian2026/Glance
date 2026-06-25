//
//  FolderStoreIndexBridge.swift
//  Glance
//
//  当 V1 FolderStore.rootFolders 变化时，把新 root 注册到 IndexStore
//  + 启动 FolderScanner 异步扫描。FolderStore 本身 0 改动，bridge 由
//  ContentView 在 IndexStore ready 后创建并显式调 sync(with:)。
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class FolderStoreIndexBridge: ObservableObject {

    let indexStore: IndexStore
    /// Track which root URLs we've already registered (by standardized path)
    /// to avoid duplicate registration / rescan across calls.
    private var registeredPaths: Set<String> = []

    /// Slice G.2 — 每 root 一个 FSEvents watcher，rootId → watcher dictionary。
    /// 删 root 时 stop + remove；新 root 注册扫描完成后 start。
    private var watchers: [Int64: FSEventsWatcher] = [:]
    private let watcherQueue = DispatchQueue(label: "com.sunhongjun.glance.fsevents", qos: .utility)

    /// M2 Slice J — FSEvents 派发新图后触发 fp indexer 重启拉一批新行。ContentView wireIfReady
    /// 调 setFeaturePrintIndexer 注入。weak 引用避免 retain cycle（indexer 由 IndexStoreHolder 强持）。
    private weak var featurePrintIndexer: FeaturePrintIndexer?

    func setFeaturePrintIndexer(_ indexer: FeaturePrintIndexer) {
        self.featurePrintIndexer = indexer
    }

    /// M4 D35 — index changed 多播 observer 容器（单播 var onIndexChanged 升级为
    /// UUID dict 多播）。Slice G.2 起 smartFolderStore.refreshSelected() 是唯一 observer；
    /// M4 任务 1 加 DuplicateOverviewModel 作为第二 observer 跟踪后台索引活动。
    /// 单播 `var onIndexChanged` 在多 observer 场景下后注册覆盖前注册 → 必须升级多播。
    /// @StateObject model 长寿不 deinit 无法用 capture-old-callback 链式调用绕开。
    private var indexChangedObservers: [UUID: () -> Void] = [:]

    /// 注册 index changed observer。返回 token，调用方持有（model 寿命 = app 寿命场景下
    /// 可 `_ = token` 忽略，未来 ContentView 重建场景需 detach 时按 token 调 remove）。
    @discardableResult
    func addIndexChangedObserver(_ observer: @escaping () -> Void) -> UUID {
        let token = UUID()
        indexChangedObservers[token] = observer
        return token
    }

    /// 按 token 移除 observer（M4 task 1 范围内未调用；预留供未来 ContentView 重建 detach 用）。
    func removeIndexChangedObserver(_ token: UUID) {
        indexChangedObservers.removeValue(forKey: token)
    }

    /// fire 帮助函数：snapshot 后遍历 fan-out 调所有 observer（顺序非确定，observer 间应独立）。
    /// snapshot：observer 回调里若调 removeIndexChangedObserver 会边遍历边改集合，先复制 values 防 trap。
    private func fireIndexChanged() {
        let snapshot = Array(indexChangedObservers.values)
        for observer in snapshot {
            observer()
        }
    }

    /// M4 任务 2 — 公开广播入口 (codex review P1(跨视图刷新闭环缺口) 修).
    /// TrashService 删除路径 / DuplicateOverviewModel.undo 撤销路径完成后主动调,
    /// 让智能文件夹 / 搜索 / 其它已注册 observer 视图自动刷新 (D33 跨视图持久 banner +
    /// 跨视图数据一致). 私有 fireIndexChanged 内部 fire 点不变, 公开版仅提供外部触发.
    func triggerIndexChanged() {
        fireIndexChanged()
    }

    /// Slice I.1 — 当首次扫描进度更新时调用，让 caller 把进度推到 UI（IndexStoreHolder
    /// .progress）。nil = 扫描结束或未开始 → 隐藏 progress chip。
    var onScanProgress: ((IndexingProgress?) -> Void)? = nil

    /// Slice I.2 — 扫描错误回调（catch error 后调；caller 设 holder.lastError 触发 banner）。
    var onScanError: ((String) -> Void)? = nil

    /// Slice I.2 — 当前正在跑的扫描 task；用户点 progress chip 上 X → bridge.cancelCurrentScan()
    /// 调 currentScanTask?.cancel() → FolderScanner.scan 内 Task.isCancelled 检测后 break。
    private var currentScanTask: Task<Void, Never>?

    func cancelCurrentScan() {
        currentScanTask?.cancel()
    }

    init(indexStore: IndexStore) {
        self.indexStore = indexStore
    }

    /// Diff incoming rootFolders vs registered set: add new + remove gone.
    /// Caller (ContentView) invokes whenever folderStore.rootFolders changes。
    /// Slice G.1：remove diff 调 IndexStore.deleteRoot 触发 FK CASCADE 连删 images +
    /// subfolder hide rows，破除 Slice A 的 stale row 残留。
    ///
    /// remove diff 改为 **DB + bookmark 权威对账**（修「侧边栏移除文件夹后智能文件夹仍残留缩略图」）：
    /// 删 DB 里所有不在 `managedRootPaths`（BookmarkManager 同步持久集，受管根真权威）的 root。
    /// **不**用内存 registeredPaths（启动空 → 从不对账清残留）也**不**用 rootFolders（异步滞后，
    /// 启动瞬态空集会误删整库）。managedRootPaths 同步读 UserDefaults 永不滞后，能区分
    /// "瞬态空" vs "用户删到最后一个"（后者 bookmark 集真空，删除正确）。
    func sync(with rootFolders: [FolderNode], managedRootPaths: Set<String>) async {
        // Add diff：注册 rootFolders 里尚未注册的 root（registeredPaths 防重复 rescan）
        let newRoots = rootFolders.filter { !registeredPaths.contains($0.url.standardizedFileURL.path) }
        for node in newRoots {
            await registerAndScan(rootURL: node.url)
            registeredPaths.insert(node.url.standardizedFileURL.path)
        }

        // Remove diff（DB 权威对账，Guard B）：删 DB 里不在受管根集的 root
        let dbRoots = (try? indexStore.fetchRootPaths()) ?? []
        for root in dbRoots where !managedRootPaths.contains(root.path) {
            await unregister(path: root.path)
            registeredPaths.remove(root.path)
        }

        // 防御性孤儿 image 清扫（folder_id 指向已删 folders 行；历史 FK off 遗留）。
        // 现行 FK ON 正常不产生孤儿；deleteRoot CASCADE 已清掉刚删 root 的 image，此处只兜历史遗留。
        if let orphans = try? indexStore.deleteOrphanImages(), orphans > 0 {
            print("[IndexStore] swept \(orphans) orphan image(s)")
            fireIndexChanged()
        }
    }

    /// Slice G.1 — 删 root 清理：path → IndexStore root id → deleteRoot。
    /// FK CASCADE 自动连删 images + subfolder hide rows；ContentView onChange 紧跟
    /// `smartFolderStore.refreshSelected()` 让 grid 立即反映。
    /// Slice G.2 — 同时 stop FSEvents watcher，释放 stream + queue 资源。
    private func unregister(path: String) async {
        do {
            guard let rootId = try indexStore.folderIdForRootPath(path) else {
                print("[IndexStore] unregister: no row for \(path) (already gone)")
                return
            }
            // 先 stop watcher（防 DELETE 后还有 events 派发到失效 folder_id）
            watchers[rootId]?.stop()
            watchers.removeValue(forKey: rootId)

            try indexStore.deleteRoot(rootId: rootId)
            print("[IndexStore] removed root \(path) (id=\(rootId)) — FK CASCADE cleaned images + subfolder rows")
            // Slice H — 删 root 后跑全 dedup pass（含 orphan cleanup 把孤儿 duplicate 升回
            // canonical=1，否则它们 dedup_canonical=0 永不在 grid 显示）
            triggerDedupFullPass()
        } catch {
            print("[IndexStore] unregister FAILED for \(path): \(error)")
        }
    }

    /// Register one root + scan in background. Security-scoped access is
    /// assumed already started by V1 BookmarkManager.startAccessing(url).
    /// 幂等：registerRoot 用 path 做 unique 键，重启同一 path 复用 id；
    /// FolderScanner 内 INSERT OR IGNORE 配合 UNIQUE(folder_id, relative_path)。
    private func registerAndScan(rootURL: URL) async {
        let normalizedPath = rootURL.standardizedFileURL.path
        do {
            let bookmark = try rootURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let folderId = try indexStore.registerRoot(path: normalizedPath, bookmark: bookmark)

            // 局部 capture indexStore 避免 capturing self 的 Sendable 警告。
            // indexStore 是 class，引用本身可跨 actor 边界。
            // rootBookmark capture 进 detached：scanner 把它复用到每条 image row 的
            // url_bookmark（macOS sandbox 不允许子文件创建 .withSecurityScope bookmark）
            let store = self.indexStore
            let rootBookmarkCopy = bookmark
            // Slice I.1 — 扫描启动前 set initial progress chip
            let rootName = rootURL.lastPathComponent
            onScanProgress?(IndexingProgress(rootName: rootName, scanned: 0, indexed: 0))

            // capture closure 安全：onScanProgress / onScanError 是 MainActor 闭包，
            // detached 内通过 Task @MainActor 调；rootName 局部 String 复制
            let progressCB = self.onScanProgress
            let errorCB = self.onScanError
            // Slice I.2 — read resume cursor（NULL → 全新扫；非 NULL → resume from cursor）
            let resumeFrom = (try? store.fetchLastProcessedPath(rootId: folderId)) ?? nil

            // Slice I.2 — 创建 cancellable task 让用户能点 progress chip X 中断
            let scanTask = Task.detached(priority: .utility) {
                let scanner = FolderScanner(store: store)
                do {
                    try scanner.scan(
                        rootURL: rootURL,
                        rootBookmark: rootBookmarkCopy,
                        folderId: folderId,
                        resumeFrom: resumeFrom
                    ) { p in
                        if p.totalScanned % 50 == 0 {
                            let snapshot = IndexingProgress(rootName: rootName, scanned: p.totalScanned, indexed: p.totalIndexed)
                            Task { @MainActor in progressCB?(snapshot) }
                        }
                    }
                    print("[IndexStore] scan complete for \(rootURL.path)\(resumeFrom != nil ? " (resumed from cursor)" : "")")
                } catch {
                    print("[IndexStore] scan FAILED for \(rootURL.path): \(error)")
                    let errMsg = "「\(rootName)」扫描失败：\(error.localizedDescription)"
                    Task { @MainActor in errorCB?(errMsg) }
                }
            }
            currentScanTask = scanTask
            await scanTask.value
            currentScanTask = nil

            // Slice I.1 — 扫描完成清 progress（nil = 隐藏 chip）
            onScanProgress?(nil)

            // Slice G.2 — 首次扫描完成后启动 FSEvents watcher 增量监听
            startWatcher(rootURL: rootURL, rootBookmark: bookmark, folderId: folderId)

            // Slice H — 扫描完成后跑 dedup pass（cheap-first：仅 candidate group 算 SHA256）
            triggerDedupFullPass()
        } catch {
            print("[IndexStore] registerAndScan FAILED for \(rootURL.path): \(error)")
        }
    }

    // MARK: - Slice H 内容去重 trigger（detached 后台跑，完后回 MainActor 触发 UI 刷新）

    private func triggerDedupFullPass() {
        let store = indexStore
        Task.detached(priority: .utility) { [weak self] in
            DedupPass.runFullPass(store: store)
            await MainActor.run { [weak self] in
                self?.fireIndexChanged()
            }
        }
    }

    private func triggerDedupGroup(fileSize: Int64, format: String) {
        let store = indexStore
        Task.detached(priority: .utility) { [weak self] in
            DedupPass.reEvaluateGroup(store: store, fileSize: fileSize, format: format)
            await MainActor.run { [weak self] in
                self?.fireIndexChanged()
            }
        }
    }

    // MARK: - Slice G.2 FSEvents 增量

    private func startWatcher(rootURL: URL, rootBookmark: Data, folderId: Int64) {
        let watcher = FSEventsWatcher(queue: watcherQueue) { [weak self] events in
            // events 在 watcherQueue 派发；切到 MainActor 处理 IndexStore mutation + UI 刷新
            Task { @MainActor [weak self] in
                self?.handleEvents(events, rootURL: rootURL, rootBookmark: rootBookmark, folderId: folderId)
            }
        }
        watcher.start(rootPath: rootURL.standardizedFileURL.path)
        watchers[folderId] = watcher
    }

    /// FSEvents callback 主路由（MainActor 上）。每 batch 处理完调一次 fireIndexChanged 触发 UI 刷新。
    /// Slice G.2 处理 Created；G.3 加 Removed + Modified + Renamed。
    /// Renamed 拆解为 delete old + insert new（按文件 exists 与否区分），实现"决策 4：rename
    /// = 不追踪 inode"。InodeMetaMod（permissions / chown 等无内容变化）跳过。
    private func handleEvents(_ events: [FSEvent], rootURL: URL, rootBookmark: Data, folderId: Int64) {
        var changed = false
        for event in events {
            guard event.isFile else { continue }
            let exists = FileManager.default.fileExists(atPath: event.path)

            if event.isRemoved || (event.isRenamed && !exists) {
                if handleRemoved(path: event.path, rootURL: rootURL, folderId: folderId) {
                    changed = true
                }
            } else if event.isCreated || (event.isRenamed && exists) {
                if handleCreated(path: event.path, rootURL: rootURL, rootBookmark: rootBookmark, folderId: folderId) {
                    changed = true
                }
            } else if event.isModified {
                if handleModified(path: event.path, rootURL: rootURL, folderId: folderId) {
                    changed = true
                }
            }
            // isInodeMetaMod 不影响图像内容 / dimensions，跳过
        }
        if changed { fireIndexChanged() }
    }

    /// FSEvents 派发的 Created event 通常在文件落盘瞬间触发；小概率元数据未稳定 → 此时
    /// ImageMetadataReader 返 nil 跳过（下一次 batch 的 Modified event 会补）。
    /// 返回 true 表示 IndexStore 状态有更新（caller 据此触发 UI refresh）。
    @discardableResult
    private func handleCreated(path: String, rootURL: URL, rootBookmark: Data, folderId: Int64) -> Bool {
        let fileURL = URL(fileURLWithPath: path)
        guard let metadata = ImageMetadataReader.read(at: fileURL) else { return false }
        let relPath = relativePath(of: fileURL, under: rootURL)
        let record = ImageInsertRecord(
            urlBookmark: rootBookmark,
            birthTime: metadata.birthTime,
            fileSize: metadata.fileSize,
            format: metadata.format,
            filename: metadata.filename,
            relativePath: relPath,
            folderId: folderId,
            dimensionsWidth: metadata.dimensionsWidth,
            dimensionsHeight: metadata.dimensionsHeight
        )
        do {
            _ = try indexStore.insertImageIfAbsent(record)
            // Slice H — 新图入索引 → 重新决议该 (file_size, format) group 的 canonical
            triggerDedupGroup(fileSize: metadata.fileSize, format: metadata.format)
            // M2 Slice J — 通知 fp indexer 重启拉新一批（含本图）
            // MainActor isolation: bridge is @MainActor; FSEvents callback hopped to
            // @MainActor in startWatcher's Task { @MainActor ... }; featurePrintIndexer
            // is @MainActor final class; this call is synchronous on MainActor — safe.
            featurePrintIndexer?.enqueueIfNeeded()
            return true
        } catch {
            print("[FSEvents] insertImageIfAbsent FAILED \(path): \(error)")
            return false
        }
    }

    /// Slice G.3 — FSEvents Removed (或 Renamed 后文件已不存在) 触发 IndexStore 删行。
    /// Slice H — 删行前 fetch group key (file_size, format) 用于后续 reEvaluateGroup
    /// （让该 group 重新决议 canonical，避免遗留 dangling 副本）。
    @discardableResult
    private func handleRemoved(path: String, rootURL: URL, folderId: Int64) -> Bool {
        let fileURL = URL(fileURLWithPath: path)
        let relPath = relativePath(of: fileURL, under: rootURL)
        let groupKey = try? indexStore.fetchImageGroupKey(folderId: folderId, relativePath: relPath)
        do {
            try indexStore.deleteImage(folderId: folderId, relativePath: relPath)
            if let key = groupKey {
                triggerDedupGroup(fileSize: key.fileSize, format: key.format)
            }
            return true
        } catch {
            print("[FSEvents] deleteImage FAILED \(path): \(error)")
            return false
        }
    }

    /// Slice G.3 — FSEvents Modified（文件内容/属性变更，非 inode-only-mod）。
    /// 重新 read metadata → UPDATE existing row（行不存在则视作 created path 误派发，走 INSERT）。
    /// Slice H — 内容已变 → reset SHA256 + canonical 到 NULL → trigger reEvaluateGroup。
    @discardableResult
    private func handleModified(path: String, rootURL: URL, folderId: Int64) -> Bool {
        let fileURL = URL(fileURLWithPath: path)
        guard let metadata = ImageMetadataReader.read(at: fileURL) else { return false }
        let relPath = relativePath(of: fileURL, under: rootURL)
        do {
            try indexStore.updateImageMetadata(folderId: folderId, relativePath: relPath, metadata: metadata)
            if let id = try? indexStore.fetchImageIdByPath(folderId: folderId, relativePath: relPath) {
                try? indexStore.resetSHA256AndCanonical(imageId: id)
            }
            triggerDedupGroup(fileSize: metadata.fileSize, format: metadata.format)
            return true
        } catch {
            print("[FSEvents] updateImageMetadata FAILED \(path): \(error)")
            return false
        }
    }

    /// 与 FolderScanner.relativePath 同算法（root 前缀去掉 + 删 leading "/"）。
    private func relativePath(of file: URL, under root: URL) -> String {
        let filePath = file.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if filePath.hasPrefix(rootPath) {
            return String(filePath.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
        }
        return file.lastPathComponent
    }

    /// M4 任务 2 — 撤销回补降级路径 (D34).
    /// restoreImageFromSnapshot 失败时 (snapshot 信息不全 / UNIQUE 冲突 / 业务认为该走
    /// FolderScanner 兜底) 走本 API. 实现路径: 找 folder root → resolve bookmark + 拼 child URL
    /// → ImageMetadataReader.read → insertImageIfAbsent → 返回新 row id.
    ///
    /// async 函数返回时 row 已恢复或明确失败, **禁止 fire-and-forget** (codex review 第三轮 P2(fire-and-forget 不行)).
    /// 调用方拿 id 立即 reEvaluateGroup + load() 无 race.
    ///
    /// 退化代价: 降级路径不还原 dedup_canonical / feature_print 系列 / exif_capture_date
    /// (IO 不可得), 这些列后续靠 DedupPass.reEvaluateGroup + FeaturePrintIndexer + EXIF
    /// reader 后台异步补齐. 用户感知: 撤销立即"图回来", 但 V2 找相似图 / 搜索可能需等几秒
    /// 到几分钟后台跑完.
    func requestRescan(folderId: Int64, relativePath: String) async throws -> Int64 {
        // 1. 找 root 拿 bookmark
        let roots = try indexStore.fetchRoots()
        guard let root = roots.first(where: { $0.id == folderId && $0.rootBookmark != nil }),
              let bookmark = root.rootBookmark else {
            throw NSError(domain: "M4.TaskTwo.RequestRescan", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "root folderId=\(folderId) not found or no bookmark"])
        }

        // 2. Resolve bookmark + startAccessing + 拼 child URL (复刻 DedupPass.computeSha 模式)
        let metadata: ImageMetadata? = await Task.detached(priority: .userInitiated) {
            var stale = false
            guard let rootURL = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &stale
            ) else { return nil }
            let didStart = rootURL.startAccessingSecurityScopedResource()
            defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }
            guard didStart else { return nil }
            let fileURL = rootURL.appendingPathComponent(relativePath)
            return ImageMetadataReader.read(at: fileURL)
        }.value

        guard let metadata else {
            throw NSError(domain: "M4.TaskTwo.RequestRescan", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "metadata read failed for \(relativePath) (file missing or scope denied)"])
        }

        // 3. insertImageIfAbsent (复用现有 ingest 路径)
        let record = ImageInsertRecord(
            urlBookmark: bookmark,
            birthTime: metadata.birthTime,
            fileSize: metadata.fileSize,
            format: metadata.format,
            filename: metadata.filename,
            relativePath: relativePath,
            folderId: folderId,
            dimensionsWidth: metadata.dimensionsWidth,
            dimensionsHeight: metadata.dimensionsHeight
        )
        let rowId = try indexStore.insertImageIfAbsent(record)
        return rowId
    }
}
