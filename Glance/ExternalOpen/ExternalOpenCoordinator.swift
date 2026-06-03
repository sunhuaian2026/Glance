import Foundation
import Combine

/// AppDelegate（application(_:open:)）→ SwiftUI ContentView 的单向桥。
/// 沙盒「打开方式」/ Dock 拖放传入的图片 URL 暂存此处，ContentView 观察 pendingOpen
/// 变化后消费（设回 nil）。单例 mirror AboutWindowController.shared pattern。
final class ExternalOpenCoordinator: ObservableObject {
    static let shared = ExternalOpenCoordinator()

    /// 待处理的外部打开图片 URL 集合。ContentView 消费后清回 nil。
    @Published var pendingOpen: [URL]?

    private init() {}
}
