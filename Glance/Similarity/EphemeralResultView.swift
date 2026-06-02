//
//  EphemeralResultView.swift
//  Glance
//
//  M2 Slice J — 临时结果视图（找类似 / M3 搜索共用骨架）。layout = topBar（关闭+title+banner）
//  + LazyVGrid（复用 ImageGridView ThumbnailCell pattern）。不持久化（关闭即销毁状态）。
//
//  与 SmartFolderGridView 区别：
//  - 不依赖 SmartFolder（M3 搜索结果不是 SF）
//  - 不做时间分段（top-N 是排序结果，不是时间序列）
//  - 单击/双击行为复用 V1 mode（onSingleClick → preview / onDoubleClick → QV，调用方接）
//
//  D14 banner：caller 计算"已索引 X / Y 张"提示，nil 时不渲染 banner row。
//

import SwiftUI

struct EphemeralResultView: View {
    let title: String
    let urls: [URL]
    let bannerText: String?

    // M3 Slice M 加：
    /// caller 控制的空态文案。M2 .similar 传 "无结果"；M3 .search 按空 input / 0 结果 传不同文案。
    var emptyStateText: String = "无结果"
    /// 启用时间分段渲染（D19）。true 时必须传 datesForBuckets 且长度等于 urls。
    var showTimeBuckets: Bool = false
    /// 跟 urls 平行的 birth_time 数组（用于时间分段）。M2 .similar 传 nil；M3 .search 传非 nil。
    var datesForBuckets: [Date]? = nil

    let onClose: () -> Void
    let onSingleClick: (Int) -> Void
    let onDoubleClick: (Int) -> Void
    /// D15 终态：父持有的 @FocusState binding（参考 ContentView.AppFocus）。
    @FocusState.Binding var focusTarget: AppFocus?

    @EnvironmentObject var folderStore: FolderStore

    @State private var highlightedURL: URL?

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: folderStore.thumbnailSize), spacing: DS.Thumbnail.spacing)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.zero) {
            topBar
            if let bannerText {
                bannerRow(text: bannerText)
            }
            GeometryReader { geo in
                let colCount = computeColumnCount(width: geo.size.width)
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        if urls.isEmpty {
                            emptyState
                        } else if showTimeBuckets, let dates = datesForBuckets, dates.count == urls.count {
                            sectionedGridContent(colCount: colCount, scrollProxy: scrollProxy)
                        } else {
                            flatGridContent(colCount: colCount, scrollProxy: scrollProxy)
                        }
                    }
                    // D15 终态：focus 仲裁由父 view 单点持有，ephemeral 通过 .focused(equals: .ephemeral)
                    // 申请焦点；ESC 在本层处理（onClose）后父 view 的 onChange/swap 会写回 .grid。
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focusTarget, equals: .ephemeral)
                    .onAppear { focusTarget = .ephemeral }
                    .onKeyPress(.escape) { onClose(); return .handled }
                    // mirror V1 ImageGridView Bug 4 真解：preview/QV 内方向键已写 folderStore.selectedImageIndex
                    // → ephemeral 监听 non-nil 分支同步 highlightedURL → 退回 ephemeral 时 highlight 跟到 Z
                    // （对齐 Photos.app / Finder Quick Look：高亮跟随浏览位置）
                    .onChange(of: folderStore.selectedImageIndex) { _, newValue in
                        if let idx = newValue, urls.indices.contains(idx) {
                            highlightedURL = urls[idx]
                        }
                    }
                    .onKeyPress(.space) {
                        guard !urls.isEmpty else { return .ignored }
                        let target = highlightedURL.flatMap({ urls.firstIndex(of: $0) }) ?? 0
                        onDoubleClick(target)
                        return .handled
                    }
                    .onKeyPress(.leftArrow)  { moveHighlight(by: -1,        colCount: colCount, proxy: scrollProxy); return .handled }
                    .onKeyPress(.rightArrow) { moveHighlight(by: +1,        colCount: colCount, proxy: scrollProxy); return .handled }
                    .onKeyPress(.upArrow)    { moveHighlight(by: -colCount, colCount: colCount, proxy: scrollProxy); return .handled }
                    .onKeyPress(.downArrow)  { moveHighlight(by: +colCount, colCount: colCount, proxy: scrollProxy); return .handled }
                }
            }
        }
        .background(DS.Color.appBackground)
    }

    // MARK: - Keyboard helpers

    private func moveHighlight(by delta: Int, colCount: Int, proxy: ScrollViewProxy) {
        guard !urls.isEmpty else { return }
        let current = highlightedURL.flatMap({ urls.firstIndex(of: $0) })
            ?? (delta > 0 ? -1 : 0)
        let next = max(0, min(urls.count - 1, current + delta))
        highlightedURL = urls[next]
        withAnimation(DS.Anim.fast) {
            proxy.scrollTo(urls[next], anchor: .center)
        }
    }

    private func computeColumnCount(width: CGFloat) -> Int {
        // grid 真实宽度 = 容器宽度 - LazyVGrid 左 padding(.horizontal, DS.Spacing.md) - 右 padding(.horizontal, DS.Spacing.md)
        // SwiftUI .adaptive(minimum:) 列数算法：floor((W + spacing) / (cellWidth + spacing))
        let gridWidth = width - DS.Spacing.md - DS.Spacing.md
        let cellWidth = folderStore.thumbnailSize
        let spacing = DS.Thumbnail.spacing
        return max(1, Int((gridWidth + spacing) / (cellWidth + spacing)))
    }

    private var topBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: DS.Similarity.closeButtonSize, height: DS.Similarity.closeButtonSize)
                    .background(DS.Similarity.neutralOverlay.opacity(DS.Similarity.closeButtonBgOpacity), in: Circle())
            }
            .buttonStyle(.plain)
            .help("返回 (ESC)")

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text("\(urls.count) 张")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(.thinMaterial)
    }

    private func bannerRow(text: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Similarity.neutralOverlay.opacity(DS.Similarity.bannerBgOpacity))
    }

    // MARK: - Grid content helpers (M3 Slice M)

    @ViewBuilder
    private func flatGridContent(colCount: Int, scrollProxy: ScrollViewProxy) -> some View {
        LazyVGrid(columns: gridColumns, spacing: DS.Thumbnail.spacing) {
            ForEach(Array(urls.enumerated()), id: \.element) { idx, url in
                cell(url: url, idx: idx)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
    }

    @ViewBuilder
    private func sectionedGridContent(colCount: Int, scrollProxy: ScrollViewProxy) -> some View {
        let sections = computeBucketSections()

        LazyVGrid(
            columns: gridColumns,
            spacing: DS.Thumbnail.spacing,
            pinnedViews: [.sectionHeaders]
        ) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in
                        cell(url: item.url, idx: item.flatIndex)
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
    }

    /// 在 EphemeralResultView 内复用 D4 时间分段算法（不重新实现），但 group 单位是 (URL, Date) pair。
    private func computeBucketSections() -> [URLBucketSection] {
        guard let dates = datesForBuckets, dates.count == urls.count else { return [] }
        let now = Date()
        let boundaries = TimeBucket.boundaries(now: now)

        var byBucket: [TimeBucket: [URLBucketItem]] = [:]
        for (idx, url) in urls.enumerated() {
            let bucket = TimeBucket.bucket(for: dates[idx], boundaries: boundaries)
            byBucket[bucket, default: []].append(URLBucketItem(url: url, flatIndex: idx))
        }
        return TimeBucket.allCases.compactMap { bucket in
            guard let items = byBucket[bucket], !items.isEmpty else { return nil }
            return URLBucketSection(bucket: bucket, items: items)
        }
    }

    /// chip 形态 section header（mirror SmartFolderGridView 形态，含反色实底 fill）。
    @ViewBuilder
    private func sectionHeader(_ section: URLBucketSection) -> some View {
        HStack {
            Text("\(section.bucket.displayName) · \(section.items.count) 张")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.SectionHeader.chipText)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.SectionHeader.chipFill, in: Capsule())
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
    }

    /// 单 cell 渲染（被 flat / sectioned 两路复用，避免代码重复）。
    @ViewBuilder
    private func cell(url: URL, idx: Int) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            ThumbnailCell(
                url: url,
                isHighlighted: highlightedURL == url,
                size: folderStore.thumbnailSize
            )
            Text(url.lastPathComponent)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: folderStore.thumbnailSize)
        }
        .id(url)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            highlightedURL = url
            onDoubleClick(idx)
        }
        .onTapGesture(count: 1) {
            highlightedURL = url
            onSingleClick(idx)
        }
    }

    // MARK: - URLBucketSection helpers

    private struct URLBucketItem: Identifiable, Equatable {
        let url: URL
        let flatIndex: Int   // 在 EphemeralResultView.urls 数组中的原始 index
        var id: URL { url }
    }

    private struct URLBucketSection: Identifiable, Equatable {
        let bucket: TimeBucket
        let items: [URLBucketItem]
        var id: Int { bucket.rawValue }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: DS.Similarity.emptyStateIconSize))
                .foregroundStyle(.tertiary)
            Text(emptyStateText)   // M3: caller 控制文案
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, DS.Similarity.emptyStateTopPadding)
    }
}
