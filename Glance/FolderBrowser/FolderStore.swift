//
//  FolderStore.swift
//  Glance
//

import Foundation
import AppKit
import Combine

// MARK: - FolderNode（树形节点）

struct FolderNode: Identifiable, Hashable {
    let url: URL
    /// nil = 无子文件夹（叶节点）；non-nil = 有子文件夹（可展开）
    var children: [FolderNode]?

    var id: URL { url }

    static func == (lhs: FolderNode, rhs: FolderNode) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

// MARK: - Sort

enum SortKey: String, CaseIterable {
    case name = "名称"
    case date = "日期"
    case size = "大小"
}

enum SortDirection: String {
    case asc  = "asc"
    case desc = "desc"

    var toggled: SortDirection { self == .asc ? .desc : .asc }
    var icon: String { self == .asc ? "↑" : "↓" }
}

// MARK: - FolderStore

@MainActor
class FolderStore: ObservableObject {
    @Published var rootFolders: [FolderNode] = []
    @Published var selectedFolder: URL? = nil
    @Published var images: [URL] = []
    @Published var selectedImageIndex: Int? = nil
    @Published var isLoadingImages: Bool = false
    @Published var imageCountByFolder: [URL: Int] = [:]
    @Published var sortKey: SortKey = {
        let raw = UserDefaults.standard.string(forKey: "sortKey") ?? ""
        return SortKey(rawValue: raw) ?? .name
    }()

    @Published var sortDirection: SortDirection = {
        let raw = UserDefaults.standard.string(forKey: "sortDirection") ?? ""
        return SortDirection(rawValue: raw) ?? .asc
    }()

    // 统一入口：同步排序，消除异步竞态
    func applySortKey(_ key: SortKey, direction: SortDirection) {
        sortKey = key
        sortDirection = direction
        UserDefaults.standard.set(key.rawValue, forKey: "sortKey")
        UserDefaults.standard.set(direction.rawValue, forKey: "sortDirection")
        guard !images.isEmpty else { return }
        // 排序前清除选中状态，防止旧索引在新数组中指向错误图片
        selectedImageIndex = nil
        images = sortImagesSync(images)
    }

    /// V1 mode 当前选中 folder 的 FSEvents watcher。selectFolder 时停旧启新；
    /// removeFolder / 切到 V2 时停。callback 内 guard selectedFolder == 监听的 url 防 race。
    private var currentFolderWatcher: FSEventsWatcher?
    private let folderWatcherQueue = DispatchQueue(label: "com.sunhongjun.glance.fs.v1", qos: .utility)

    @Published var thumbnailSize: CGFloat = DS.Thumbnail.defaultSize {
        didSet {
            UserDefaults.standard.set(Double(thumbnailSize), forKey: "thumbnailSize")
        }
    }

    private let bookmarkManager: BookmarkManager

    private static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "svg"
    ]

    init(bookmarkManager: BookmarkManager) {
        self.bookmarkManager = bookmarkManager
        let saved = UserDefaults.standard.double(forKey: "thumbnailSize")
        if saved >= Double(DS.Thumbnail.minSize) && saved <= Double(DS.Thumbnail.maxSize) {
            thumbnailSize = CGFloat(saved)
        }
    }

    // MARK: - Public

    /// 当前持久化受管根路径集（转发 BookmarkManager，同步读 UserDefaults）。
    /// 索引对账（FolderStoreIndexBridge）用作权威来源——不用异步滞后的 rootFolders，
    /// 避免启动瞬态空集误删整个索引。
    var managedRootPaths: Set<String> { bookmarkManager.managedRootPaths() }

    func loadSavedFolders() {
        let restored = bookmarkManager.restoreBookmarks()
        for url in restored {
            _ = bookmarkManager.startAccessing(url)
        }
        Task {
            var nodes: [FolderNode] = []
            for url in restored {
                let node = await discoverTree(at: url)
                nodes.append(node)
            }
            rootFolders = nodes.sorted {
                $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
            // 统计各文件夹图片数（后台完成，badge 会自动更新）
            for node in rootFolders {
                await countImagesInTree(node)
            }
        }
    }

    /// V2 升级触发点用 — BookmarkManager.clearAllForMigration 后同步内存状态重置.
    /// 与 loadSavedFolders 区别: 主动清空 rootFolders + selectedFolder + images,
    /// 不调 restoreBookmarks (因为 clearAllForMigration 已清空持久化, 重新选才会有 root).
    /// 调用方: DuplicateOverviewModel.trashSelected 入口 (M4 删除入口首次, design 4.5.4.4).
    ///
    /// **同步停 currentFolderWatcher** (codex P2 修): reset 后旧 root FSEvents 不再派发避免回写;
    /// 已在跑的 scanImages Task 是 fire-and-forget, 回写前 scanImages 末尾 guard
    /// `selectedFolder == url` 兜底防覆盖.
    @MainActor
    func reloadFromDefaults() {
        currentFolderWatcher?.stop()
        currentFolderWatcher = nil
        rootFolders.removeAll()
        selectedFolder = nil
        images.removeAll()
        selectedImageIndex = nil
        imageCountByFolder.removeAll()
        isLoadingImages = false
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addFolder(from: url)
    }

    // Finder 拖入 / 程序化入口。非目录 URL 静默忽略；已存在则跳到选中。
    // autoSelect 默认 true；批量添加（addFolders 多 URL 分支）时传 false 保留原选择。
    func addFolder(from url: URL, autoSelect: Bool = true) {
        guard url.hasDirectoryPath else { return }

        if rootFolders.contains(where: { $0.url == url }) {
            if autoSelect { selectFolder(url) }
            return
        }

        do {
            try bookmarkManager.saveBookmark(for: url)
        } catch {
            print("saveBookmark failed: \(error)")
            return
        }

        _ = bookmarkManager.startAccessing(url)

        Task {
            let node = await discoverTree(at: url)
            rootFolders.append(node)
            rootFolders.sort {
                $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
            await countImagesInTree(node)
            if autoSelect { selectFolder(url) }
        }
    }

    // 批量添加（Finder 多选拖入）：单个 auto-select，多个保留当前选择避免焦点跳。
    func addFolders(from urls: [URL]) {
        let folders = urls.filter { $0.hasDirectoryPath }
        switch folders.count {
        case 0:
            return
        case 1:
            addFolder(from: folders[0], autoSelect: true)
        default:
            for url in folders {
                addFolder(from: url, autoSelect: false)
            }
        }
    }

    func removeFolder(_ url: URL) {
        guard rootFolders.contains(where: { $0.url == url }) else { return }
        bookmarkManager.stopAccessing(url)
        bookmarkManager.removeBookmark(for: url)
        rootFolders.removeAll { $0.url == url }
        imageCountByFolder.removeValue(forKey: url)
        // 若选中的是被删除树中的任意节点，则取消选择 + 停 V1 watcher
        if let selected = selectedFolder,
           selected == url || selected.path.hasPrefix(url.path + "/") {
            currentFolderWatcher?.stop()
            currentFolderWatcher = nil
            selectedFolder = nil
            images = []
            selectedImageIndex = nil
        }
    }

    func selectFolder(_ url: URL) {
        // 停旧 watcher（防切 folder 后旧 events 派发到错的 selectedFolder）
        currentFolderWatcher?.stop()
        currentFolderWatcher = nil

        selectedFolder = url
        selectedImageIndex = nil
        images = []
        Task { await scanImages(in: url) }

        // V1 FSEvents：监听 url 子树文件变化 → reload images
        startCurrentFolderWatcher(for: url)
    }

    /// V1 sidebar 右键"刷新"调。重建该 node 所属 root 的整子文件夹树（捕获 Finder 里新增/删除的子文件夹，
    /// FSEvents 偶发漏的兜底），同时刷该 root 树内所有节点的图片计数 + 若选中节点也在该树内则 reload grid 图片。
    /// 嵌套 root 场景按最长前缀匹配定位真实 root（避免错路由到 parent root）。
    func refreshNode(_ url: URL) {
        let nodePath = url.standardizedFileURL.path
        let candidates = rootFolders.map(\.url).filter { root in
            let rootPath = root.standardizedFileURL.path
            return rootPath == nodePath || nodePath.hasPrefix(rootPath + "/")
        }
        guard let rootURL = candidates.max(by: {
            $0.standardizedFileURL.path.count < $1.standardizedFileURL.path.count
        }) else { return }

        Task {
            let newNode = await discoverTree(at: rootURL)
            if let idx = rootFolders.firstIndex(where: { $0.url == rootURL }) {
                rootFolders[idx] = newNode
            }
            await countImagesInTree(newNode)
            // 若 selectedFolder 落在该 root 树内（含 root 本身），重扫 grid 图片
            if let selected = selectedFolder {
                let selPath = selected.standardizedFileURL.path
                let rootPath = rootURL.standardizedFileURL.path
                if selPath == rootPath || selPath.hasPrefix(rootPath + "/") {
                    await scanImages(in: selected)
                }
            }
        }
    }

    private func startCurrentFolderWatcher(for url: URL) {
        let watcher = FSEventsWatcher(queue: folderWatcherQueue) { [weak self] events in
            // 只关心文件变化（非 metadata-only），避免 inode meta 变动触发无意义 reload
            let hasFileChange = events.contains { ev in
                ev.isFile && (ev.isCreated || ev.isRemoved || ev.isModified || ev.isRenamed)
            }
            guard hasFileChange else { return }
            Task { @MainActor [weak self] in
                guard let self, let current = self.selectedFolder, current == url else { return }
                await self.scanImages(in: current)
            }
        }
        watcher.start(rootPath: url.standardizedFileURL.path)
        currentFolderWatcher = watcher
    }

    // MARK: - Tree Discovery

    /// 递归构建 FolderNode 树（只扫目录，不扫图片）
    private func discoverTree(at url: URL) async -> FolderNode {
        let subdirs: [URL] = await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return contents
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }.value

        if subdirs.isEmpty {
            return FolderNode(url: url, children: nil)
        }

        var children: [FolderNode] = []
        for subdir in subdirs {
            let child = await discoverTree(at: subdir)
            children.append(child)
        }
        return FolderNode(url: url, children: children)
    }

    /// 递归统计每个节点的直接图片数，结果写入 imageCountByFolder
    private func countImagesInTree(_ node: FolderNode) async {
        let ext = Self.supportedExtensions
        let url = node.url
        let count: Int = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return 0 }
            return contents.filter { ext.contains($0.pathExtension.lowercased()) }.count
        }.value
        imageCountByFolder[node.url] = count
        if let children = node.children {
            for child in children {
                await countImagesInTree(child)
            }
        }
    }

    // MARK: - Image Scanning

    private func scanImages(in url: URL) async {
        isLoadingImages = true
        let ext = Self.supportedExtensions
        let scanned: [URL] = await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return contents.filter { ext.contains($0.pathExtension.lowercased()) }
        }.value
        let sorted = await sortImages(scanned)
        // 旧 scan guard (codex P2 修, design 4.5.4.4 迁移流): 回写前确认 selectedFolder
        // 仍是发起扫描的 url. reloadFromDefaults 把 selectedFolder 清空后,
        // 已在跑的旧 scanImages 完成不会回写覆盖刚清的 images 数组.
        //
        // 关键: guard return 时**不动** isLoadingImages — 它属于当前活跃的 scanImages
        // (selectFolder 后新启的) 管, 否则旧 scan 完成把新 scan 设的 isLoadingImages=true
        // 擦掉, 新 scan 的 loading 指示器丢失 (codex pre-push P2 抓).
        guard selectedFolder == url else { return }
        images = sorted
        imageCountByFolder[url] = sorted.count
        isLoadingImages = false
    }

    // 同步排序：供 applySortKey 使用，URL 已在内存，无 I/O，毫秒级
    private func sortImagesSync(_ urls: [URL]) -> [URL] {
        let key = sortKey
        let asc = sortDirection == .asc
        switch key {
        case .name:
            return urls.sorted {
                let cmp = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                return asc ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        case .date:
            let keys: Set<URLResourceKey> = [.contentModificationDateKey]
            let dated: [(URL, Date)] = urls.map { url in
                let date = (try? url.resourceValues(forKeys: keys))?.contentModificationDate
                return (url, date ?? .distantPast)
            }
            return dated.sorted { asc ? $0.1 < $1.1 : $0.1 > $1.1 }.map { $0.0 }
        case .size:
            let keys: Set<URLResourceKey> = [.fileSizeKey]
            let sized: [(URL, Int)] = urls.map { url in
                let size = (try? url.resourceValues(forKeys: keys))?.fileSize
                return (url, size ?? Int.max)
            }
            return sized.sorted { asc ? $0.1 < $1.1 : $0.1 > $1.1 }.map { $0.0 }
        }
    }

    // 异步排序：供 scanImages 使用，避免扫描时阻塞主线程
    private func sortImages(_ urls: [URL]) async -> [URL] {
        let key = sortKey
        let asc = sortDirection == .asc
        return await Task.detached(priority: .userInitiated) {
            switch key {
            case .name:
                return urls.sorted {
                    let cmp = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                    return asc ? cmp == .orderedAscending : cmp == .orderedDescending
                }
            case .date:
                let keys: Set<URLResourceKey> = [.contentModificationDateKey]
                let dated: [(URL, Date)] = urls.map { url in
                    let date = (try? url.resourceValues(forKeys: keys))?.contentModificationDate
                    return (url, date ?? .distantPast)
                }
                return dated.sorted { asc ? $0.1 < $1.1 : $0.1 > $1.1 }.map { $0.0 }
            case .size:
                let keys: Set<URLResourceKey> = [.fileSizeKey]
                let sized: [(URL, Int)] = urls.map { url in
                    let size = (try? url.resourceValues(forKeys: keys))?.fileSize
                    return (url, size ?? Int.max)
                }
                return sized.sorted { asc ? $0.1 < $1.1 : $0.1 > $1.1 }.map { $0.0 }
            }
        }.value
    }
}
