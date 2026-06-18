//
//  MainQuickViewerWindowController.swift
//  Glance
//
//  主窗 QV（双击进全窗看图）的独立无装饰 NSWindow。Task 1.1 契约骨架：enum +
//  API 签名 + 窗口创建骨架（mirror ExternalViewerWindowController）。Task 1.2
//  填 show/close 实现 + 同框 frame 跟随 + windowWillClose 的 focus 4 步时序。
//
//  与 ExternalViewerWindowController 的区别：本 controller 服务图库主窗内部 QV，
//  砍掉 ViewerSession/security-scope/terminateOnClose/retiredSessions（主窗图源已有
//  scope，不需要本 controller 单独持权限）。
//
//  inheritedMainFullScreen（主窗已全屏时双击进 QV）走 codex 候选2：QV 自己 toggleFullScreen
//  进原生全屏（新 Space B），主窗保持其全屏 Space A 不动。退 QV 全屏后关 QV，AppKit 销毁
//  Space B 自动回 Space A 主窗全屏 grid。走 documented 生命周期，可靠（候选1 borderless +
//  fullScreenAuxiliary 满屏覆盖真机踩坑：关 QV 时 AppKit 私有 heuristic 把主窗全屏 Space 塌缩）。
//

import AppKit
import Combine
import SwiftUI

/// QV 关闭原因。caller（ContentView）据此决定退出后续动作：
/// .normal 仅退出；.findSimilar 退出并以 URL 触发找类似；.commandF 退出并打开搜索。
enum QVDismissalReason {
    case normal
    case findSimilar(URL)
    case commandF
}

@MainActor
final class MainQuickViewerWindowController: NSObject, ObservableObject {
    static let shared = MainQuickViewerWindowController()

    /// QV 窗全屏呈现态（候选2 3 态状态机）。viewerAppState.isFullScreen 是「语义全屏」
    /// 镜像（给 QuickViewerOverlay 判 ESC），presentation 是「物理 + 过渡」真值。
    private enum Presentation {
        /// QV top-level 同框盖主窗 + `.fullScreenPrimary`；F 切 QV 原生全屏。
        case windowedCover
        /// QV 自己拥有全屏 Space（windowedCover 下按 F 进，或主窗全屏来源 show 时异步进）。
        case qvNativeFullScreen
        /// 全屏进/出过渡期，拒绝重复 F 触发。
        case transitioning
    }
    private var presentation: Presentation = .windowedCover

    @Published private(set) var isPresenting: Bool = false

    // MARK: - D-mb-9.2 菜单栏 closure registry

    @Published private(set) var commandHandlers: [QuickViewerCommand: () -> Void] = [:]
    private(set) var trashHandler: (() async -> Void)? = nil
    private(set) var hasImageProvider: () -> Bool = { false }

    func registerCommandHandlers(
        handlers: [QuickViewerCommand: () -> Void],
        trash: @escaping () async -> Void,
        hasImage: @escaping () -> Bool
    ) {
        self.commandHandlers = handlers
        self.trashHandler = trash
        self.hasImageProvider = hasImage
        // commandHandlers 是 @Published 自动 send; trashHandler/hasImageProvider 不是,
        // 显式 send 确保 hasCurrentImage computed property 的 view binding 同步更新.
        objectWillChange.send()
    }

    func clearCommandHandlers() {
        self.commandHandlers = [:]
        self.trashHandler = nil
        self.hasImageProvider = { false }
        objectWillChange.send()
    }

    private var window: NSWindow?
    /// 用 NSHostingView 当 window.contentView（mirror ExternalViewerWindowController）。**不用**
    /// NSHostingController 当 contentViewController——那样 AppKit 会忽略 contentRect、改用 hosting
    /// 的 fittingSize 把窗口压成 1×1（看不见图）。
    private var hosting: NSHostingView<AnyView>?
    /// 看图窗专属 AppState（F 全屏 / traffic light / 焦点都作用在 QV 窗，不碰图库主窗）。
    private let viewerAppState = AppState()

    // MARK: - Per-show instance state

    /// QV 内导航上报回调，透传给 QuickViewerOverlay。
    private var onIndexChange: ((Int) -> Void)?
    /// 同步退出准备回调（design 6.3 step 1）：windowWillClose 第 1 步**之前**同步触发，
    /// 用来清非焦点状态（如 selectedImageIndex），防 previewOverlay 在 isPresenting 翻 false 后
    /// 用 stale selectedImageIndex remount。区别于延迟的 onDismiss（只管 focus + 后续动作）。
    private var onPrepareDismiss: ((QVDismissalReason, QuickViewerEntry) -> Void)?
    /// 退出回调：windowWillClose 时经 MainWindowController.runAfterNextBecomeKey 延迟触发。
    private var onDismiss: ((QVDismissalReason, QuickViewerEntry) -> Void)?
    /// 任务 C.5 — 单张删除入口：Overlay 按 Delete/⌘⌫/右键废纸篓时回调，caller (ContentView)
    /// 转给 QuickViewerTrashCoordinator.trash(url:)。默认 nil 兼容 ExternalViewerWindowController
    /// OpenWith 路径（看图器单 session 不挂主索引，无删除入口）。
    private var onTrash: ((URL) async -> TrashOutcome?)?
    /// 任务 C.9 — toast「撤销」按钮触发，caller 转给 Coordinator.restore。默认 nil 兼容 OpenWith。
    private var onUndoTrash: ((TrashOutcome) async -> Void)?
    /// 本次 show 的进入路径，原样回传给 onDismiss。
    private var entry: QuickViewerEntry?
    /// 弱引用图库主窗：windowWillClose 时归还焦点 + 同框 frame 跟随用。
    private weak var mainWindow: NSWindow?
    /// 关闭原因：close(reason:) 写入；系统直接关窗（红绿灯/⌘W）未经 close 时取默认 .normal。
    private var pendingDismissReason: QVDismissalReason = .normal
    /// 幂等 guard：close 已触发后再次进入直接 return。
    private var isClosing = false
    /// 终结信号：close(force: true)（主窗 willClose/miniaturize）置 true，windowWillClose 据此
    /// 走「只清 QV 自身、不碰主窗」的终结路径，跳过 focus 4 步（主窗已没/最小化，归还焦点有害 +
    /// onDismiss 会对死 ContentView 跑）。清状态那步复位回 false。
    private var isTerminating = false
    /// show 代次（I2）：防快速 show→close→show 串扰。show 自增；windowWillClose 捕获当时值，
    /// 延迟 drain 的 onDismiss 回调里 guard 代次未变才触发（变了说明已有更新 session，skip 旧回调）。
    private var showGeneration = 0
    /// 候选2：主窗全屏来源标记。show 时主窗已全屏则 true，标记「QV 全屏关闭后要回主窗全屏 grid
    /// （一段关）」。false 则是 windowedCover 来源，F 进的全屏首 ESC 只退回 windowed QV。
    private var enteredFromMainFullScreen = false
    /// 同框 frame 跟随：监听主窗 didMove/didResize/didChangeScreen 同步 QV 窗 frame，
    /// 监听主窗 didMiniaturize（→ close QV 避免悬空）。
    private var frameObservers: [NSObjectProtocol] = []

    private override init() { super.init() }

    /// 打开 QV 窗显示 images（windowedCover 态，盖住主窗同框）。
    func show(images: [URL], startIndex: Int, entry: QuickViewerEntry,
              mainWindow: NSWindow,
              currentSupportsFeaturePrint: Bool,
              onIndexChange: @escaping (Int) -> Void,
              onPrepareDismiss: @escaping (QVDismissalReason, QuickViewerEntry) -> Void,
              onDismiss: @escaping (QVDismissalReason, QuickViewerEntry) -> Void,
              onTrash: ((URL) async -> TrashOutcome?)? = nil,
              onUndoTrash: ((TrashOutcome) async -> Void)? = nil) {
        // M6：isClosing 复位前移到方法开头，empty-images 早退路径也对称复位。
        isClosing = false
        // I2：新 session 自增代次，让上个 session 延迟 drain 的 onDismiss guard 失配被 skip。
        showGeneration += 1
        guard !images.isEmpty else { return }

        if window == nil {
            createWindow()
        }
        guard let win = window else { return }

        // 存实例状态供 windowWillClose 归还焦点 + 回调使用。
        self.onIndexChange = onIndexChange
        self.onPrepareDismiss = onPrepareDismiss
        self.onDismiss = onDismiss
        self.onTrash = onTrash
        self.onUndoTrash = onUndoTrash
        self.entry = entry
        self.mainWindow = mainWindow
        self.pendingDismissReason = .normal

        // 候选2：主窗全屏来源判定。两态都用同样的 windowedCover 窗口配置（titled + fullScreenPrimary
        // + 盖主窗 frame）。区别只在：主窗全屏时额外异步 toggleFullScreen 让 QV 进原生全屏（新 Space）。
        let mainIsFullScreen = mainWindow.styleMask.contains(.fullScreen)

        // windowedCover 窗口装饰：titled 同框（隐 title + 透明 titlebar + 有阴影）+ fullScreenPrimary。
        // 两态都按主窗 frame 盖住；主窗全屏来源时其 frame 是全屏 Space 尺寸，QV 先按此建窗，随后
        // 异步进自己的原生全屏（新 Space B），尺寸由全屏过渡接管。
        applyWindowedCoverStyle(to: win)
        win.setFrame(mainWindow.frame, display: true)
        // 初始语义全屏=false，由全屏过渡的 windowDidEnterFullScreen 翻 true（主窗来源亦然）。
        viewerAppState.isFullScreen = false
        presentation = .windowedCover
        enteredFromMainFullScreen = mainIsFullScreen

        // 先 attach（播种 window 指针，让 QV onAppear 时 viewerAppState.window 非 nil），再换 rootView。
        viewerAppState.attachWindow(win)
        // 换 rootView：.id(UUID()) 强制 QuickViewerOverlay 每次 show 重建 viewModel 显新图源。
        hosting?.rootView = AnyView(
            QuickViewerOverlay(
                images: images,
                startIndex: startIndex,
                onDismiss: { [weak self] in self?.close(reason: .normal) },
                onIndexChange: onIndexChange,
                onFindSimilar: { [weak self] url in self?.close(reason: .findSimilar(url)) },
                currentSupportsFeaturePrint: currentSupportsFeaturePrint,
                onCommandF: { [weak self] in self?.close(reason: .commandF) },
                onToggleFullScreen: { [weak self] in self?.toggleFullScreenFromViewer() },
                onTrash: onTrash,
                onUndoTrash: onUndoTrash
            )
            .environmentObject(viewerAppState)
            .id(UUID())
        )

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // titled 窗 makeKeyAndOrderFront 后 AppKit 一般会把 NSHostingView 设为 first responder，
        // 但显式 make 确保键盘事件（ESC/F/方向键）进 SwiftUI 的 .onKeyPress；幂等无害。
        if let hosting { win.makeFirstResponder(hosting) }
        isPresenting = true

        registerFrameObservers(mainWindow: mainWindow, viewerWindow: win)

        // 候选2 核心：主窗全屏来源 → 异步（下一 main run-loop）让 QV 进自己的原生全屏新 Space。
        // **异步是 codex 强调的**：让窗口先 key/firstResponder ready 再 toggle，否则 AppKit 可能
        // 在窗口尚未稳定时拒绝全屏过渡。调前 guard 窗口仍可见 + generation 未变（防 show→close→show 串扰）。
        if mainIsFullScreen {
            let gen = showGeneration
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.showGeneration == gen,
                      let win = self.window, win.isVisible,
                      self.presentation == .windowedCover else { return }
                win.toggleFullScreen(nil)
            }
        }
    }

    /// 关闭 QV 窗。统一 close path：window.close() → windowWillClose 完成 focus 归还 + onDismiss。
    /// force=true 绕过 transitioning guard：仅用于主窗终结信号（willClose/miniaturize），
    /// 此时主窗已关/最小化，QV 必须跟着终结，即使在全屏过渡中（过渡卡死无所谓，会话已结束）。
    /// 用户 ESC/Space 等正常关闭用 force=false（默认），保留 transitioning guard 防过渡中途关窗。
    func close(reason: QVDismissalReason, force: Bool = false) {
        // 全屏进/出过渡期忽略 close：在 toggleFullScreen 动画中途 window.close() 会让 AppKit
        // 全屏状态卡死/未定义。过渡由 QV delegate windowDidEnter/ExitFullScreen 清回
        // qvNativeFullScreen/windowedCover，之后 close 正常。过渡 <1s，用户体感是过渡期按 ESC 被吞一次。
        if !force {
            guard presentation != .transitioning else { return }
        } else {
            // 主窗终结信号：标记终结路径，windowWillClose 跳 focus 归还。
            isTerminating = true
        }
        guard !isClosing else { return }
        isClosing = true
        pendingDismissReason = reason
        // 终结路径走 window.close()（不触发 windowShouldClose，故 transitioning 也能强制关）。
        window?.close()
    }

    /// QV 全屏切换入口（F / overlay 退全屏均经此）。按 3 态状态机路由（候选2）。
    private func toggleFullScreenFromViewer() {
        switch presentation {
        case .windowedCover:
            // 进 QV 原生全屏。物理过渡由 QV delegate 接管：will→transitioning，did→qvNativeFullScreen。
            window?.toggleFullScreen(nil)
        case .qvNativeFullScreen:
            // 退原生全屏；inheritedMain 来源（enteredFromMainFullScreen=true）由 windowDidExitFullScreen
            // 据 enteredFromMainFullScreen 关 QV（一段回主窗全屏 grid），windowedCover 来源停回 windowed QV。
            window?.toggleFullScreen(nil)
        case .transitioning:
            // 过渡期忽略，防重复触发把状态机搅乱。
            break
        }
    }

    private func createWindow() {
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.autoresizingMask = [.width, .height]  // 跟随 window resize / 进全屏铺满
        let win = NSWindow(
            contentRect: NSRect(origin: .zero,
                                size: NSSize(width: DS.ExternalViewer.defaultWindowWidth,
                                             height: DS.ExternalViewer.defaultWindowHeight)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.contentView = host  // 用 contentView 而非 contentViewController，保住 contentRect 尺寸
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false  // 关闭后保留实例，下次 show 复用同一 window
        win.collectionBehavior.insert(.fullScreenPrimary)  // 允许 QV 进原生全屏（候选2 两态都需要）
        win.center()
        win.delegate = self
        self.window = win
        self.hosting = host
    }

    /// windowedCover 态的窗口装饰：titled 同框（隐 title + 透明 titlebar + 有阴影）+ fullScreenPrimary。
    /// 候选2 下两态都是 titled，故无需「borderless ↔ titled」切换，仅在 show 时统一应用一次。
    /// `setFrame` 由 caller 负责（frame 跟随主窗，不在此处定）。
    private func applyWindowedCoverStyle(to win: NSWindow) {
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.hasShadow = true
        win.collectionBehavior.insert(.fullScreenPrimary)
    }

    // MARK: - 同框 frame 跟随（windowedCover 最小集）

    /// 监听主窗 didMove/didResize/didChangeScreen，把 QV 窗 frame 同步成主窗 frame（盖住）；
    /// 监听主窗 didMiniaturize / willClose → close QV（top-level 同框盖窗依附主窗，主窗最小化或
    /// 关闭后盖窗悬空无意义：minimize 关掉比同步干净避免 Dock 孤立缩略图 + 复杂复位；
    /// willClose 防止用户独立关主窗（⌘W/红灯，不经 QV）时 QV 窗成孤立悬挂盖窗）。
    /// 注：主窗 willClose/miniaturize 是一次性终结信号，调 close(force: true) 绕过 transitioning
    /// guard——主窗关后无第二次 willClose 重试机会，过渡中被 guard 吞会让 QV 悬挂成孤立窗。
    private func registerFrameObservers(mainWindow: NSWindow, viewerWindow: NSWindow) {
        removeFrameObservers()
        let center = NotificationCenter.default
        // queue: .main → block 必在主线程跑；用 assumeIsolated 桥到 MainActor 同步 frame，
        // 既满足 @Sendable closure 约束又不引入 data race（mainWindow/viewerWindow 仅主线程访问）。
        let sync: @Sendable (Notification) -> Void = { [weak viewerWindow, weak mainWindow] _ in
            MainActor.assumeIsolated {
                guard let viewerWindow, let mainWindow else { return }
                viewerWindow.setFrame(mainWindow.frame, display: true)
            }
        }
        for name in [NSWindow.didMoveNotification,
                     NSWindow.didResizeNotification,
                     NSWindow.didChangeScreenNotification] {
            frameObservers.append(
                center.addObserver(forName: name, object: mainWindow, queue: .main, using: sync)
            )
        }
        // 主窗最小化 / 关闭 → 关 QV（见上注释）。同一 closure 注册到两个 notification。
        let closeQV: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close(reason: .normal, force: true)
            }
        }
        for name in [NSWindow.didMiniaturizeNotification,
                     NSWindow.willCloseNotification] {
            frameObservers.append(
                center.addObserver(forName: name, object: mainWindow, queue: .main, using: closeQV)
            )
        }
    }

    private func removeFrameObservers() {
        let center = NotificationCenter.default
        frameObservers.forEach { center.removeObserver($0) }
        frameObservers.removeAll()
    }
}

// MARK: - NSWindowDelegate（key 跟踪 + 统一 close path 的 focus 4 步时序）

extension MainQuickViewerWindowController: NSWindowDelegate {
    func windowWillEnterFullScreen(_ notification: Notification) {
        presentation = .transitioning
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        viewerAppState.isFullScreen = true
        presentation = .qvNativeFullScreen
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        presentation = .transitioning
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        viewerAppState.isFullScreen = false
        presentation = .windowedCover
        // inheritedMain 来源（主窗全屏进的 QV）：任何方式退原生全屏（ESC/F/绿灯/手势/系统菜单）
        // 都关 QV 回主窗全屏 grid——无 windowed QV 中间态。windowedCover 来源退全屏停在 windowed QV。
        if enteredFromMainFullScreen {
            close(reason: .normal)
        }
    }

    /// 全屏进入失败：AppKit 未能进原生全屏（罕见，如 Space 切换被打断）。恢复到 windowedCover
    /// 稳态，否则 presentation 永久卡 transitioning 让 close 被吞死。
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        presentation = .windowedCover
        viewerAppState.isFullScreen = false
    }

    /// 全屏退出失败：AppKit 未能退原生全屏。恢复到 qvNativeFullScreen 稳态，防卡死 transitioning。
    /// 仍在全屏中，关 QV 意图未完成；下次成功退出（windowDidExitFullScreen）再据 enteredFromMainFullScreen 消费。
    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        presentation = .qvNativeFullScreen
        viewerAppState.isFullScreen = true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        viewerAppState.attachWindow(win)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let win = notification.object as? NSWindow,
              win === viewerAppState.window else { return }
        viewerAppState.isWindowKey = false
    }

    /// 全屏进/出过渡期拒绝关闭：⌘W/红灯/menu 走 performClose→windowShouldClose，
    /// 此处拦住防过渡中途关窗卡死 AppKit（程序化 close(force:false) 由其自身 transitioning guard 拦；
    /// 主窗终结 force close 走 window.close() 不经 shouldClose，不受此拦截，确保能强制关）。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return presentation != .transitioning
    }

    /// 统一 close path：ESC（onDismiss→close）/ ⌘W / 红灯 / 系统关闭都汇到这。
    /// 按 isTerminating 分两路：
    /// - **终结路径**（主窗 willClose/miniaturize → force close）：只清 QV 自身状态 + observer，
    ///   跳过 focus 4 步（主窗都没了/最小化了，归还焦点有害 + onDismiss 对死 ContentView 跑）。
    /// - **正常路径**（用户关 QV / images 变化）：走完整 focus 4 步时序（D-QVT7，**别改次序**）：
    ///   先清 QV 态 → 捕获回调 → 延迟到主窗 become key 后触发 onDismiss（此时主 hosting 已 key，
    ///   SwiftUI focusTarget 赋值才生效）→ 拉主窗回前台 → 清状态。
    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }

        if isTerminating {
            // 终结路径：主窗已没/最小化，只清 QV 自身、不碰主窗 state，也不归还焦点。
            // 跳过 prepareDismiss（ContentView 在销毁，selectedImageIndex 清不清无所谓，
            // 保持「只清 QV 自身」干净语义）。
            viewerAppState.isFullScreen = false
            viewerAppState.detachWindow(win)
            isPresenting = false
            resetInstanceStateAfterClose()
            return
        }

        // 0. 同步 prepareDismiss（design 6.3 step 1）：必须在 isPresenting=false **之前**触发，
        //    让 caller 同步清非焦点状态（selectedImageIndex），否则 isPresenting 翻 false 后
        //    previewOverlay 会用 stale selectedImageIndex remount 显旧图（find-similar 尤甚）。
        if let savedEntryForPrepare = entry {
            onPrepareDismiss?(pendingDismissReason, savedEntryForPrepare)
        }

        // 1. 清 QV 态：无条件 reset isFullScreen（全屏中关窗后残留会让下次 ESC 被误判为退全屏）+ detach + 收起。
        viewerAppState.isFullScreen = false
        viewerAppState.detachWindow(win)
        isPresenting = false

        // 2. 在清 closure 之前捕获到 local（含 I2 代次）。
        let reason = pendingDismissReason
        let savedEntry = entry
        let onDismiss = self.onDismiss
        let mainWin = self.mainWindow
        let gen = showGeneration

        // 3. 延迟到主窗 become key 后触发 onDismiss（主 hosting 已 key，focusTarget 赋值才生效）。
        //    绝不在此处直接设主窗 focusTarget——主 hosting 尚未 become key，SwiftUI 会静默丢弃。
        //    I2：drain 时 guard 代次未变；变了说明已有更新 session，skip 旧回调避免状态串扰。
        if let savedEntry {
            MainWindowController.shared.runAfterNextBecomeKey { [weak self] in
                guard self?.showGeneration == gen else { return }
                onDismiss?(reason, savedEntry)
            }
        }

        // 4. 拉主窗回前台（触发其 windowDidBecomeKey → drain 第 3 步注册的 block）。
        mainWin?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 5. 清实例存的 closure/状态 + 移除 frame observer。
        resetInstanceStateAfterClose()
    }

    /// windowWillClose 两条路径共用的「清 QV 自身实例状态 + observer」收尾。
    /// 不碰主窗 state（焦点归还/onDismiss 由正常路径在调本方法前自行处理；终结路径整段跳过）。
    private func resetInstanceStateAfterClose() {
        self.onDismiss = nil
        self.onPrepareDismiss = nil
        self.onIndexChange = nil
        self.onTrash = nil
        self.onUndoTrash = nil
        self.entry = nil
        self.mainWindow = nil
        self.pendingDismissReason = .normal
        self.isClosing = false
        self.isTerminating = false
        // 复位 presentation + enteredFromMainFullScreen，让下次 show 干净重判初始态（窗口复用，不复位会带残留态）。
        self.presentation = .windowedCover
        self.enteredFromMainFullScreen = false
        removeFrameObservers()
        // A.7.1 — 兜底清 closure registry：覆盖 Overlay .onDisappear 漏触发的边缘路径
        //（终结路径、close(force: true)、windowWillClose 直接来源等），防 stale closure 残留.
        clearCommandHandlers()
    }
}
