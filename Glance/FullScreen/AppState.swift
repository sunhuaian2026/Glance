//
//  AppState.swift
//  Glance
//

import AppKit
import Combine

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }
}

class AppState: ObservableObject {
    @Published var isFullScreen = false
    /// 窗口是否为 key window。QuickViewerOverlay 靠它在外部打开/冷启动路径下，
    /// 等窗口 become key 后再 assert 键盘焦点（onAppear 时窗口非 key 则 @FocusState 赋值被静默丢弃）。
    @Published var isWindowKey = false
    /// 窗口"身份"token：每次 attach 到新 NSWindow 换一个 UUID。weak var window 本身非 @Published，
    /// view 观察不到其变化；ContentView 靠 .onChange(of: windowIdentity) 检测"窗口已重新出现并稳定"，
    /// 用于 OpenWith warm 激活在单 Window scene 瞬态 close/reopen 后重试 makeKeyAndOrderFront + activate。
    @Published private(set) var windowIdentity = UUID()
    weak var window: NSWindow?

    /// WindowAccessor 拿到（或重新拿到）NSWindow 时调。窗口换了 → 换 windowIdentity 触发观察者。
    func attachWindow(_ newWindow: NSWindow) {
        if window !== newWindow {
            window = newWindow
            windowIdentity = UUID()
        }
        isWindowKey = newWindow.isKeyWindow
    }

    /// 窗口 willClose 时调（单 Window scene 处理 open-document 的瞬态 close 也会触发）。
    func detachWindow(_ closedWindow: NSWindow) {
        guard window === closedWindow else { return }
        window = nil
        isWindowKey = false
        windowIdentity = UUID()
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
            applyAppearance()
        }
    }

    // isFullScreen 默认 false，window 默认 nil，无需显式赋值
    init() {
        let raw = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        self.appearanceMode = AppearanceMode(rawValue: raw) ?? .system
        applyAppearance()
    }

    // SwiftUI .preferredColorScheme(nil) 在 macOS 上无法撤销之前设过的强制值，
    // 改用 NSApp.appearance 直接控 NSAppearance。AppKit 标准 API，最稳定。
    private func applyAppearance() {
        switch appearanceMode {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    func exitFullScreenIfNeeded() {
        guard isFullScreen else { return }
        window?.toggleFullScreen(nil)
    }

    func hideTrafficLights() {
        guard !isFullScreen else { return }
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
            window?.standardWindowButton($0)?.isHidden = true
        }
    }

    func showTrafficLights() {
        // 不加 isFullScreen guard：全屏下系统靠 hover 显示 traffic light，
        // 但前提是 isHidden == false。若之前显式隐藏过，此处必须恢复，否则按钮永久消失。
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
            window?.standardWindowButton($0)?.isHidden = false
        }
    }
}
