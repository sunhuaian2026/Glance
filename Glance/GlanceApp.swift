//
//  GlanceApp.swift
//  Glance
//
//  Created by 孙红军 on 2026/3/16.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct GlanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 方向2 Slice2：移除 Window("一眼") 主窗 scene，图库主窗改由 AppDelegate +
        // MainWindowController 自建（D-OW9）。App body 只留 Settings 非主窗 scene 挂
        // .commands（About 菜单）。冷启动首窗 / reopen 全走 AppDelegate（D-OW14）。
        Settings {
            EmptySettingsView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuButton()
            }
            // 任务 B — 文件菜单「添加文件夹根…」
            CommandGroup(after: .newItem) {
                FileMenuCommands(folderStore: appDelegate.folderStore)
            }
            // 任务 B — 窗口菜单「图库主窗」reopen (hide when hasWindow)
            CommandGroup(after: .windowList) {
                WindowMenuCommands(
                    bookmarkManager: appDelegate.bookmarkManager,
                    folderStore: appDelegate.folderStore,
                    appState: appDelegate.appState,
                    indexStoreHolder: appDelegate.indexStoreHolder,
                    searchOverlayState: appDelegate.searchOverlayState,
                    inspectorState: appDelegate.inspectorState,
                    mainWindowController: MainWindowController.shared
                )
            }
        }
    }
}

private struct AboutMenuButton: View {
    var body: some View {
        Button("关于一眼") {
            AboutWindowController.shared.show()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // 对象 ownership（原 GlanceApp @StateObject 迁来，D-OW12）。
    let bookmarkManager: BookmarkManager
    let folderStore: FolderStore
    let appState = AppState()
    let indexStoreHolder = IndexStoreHolder()

    // D-mb-9 新增 2 单例(菜单栏增补 第一批)
    let searchOverlayState = SearchOverlayState()
    let inspectorState = InspectorState()

    // D-OW14 lifecycle 状态机
    private var hasFinishedLaunching = false
    private var launchedForFileOpen = false

    // security-scope 兜底（原有）
    var accessedURLs: [URL] = []

    override init() {
        // 只构造 BookmarkManager/FolderStore（读 UserDefaults/bookmark，不碰 live NSWindow/NSApp）。
        let bm = BookmarkManager()
        self.bookmarkManager = bm
        self.folderStore = FolderStore(bookmarkManager: bm)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hasFinishedLaunching = true
        // 不是为打开文件而启动 → 建图库主窗（普通 launch）。是 → 只看图窗（cold 看完即走）。
        if !launchedForFileOpen {
            showMainWindow()
        }
    }

    // 点 Dock 图标 / reopen：无图库主窗则重建（D-OW14）。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !MainWindowController.shared.hasWindow {
            showMainWindow()
        }
        return true
    }

    // 退出语义（D-OW15 修正，用户拍板「关窗驻留」）：图库 app 关最后一窗不自动退、驻留 dock
    // 可 reopen、⌘Q 才真退（像 Photos/Preview/访达）。cold 看完即走**不受影响**——由
    // ExternalViewerWindowController 看图窗 terminateOnClose=true 主动 NSApp.terminate 控制，
    // 与 last-window 语义独立。（Window scene 已移除，false 不再有 Slice1 的瞬态自杀风险。）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // Finder「打开方式」/ Dock 拖放（D-OW14 cold/warm 分流）。
    func application(_ application: NSApplication, open urls: [URL]) {
        let images = urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        }
        guard !images.isEmpty else { return }
        // cold（启动前收到 open）：标记 + terminateOnClose=true（看完即走）。
        // warm（已 finishedLaunching）：terminateOnClose=false（只关看图窗，主窗不动）。
        if !hasFinishedLaunching {
            launchedForFileOpen = true
        }
        ExternalViewerWindowController.shared.show(
            urls: images,
            terminateOnClose: !hasFinishedLaunching
        )
    }

    private func showMainWindow() {
        MainWindowController.shared.show(
            bookmarkManager: bookmarkManager,
            folderStore: folderStore,
            appState: appState,
            indexStoreHolder: indexStoreHolder,
            searchOverlayState: searchOverlayState,
            inspectorState: inspectorState
        )
    }
}
