//
//  MainWindowController.swift
//  Glance
//
//  图库主窗（ContentView）的自建 NSWindow 管理。方向2 Slice2：把主窗创建权从 SwiftUI
//  Window scene 收回 AppDelegate（D-OW9），odoc 进来时 SwiftUI 不再瞬态 close 主窗，
//  根治 cold 双窗 + warm 关图主窗丢失。mirror AboutWindowController 骨架 + 自任
//  NSWindowDelegate 接管 AppState 挂接（D-OW16，单一 delegate 归属，避免与 WindowAccessor 争抢）。
//

import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject {
    static let shared = MainWindowController()

    private var window: NSWindow?
    /// delegate 回调驱动图库 appState（attach/fullscreen/key）。ownership 在 AppDelegate，
    /// 此处弱引用避免循环（AppDelegate 持 appState 整个 app 生命周期，回调时必非 nil）。
    private weak var appState: AppState?
    /// 「主窗下次 become key 后执行一次」的回调队列（QV 关闭后归还焦点的时序地基，Task 1.2 用）。
    private var pendingBecomeKeyBlocks: [() -> Void] = []

    /// AppDelegate 查"图库主窗是否已建且在场"决定首窗/reopen（D-OW14，禁扫 NSApp.windows）。
    var hasWindow: Bool { window != nil }

    private override init() { super.init() }

    /// 注册「主窗下次 become key 后执行一次」的回调。QV 关闭归还焦点时序地基（Task 1.2 用）。
    /// I1 fallback：若主窗当前已是 key window（QV 显示期间没真正 resign key / 激活竞态），则
    /// makeKeyAndOrderFront 是 no-op、不产生 become-key transition、block 永不 drain → focus 死结。
    /// 此时直接调度（mirror drain 路径同样的 Task.yield 让 SwiftUI 焦点请求生效），不入队等永不来的下次 become key。
    func runAfterNextBecomeKey(_ block: @escaping () -> Void) {
        if window?.isKeyWindow == true {
            Task { @MainActor in
                await Task.yield()
                block()
            }
        } else {
            pendingBecomeKeyBlocks.append(block)
        }
    }

    /// 建/复用图库主窗。注入集由 AppDelegate 传入（ownership 在 AppDelegate，D-OW12）。
    func show(
        bookmarkManager: BookmarkManager,
        folderStore: FolderStore,
        appState: AppState,
        indexStoreHolder: IndexStoreHolder
    ) {
        self.appState = appState
        if window == nil {
            createWindow(
                bookmarkManager: bookmarkManager,
                folderStore: folderStore,
                appState: appState,
                indexStoreHolder: indexStoreHolder
            )
            folderStore.loadSavedFolders()  // 原 ContentView .onAppear 的加载迁来（scene 没了，显式调）
        }
        guard let win = window else { return }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appState.attachWindow(win)  // 兜底再 attach（幂等：同 win 第二次只刷新 isWindowKey，不重换 windowIdentity）
    }

    private func createWindow(
        bookmarkManager: BookmarkManager,
        folderStore: FolderStore,
        appState: AppState,
        indexStoreHolder: IndexStoreHolder
    ) {
        // ContentView 在后续 task 已移除内部 WindowAccessor（delegate 单一归属 D-OW16）；
        // 本 controller 自任 NSWindowDelegate 接管 attach/fullscreen/key/close 驱动 appState。
        let root = ContentView()
            .environmentObject(bookmarkManager)
            .environmentObject(folderStore)
            .environmentObject(appState)
            .environmentObject(indexStoreHolder)
        let host = NSHostingView(rootView: AnyView(root))
        host.autoresizingMask = [.width, .height]
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: DS.ExternalViewer.defaultWindowWidth,
                                height: DS.ExternalViewer.defaultWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.contentView = host
        win.title = "一眼"
        win.isReleasedWhenClosed = false  // 防 windowWillClose 期间访问已释放 window；windowWillClose 置 window=nil → 下次 show 重建新实例（非复用同窗）
        win.collectionBehavior.insert(.fullScreenPrimary)
        win.center()
        win.delegate = self            // 单一 delegate 归属（D-OW16）
        self.window = win
        appState.attachWindow(win)     // 主动 attach 播种 window 指针（替代原 WindowAccessor 的 attach）
    }
}

// MARK: - NSWindowDelegate（mirror Slice 1 ExternalViewerWindowController：接管 attach/fullscreen/key/close）
extension MainWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        appState?.attachWindow(win)
        // Drain one-shot become-key blocks. 包一层 Task + Task.yield 让 SwiftUI 焦点请求在
        // 本帧 attach 之后生效（QV 关闭后归还焦点的时序地基）。
        guard !pendingBecomeKeyBlocks.isEmpty else { return }
        let blocks = pendingBecomeKeyBlocks
        pendingBecomeKeyBlocks.removeAll()
        Task { @MainActor in
            await Task.yield()
            blocks.forEach { $0() }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win === appState?.window else { return }
        appState?.isWindowKey = false
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        appState?.isFullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        appState?.isFullScreen = false
    }

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        // 主窗关闭：reset isFullScreen + detach + 清 window 引用（hasWindow 翻 false，reopen 重建）。
        appState?.isFullScreen = false
        appState?.detachWindow(win)
        window = nil
    }
}
