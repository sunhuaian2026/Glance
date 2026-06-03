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
            // attachWindow 同时播种 isWindowKey（delegate 安装时窗口可能已是 key，错过
            // windowDidBecomeKey 通知）+ 换 windowIdentity 通知 ContentView 窗口已就绪。
            appState.attachWindow(window)
            window.delegate = context.coordinator
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                appState.attachWindow(window)
                if window.delegate == nil {
                    window.delegate = context.coordinator
                }
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
            // 不 guard `=== appState.window`：reopen 时新窗口 become key 可能早于 makeNSView
            // 更新 appState.window，此处用 attachWindow 把新窗口认下来（含换 identity + 置 key）。
            guard let window = notification.object as? NSWindow else { return }
            appState.attachWindow(window)
        }

        func windowDidResignKey(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                  window === appState.window else { return }
            appState.isWindowKey = false
        }

        func windowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            appState.detachWindow(window)
        }
    }
}
