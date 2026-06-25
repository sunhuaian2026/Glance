import Foundation

struct ScanProgress {
    let totalScanned: Int
    let totalIndexed: Int
    let lastIndexed: URL?
}

nonisolated final class FolderScanner {

    let store: IndexStore

    init(store: IndexStore) {
        self.store = store
    }

    /// Recursively scan a root URL and insert image records into IndexStore.
    /// `onProgress` is called every 50 files (best-effort).
    /// Caller must have started accessing the security-scoped resource if needed.
    /// `rootBookmark`：调用方已对 rootURL 创建好的 .withSecurityScope bookmark；scanner 把它
    /// 复制进每个 image row 的 url_bookmark 字段（**不**为 enumerator 出来的子文件单独创建
    /// bookmark —— macOS 沙盒规则：子 URL 仅通过 active 父 scope 隐式访问，自身无 scope，
    /// 不能创建 .withSecurityScope bookmark）。读图时由调用方解析 root bookmark + 拼
    /// relative_path 重建子 URL 访问。
    func scan(
        rootURL: URL,
        rootBookmark: Data,
        folderId: Int64,
        resumeFrom: String? = nil,
        onProgress: ((ScanProgress) -> Void)? = nil
    ) throws {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey, .contentTypeKey]
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw IndexDatabaseError.execFailed(sql: "FolderScanner.enumerator", message: "could not enumerate \(rootURL.path)")
        }

        var totalScanned = 0
        var totalIndexed = 0
        var lastIndexed: URL?
        var skippingForResume = (resumeFrom != nil)
        // Cleanup pass：仅完整 scan（非 resume）时收集，扫完删 stored - seen 的 stale row。
        // resume 场景跳过 cleanup 避免误删 lastProcessedPath 之前已 indexed 但本次未 enumerate 的合法 row。
        let isFullScan = (resumeFrom == nil)
        var seenPaths: Set<String> = []

        for case let fileURL as URL in enumerator {
            // Slice I.2 — Task cancellation：用户点 X / app 关闭 → break loop（cursor 已持久化）
            if Task.isCancelled {
                print("[FolderScanner] cancelled at scanned=\(totalScanned)")
                return
            }

            totalScanned += 1
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }

            let relPath = relativePath(of: fileURL, under: rootURL)

            // Slice I.2 — resume from cursor：跳过 ≤ lastProcessedPath 的文件（依赖 macOS
            // FileManager DirectoryEnumerator 字典序稳定 traversal）
            if skippingForResume, let resume = resumeFrom {
                if relPath <= resume {
                    continue
                }
                skippingForResume = false
            }

            guard let metadata = ImageMetadataReader.read(at: fileURL) else { continue }

            // 复用 root bookmark（不为子文件单独建 .withSecurityScope bookmark，sandbox 不允许）；
            // 读图时由调用方 resolve(rootBookmark) → startAccessing → root.appendingPathComponent(relPath)
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
            _ = try store.insertImageIfAbsent(record)
            totalIndexed += 1
            lastIndexed = fileURL
            if isFullScan { seenPaths.insert(relPath) }

            if totalIndexed % 100 == 0 {
                // Slice I.2 — 每 100 张写 cursor 让重启可 resume from 该位置
                try? store.setLastProcessedPath(rootId: folderId, path: relPath)
            }

            if totalScanned % 50 == 0 {
                onProgress?(ScanProgress(totalScanned: totalScanned, totalIndexed: totalIndexed, lastIndexed: lastIndexed))
            }
        }
        onProgress?(ScanProgress(totalScanned: totalScanned, totalIndexed: totalIndexed, lastIndexed: lastIndexed))
        // Slice I.2 — 扫完清 cursor，下次启动不再 resume
        try? store.clearLastProcessedPath(rootId: folderId)

        // Cleanup pass — 完整 scan 后删 stale row（FSEvents 离线漏掉的 delete/move）。
        // resume 场景 seenPaths 不全，跳过；DedupPass 在 cleanup 后由 caller 重跑修正 canonical。
        if isFullScan {
            do {
                let stored = try store.fetchAllRelativePaths(folderId: folderId)
                let stalePaths = Array(stored.subtracting(seenPaths))
                if !stalePaths.isEmpty {
                    let removed = try store.deleteImages(folderId: folderId, relativePaths: stalePaths)
                    print("[FolderScanner] cleanup folderId=\(folderId): removed \(removed) stale rows (offline delete/move)")
                }
            } catch {
                print("[FolderScanner] cleanup FAILED for folderId=\(folderId): \(error)")
            }
        }
    }

    private func relativePath(of file: URL, under root: URL) -> String {
        let filePath = file.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if filePath.hasPrefix(rootPath) {
            return String(filePath.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
        }
        return file.lastPathComponent
    }
}
