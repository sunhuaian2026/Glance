//
//  ExternalViewerWindowController.swift
//  Glance
//
//  外部打开（Finder「打开方式」/ Dock 拖放）的独立看图窗（Preview/Quick Look 式）。
//  纯 AppKit 单例：自建 NSWindow + NSHostingController(QuickViewerOverlay)，自任
//  NSWindowDelegate（不接 WindowAccessor，避免 delegate 被抢）。持有 ViewerSession
//  管理 security-scope + terminateOnClose。窗口关闭统一走 windowWillClose path。
//

import AppKit
import SwiftUI

@MainActor
final class ExternalViewerWindowController: NSObject {
    static let shared = ExternalViewerWindowController()

    private var window: NSWindow?
    private var hosting: NSHostingController<AnyView>?
    /// 看图窗专属 AppState（F 全屏 / traffic light / 焦点都作用在看图窗，不碰图库窗）。
    private let viewerAppState = AppState()
    private var session: ViewerSession?
    /// 二次 show 退役的旧 session。**不在二次 show 时 end**——旧 VM 的嵌套 `Task.detached{loadFullNSImage}`
    /// 是同步读盘、协作式 cancel 挡不住，过早 stop scope 与之竞态。改为累积到 windowWillClose 统一 end：
    /// 短期 scope 重叠无害（sandbox 允许同进程多 scoped resource），可证安全。代价：一次 warm 会话内反复
    /// 开图，scope 保留到关窗才释放——Slice 1 只测几张~几十张可接受。
    private var retiredSessions: [ViewerSession] = []

    private override init() { super.init() }

    /// 打开/复用看图窗显示 urls。terminateOnClose：Slice 1 恒 false（warm-only）。
    func show(urls: [URL], terminateOnClose: Bool) {
        guard !urls.isEmpty else { return }

        // 二次打开：旧 session 退役但不 end（见 retiredSessions 注释），新 session start 新 scope。
        if let current = session {
            retiredSessions.append(current)
        }
        let newSession = ViewerSession(urls: urls, terminateOnClose: terminateOnClose)
        newSession.start()
        session = newSession

        if window == nil {
            createWindow()
        }
        guard let win = window else { return }

        // 先 attach（播种 window 指针，让 QV onAppear 时 viewerAppState.window 非 nil），再换 rootView。
        viewerAppState.attachWindow(win)
        // 换 rootView：.id(session.id) 强制 QuickViewerOverlay 重建 viewModel 显新图源。
        hosting?.rootView = makeRootView(session: newSession)

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // deferred 置顶 reassert：主 SwiftUI scene 仍在场，warm open 时它可能在本帧后手 order/key 抢走置顶。
        // 下一 main-actor hop 再 assert 一次。guard session.id 仍 current + 窗口仍 visible，避免窗口已关闭
        // （isReleasedWhenClosed=false → self.window 仍非 nil）或已被更新的 show 取代时把旧窗拉前台。
        let currentID = newSession.id
        Task { @MainActor [weak self] in
            guard let self, let win = self.window,
                  self.session?.id == currentID, win.isVisible else { return }
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func makeRootView(session: ViewerSession) -> AnyView {
        AnyView(
            QuickViewerOverlay(
                images: session.urls,
                startIndex: 0,
                onDismiss: { [weak self] in self?.closeWindow() },
                onIndexChange: { _ in },          // 看图窗不同步任何图库选中
                onFindSimilar: nil,               // 纯看图，砍找类似（D-OW7）
                currentSupportsFeaturePrint: false,
                onCommandF: nil,                  // 纯看图，砍搜索（D-OW7）
                onBrowseFolder: nil               // 纯看图，砍浏览所在文件夹（D-OW7）
            )
            .environmentObject(viewerAppState)
            .id(session.id)
        )
    }

    private func createWindow() {
        let host = NSHostingController(rootView: AnyView(EmptyView()))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.contentViewController = host
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false  // 关闭后保留实例，下次 show 复用同一 window
        win.collectionBehavior.insert(.fullScreenPrimary)  // 允许 F 进原生全屏
        win.center()
        win.delegate = self
        self.window = win
        self.hosting = host
    }

    /// onDismiss / 外部主动关窗入口。触发 window.close() → windowWillClose 走统一 close path。
    private func closeWindow() {
        window?.close()
    }
}

// MARK: - NSWindowDelegate（复刻 WindowAccessor.Coordinator 的 fullscreen/key 跟踪 + 统一 close path）

extension ExternalViewerWindowController: NSWindowDelegate {
    func windowDidEnterFullScreen(_ notification: Notification) {
        viewerAppState.isFullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        viewerAppState.isFullScreen = false
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

    /// 统一 close path：ESC（onDismiss→closeWindow）/ ⌘W / 红灯 / 系统关闭都汇到这。
    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        // 无条件 reset：全屏中 ⌘W/红灯关窗后若残留 isFullScreen=true，下次打开第一下 ESC
        // 会被 QV 当成"退全屏"而非关窗。detach 已清 isWindowKey，这里补 isFullScreen。
        viewerAppState.isFullScreen = false
        viewerAppState.detachWindow(win)
        let terminate = session?.terminateOnClose ?? false
        // 统一在关窗时 end 当前 + 所有退役 session（stop 全部 security-scope，幂等）。
        session?.end()
        retiredSessions.forEach { $0.end() }
        retiredSessions.removeAll()
        session = nil
        if terminate {
            NSApp.terminate(nil)
        }
        // terminate=false：isReleasedWhenClosed=false，window 实例保留待下次 show 复用。
    }
}
