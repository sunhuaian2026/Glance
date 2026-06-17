//
//  BookmarkMigrationView.swift
//  Glance
//
//  M4 任务 2 收尾 — V1→V2 bookmark 升级引导 sheet 纯展示 view.
//  状态由 BookmarkMigrationCoordinator 持, 本 view 不持状态.
//  入参: onConfirm (点「重新选择根目录 →」) / onDismiss (点「以后再说」).
//  D1-bm-ui 拍 SwiftUI .sheet 形态. D6-bm-ui 拍三句话简洁 + DisclosureGroup 默认折起.
//

import SwiftUI

struct BookmarkMigrationView: View {
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    @State private var showWhy: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.BookmarkMigration.contentSpacing) {
            Text("升级清理权限")
                .font(DS.BookmarkMigration.titleFont)

            Text("Glance 早期版本使用只读授权，无法把图片移入废纸篓。请重新选择你的根目录，授予写权限。一次性操作。")
                .font(DS.BookmarkMigration.bodyFont)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup(isExpanded: $showWhy) {
                Text("macOS 沙盒授权模型限定：只读 bookmark 不能升级为读写，必须重新创建。")
                    .font(DS.BookmarkMigration.disclosureFont)
                    .foregroundStyle(.secondary)
                    .padding(.top, DS.Spacing.xs)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                Text("为什么需要重新选?")
                    .font(DS.BookmarkMigration.disclosureFont)
            }

            HStack(spacing: DS.BookmarkMigration.buttonSpacing) {
                Spacer(minLength: DS.Spacing.zero)
                Button("以后再说") { onDismiss() }
                    .buttonStyle(.bordered)
                Button("重新选择根目录 →") { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, DS.BookmarkMigration.sheetVerticalPadding)
        .padding(.horizontal, DS.BookmarkMigration.sheetHorizontalPadding)
        .frame(minWidth: DS.BookmarkMigration.sheetMinWidth)
    }
}
