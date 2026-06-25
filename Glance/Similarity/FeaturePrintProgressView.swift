//
//  FeaturePrintProgressView.swift
//  Glance
//
//  M2 Slice J — feature print 索引进度 chip。形态 mirror Slice I IndexingProgressView：
//  Capsule + .thickMaterial + .strokeBorder hairline + 取消 X 按钮。视觉差异化：图标用
//  rectangle.stack.badge.plus 区分扫描 chip（progress spinner）。
//
//  挂在 ContentView mainContent ZStack 顶层 VStack 第二行（Slice I chip 之下），共享相同
//  动效 + 隐藏规则（progress = nil → fade out）。
//

import SwiftUI

struct FeaturePrintProgressView: View {
    let progress: FeaturePrintIndexingProgress
    var onCancel: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Similarity.chipAccent)
            Text("正在索引相似度 · \(progress.indexed) / \(progress.total)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            if let onCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.secondaryText)
                }
                .buttonStyle(.borderless)
                .help("取消相似度索引")
            }
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(.thickMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                .primary.opacity(DS.SectionHeader.chipBorderOpacity),
                lineWidth: DS.SectionHeader.chipBorderWidth
            )
        )
    }
}
