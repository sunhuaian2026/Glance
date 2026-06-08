//
//  MainQuickViewerWindowController.swift
//  Glance
//
//  主窗 QV（双击进全窗看图）的独立无装饰 NSWindow。Task 1.1 契约骨架：enum +
//  API 签名 + 窗口创建骨架（mirror ExternalViewerWindowController）。Task 1.2/1.3
//  填 show/close 实现 + NSWindowDelegate 回调。
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

    @Published private(set) var isPresenting: Bool = false

    private var window: NSWindow?
    /// 用 NSHostingView 当 window.contentView（mirror ExternalViewerWindowController）。**不用**
    /// NSHostingController 当 contentViewController——那样 AppKit 会忽略 contentRect、改用 hosting
    /// 的 fittingSize 把窗口压成 1×1（看不见图）。
    private var hosting: NSHostingView<AnyView>?
    /// 看图窗专属 AppState（F 全屏 / traffic light / 焦点都作用在 QV 窗，不碰图库主窗）。
    private let viewerAppState = AppState()

    private override init() { super.init() }

    /// 打开 QV 窗显示 images。Task 1.2 填实现。
    func show(images: [URL], startIndex: Int, entry: QuickViewerEntry,
              mainWindow: NSWindow,
              currentSupportsFeaturePrint: Bool,
              onIndexChange: @escaping (Int) -> Void,
              onDismiss: @escaping (QVDismissalReason, QuickViewerEntry) -> Void) {
        // TODO: [2026-06-08] Task 1.2: 同框定位 + attach viewerAppState + 换 rootView + makeKeyAndOrderFront
    }

    /// 关闭 QV 窗。Task 1.2 填实现。
    func close(reason: QVDismissalReason) {
        // TODO: [2026-06-08] Task 1.2: window.close() → windowWillClose 统一 close path 回调 onDismiss
    }

    /// 窗口创建骨架（mirror ExternalViewerWindowController.createWindow）。
    /// 尺寸暂用 DS.ExternalViewer 默认 + center；Task 1.2 改成盖住主窗同框。
    private func createWindow() {
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.autoresizingMask = [.width, .height]  // 跟随 window resize / 进全屏铺满
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: DS.ExternalViewer.defaultWindowWidth,
                                height: DS.ExternalViewer.defaultWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.contentView = host  // 用 contentView 而非 contentViewController，保住 contentRect 尺寸
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false  // 关闭后保留实例，下次 show 复用同一 window
        win.collectionBehavior.insert(.fullScreenPrimary)  // 允许 F 进原生全屏
        win.center()
        win.delegate = self
        self.window = win
        self.hosting = host
    }
}

// MARK: - NSWindowDelegate（Task 1.2 填 fullscreen/key 跟踪 + 统一 close path）

extension MainQuickViewerWindowController: NSWindowDelegate {
    // TODO: [2026-06-08] Task 1.2: windowDidEnterFullScreen / windowDidExitFullScreen /
    // windowDidBecomeKey / windowDidResignKey / windowWillClose（reset isPresenting + 回调 onDismiss）
}
