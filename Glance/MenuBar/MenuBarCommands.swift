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
        Group {
            // D-mb-3 / D-mb-7 — 手工拼快捷键 hint, 零 .keyboardShortcut (方向 Y)
            Button("查找…  (⌘F)") {
                searchOverlayState.requestOpen()
            }

            Divider()

            Button("复制图片  (⌘C)") {
                qvController.performCommand(.copyImage)
            }
            .disabled(!qvController.hasCurrentImage)

            Button("复制路径  (⌘⌥C)") {
                qvController.performCommand(.copyPath)
            }
            .disabled(!qvController.isPresenting)
        }
    }
}

/// 显示菜单(任务 E).
struct ViewMenuCommands: View {
    @ObservedObject var inspectorState: InspectorState
    @ObservedObject var qvController: MainQuickViewerWindowController
    @ObservedObject var folderStore: FolderStore

    var body: some View {
        Group {
            // D-mb-8 — 动态文案: 信息切换
            Button(inspectorState.isShown ? "隐藏信息  (⌘I)" : "显示信息  (⌘I)") {
                inspectorState.isShown.toggle()
            }
            .disabled(folderStore.selectedImageIndex == nil)

            Divider()

            // 缩放系列 (快速看图器在场时 enable)
            Button("适合窗口  (⌘0)") {
                qvController.performCommand(.resetToFit)
            }
            .disabled(!qvController.isPresenting)

            Button("实际大小  (0)") {
                qvController.performCommand(.resetToOneToOne)
            }
            .disabled(!qvController.isPresenting)

            Button("放大  (⌘=)") {
                qvController.performCommand(.zoomIn)
            }
            .disabled(!qvController.isPresenting)

            Button("缩小  (⌘−)") {
                qvController.performCommand(.zoomOut)
            }
            .disabled(!qvController.isPresenting)
        }
    }
}

/// 图像菜单(任务 D 填充).
struct ImageMenuCommands: View {
    @ObservedObject var qvController: MainQuickViewerWindowController

    var body: some View {
        Group {
            // 旋转
            Button("旋转左  (L)") {
                qvController.performCommand(.rotateLeft)
            }
            .disabled(!qvController.isPresenting)

            Button("旋转右  (R)") {
                qvController.performCommand(.rotateRight)
            }
            .disabled(!qvController.isPresenting)

            Divider()

            // 翻转 (无快捷键)
            Button("水平翻转") {
                qvController.performCommand(.toggleFlipH)
            }
            .disabled(!qvController.isPresenting)

            Button("垂直翻转") {
                qvController.performCommand(.toggleFlipV)
            }
            .disabled(!qvController.isPresenting)

            Divider()

            // Finder 显示
            Button("在 Finder 中显示  (⌘⇧R)") {
                qvController.performCommand(.revealInFinder)
            }
            .disabled(!qvController.isPresenting)

            Divider()

            // 移到废纸篓 (async)
            Button("移到废纸篓  (⌫)") {
                Task { await qvController.performTrash() }
            }
            .disabled(!qvController.isPresenting)
        }
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
