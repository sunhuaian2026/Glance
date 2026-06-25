//
//  InspectorState.swift
//  Glance
//
//  D-mb-8 + D-mb-9.1 — Inspector 状态共享(ContentView showInspector 双向 sync).
//  菜单栏「显示信息 / 隐藏信息」动态文案读这里.
//

import SwiftUI
import Combine

@MainActor
final class InspectorState: ObservableObject {
    @Published var isShown: Bool = false
}
