//
//  TrashUndoBanner.swift
//  Glance
//
//  M4 任务 2 — ContentView 级 overlay banner (D33).
//  「已移 N 张到废纸篓 [撤销] [×]」+ 副文案 (「+M 张失败 / 已取消」) + 30s auto-dismiss.
//  快速看图器在场不可见 (NSWindow 独立, ZStack 外) 但 state 保留, 关闭后回归.
//  纯展示, state 由 ContentView 拥有.
//

import SwiftUI

struct TrashUndoBanner: View {
    let event: TrashOutcomeEvent
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DS.Dedup.bannerButtonSpacing) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(mainText)
                    .font(.body.weight(.medium))
                if let sub = subText {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: DS.Spacing.zero)
            if !isUndoPhase {
                Button("撤销") { onUndo() }
                    .buttonStyle(.borderedProminent)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Dedup.bannerHorizontalPadding)
        .padding(.vertical, DS.Dedup.bannerVerticalPadding)
        .frame(maxWidth: DS.Dedup.bannerMaxWidth)
        .background(.thinMaterial.opacity(DS.Dedup.bannerBackgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.bannerCornerRadius))
    }

    private var isUndoPhase: Bool { event.undoResult != nil }

    /// trash 阶段: 「已移 N 张到废纸篓」; undo 阶段: 「撤销完成 N 张」
    private var mainText: String {
        if let restore = event.undoResult {
            return "撤销完成 \(restore.successCount) 张"
        }
        return "已移 \(event.trash.successCount) 张到废纸篓"
    }

    /// 副文案统一汇总: trash 失败 + 取消 + (undo 阶段) restore 失败 + DB 双失败
    private var subText: String? {
        var parts: [String] = []
        if event.trash.failureCount > 0 {
            parts.append("\(event.trash.failureCount) 张未移入")
        }
        if event.trash.cancelled {
            parts.append("已取消")
        }
        if let restore = event.undoResult {
            if restore.failureCount > 0 {
                parts.append("\(restore.failureCount) 张撤销失败")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
