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

    /// QV 窗全屏呈现态（D-QVT6 4 态状态机）。viewerAppState.isFullScreen 是「语义全屏」
    /// 镜像（给 QuickViewerOverlay 判 ESC），presentation 是「物理 + 来源」真值，二者不能合一：
    /// inheritedMainFullScreen 下 QV 窗物理没全屏但语义在全屏环境。
    private enum Presentation {
        /// QV top-level 同框盖主窗 + `.fullScreenPrimary`；F 切 QV 原生全屏。
        case windowedCover
        /// QV 自己拥有全屏 Space（windowedCover 下按 F 进），主窗不变。
        case qvNativeFullScreen
        /// 主窗已全屏；QV 以 `.fullScreenAuxiliary` 在主窗的全屏 Space 上层展示，QV 物理未全屏。
        case inheritedMainFullScreen
        /// 全屏进/出过渡期，拒绝重复 F 触发。
        case transitioning
    }
    private var presentation: Presentation = .windowedCover

    @Published private(set) var isPresenting: Bool = false

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
    /// 本次 show 的进入路径，原样回传给 onDismiss。
    private var entry: QuickViewerEntry?
    /// 弱引用图库主窗：windowWillClose 时归还焦点 + 同框 frame 跟随用。
    private weak var mainWindow: NSWindow?
    /// 关闭原因：close(reason:) 写入；系统直接关窗（红绿灯/⌘W）未经 close 时取默认 .normal。
    private var pendingDismissReason: QVDismissalReason = .normal
    /// 幂等 guard：close 已触发后再次进入直接 return。
    private var isClosing = false
    /// show 代次（I2）：防快速 show→close→show 串扰。show 自增；windowWillClose 捕获当时值，
    /// 延迟 drain 的 onDismiss 回调里 guard 代次未变才触发（变了说明已有更新 session，skip 旧回调）。
    private var showGeneration = 0
    /// 同框 frame 跟随：监听主窗 didMove/didResize/didChangeScreen 同步 QV 窗 frame，
    /// 监听主窗 didMiniaturize（→ close QV 避免悬空）。
    private var frameObservers: [NSObjectProtocol] = []
    /// inheritedMainFullScreen 专用：监听主窗 didExitFullScreen，触发 QV 切回 fullScreenPrimary +
    /// 对齐主窗恢复尺寸 + 转 windowedCover。仅在进入 inheritedMainFullScreen 时注册，close 时清。
    private var mainExitFullScreenObserver: NSObjectProtocol?

    private override init() { super.init() }

    /// 打开 QV 窗显示 images（windowedCover 态，盖住主窗同框）。
    func show(images: [URL], startIndex: Int, entry: QuickViewerEntry,
              mainWindow: NSWindow,
              currentSupportsFeaturePrint: Bool,
              onIndexChange: @escaping (Int) -> Void,
              onPrepareDismiss: @escaping (QVDismissalReason, QuickViewerEntry) -> Void,
              onDismiss: @escaping (QVDismissalReason, QuickViewerEntry) -> Void) {
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
        self.entry = entry
        self.mainWindow = mainWindow
        self.pendingDismissReason = .normal

        // 初始态判定（D-QVT6）：主窗已全屏 → inheritedMainFullScreen，否则 windowedCover。
        // collectionBehavior 每次 show 按态重设（窗口复用，不能只在 createWindow 设一次）。
        if mainWindow.styleMask.contains(.fullScreen) {
            // 主窗已在全屏 Space：QV 用 fullScreenAuxiliary（**不是** fullScreenPrimary）显在该 Space
            // 上层，**不调** QV toggleFullScreen（那会新建独立 Space 把用户踢出主窗 Space）。
            win.collectionBehavior.remove(.fullScreenPrimary)
            win.collectionBehavior.insert(.fullScreenAuxiliary)
            // 关键：QV 窗物理没全屏，但语义在全屏环境。主动置 isFullScreen=true，否则
            // QuickViewerOverlay 首 ESC 会走关窗而非「退全屏」。
            viewerAppState.isFullScreen = true
            presentation = .inheritedMainFullScreen
            // 注册主窗退全屏监听：用户在主窗 Space 退全屏时把 QV 拉回 windowedCover。
            registerMainExitFullScreenObserver(mainWindow: mainWindow, viewerWindow: win)
        } else {
            win.collectionBehavior.remove(.fullScreenAuxiliary)
            win.collectionBehavior.insert(.fullScreenPrimary)
            viewerAppState.isFullScreen = false
            presentation = .windowedCover
        }

        // 同框定位：盖住主窗（完整跟随见 frame observer）。
        win.setFrame(mainWindow.frame, display: true)

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
                onToggleFullScreen: { [weak self] in self?.toggleFullScreenFromViewer() }
            )
            .environmentObject(viewerAppState)
            .id(UUID())
        )

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isPresenting = true

        registerFrameObservers(mainWindow: mainWindow, viewerWindow: win)
    }

    /// 关闭 QV 窗。统一 close path：window.close() → windowWillClose 完成 focus 归还 + onDismiss。
    func close(reason: QVDismissalReason) {
        // 全屏进/出过渡期忽略 close：在 toggleFullScreen 动画中途 window.close() 会让 AppKit
        // 全屏状态卡死/未定义。过渡由 QV delegate windowDidEnter/ExitFullScreen 清回
        // qvNativeFullScreen/windowedCover，之后 close 正常。过渡 <1s，用户体感是过渡期按 ESC 被吞一次。
        // TODO: [2026-06-08] Slice3: 过渡失败（AppKit 未发 did*）时 transitioning 不自清会导致 close
        // 永久被吞，需超时兜底；toggleFullScreen 基本可靠故暂不实现，真机遇到再加。
        guard presentation != .transitioning else { return }
        guard !isClosing else { return }
        isClosing = true
        pendingDismissReason = reason
        window?.close()
    }

    /// QV 全屏切换入口（F / overlay 退全屏均经此）。按 4 态状态机路由（D-QVT6）。
    private func toggleFullScreenFromViewer() {
        switch presentation {
        case .windowedCover:
            // 进 QV 原生全屏。物理过渡由 QV delegate 接管：will→transitioning，did→qvNativeFullScreen。
            window?.toggleFullScreen(nil)
        case .qvNativeFullScreen:
            // 退回 windowedCover（QV delegate 的 willExit→transitioning，didExit→windowedCover）。
            window?.toggleFullScreen(nil)
        case .inheritedMainFullScreen:
            // 首 ESC/F：退主窗全屏（QV 本就没物理全屏，不能 toggle QV）。主窗 didExitFullScreen
            // 监听负责把 QV 切回 fullScreenPrimary + 对齐尺寸 + 转 windowedCover。
            // M-1：过渡发生在主窗、QV 自己 will/didExitFullScreen 不触发，故主动设 transitioning，
            // 否则退全屏动画期再按 ESC 会重入本分支二次 toggle（AppKit 未定义行为）。
            // transitioning→windowedCover 的闭环由 mainExitFullScreenObserver fire 时兜上。
            presentation = .transitioning
            mainWindow?.toggleFullScreen(nil)
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
        // collectionBehavior 不在此处定死：show 时按 presentation 态设
        // fullScreenPrimary（windowedCover）或 fullScreenAuxiliary（inheritedMainFullScreen）。
        win.center()
        win.delegate = self
        self.window = win
        self.hosting = host
    }

    // MARK: - 同框 frame 跟随（windowedCover 最小集）

    /// 监听主窗 didMove/didResize/didChangeScreen，把 QV 窗 frame 同步成主窗 frame（盖住）；
    /// 监听主窗 didMiniaturize → close QV（top-level 同框盖窗在主窗最小化后悬空无意义，
    /// 关掉比同步 miniaturize 干净：避免 Dock 出现一个孤立 QV 缩略图 + 复杂的 deminiaturize 复位）。
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
        // 主窗最小化 → 关 QV（见上注释）。
        let closeOnMiniaturize: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close(reason: .normal)
            }
        }
        frameObservers.append(
            center.addObserver(forName: NSWindow.didMiniaturizeNotification, object: mainWindow,
                               queue: .main, using: closeOnMiniaturize)
        )
    }

    private func removeFrameObservers() {
        let center = NotificationCenter.default
        frameObservers.forEach { center.removeObserver($0) }
        frameObservers.removeAll()
    }

    // MARK: - inheritedMainFullScreen 退出处理

    /// 监听主窗 didExitFullScreen：用户在主窗全屏 Space 退出全屏时（首 ESC/F 经
    /// toggleFullScreenFromViewer 调 mainWindow.toggleFullScreen，或用户直接操作主窗），
    /// QV 切回 fullScreenPrimary + 对齐主窗恢复后尺寸 + 转 windowedCover + isFullScreen=false。
    private func registerMainExitFullScreenObserver(mainWindow: NSWindow, viewerWindow: NSWindow) {
        removeMainExitFullScreenObserver()
        let center = NotificationCenter.default
        let onExit: @Sendable (Notification) -> Void = { [weak self, weak viewerWindow, weak mainWindow] _ in
            MainActor.assumeIsolated {
                guard let self, let viewerWindow, let mainWindow else { return }
                viewerWindow.collectionBehavior.remove(.fullScreenAuxiliary)
                viewerWindow.collectionBehavior.insert(.fullScreenPrimary)
                viewerWindow.setFrame(mainWindow.frame, display: true)
                self.viewerAppState.isFullScreen = false
                self.presentation = .windowedCover
                // 一次性使命完成：退出 inheritedMainFullScreen 后不再需要本监听。
                self.removeMainExitFullScreenObserver()
            }
        }
        mainExitFullScreenObserver = center.addObserver(
            forName: NSWindow.didExitFullScreenNotification, object: mainWindow,
            queue: .main, using: onExit
        )
    }

    private func removeMainExitFullScreenObserver() {
        if let obs = mainExitFullScreenObserver {
            NotificationCenter.default.removeObserver(obs)
            mainExitFullScreenObserver = nil
        }
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
        // I-3：离开 inheritedMain 语义，清掉主窗退全屏监听（否则之后主窗退全屏会强拉脱节的 QV）。
        removeMainExitFullScreenObserver()
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        presentation = .transitioning
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        viewerAppState.isFullScreen = false
        presentation = .windowedCover
        // I-3：离开 inheritedMain 语义，清掉主窗退全屏监听（幂等，重复调安全）。
        removeMainExitFullScreenObserver()
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

    /// 统一 close path：ESC（onDismiss→close）/ ⌘W / 红灯 / 系统关闭都汇到这。
    /// focus 4 步时序（D-QVT7，**别改次序**）：先清 QV 态 → 捕获回调 → 延迟到主窗 become key
    /// 后触发 onDismiss（此时主 hosting 已 key，SwiftUI focusTarget 赋值才生效）→ 拉主窗回前台 → 清状态。
    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }

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
        self.onDismiss = nil
        self.onPrepareDismiss = nil
        self.onIndexChange = nil
        self.entry = nil
        self.mainWindow = nil
        self.pendingDismissReason = .normal
        self.isClosing = false
        // 复位 presentation，让下次 show 干净重判初始态（窗口复用，不复位会带上次残留态）。
        self.presentation = .windowedCover
        // I-1：复位 collectionBehavior（状态对称）。若在 inheritedMainFullScreen 态直接关 QV
        // （⌘W/红灯/findSimilar/commandF 不经 toggleFullScreenFromViewer），.fullScreenAuxiliary
        // 会残留在复用窗上；此处恢复默认，不再依赖下次 show 全量重设兜底。
        window?.collectionBehavior.remove(.fullScreenAuxiliary)
        window?.collectionBehavior.insert(.fullScreenPrimary)
        removeFrameObservers()
        removeMainExitFullScreenObserver()
    }
}
