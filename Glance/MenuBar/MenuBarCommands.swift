//
//  MenuBarCommands.swift
//  Glance
//
//  D-mb-1 / D-mb-6 — 5 个菜单 commands view struct.
//  任务 B-E 逐个填充内容.
//

import SwiftUI

/// 文件菜单(任务 B).
struct FileMenuCommands: View {
    @ObservedObject var folderStore: FolderStore

    var body: some View {
        Button("添加文件夹根…") {
            folderStore.addFolder()
        }
    }
}

/// 编辑菜单(任务 C 填充).
struct EditMenuCommands: View {
    @ObservedObject var searchOverlayState: SearchOverlayState
    @ObservedObject var qvController: MainQuickViewerWindowController

    var body: some View {
        EmptyView()  // 任务 C 填充
    }
}

/// 显示菜单(任务 E 填充).
struct ViewMenuCommands: View {
    @ObservedObject var inspectorState: InspectorState
    @ObservedObject var qvController: MainQuickViewerWindowController
    @ObservedObject var folderStore: FolderStore

    var body: some View {
        EmptyView()  // 任务 E 填充
    }
}

/// 图像菜单(任务 D 填充).
struct ImageMenuCommands: View {
    @ObservedObject var qvController: MainQuickViewerWindowController

    var body: some View {
        EmptyView()  // 任务 D 填充
    }
}

/// 窗口菜单(任务 B).
struct WindowMenuCommands: View {
    let bookmarkManager: BookmarkManager
    let folderStore: FolderStore
    let appState: AppState
    let indexStoreHolder: IndexStoreHolder
    let searchOverlayState: SearchOverlayState
    let inspectorState: InspectorState
    @ObservedObject var mainWindowController: MainWindowController

    var body: some View {
        if !mainWindowController.hasWindow {
            Button("图库主窗") {
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
    }
}
