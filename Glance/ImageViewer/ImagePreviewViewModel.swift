//
//  ImagePreviewViewModel.swift
//  Glance
//
//  ImagePreviewView 的状态管理 + ±1 预加载缓存。
//  与 QuickViewerViewModel 的 prefetch 策略对齐：方向键切换命中缓存零延迟。
//

import Foundation
import AppKit
import Combine

final class ImagePreviewViewModel: ObservableObject {
    // 预加载/缓存窗口（与 QuickViewerViewModel 策略对齐）
    private static let prefetchRadius = 1   // 预加载 currentIndex ± 1
    private static let cacheKeepRadius = 2  // 缓存保留 currentIndex ± 2，超出 evict

    @Published var nsImage: NSImage?
    /// 方案 3 — 加载失败（文件已删 / 解码失败）→ View 显占位而非无限 ProgressView。
    @Published var loadFailed = false

    private var imageLoadTask: Task<Void, Never>?
    private var prefetchCache: [Int: CGImage] = [:]
    private var prefetchTasks: [Int: Task<Void, Never>] = [:]

    func load(images: [URL], index: Int) {
        guard images.indices.contains(index) else {
            nsImage = nil
            loadFailed = false
            return
        }
        let url = images[index]

        // 任何切换都先取消上一张未完成的磁盘读取，避免后到的旧 task 覆盖当前图
        imageLoadTask?.cancel()
        imageLoadTask = nil
        loadFailed = false

        if let cached = prefetchCache[index] {
            nsImage = NSImage(cgImage: cached, size: NSSize(width: cached.width, height: cached.height))
            prefetchAdjacent(images: images, currentIndex: index)
            return
        }

        nsImage = nil
        // prefetch 与当前张磁盘读并发启动；不等首张读完才排队，避免用户 < 1s 按方向键时 prefetch 还没跑
        prefetchAdjacent(images: images, currentIndex: index)
        imageLoadTask = Task { [weak self] in
            let result: NSImage? = await Task.detached(priority: .userInitiated) {
                loadFullNSImage(url: url)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.nsImage = result
            self.loadFailed = (result == nil)
        }
    }

    func clearCache() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        prefetchTasks.values.forEach { $0.cancel() }
        prefetchTasks.removeAll()
        prefetchCache.removeAll()
    }

    private func prefetchAdjacent(images: [URL], currentIndex: Int) {
        let r = Self.prefetchRadius
        let targets = (-r...r)
            .filter { $0 != 0 }
            .map { currentIndex + $0 }
            .filter { $0 >= 0 && $0 < images.count }
            .filter { prefetchCache[$0] == nil && prefetchTasks[$0] == nil }

        for idx in targets {
            let url = images[idx]
            // SVG 是 vector 没 CGImage 形态；prefetchCache 类型 [Int: CGImage] 存不了，
            // 跳过 prefetch（vector 文件通常 KB 级，cache miss 时主路径走 NSImage 直接 load 不亏）
            if url.pathExtension.lowercased() == "svg" { continue }
            prefetchTasks[idx] = Task { [weak self] in
                let img: CGImage? = await Task.detached(priority: .utility) {
                    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
                    return cg
                }.value
                guard let self, !Task.isCancelled, let img else { return }
                self.prefetchCache[idx] = img
                self.prefetchTasks.removeValue(forKey: idx)
                self.evictCacheIfNeeded(currentIndex: currentIndex)
            }
        }
    }

    private func evictCacheIfNeeded(currentIndex: Int) {
        let r = Self.cacheKeepRadius
        let keepRange = (currentIndex - r)...(currentIndex + r)
        prefetchCache.keys
            .filter { !keepRange.contains($0) }
            .forEach { prefetchCache.removeValue(forKey: $0) }
    }
}
