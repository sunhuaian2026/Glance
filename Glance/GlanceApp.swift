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

    // 退出语义回标准 true（D-OW15）：Window scene 已移除，瞬态 close 不再发生。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
            indexStoreHolder: indexStoreHolder
        )
    }
}
