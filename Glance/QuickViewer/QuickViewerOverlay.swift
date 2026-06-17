//
//  QuickViewerOverlay.swift
//  Glance
//

import SwiftUI

struct QuickViewerOverlay: View {
    @StateObject private var viewModel: QuickViewerViewModel
    @EnvironmentObject var appState: AppState
    let onDismiss: () -> Void
    // QV 内方向键 / nav button (goBack/goForward) / filmstrip tap (goTo) 都触发
    // viewModel.currentIndex 变化，统一通过此回调上报给 ContentView 同步 selectedImageIndex
    let onIndexChange: (Int) -> Void
    /// M2 Slice J — 用户点「找类似」按钮触发；caller (ContentView) 接到当前图 URL 后
    /// 反查 image id + 调 SimilarityService.queryTopN + 切到 EphemeralResultView。
    /// nil → 不渲染按钮（caller 未提供能力时静默隐藏）。
    let onFindSimilar: ((URL) -> Void)?
    /// M2 Slice J — 当前图是否支持找类似（IndexStore.supports_feature_print 反查）。
    /// false → 按钮 disable + tooltip 提示。caller 在 ContentView 算好传入。
    let currentSupportsFeaturePrint: Bool
    /// M3 Slice M — QV 内按 ⌘F → ContentView 同帧关 QV + 浮 search overlay。
    /// nil = 无搜索能力（caller 未提供时静默 fallback 到全屏切换）。
    let onCommandF: (() -> Void)?
    /// Slice 2 Task2.1 — 全屏切换经 controller 路由（4 态状态机前提）。
    /// nil → 退化到 appState.toggleFullScreen()（ExternalViewer 等独立看图窗不路由）。
    let onToggleFullScreen: (() -> Void)?
    /// 任务 C.5/C.6 — 单张移废纸篓回调，按 Delete/⌘⌫/右键菜单触发。
    /// nil = 不渲染删除入口（ExternalViewer OpenWith 路径不挂主索引，无删除能力）。
    let onTrash: ((URL) async -> TrashOutcome?)?

    @FocusState private var isFocused: Bool
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    /// 任务 A.7 — 当前图 metadata（分辨率 · 大小），跟随 currentIndex 异步加载；nil = 未加载完 / 失败 → 气泡不渲染
    @State private var currentMetadata: ImageMetadata?
    /// 任务 C.6 — 单张删除成功 toast state（含 outcome 用于撤销）
    @State private var trashUndoOutcome: TrashOutcome?
    /// 任务 C.6 — 单张删除失败 toast state（codex P0 修支持失败显式提示）
    @State private var trashFailureMessage: String?
    /// 任务 C.6 — toast auto-dismiss timer
    @State private var trashDismissTask: Task<Void, Never>?

    init(
        images: [URL],
        startIndex: Int,
        onDismiss: @escaping () -> Void,
        onIndexChange: @escaping (Int) -> Void,
        onFindSimilar: ((URL) -> Void)? = nil,
        currentSupportsFeaturePrint: Bool = true,
        onCommandF: (() -> Void)? = nil,
        onToggleFullScreen: (() -> Void)? = nil,
        onTrash: ((URL) async -> TrashOutcome?)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: QuickViewerViewModel(images: images, startIndex: startIndex))
        self.onDismiss = onDismiss
        self.onIndexChange = onIndexChange
        self.onFindSimilar = onFindSimilar
        self.currentSupportsFeaturePrint = currentSupportsFeaturePrint
        self.onCommandF = onCommandF
        self.onToggleFullScreen = onToggleFullScreen
        self.onTrash = onTrash
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 背景
                DS.Color.appBackground
                    .ignoresSafeArea()

                // 紫色光晕（左上角）
                RadialGradient(
                    colors: [DS.Color.glowPrimary.opacity(0.15), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 350
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // 青绿光晕（右下角）
                RadialGradient(
                    colors: [DS.Color.glowSecondary.opacity(0.10), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 400
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // 图片 + 缩放层
                ZoomScrollView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        imageLayer
                    }
                    // 任务 B.5 — 右键菜单（D37 快捷键可发现镜像）；任务 C 会在末尾追加「移到废纸篓」
                    .contextMenu {
                        Button { viewModel.rotateLeft() } label: {
                            Label("旋转左 (L)", systemImage: DS.Icon.rotateLeft)
                        }
                        Button { viewModel.rotateRight() } label: {
                            Label("旋转右 (R)", systemImage: DS.Icon.rotateRight)
                        }
                        Divider()
                        Button { viewModel.toggleFlipH() } label: {
                            Label("水平翻转", systemImage: DS.Icon.flipHorizontal)
                        }
                        Button { viewModel.toggleFlipV() } label: {
                            Label("垂直翻转", systemImage: DS.Icon.flipVertical)
                        }
                        Divider()
                        Button { copyImageToPasteboard() } label: {
                            Label("复制图片 (⌘C)", systemImage: DS.Icon.copy)
                        }
                        .disabled(viewModel.currentNSImage == nil)
                        Button { copyCurrentPath() } label: {
                            Label("复制路径 (⌘⌥C)", systemImage: DS.Icon.copyPath)
                        }
                        Button { revealInFinder() } label: {
                            Label("在 Finder 中显示 (⌘⇧R)", systemImage: DS.Icon.finder)
                        }
                    }

                // 顶部状态栏
                VStack {
                    topBar
                    Spacer()
                }
                .opacity(controlsVisible ? 1 : 0)

                // 左右导航
                HStack {
                    navButton(systemImage: DS.Icon.previous, enabled: viewModel.canGoBack, help: "上一张 (←)") {
                        viewModel.goBack()
                    }
                    Spacer()
                    navButton(systemImage: DS.Icon.next, enabled: viewModel.canGoForward, help: "下一张 (→)") {
                        viewModel.goForward()
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Viewer.filmstripHeight + DS.Spacing.sm)
                .opacity(controlsVisible ? 1 : 0)

                // 底部：工具栏 + 胶片条
                VStack(spacing: 0) {
                    Spacer()
                    bottomToolbar
                        .opacity(controlsVisible ? 1 : 0)
                    filmstrip
                        .opacity(controlsVisible ? 1 : 0)
                }

                // 任务 A.7 — 左下角信息气泡（分辨率 · 大小），跟随 controlsVisible 隐藏
                VStack {
                    Spacer()
                    HStack {
                        infoBadge
                            .opacity(controlsVisible ? 1 : 0)
                        Spacer()
                    }
                }
                .padding(.leading, DS.Spacing.lg)
                .padding(.bottom, DS.Viewer.filmstripHeight + DS.Spacing.md)
                .allowsHitTesting(false)

                // 任务 C.7 — 右下角 toast（成功 撤销 / 失败 提示），不跟 controlsVisible 联动：
                // 反馈通知不应随鼠标静止隐藏，跟 M4 全局 banner 行为对齐。允许命中（撤销/× 按钮）。
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        trashToast
                    }
                }
                .padding(.trailing, DS.Spacing.lg)
                .padding(.bottom, DS.Viewer.filmstripHeight + DS.Spacing.md)
            }
            .onAppear {
                viewModel.applyViewportSize(geo.size)
                requestKeyboardFocusIfWindowIsKey()
                showControlsTemporarily()
                loadCurrentMetadata()
            }
            .onChange(of: geo.size) { _, newSize in
                viewModel.applyViewportSize(newSize)
            }
            // 外部打开/冷启动路径：onAppear 时窗口可能还不是 key，isFocused 赋值被丢弃。
            // 等 windowDidBecomeKey → isWindowKey 翻 true 时补 assert，ESC 无需先点击即生效。
            .onChange(of: appState.isWindowKey) { _, _ in
                requestKeyboardFocusIfWindowIsKey()
            }
            // 监听 viewModel.currentIndex 一处统一上报，覆盖 nav button (goBack/goForward)
            // / filmstrip tap (goTo) / 方向键 三种 QV 内导航路径，避免补 key handler 漏渠道
            .onChange(of: viewModel.currentIndex) { _, newValue in
                onIndexChange(newValue)
                loadCurrentMetadata()
            }
        }
        // 用本地 SwiftUI environment 注入 dark colorScheme 而非 .preferredColorScheme(.dark)。
        // .preferredColorScheme 是 presentation-scoped 偏好（写到 NSHostingView/NSWindow.contentView
        // appearance 链），ESC 退 QV 时撤销时序滞后，会渗透 dark 到底层 sidebar/preview，浅色模式下
        // 出现"sidebar 变灰 / 整个 app 变深"现象，需失焦自愈。.environment(\.colorScheme, .dark) 仅
        // 影响 QV 子树 SwiftUI 环境，QV 内部全用显式颜色无 AppKit material 故视觉等价
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear  { appState.hideTrafficLights() }
        .onDisappear {
            hideTask?.cancel()
            appState.showTrafficLights()
            viewModel.clearPrefetchCache()
        }
        .onContinuousHover { phase in
            switch phase {
            case .active: showControlsTemporarily()
            case .ended:  scheduleHide(after: DS.Viewer.controlsAutoHideSeconds)
            }
        }
        // 键盘快捷键
        .onKeyPress(.escape)     { handleDismissOrExitFullScreen(); return .handled }
        .onKeyPress(.space)      { handleDismissOrExitFullScreen(); return .handled }
        .onKeyPress(.leftArrow)  { viewModel.goBack(); return .handled }
        .onKeyPress(.rightArrow) { viewModel.goForward(); return .handled }
        .onKeyPress(.init("0"), phases: .down) { _ in
            if NSEvent.modifierFlags.contains(.command) {
                viewModel.resetToFit()
            } else {
                viewModel.resetToOneToOne()
            }
            return .handled
        }
        .onKeyPress(.init("="), phases: .down) { _ in
            if NSEvent.modifierFlags.contains(.command) { viewModel.zoomIn() }
            return .handled
        }
        .onKeyPress(.init("-"), phases: .down) { _ in
            if NSEvent.modifierFlags.contains(.command) { viewModel.zoomOut() }
            return .handled
        }
        // M3 Slice M：⌘F 路由到 onCommandF（同帧关 QV + 浮 search overlay）；
        // 裸 F 仍走原全屏切换。检查 .command 修饰符决定分支。
        .onKeyPress(.init("f"), phases: .down) { event in
            if event.modifiers.contains(.command), let onCommandF {
                onCommandF()
                return .handled
            }
            if let onToggleFullScreen { onToggleFullScreen() } else { appState.toggleFullScreen() }
            return .handled
        }
        // 任务 A.6 — 裸 L 触发 VM 旋转
        .onKeyPress(.init("l"), phases: .down) { _ in
            viewModel.rotateLeft()
            return .handled
        }
        // 任务 B.4 — R 合并：⌘⇧R 在 Finder 中显示 / 裸 R 旋转（同 .onKeyPress("r") 内分支，
        // SwiftUI 同 key 多 handler 仅挂最后一个会丢前者，必须合并）
        .onKeyPress(.init("r"), phases: .down) { event in
            if event.modifiers.contains(.command) && event.modifiers.contains(.shift) {
                revealInFinder()
                return .handled
            }
            viewModel.rotateRight()
            return .handled
        }
        // 任务 B.4 — ⌘C 复制图片 / ⌘⌥C 复制路径（先判 ⌘⌥ 组合再判 ⌘，避免 ⌘ 路径吃掉 ⌘⌥）
        .onKeyPress(.init("c"), phases: .down) { event in
            if event.modifiers.contains(.command) && event.modifiers.contains(.option) {
                copyCurrentPath()
                return .handled
            }
            if event.modifiers.contains(.command) {
                copyImageToPasteboard()
                return .handled
            }
            return .ignored
        }
        // 任务 C.6 — Delete（backspace） / ⌘⌫ 触发移废纸篓。.delete 是 Apple 键盘上 backspace
        // 的 KeyEquivalent；.deleteForward 是 fn+delete（兜底覆盖）。⌘⌫ 由同一 handler 接走
        //（SwiftUI .onKeyPress 不区分裸 / ⌘ 修饰，统一进 handler）。
        .onKeyPress(.delete, phases: .down) { _ in
            Task { await handleTrashCurrent() }
            return .handled
        }
        .onKeyPress(.deleteForward, phases: .down) { _ in
            Task { await handleTrashCurrent() }
            return .handled
        }
        // 捏合手势
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let newScale = viewModel.baseScale * value
                    viewModel.scale = max(DS.Viewer.minZoom, min(DS.Viewer.maxZoom, newScale))
                    viewModel.zoomMode = .custom
                }
                .onEnded { _ in
                    viewModel.baseScale = viewModel.scale
                }
        )
    }

    // MARK: - Image Layer

    @ViewBuilder
    private var imageLayer: some View {
        if let nsImage = viewModel.currentNSImage {
            // Explicit frame = nativeSize × scale，替代 .scaledToFit() + .scaleEffect 的双变换。
            // 原先双变换导致 scale 被 fit 容器的隐式缩放再乘一次，图只剩窗口 30-40%。
            // 现在 scale 的语义与 ViewModel 一致：相对原生像素尺寸的缩放倍率。
            Image(nsImage: nsImage)
                .resizable()
                .frame(
                    width: nsImage.size.width * viewModel.scale,
                    height: nsImage.size.height * viewModel.scale
                )
                // 任务 A.5 — 旋转 / 翻转 modifier 顺序：frame → rotationEffect → scaleEffect → offset
                // 先旋转（绕中心）再镜像，跟用户视觉直觉「转完再翻」一致
                .rotationEffect(.degrees(Double(viewModel.rotationQuarterTurns) * Double(DS.Viewer.rotationStepDegrees)))
                .scaleEffect(x: viewModel.flippedH ? -1 : 1, y: viewModel.flippedV ? -1 : 1)
                .offset(viewModel.offset)
                .animation(nil, value: viewModel.scale)
                .animation(nil, value: viewModel.offset)
                .allowsHitTesting(false)
        } else if viewModel.loadFailed {
            ImageLoadFailedView()
        } else {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        // 三个独立浮动小气泡，不连成一整条
        HStack {
            // 关闭按钮（圆形气泡）
            Button(action: handleDismissOrExitFullScreen) {
                Image(systemName: DS.Icon.close)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(Color(white: 0, opacity: 0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .help("关闭 (ESC)")

            Spacer()

            // 文件名（居中小气泡）
            if let url = viewModel.images[safe: viewModel.currentIndex] {
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(Color(white: 0, opacity: 0.35), in: RoundedRectangle(cornerRadius: DS.Toolbar.cornerRadius))
                    .frame(maxWidth: 320)
            }

            Spacer()

            // 缩放 + 进度（右侧小气泡）
            HStack(spacing: DS.Spacing.xs) {
                Text(viewModel.zoomPercent)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Text(viewModel.progress)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xs)
            .padding(.vertical, DS.Spacing.xs + 2)
            .background(Color(white: 0, opacity: 0.35), in: RoundedRectangle(cornerRadius: DS.Spacing.sm))
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.sm + DS.Spacing.xs)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: DS.Spacing.sm) {
            toolbarButton(title: "适合 (⌘0)", systemImage: "arrow.up.left.and.down.right.magnifyingglass") {
                viewModel.resetToFit()
            }
            toolbarButton(title: "1:1 (0)", systemImage: "1.magnifyingglass") {
                viewModel.resetToOneToOne()
            }
            toolbarButton(title: "缩小 (⌘−)", systemImage: "minus.magnifyingglass") {
                viewModel.zoomOut()
            }
            Text(viewModel.zoomPercent)
                .font(.caption)
                .foregroundColor(.white)
                .frame(minWidth: 44)
                .padding(.horizontal, DS.Spacing.xs)
                .frame(height: 32)
                .background(Color(white: 1, opacity: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            toolbarButton(title: "放大 (⌘=)", systemImage: "plus.magnifyingglass") {
                viewModel.zoomIn()
            }
            if let onFindSimilar {
                toolbarButton(
                    title: currentSupportsFeaturePrint ? "找类似" : "该格式暂不支持类似图查找",
                    systemImage: "rectangle.stack.badge.plus"
                ) {
                    if currentSupportsFeaturePrint,
                       let url = viewModel.images[safe: viewModel.currentIndex] {
                        onFindSimilar(url)
                    }
                }
                .opacity(currentSupportsFeaturePrint ? DS.Similarity.buttonEnabledOpacity : DS.Similarity.buttonDisabledOpacity)
            }
            toolbarButton(title: "全屏 (F)", systemImage: appState.isFullScreen ? "arrow.down.right.and.arrow.up.left" : DS.Icon.fullscreen) {
                if let onToggleFullScreen { onToggleFullScreen() } else { appState.toggleFullScreen() }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DS.Toolbar.cornerRadius)
                .fill(Color(white: 0, opacity: 0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Toolbar.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        )
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.xs)
    }

    // MARK: - Filmstrip

    private var filmstrip: some View {
        let selectedURL = viewModel.images.indices.contains(viewModel.currentIndex)
            ? viewModel.images[viewModel.currentIndex]
            : nil

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DS.Spacing.xs + 2) {
                    ForEach(viewModel.images, id: \.self) { url in
                        FilmstripCell(url: url, isSelected: url == selectedURL)
                            .id(url)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let idx = viewModel.images.firstIndex(of: url) {
                                    viewModel.goTo(index: idx)
                                }
                            }
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm + DS.Spacing.xs)
            }
            .frame(height: DS.Viewer.filmstripHeight)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: viewModel.currentIndex) { _, newIndex in
                if viewModel.images.indices.contains(newIndex) {
                    withAnimation(DS.Anim.fast) {
                        proxy.scrollTo(viewModel.images[newIndex], anchor: .center)
                    }
                }
            }
            .onAppear {
                if viewModel.images.indices.contains(viewModel.currentIndex) {
                    proxy.scrollTo(viewModel.images[viewModel.currentIndex], anchor: .center)
                }
            }
        }
    }

    // MARK: - Info Badge (任务 A.7 — 分辨率 · 大小)

    @ViewBuilder
    private var infoBadge: some View {
        if let meta = currentMetadata,
           let w = meta.dimensionsWidth, let h = meta.dimensionsHeight {
            let sizeText = ByteCountFormatter().string(fromByteCount: meta.fileSize)
            Text("\(w)×\(h) · \(sizeText)")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xs)
                .padding(.vertical, DS.Spacing.xs)
                .background(
                    Color(white: 0, opacity: DS.Viewer.infoBadgeOpacity),
                    in: RoundedRectangle(cornerRadius: DS.Viewer.infoBadgeCornerRadius)
                )
        } else {
            EmptyView()
        }
    }

    // MARK: - 任务 C.7 — Trash Toast（成功撤销 / 失败提示）

    @ViewBuilder
    private var trashToast: some View {
        if let outcome = trashUndoOutcome {
            HStack(spacing: DS.Spacing.sm) {
                Text("已移废纸篓")
                    .font(.subheadline)
                    .foregroundColor(.white)
                Button("撤销") { Task { await handleUndoTrash() } }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .font(.subheadline.weight(.medium))
                Button {
                    trashUndoOutcome = nil
                    trashDismissTask?.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                Color(white: 0, opacity: DS.QuickViewerTrash.toastBackgroundOpacity),
                in: RoundedRectangle(cornerRadius: DS.QuickViewerTrash.toastCornerRadius)
            )
            // 抑制 outcome.successCount 未读警告（撤销时仍可访问 outcome 整体值）
            .accessibilityLabel("已移废纸篓 \(outcome.successCount) 张")
        } else if let msg = trashFailureMessage {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.white)
                Text(msg)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(2)
                Button {
                    trashFailureMessage = nil
                    trashDismissTask?.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                Color.red.opacity(DS.QuickViewerTrash.toastBackgroundOpacity),
                in: RoundedRectangle(cornerRadius: DS.QuickViewerTrash.toastCornerRadius)
            )
            .frame(maxWidth: 360)
        } else {
            EmptyView()
        }
    }

    /// 任务 C.8 占位 — 撤销 callback 实施在 C.8 步骤补全（onUndoTrash 参数 + 文案切换）。
    /// C.7 commit 阶段先空实现，让 trashToast.撤销按钮可编译。
    private func handleUndoTrash() async {
        // C.8 step 实现：调 onUndoTrash(outcome) + 切 failureMessage 显「文件恢复, 列表稍后刷新」
    }

    /// 任务 A.7 — 异步读 ImageMetadata（off-main IO + ImageIO 读 dimensions），回主线程赋值
    private func loadCurrentMetadata() {
        guard let url = viewModel.images[safe: viewModel.currentIndex] else {
            currentMetadata = nil
            return
        }
        // 切图先清旧 metadata，避免新图未加载完时短暂显示上一张的尺寸
        currentMetadata = nil
        let capturedIndex = viewModel.currentIndex
        Task.detached(priority: .userInitiated) {
            let meta = ImageMetadataReader.read(at: url)
            await MainActor.run {
                // currentIndex 已切走 → 丢弃 stale 结果
                guard capturedIndex == viewModel.currentIndex else { return }
                currentMetadata = meta
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func navButton(systemImage: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(.white.opacity(enabled ? 0.9 : 0.25))
                .frame(width: 44, height: 44)
                .background(Color(white: 0, opacity: enabled ? 0.45 : 0.2))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    @ViewBuilder
    private func toolbarButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    // MARK: - Dismiss / Exit Fullscreen

    private func handleDismissOrExitFullScreen() {
        if appState.isFullScreen {
            if let onToggleFullScreen { onToggleFullScreen() } else { appState.toggleFullScreen() }
        } else {
            // 先撤焦点再 dismiss：.transition(.opacity) 退场期 overlay 仍存活，若仍是
            // active key target 用户随后按方向键会被本 view onKeyPress 接走（QV B-side
            // 加固，对称 ImagePreviewView dismissPreview()）
            isFocused = false
            onDismiss()
        }
    }

    /// 仅当窗口已是 key 时 assert 键盘焦点。非 key 时 @FocusState 赋值被 SwiftUI 静默丢弃，
    /// 等 windowDidBecomeKey 后由 .onChange(of: appState.isWindowKey) 补 assert。幂等可重复调。
    private func requestKeyboardFocusIfWindowIsKey() {
        guard appState.isWindowKey else { return }
        isFocused = true
        // 独立看图窗首开：isWindowKey 在本 view mount 前就翻 true（onChange 漏触发），只剩
        // onAppear 这次 assert，但刚 mount 的 hosting view focus 系统未 ready，赋值被静默丢弃
        // → 要鼠标点一下才接管键盘。让出一个 runloop 周期后补一次（async/await，非 callback）。幂等，主窗无副作用。
        Task { @MainActor in
            await Task.yield()
            isFocused = true
        }
    }

    // MARK: - Auto-hide

    private func showControlsTemporarily() {
        withAnimation(DS.Anim.normal) { controlsVisible = true }
        scheduleHide(after: DS.Viewer.controlsAutoHideSeconds)
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(DS.Anim.normal) { controlsVisible = false }
            }
        }
    }

    // MARK: - 任务 C — 单张删除

    /// 任务 C.6 — Delete/⌘⌫/右键废纸篓统一入口。先 await onTrash 拿 outcome，仅成功才
    /// removeCurrent + 显成功 toast；失败 / nil outcome 显失败 toast 不动 VM。删完最后一张
    /// 自动 onDismiss（D40）。
    private func handleTrashCurrent() async {
        guard let url = viewModel.images[safe: viewModel.currentIndex], let onTrash else { return }
        let outcome = await onTrash(url)
        if let outcome, outcome.successCount == 1 {
            viewModel.removeCurrent()
            trashUndoOutcome = outcome
            trashFailureMessage = nil
            scheduleTrashDismiss()
            if viewModel.images.isEmpty { onDismiss() }
        } else if let outcome, outcome.failures.count == 1 {
            trashFailureMessage = outcome.failures.first?.reason ?? "移废纸篓失败"
            trashUndoOutcome = nil
            scheduleTrashDismiss()
        } else {
            // 无 outcome = Coordinator schema gate 拦截 / IndexStore 反查 nil / 未入库图
            trashFailureMessage = "无法删除该图(可能未入库 / V1 老 bookmark / 已升级 V2 才能删)"
            trashUndoOutcome = nil
            scheduleTrashDismiss()
        }
    }

    /// 任务 C.6 — 复刻 scheduleHide pattern，sleep 后清两个 toast state。
    private func scheduleTrashDismiss() {
        trashDismissTask?.cancel()
        trashDismissTask = Task {
            try? await Task.sleep(for: .seconds(DS.QuickViewerTrash.toastAutoDismissSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                trashUndoOutcome = nil
                trashFailureMessage = nil
            }
        }
    }

    // MARK: - 任务 B — 复制 / Finder helpers

    /// 任务 B.2 — 复制当前图到系统剪贴板（NSPasteboard.writeObjects），Finder/Notes/Slack 等可粘贴
    private func copyImageToPasteboard() {
        guard let nsImage = viewModel.currentNSImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }

    /// 任务 B.3 — 复制当前图文件 path 到剪贴板（字符串）
    private func copyCurrentPath() {
        guard let url = viewModel.images[safe: viewModel.currentIndex] else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    /// 任务 B.3 — 在 Finder 中显示当前图（fileExists 预检；R-finder-reveal-not-exist
    /// 失败暂 noop，任务 C toast ship 后再加显式提示）
    private func revealInFinder() {
        guard let url = viewModel.images[safe: viewModel.currentIndex] else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - FilmstripCell（迁移自 ImageViewerView）

struct FilmstripCell: View {
    let url: URL
    let isSelected: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipped()
            } else {
                Rectangle()
                    .fill(DS.Color.hoverOverlay)
                    .frame(width: 56, height: 56)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Thumbnail.cornerRadius + DS.Spacing.xs))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Thumbnail.cornerRadius + DS.Spacing.xs)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isSelected ? 1.08 : 1.0)
        .animation(DS.Anim.fast, value: isSelected)
        .task(id: url) {
            thumbnail = nil
            let result = await loadThumbnail(url: url, maxPixelSize: DS.Viewer.filmstripThumbLoadSize)
            guard !Task.isCancelled else { return }
            thumbnail = result
        }
    }
}
