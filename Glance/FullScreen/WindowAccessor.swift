//
//  WindowAccessor.swift
//  Glance
//

import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let appState: AppState

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            appState.window = window
            window.delegate = context.coordinator
            // 播种当前 key 真值：delegate 安装时窗口可能已是 key（错过 windowDidBecomeKey
            // 通知），否则 isWindowKey 永为 false 会拖垮 grid/preview 路径的 QV 焦点。
            appState.isWindowKey = window.isKeyWindow
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                appState.window = window
                if window.delegate == nil {
                    window.delegate = context.coordinator
                }
                appState.isWindowKey = window.isKeyWindow
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    class Coordinator: NSObject, NSWindowDelegate {
        let appState: AppState

        init(appState: AppState) {
            self.appState = appState
        }

        func windowDidEnterFullScreen(_ notification: Notification) {
            appState.isFullScreen = true
        }

        func windowDidExitFullScreen(_ notification: Notification) {
            appState.isFullScreen = false
        }

        func windowDidBecomeKey(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                  window === appState.window else { return }
            appState.isWindowKey = true
        }

        func windowDidResignKey(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                  window === appState.window else { return }
            appState.isWindowKey = false
        }
    }
}
