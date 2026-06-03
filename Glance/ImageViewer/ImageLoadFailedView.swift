//
//  ImageLoadFailedView.swift
//  Glance
//
//  方案 3 — 图片加载失败占位。三处复用（智能文件夹 cell / 内嵌预览 / QuickViewer）：
//  区分"加载中"（ProgressView）vs"加载失败"（本 view），避免文件已删 / 解码失败 / 无权限时
//  无限转圈。.secondary 前景在 QV 深色环境与浅/深全局下都自适应可见。
//

import SwiftUI

struct ImageLoadFailedView: View {
    /// 紧凑模式（grid cell 小尺寸）：仅图标无文字；非紧凑（预览/QV 大区域）：图标 + 文字。
    var compact: Bool = false

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(compact ? .title3 : .largeTitle)
                .foregroundStyle(.secondary)
            if !compact {
                Text("无法加载")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
