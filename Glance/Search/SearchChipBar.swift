//
//  SearchChipBar.swift
//  Glance
//
//  M3 chips — 搜索筛选 chip 行（D21/D22/D25）。chip 选中态绑父 SearchFilterState。
//  popover 用 SwiftUI 原生 .popover（系统管层级/dismiss，design R4）。
//

import SwiftUI

struct SearchChipBar: View {
    @Binding var filterState: SearchFilterState
    /// 任一 chip 变更 → 通知父即时查询（skipDebounce）。
    let onChange: () -> Void
    /// 父（ContentView）持有的单一 @FocusState binding，透过 SearchOverlayView 链式下发。
    /// popover dismiss 后把焦点弹回搜索框 .search（根因修复：否则关 popover 后无法继续打字/回车提交）。
    @FocusState.Binding var focusTarget: AppFocus?

    @State private var showTypePopover = false
    @State private var showSizePopover = false
    @State private var showTimePopover = false

    var body: some View {
        HStack(spacing: DS.Search.chipSpacing) {
            typeChip
            sizeChip
            timeChip
            Spacer(minLength: DS.Spacing.zero)
        }
    }

    // MARK: 类型（多选）
    private var typeChip: some View {
        chipButton(title: typeTitle, selected: !filterState.selectedFormats.isEmpty) { showTypePopover = true }
        .popover(isPresented: $showTypePopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(ImageMetadataReader.canonicalFormatLabels, id: \.self) { fmt in
                    Button {
                        if filterState.selectedFormats.contains(fmt) { filterState.selectedFormats.remove(fmt) }
                        else { filterState.selectedFormats.insert(fmt) }
                        onChange()
                    } label: {
                        HStack {
                            Image(systemName: filterState.selectedFormats.contains(fmt) ? "checkmark.square.fill" : "square")
                            Text(fmt); Spacer()
                        }
                    }.buttonStyle(.plain)
                }
                Divider()
                Button("清除") { filterState.selectedFormats = []; onChange() }.buttonStyle(.plain)
            }
            .padding(DS.Spacing.sm).frame(minWidth: DS.Search.popoverMinWidth)
            .onExitCommand { showTypePopover = false }   // codex R4：ESC 关本 popover，不冒泡到 overlay
        }
        .onChange(of: showTypePopover) { _, isOpen in if !isOpen { returnFocusToSearch() } }   // 根因：popover 关后焦点弹回搜索框
    }
    private var typeTitle: String {
        let s = filterState.selectedFormats.sorted()
        if s.isEmpty { return "类型" }
        return s.count == 1 ? "类型: \(s[0])" : "类型: \(s[0]) +\(s.count - 1)"
    }

    // MARK: 大小（单选）
    private var sizeChip: some View {
        chipButton(title: filterState.selectedSize.map { "大小: \($0.label)" } ?? "大小",
                   selected: filterState.selectedSize != nil) { showSizePopover = true }
        .popover(isPresented: $showSizePopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(SearchSizeBucket.allCases, id: \.self) { b in
                    Button {
                        filterState.selectedSize = (filterState.selectedSize == b) ? nil : b
                        onChange(); showSizePopover = false
                    } label: {
                        HStack {
                            Image(systemName: filterState.selectedSize == b ? "largecircle.fill.circle" : "circle")
                            Text(b.label); Spacer()
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(DS.Spacing.sm).frame(minWidth: DS.Search.popoverMinWidth)
            .onExitCommand { showSizePopover = false }   // codex R4
        }
        .onChange(of: showSizePopover) { _, isOpen in if !isOpen { returnFocusToSearch() } }   // 根因：同 typeChip
    }

    // MARK: 时间（单选）
    private var timeChip: some View {
        chipButton(title: filterState.selectedTime.map { "时间: \($0.label)" } ?? "时间",
                   selected: filterState.selectedTime != nil) { showTimePopover = true }
        .popover(isPresented: $showTimePopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(SearchTimeBucket.allCases, id: \.self) { b in
                    Button {
                        filterState.selectedTime = (filterState.selectedTime == b) ? nil : b
                        onChange(); showTimePopover = false
                    } label: {
                        HStack {
                            Image(systemName: filterState.selectedTime == b ? "largecircle.fill.circle" : "circle")
                            Text(b.label); Spacer()
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(DS.Spacing.sm).frame(minWidth: DS.Search.popoverMinWidth)
            .onExitCommand { showTimePopover = false }   // codex R4
        }
        .onChange(of: showTimePopover) { _, isOpen in if !isOpen { returnFocusToSearch() } }   // 根因：同 typeChip
    }

    /// popover dismiss 后把焦点弹回搜索框。先 nil 再延迟设 .search，绕过「@FocusState 值不变不
    /// 重新聚焦」（关 popover 时 focusTarget 仍 == .search，直接重设无效）。mirror
    /// ContentView.openSearch 的 Task.yield 延迟单点设法。
    private func returnFocusToSearch() {
        focusTarget = nil
        Task { @MainActor in
            await Task.yield()
            focusTarget = .search
        }
    }

    // MARK: chip 按钮通用
    private func chipButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Text(title).font(.caption)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, DS.Search.chipHPadding).padding(.vertical, DS.Search.chipVPadding)
            .background(selected ? Color.accentColor.opacity(DS.Search.chipSelectedOpacity) : Color.secondary.opacity(DS.Search.chipUnselectedOpacity),
                        in: RoundedRectangle(cornerRadius: DS.Search.chipCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: DS.Search.chipCornerRadius)
                .strokeBorder(selected ? Color.accentColor.opacity(DS.Search.chipStrokeOpacity) : .clear, lineWidth: DS.Search.chipStrokeWidth))
        }
        .buttonStyle(.plain)
    }
}
