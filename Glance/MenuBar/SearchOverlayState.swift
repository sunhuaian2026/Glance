//
//  SearchOverlayState.swift
//  Glance
//
//  D-mb-9.1 — Search overlay trigger event 模式
//  仅持 trigger token, ContentView 仍是 sole state owner.
//

import SwiftUI
import Combine

@MainActor
final class SearchOverlayState: ObservableObject {
    /// 每次 requestOpen() 换新 UUID, ContentView 通过 .onReceive 监听变更触发原 openSearch().
    @Published private(set) var triggerToken: UUID = UUID()

    /// 菜单栏「查找…」点击入口.
    func requestOpen() {
        triggerToken = UUID()
    }
}
