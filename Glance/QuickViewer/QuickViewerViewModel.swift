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
    /// 快速看图器增强 任务 C — 单张删除后 removeCurrent() 需 in-place 改 images,
    /// 改成 private(set) var 让外部仍只读 (progress / canGoBack 等 computed 不破坏),
    /// 写权限仅本类内部.
    private(set) var images: [URL]
    @Published var currentIndex: Int
    @Published var currentNSImage: NSImage?
    /// 方案 3 — 加载失败（文件已删 / 解码失败）→ overlay 显占位而非无限 ProgressView。
    @Published var loadFailed = false

    // 缩放
    @Published var zoomMode: ZoomMode = .fit
    @Published var scale: CGFloat = 1.0
    @Published var offset: CGSize = .zero

    // 快速看图器增强 任务 A — 临时旋转 / 翻转状态（关窗丢失 + 切图重置）
    @Published var rotationQuarterTurns: Int = 0
    @Published var flippedH: Bool = false
    @Published var flippedV: Bool = false

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
        // 注: fitScale 内部已用 effectiveImageSize 口径，此处不必再换算
        return scale > fitScale(for: image, in: viewportSize)
    }

    // MARK: - Navigation

    func goBack() {
        guard canGoBack else { return }
        currentIndex -= 1
        resetRotationAndFlip()
        resetToFit()
        loadCurrentImage()
    }

    func goForward() {
        guard canGoForward else { return }
        currentIndex += 1
        resetRotationAndFlip()
        resetToFit()
        loadCurrentImage()
    }

    func goTo(index: Int) {
        guard index >= 0, index < images.count, index != currentIndex else { return }
        currentIndex = index
        resetRotationAndFlip()
        resetToFit()
        loadCurrentImage()
    }

    // MARK: - 快速看图器增强 任务 C — 单张删除后导航

    /// 列表是否被删空 (Overlay 据此触发 onDismiss 关 QV 窗 — D40 策略).
    /// computed 跟 images.isEmpty, removeCurrent 把最后一张删掉后立即翻 true.
    var wasEmptied: Bool { images.isEmpty }

    /// QuickViewerTrashCoordinator.trash 成功后由 Overlay 调.
    /// (a) 校验当前 index 合法 (b) 从 images in-place 移除 (c) 全清 prefetch 重建
    /// (d) D40 导航策略: 空 → 设 nil 让 Overlay onDismiss; 末尾被删 → 回退到新末尾; 否则
    /// 当前 index 自动落到下一张 (index 不变, 但 images[index] 已变).
    func removeCurrent() {
        // (a) 校验
        guard !images.isEmpty, currentIndex >= 0, currentIndex < images.count else { return }

        // (b) in-place 移除当前
        images.remove(at: currentIndex)

        // (c) prefetch 全清重建 — 不能仅 removeValue(forKey: currentIndex), 否则 > currentIndex
        //     的所有 key 错位 (cache 用 absolute index 做 key).
        clearPrefetchCache()

        // (d) D40 导航策略
        if images.isEmpty {
            // 列表空 → 让 Overlay onChange(wasEmptied) 触发 onDismiss; 不加载新图
            currentNSImage = nil
            return
        }
        if currentIndex >= images.count {
            // 删的是末尾 → 回退到新末尾
            currentIndex = images.count - 1
        }
        // 否则 currentIndex 不变, images[currentIndex] 已自动落到原来的下一张
        resetRotationAndFlip()
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

    // MARK: - Rotation / Flip (快速看图器增强 任务 A)

    /// 旋转 / 翻转后的有效图像尺寸（90/270° 宽高互换；翻转不变尺寸）。
    /// A.3 之后 fitScale / clampOffset / applyViewportSize / onImageLoaded 全用此口径。
    func effectiveImageSize(_ image: NSImage) -> CGSize {
        let normalized = ((rotationQuarterTurns % 4) + 4) % 4
        if normalized == 1 || normalized == 3 {
            return CGSize(width: image.size.height, height: image.size.width)
        }
        return image.size
    }

    func rotateLeft() {
        rotationQuarterTurns -= 1
        applyRotationLayoutSideEffects()
    }

    func rotateRight() {
        rotationQuarterTurns += 1
        applyRotationLayoutSideEffects()
    }

    /// 旋转后 fit 模式重算 scale（90/270 宽高互换后 fit 比例变了）；
    /// 非 fit 模式（zoomIn/Out 后）保 scale 仅 clamp 现 offset，避免缩放级别被旋转吞掉。
    private func applyRotationLayoutSideEffects() {
        if zoomMode == .fit, let image = currentNSImage, viewportSize != .zero {
            scale = fitScale(for: image, in: viewportSize)
            baseScale = scale
            offset = .zero
        } else {
            clampOffset()
        }
    }

    func toggleFlipH() {
        flippedH.toggle()
    }

    func toggleFlipV() {
        flippedV.toggle()
    }

    /// 切图时复位旋转/翻转（D34 — 每张独立，关窗即丢）。在 fitScale 重算前调用。
    private func resetRotationAndFlip() {
        rotationQuarterTurns = 0
        flippedH = false
        flippedV = false
    }

    // MARK: - Private

    // 打开默认自适应策略（Preview + Quick Look 混合）：
    //   图 ≤ 窗口：保 nativeScale（1:1 原生像素，避免上采样模糊，小图不强拉伸）
    //   图 >  窗口：缩到窗口 fitPadding 占比，四周留呼吸边
    //   全屏 + 图分辨率 ≥ viewport + 宽高比一致 (3% 容差) → 无 fitPadding 完美填满 (2026-06-25 军哥需求)
    func fitScale(for image: NSImage, in viewport: CGSize) -> CGFloat {
        let eff = effectiveImageSize(image)
        guard eff.width > 0, eff.height > 0 else { return DS.Viewer.nativeScale }
        let scaleW = viewport.width / eff.width
        let scaleH = viewport.height / eff.height
        let fit = min(scaleW, scaleH)
        if shouldFillFullScreen(image: eff, viewport: viewport) {
            return fit
        }
        return fit >= DS.Viewer.nativeScale ? DS.Viewer.nativeScale : fit * DS.Viewer.fitPadding
    }

    /// 全屏完美填满判定 (2026-06-25 军哥需求):
    /// (a) viewport 等于某个 NSScreen frame (1pt 容差兼容浮点); 任一全屏态 (qvNativeFullScreen /
    ///     windowedCover / inheritedMainFullScreen) viewport 都满屏, 不区分;
    /// (b) 图分辨率两维都 ≥ viewport (避免上采样模糊);
    /// (c) 宽高比与 viewport 的差 < 3% (避免勉强填满裁掉太多内容).
    /// 不满足任一 → 维持现状 fitPadding 留黑边.
    private func shouldFillFullScreen(image eff: CGSize, viewport: CGSize) -> Bool {
        let isFullScreen = NSScreen.screens.contains { screen in
            abs(viewport.width - screen.frame.width) < 1 &&
            abs(viewport.height - screen.frame.height) < 1
        }
        guard isFullScreen else { return false }
        guard eff.width >= viewport.width, eff.height >= viewport.height else { return false }
        let imgRatio = eff.width / eff.height
        let viewportRatio = viewport.width / viewport.height
        let ratioDiff = abs(imgRatio - viewportRatio) / viewportRatio
        return ratioDiff < 0.03
    }

    private func clampOffset() {
        guard let image = currentNSImage, viewportSize != .zero else {
            offset = .zero
            return
        }
        let eff = effectiveImageSize(image)
        let scaledW = eff.width * scale
        let scaledH = eff.height * scale
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

    // teardown 卫生：.id(idx) / .id(session.id) 重建销毁本 VM 时取消在途加载，减少 teardown 后
    // 还更新 UI/缓存的风险（外层 imageLoadTask 协作式 cancel；内层 Task.detached 同步读盘挡不住，
    // 故非 security-scope 安全边界——scope 生命周期由 ExternalViewerWindowController.retiredSessions 兜底）。
    deinit {
        imageLoadTask?.cancel()
        prefetchTasks.values.forEach { $0.cancel() }
    }
}
