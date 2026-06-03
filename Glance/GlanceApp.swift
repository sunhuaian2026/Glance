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

    func applicationWillTerminate(_ notification: Notification) {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // 从 Finder「打开方式」/ Dock 拖放 / 拖图到窗口接收图片文件。
    // 过滤出图片 URL 后写入 coordinator，由 ContentView 观察消费驱动 QuickViewer。
    func application(_ application: NSApplication, open urls: [URL]) {
        let images = urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        }
        guard !images.isEmpty else { return }
        // warm 场景（Glance 后台运行时 Open With）确保唯一窗口激活到 key/front，
        // 否则 QV 的 .onAppear { isFocused = true } 焦点请求落空，ESC 失效需点一下。
        NSApp.activate(ignoringOtherApps: true)
        ExternalOpenCoordinator.shared.pendingOpen = images
    }
}
