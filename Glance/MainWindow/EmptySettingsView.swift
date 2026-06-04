//
//  EmptySettingsView.swift
//  Glance
//
//  Settings scene 占位。方向2 Slice2：App body 移除 Window scene 后需保留 ≥1 个非主窗
//  scene 挂 .commands（About 菜单），选 Settings。Glance 暂无设置项故最小占位（YAGNI）。
//

import SwiftUI

struct EmptySettingsView: View {
    var body: some View {
        Text("Glance · 一眼")
            .font(.headline)
            .frame(width: 360, height: 120)
    }
}
