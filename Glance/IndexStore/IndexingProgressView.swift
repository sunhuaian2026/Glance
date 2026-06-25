//
//  IndexingProgressView.swift
//  Glance
//
//  Slice I.1 — 首次索引进度 chip。形态 mirror Slice B sticky chip：Capsule +
//  .thickMaterial + .strokeBorder hairline，左对齐 fit-content。
//
//  挂在 ContentView mainContent ZStack 顶层（top alignment），扫描进行中显示，
//  扫完自动隐藏（IndexStoreHolder.progress = nil）。
//

import SwiftUI

struct IndexingProgressView: View {
    let progress: IndexingProgress
    /// Slice I.2 — 用户点 X 按钮时调（取消当前扫描；nil → 不显示按钮，scan 不可中断）。
    var onCancel: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(DS.IndexingProgress.spinnerScale)
            Text("正在索引「\(progress.rootName)」 · \(progress.scanned) 已扫 / \(progress.indexed) 入库")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            if let onCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.secondaryText)
                }
                .buttonStyle(.borderless)
                .help("取消索引")
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
