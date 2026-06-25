//
//  ViewerSession.swift
//  Glance
//
//  一次"看图"会话：持有本次 urls 对应的 security-scoped resource token，
//  并记录关闭时是否要终止 app（冷启动看完即走 = true / warm = false）。
//  二次 show 时旧 session 的 end() 由控制器延后到看图窗关闭再统一调，配平 start/stop
//  且避开与旧加载 task（同步读盘）的竞态。仅被控制器（main actor）调用。
//

import Foundation

@MainActor
final class ViewerSession {
    let id = UUID()
    let urls: [URL]
    /// 看图窗关闭后是否终止整个 app。冷启动 open = true（看完即走）；warm = false（只关窗）。
    let terminateOnClose: Bool

    /// 实际 start 成功、需要在 end 时 stop 的 URL（start 返回 false 的不记，避免不配平 stop）。
    private var accessedURLs: [URL] = []
    private var started = false

    init(urls: [URL], terminateOnClose: Bool) {
        self.urls = urls
        self.terminateOnClose = terminateOnClose
    }

    /// 幂等：重复调只第一次生效。
    func start() {
        guard !started else { return }
        started = true
        for url in urls where url.startAccessingSecurityScopedResource() {
            accessedURLs.append(url)
        }
    }

    /// 幂等：stop 所有 start 成功的 URL，清空。重复调无副作用。
    func end() {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessedURLs.removeAll()
        started = false
    }
}
