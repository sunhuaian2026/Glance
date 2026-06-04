//
//  SearchOverlayView.swift
//  Glance
//
//  M3 Slice M — ⌘F 触发的顶部 Spotlight 式 search overlay。
//  - D16: 顶部 slide-in overlay 而非 toolbar field / sheet
//  - D15 终态：FocusState.Binding 接父 view 单仲裁焦点，layer = .search
//  - input 内 ESC self-dismiss；Enter 跳 debounce 立即查；↑↓←→ text cursor 不 forward
//

import SwiftUI

struct SearchOverlayView: View {
    /// 父 view（ContentView）持有的 @FocusState binding。input 拿焦点时 binding == .search。
    @FocusState.Binding var focusTarget: AppFocus?

    /// 输入变化 callback。skipDebounce=true 时 caller 立即查不走 200ms timer（Enter 路径）。
    let onInputChange: (_ input: String, _ skipDebounce: Bool) -> Void

    /// ESC / × 关闭 callback。caller 清 currentEphemeral + focusTarget = .grid。
    let onClose: () -> Void

    /// 回车提交 callback。caller 收起 overlay + 结果留为 ephemeral + 焦点移结果网格（空输入 no-op）。
    let onSubmit: (_ input: String) -> Void

    @State private var searchInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            inputRow
            hintRow
        }
        .padding(DS.Search.overlayPadding)
        .frame(maxWidth: DS.Search.overlayMaxWidth)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: DS.Search.overlayCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Search.overlayCornerRadius)
                .strokeBorder(.primary.opacity(DS.Search.overlayBorderOpacity), lineWidth: DS.Search.overlayBorderWidth)
        )
        .padding(.top, DS.Spacing.md)
        .padding(.horizontal, DS.Spacing.lg)
    }

    private var inputRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索...", text: $searchInput)
                .textFieldStyle(.plain)
                .focused($focusTarget, equals: .search)
                .onChange(of: searchInput) { _, newValue in
                    onInputChange(newValue, false)
                }
                .onKeyPress(.return) {
                    onSubmit(searchInput)
                    return .handled
                }
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭 (ESC)")
        }
    }

    private var hintRow: some View {
        Text("提示：type:png · size:>1mb · birth:>2026-01-01")
            .font(.caption)
            .foregroundStyle(.primary.opacity(DS.Search.modifierHintOpacity))
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
