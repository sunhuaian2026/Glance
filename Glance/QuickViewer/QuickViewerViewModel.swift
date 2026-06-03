//
//  QuickViewerViewModel.swift
//  Glance
//

import Foundation
import AppKit
import Combine

enum ZoomMode {
    case fit
    case oneToOne
    case custom
}

class QuickViewerViewModel: ObservableObject {
    // 数据
    let images: [URL]
    @Published var currentIndex: Int
    @Published var currentNSImage: NSImage?
    /// 方案 3 — 加载失败（文件已删 / 解码失败）→ overlay 显占位而非无限 ProgressView。
    @Published var loadFailed = false

    // 缩放
    @Published var zoomMode: ZoomMode = .fit
    @Published var scale: CGFloat = 1.0
    @Published var offset: CGSize = .zero

    // 辅助
    var baseScale: CGFloat = 1.0
    var viewportSize: CGSize = .zero

    private var imageLoadTask: Task<Void, Never>?

    // MARK: - Prefetch Cache

    private var prefetchCache: [Int: CGImage] = [:]
    private var prefetchTasks: [Int: Task<Void, Never>] = [:]

    init(images: [URL], startIndex: Int) {
        self.images = images
        self.currentIndex = max(0, min(startIndex, images.count - 1))
        loadCurrentImage()
    }

    // MARK: - Computed

    var progress: String { "\(currentIndex + 1) / \(images.count)" }

    var zoomPercent: String { "\(Int(scale * 100))%" }

    var canGoBack: Bool { currentIndex > 0 }

    var canGoForward: Bool { currentIndex < images.count - 1 }

    var canPan: Bool {
        guard let image = currentNSImage, viewportSize != .zero else { return false }
        return scale > fitScale(for: image, in: viewportSize)
    }

    // MARK: - Navigation

    func goBack() {
        guard canGoBack else { return }
        currentIndex -= 1
        resetToFit()
        loadCurrentImage()
    }

    func goForward() {
        guard canGoForward else { return }
        currentIndex += 1
        resetToFit()
        loadCurrentImage()
    }

    func goTo(index: Int) {
        guard index >= 0, index < images.count, index != currentIndex else { return }
        currentIndex = index
        resetToFit()
        loadCurrentImage()
    }

    // MARK: - Zoom

    func resetToFit() {
        zoomMode = .fit
        if let image = currentNSImage, viewportSize != .zero {
            scale = fitScale(for: image, in: viewportSize)
        } else {
            scale = 1.0
        }
        offset = .zero
        baseScale = scale
    }

    func resetToOneToOne() {
        zoomMode = .oneToOne
        scale = 1.0
        offset = .zero
        baseScale = 1.0
    }

    func zoomIn() {
        let newScale = min(scale * 1.25, DS.Viewer.maxZoom)
        scale = newScale
        zoomMode = .custom
        baseScale = scale
        clampOffset()
    }

    func zoomOut() {
        let newScale = max(scale / 1.25, DS.Viewer.minZoom)
        scale = newScale
        zoomMode = .custom
        baseScale = scale
        clampOffset()
    }

    func setScale(_ s: CGFloat, anchor: CGPoint, viewSize: CGSize) {
        let clamped = max(DS.Viewer.minZoom, min(DS.Viewer.maxZoom, s))
        let ratio = clamped / scale

        // 以光标为中心调整 offset
        let anchorOffsetX = anchor.x - viewSize.width / 2
        let anchorOffsetY = anchor.y - viewSize.height / 2
        offset = CGSize(
            width: (offset.width + anchorOffsetX) * ratio - anchorOffsetX,
            height: (offset.height + anchorOffsetY) * ratio - anchorOffsetY
        )

        scale = clamped
        zoomMode = .custom
        clampOffset()
    }

    // 拖拽平移：每次 mouseDragged 累加增量，由 VM 内 clampOffset 兜底边界。
    // 由 ZoomScrollView.mouseDragged 调用；event.delta 是自上次 event 的 incremental 位移。
    func panBy(deltaX: CGFloat, deltaY: CGFloat) {
        offset = CGSize(
            width: offset.width + deltaX,
            height: offset.height + deltaY
        )
        clampOffset()
    }

    func applyViewportSize(_ size: CGSize) {
        guard size != viewportSize else { return }
        viewportSize = size
        if zoomMode == .fit, let image = currentNSImage {
            scale = fitScale(for: image, in: size)
            baseScale = scale
        }
    }

    func onImageLoaded(_ image: NSImage) {
        if zoomMode == .fit, viewportSize != .zero {
            scale = fitScale(for: image, in: viewportSize)
            baseScale = scale
        }
        offset = .zero
    }

    // MARK: - Private

    // 打开默认自适应策略（Preview + Quick Look 混合）：
    //   图 ≤ 窗口：保 nativeScale（1:1 原生像素，避免上采样模糊，小图不强拉伸）
    //   图 >  窗口：缩到窗口 fitPadding 占比，四周留呼吸边
    func fitScale(for image: NSImage, in viewport: CGSize) -> CGFloat {
        guard image.size.width > 0, image.size.height > 0 else { return DS.Viewer.nativeScale }
        let scaleW = viewport.width / image.size.width
        let scaleH = viewport.height / image.size.height
        let fit = min(scaleW, scaleH)
        return fit >= DS.Viewer.nativeScale ? DS.Viewer.nativeScale : fit * DS.Viewer.fitPadding
    }

    private func clampOffset() {
        guard let image = currentNSImage, viewportSize != .zero else {
            offset = .zero
            return
        }
        let scaledW = image.size.width * scale
        let scaledH = image.size.height * scale
        let maxOffsetX = max(0, (scaledW - viewportSize.width) / 2)
        let maxOffsetY = max(0, (scaledH - viewportSize.height) / 2)
        offset = CGSize(
            width: max(-maxOffsetX, min(maxOffsetX, offset.width)),
            height: max(-maxOffsetY, min(maxOffsetY, offset.height))
        )
    }

    private func loadCurrentImage() {
        let url = images[currentIndex]
        let idx = currentIndex

        // Cache hit：直接使用已解码的 CGImage
        if let cached = prefetchCache[idx] {
            let nsImage = NSImage(cgImage: cached, size: NSSize(width: cached.width, height: cached.height))
            currentNSImage = nsImage
            loadFailed = false
            onImageLoaded(nsImage)
            prefetchAdjacent()
            return
        }

        // Cache miss：从磁盘加载
        currentNSImage = nil
        loadFailed = false
        imageLoadTask?.cancel()
        imageLoadTask = Task {
            let result: NSImage? = await Task.detached(priority: .userInitiated) {
                loadFullNSImage(url: url)
            }.value
            guard !Task.isCancelled else { return }
            currentNSImage = result
            loadFailed = (result == nil)
            if let image = result {
                onImageLoaded(image)
            }
            prefetchAdjacent()
        }
    }

    // MARK: - Prefetch

    private func prefetchAdjacent() {
        let targets = [currentIndex - 1, currentIndex + 1]
            .filter { $0 >= 0 && $0 < images.count }
            .filter { prefetchCache[$0] == nil && prefetchTasks[$0] == nil }

        for idx in targets {
            let url = images[idx]
            // SVG vector 没 CGImage 形态，跳过 prefetch（cache miss 时主路径走 NSImage 直 load）
            if url.pathExtension.lowercased() == "svg" { continue }
            prefetchTasks[idx] = Task.detached(priority: .background) { [weak self] in
                guard let self else { return }
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
                await MainActor.run {
                    self.prefetchCache[idx] = img
                    self.prefetchTasks.removeValue(forKey: idx)
                    self.evictCacheIfNeeded()
                }
            }
        }
    }

    private func evictCacheIfNeeded() {
        let keepRange = (currentIndex - 2)...(currentIndex + 2)
        prefetchCache.keys
            .filter { !keepRange.contains($0) }
            .forEach { prefetchCache.removeValue(forKey: $0) }
    }

    func clearPrefetchCache() {
        prefetchTasks.values.forEach { $0.cancel() }
        prefetchTasks.removeAll()
        prefetchCache.removeAll()
    }
}
