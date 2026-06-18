//
//  MainQuickViewerWindowController+Commands.swift
//  Glance
//
//  D-mb-9.2 — 快速看图器命令 closure registry (只读 facade 段, 写入在主文件).
//

import SwiftUI

enum QuickViewerCommand: Hashable {
    case rotateLeft, rotateRight
    case toggleFlipH, toggleFlipV
    case copyImage, copyPath
    case revealInFinder
    case resetToFit, resetToOneToOne
    case zoomIn, zoomOut
}

@MainActor
extension MainQuickViewerWindowController {
    /// 菜单栏 commands 触发入口(同步动作).
    func performCommand(_ cmd: QuickViewerCommand) {
        guard isPresenting, let handler = commandHandlers[cmd] else { return }
        handler()
    }

    /// 菜单栏 commands 触发入口(异步动作, 仅 trash).
    func performTrash() async {
        guard isPresenting, let handler = trashHandler else { return }
        await handler()
    }

    /// commands view 用作 .disabled binding 第三层(快速看图器在场 + 有图).
    var hasCurrentImage: Bool {
        guard isPresenting else { return false }
        return hasImageProvider()
    }
}
