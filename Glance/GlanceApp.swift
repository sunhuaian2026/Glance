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
    @StateObject private var bookmarkManager: BookmarkManager
    @StateObject private var folderStore: FolderStore
    @StateObject private var appState = AppState()
    @StateObject private var indexStoreHolder: IndexStoreHolder

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let bm = BookmarkManager()
        _bookmarkManager = StateObject(wrappedValue: bm)
        _folderStore = StateObject(wrappedValue: FolderStore(bookmarkManager: bm))
        _indexStoreHolder = StateObject(wrappedValue: IndexStoreHolder())
    }

    var body: some Scene {
        // 单实例 Window 而非 WindowGroup：声明 CFBundleDocumentTypes 后 WindowGroup 会被
        // macOS 当"可开文档"按每个外部打开文件 spawn 一个空白窗口实例，抢 key window 导致
        // QV 焦点落空（ESC 失效）+ 空白 grid 窗口遮挡 QV。Window 是单实例场景，系统无法
        // spawn 第二个，所有外部打开都进同一窗口。看图器本就单窗口，去掉 ⌘N 多窗口符合设计。
        Window("一眼", id: "main") {
            ContentView()
                .environmentObject(bookmarkManager)
                .environmentObject(folderStore)
                .environmentObject(appState)
                .environmentObject(indexStoreHolder)
                .environmentObject(ExternalOpenCoordinator.shared)
                .onAppear {
                    folderStore.loadSavedFolders()
                }
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            // 替换标准"关于"菜单：弹自定义 AboutView 支持点击复制
            // 通过 AboutWindowController（纯 AppKit）显示，避免 SwiftUI Window scene
            // 无法在显示前定位导致的 A→B 跳跃问题
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

class AppDelegate: NSObject, NSApplicationDelegate {
    var accessedURLs: [URL] = []

    // OpenWith — 单 Window scene + CFBundleDocumentTypes 下，warm（app 运行中）从 Finder
    // 「打开方式」打开图片时，SwiftUI 处理 open-document 会让窗口瞬间 close（窗口数→0），
    // 默认 true 会在 QV 显出前就终止 app。返回 false 让 app 在零窗口瞬态存活；用户关窗后
    // app 驻留，点 Dock 图标可重开窗口，⌘Q 退出。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // 从 Finder「打开方式」/ Dock 拖放接收图片文件 → 过滤图片 URL → 直接打开独立看图窗
    // （方向 2：ExternalViewerWindowController 自建 NSWindow，置顶可控，不复用图库主窗）。
    // Slice 1 恒传 terminateOnClose:false（warm-only 验证）；冷启动"看完即走"在 Slice 2 收 lifecycle 后接。
    func application(_ application: NSApplication, open urls: [URL]) {
        let images = urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        }
        guard !images.isEmpty else { return }
        ExternalViewerWindowController.shared.show(urls: images, terminateOnClose: false)
    }
}
