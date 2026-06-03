//
//  SmartFolderGridView.swift
//  Glance
//
//  跨文件夹 grid。显示 SmartFolderStore.queryResult 的图，复用 V1 顶层
//  loadThumbnail(url:maxPixelSize:) 函数（位于 ImageGridView.swift）。
//
//  Slice A 行为对齐 V1 ImageGridView：单击进 preview / 双击进 QuickViewer /
//  方向键 grid 内导航 / Space 进 QV / F 切全屏 / focus 同步管理 / hover tooltip 显示
//  relative path（D5）。
//
//  Slice B-α：时间分段 sticky header（D4 5 段：今天/昨天/本周/本月/更早），
//  LazyVGrid pinnedViews [.sectionHeaders] 实现；空段跳过。
//  Header 视觉形态：chip — Capsule + .regularMaterial 包左对齐文字，row 其余透明
//  （cell 透过显示），破除"全宽横条"视觉感（前两次 #141419 不透明 / .regularMaterial
//  全 row 半透明都失败的根因 = SwiftUI Section header 全宽属性，仅改 background 改不掉）。
//  键盘导航：←→ 走 flat queryResult ±1（跨段自然连续）；
//          ↑↓ 走 (sectionIdx, rowInSection, col) 模型，跨段跳邻段对应 col
//          （col 超过目标行末则 clamp 到末 cell）。
//  sections 在 body 顶部一次算，render + nav 共用同一快照（避免跨午夜
//  render/nav 双源不一致 — codex review Q5.1）。
//

import SwiftUI

struct SmartFolderGridView: View {

    @EnvironmentObject var smartFolderStore: SmartFolderStore
    @EnvironmentObject var folderStore: FolderStore
    @EnvironmentObject var appState: AppState

    /// 单击 cell 回调（参数：被点 cell 在 queryResult 中的当前位置 index）。
    /// 实时 firstIndex 查找避免 LazyVGrid 复用 cell 时闭包捕获 index 过期（参考 V1 c112059 修法）。
    let onSingleClick: (Int) -> Void
    /// 双击 cell 回调（同 onSingleClick 的 index 语义）。
    let onDoubleClick: (Int) -> Void
    /// D15 终态：父持有的 @FocusState binding，本 view 通过
    /// `.focused($focusTarget, equals: .grid)` 申请焦点（与 V1 ImageGridView 共用 .grid case）。
    @FocusState.Binding var focusTarget: AppFocus?

    /// V2 grid 内 cell 高亮状态（mirror V1 ImageGridView.highlightedURL）。
    /// 同步规则：cell 单击 / 双击设当前 cell；preview 方向键 navigate 写
    /// folderStore.selectedImageIndex → 这里 onChange 同步到 queryResult[idx].id；
    /// queryResult 整体变化（重新 query）→ reset nil。
    @State private var highlightedID: Int64?

    var body: some View {
        GeometryReader { geo in
            // colCount 用 grid 实际可用宽度算（geo.size.width 反映 mainContent 区，
            // 不含 sidebar / inspector），上下方向键步长才与 LazyVGrid 实际列数一致
            let colCount = computeColumnCount(width: geo.size.width)
            // sections 一次算，render + ↑↓ nav 共用同一快照（codex Q5.1）
            let sections = groupedByTimeBucket(smartFolderStore.queryResult, now: Date())

            ScrollViewReader { scrollProxy in
                ScrollView {
                    if smartFolderStore.queryResult.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(
                            columns: gridColumns,
                            spacing: DS.Thumbnail.spacing,
                            pinnedViews: [.sectionHeaders]
                        ) {
                            ForEach(sections) { section in
                                Section {
                                    ForEach(section.images) { image in
                                        VStack(spacing: DS.Spacing.xs) {
                                            SmartFolderImageCell(
                                                image: image,
                                                isHighlighted: highlightedID == image.id,
                                                size: folderStore.thumbnailSize
                                            )
                                            Text(image.filename)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .frame(maxWidth: folderStore.thumbnailSize)
                                        }
                                            .id(image.id)
                                            .contentShape(Rectangle())
                                            // 双击优先注册（macOS SwiftUI 双 onTapGesture pattern；count:1 在 count:2 之后注册可让
                                            // tap recognizer 优先识别双击不触发单击）。参考 V1 ImageGridView 同模式。
                                            .onTapGesture(count: 2) {
                                                if let idx = smartFolderStore.queryResult.firstIndex(where: { $0.id == image.id }) {
                                                    highlightedID = image.id
                                                    onDoubleClick(idx)
                                                }
                                            }
                                            .onTapGesture(count: 1) {
                                                if let idx = smartFolderStore.queryResult.firstIndex(where: { $0.id == image.id }) {
                                                    highlightedID = image.id
                                                    onSingleClick(idx)
                                                }
                                            }
                                    }
                                } header: {
                                    sectionHeader(section)
                                }
                            }
                        }
                        .animation(DS.Anim.fast, value: folderStore.thumbnailSize)
                        .padding(DS.Spacing.sm)
                    }
                }
                .background(DS.Color.gridBackground)
                .focusable()
                .focusEffectDisabled()
                .focused($focusTarget, equals: .grid)
                .onAppear { focusTarget = .grid }
                .navigationTitle({
                    // mirror V1 ImageGridView 行为：preview 模式（selectedImageIndex 非 nil）显示 filename，
                    // grid 模式显示 SmartFolder displayName
                    if let idx = folderStore.selectedImageIndex,
                       smartFolderStore.queryResult.indices.contains(idx) {
                        return smartFolderStore.queryResult[idx].filename
                    }
                    return smartFolderStore.selected?.displayName ?? ""
                }())
                // preview 方向键 navigate 时 selectedImageIndex 变 → 同步 highlight 跟到当前预览图。
                // focus 仲裁由父 view 单点持有，本 view 不再需要 newValue == nil 时主动 refocus。
                .onChange(of: folderStore.selectedImageIndex) { _, newValue in
                    if let idx = newValue, smartFolderStore.queryResult.indices.contains(idx) {
                        highlightedID = smartFolderStore.queryResult[idx].id
                    }
                }
                // queryResult 整体重新 query → 老 highlight 已无意义，reset
                .onChange(of: smartFolderStore.queryResult) { _, _ in
                    highlightedID = nil
                }
                // Space：进入全窗口查看器（用当前 highlight 或第一张）
                .onKeyPress(.space) {
                    guard !smartFolderStore.queryResult.isEmpty else { return .ignored }
                    let target = smartFolderStore.queryResult.firstIndex(where: { $0.id == highlightedID }) ?? 0
                    onDoubleClick(target)
                    return .handled
                }
                // F：切换全屏（跟 QuickViewer / preview 一致，spec AppState.md 全局 F 键设计）
                .onKeyPress(.init("f"), phases: .down) { _ in
                    appState.toggleFullScreen()
                    return .handled
                }
                // 方向键导航：←→ flat ±1，↑↓ (sectionIdx, row, col) 模型
                .onKeyPress(.leftArrow)  { moveHighlight(.left,  sections: sections, colCount: colCount, proxy: scrollProxy); return .handled }
                .onKeyPress(.rightArrow) { moveHighlight(.right, sections: sections, colCount: colCount, proxy: scrollProxy); return .handled }
                .onKeyPress(.upArrow)    { moveHighlight(.up,    sections: sections, colCount: colCount, proxy: scrollProxy); return .handled }
                .onKeyPress(.downArrow)  { moveHighlight(.down,  sections: sections, colCount: colCount, proxy: scrollProxy); return .handled }
            }
        }
    }

    /// 时间分段 sticky header — chip 形态。row 自身完全透明（无 background），
    /// pinned 时只看到左上角一个 Capsule chip 浮着，row 其余区域 cell 透过显示。
    /// 破"全宽横条"视觉感（前两次修法 #141419 不透明 / .regularMaterial 半透明 row 都失败的根因）。
    /// chip fill 用反色实底（DS.SectionHeader.chipFill/chipText）：dark 浅底 / light 深底，
    /// 跟背景永远拉开整级明度差，解决半透明 material 在同明度背景上撞色糊边的问题。
    @ViewBuilder
    private func sectionHeader(_ section: TimeBucketSection) -> some View {
        HStack {
            Text("\(section.bucket.displayName) · \(section.images.count) 张")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.SectionHeader.chipText)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.SectionHeader.chipFill, in: Capsule())
            Spacer()
        }
        .padding(.vertical, DS.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            if smartFolderStore.isQuerying {
                ProgressView()
                Text("正在加载...")
                    .foregroundStyle(.secondary)
            } else {
                Text("暂无图片")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("受管文件夹里没找到图片，或还在首次扫描")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Spacing.xl)
    }

    // MARK: - Helpers

    private enum MoveDirection { case left, right, up, down }

    /// 键盘方向导航。←→ 走 flat queryResult ±1（A 方案，跨段自然连续，行为继承 V1）；
    /// ↑↓ 走 (sectionIdx, rowInSection, col) 模型，跨段时跳邻段对应 col，col 超过目标行
    /// 末则 clamp 到末 cell（codex Q1）。nil/stale highlightedID：down→第一段第一项 /
    /// up→末段末项 / right→第一项 / left→第一项（mirror V1 nil 行为）。
    private func moveHighlight(
        _ direction: MoveDirection,
        sections: [TimeBucketSection],
        colCount: Int,
        proxy: ScrollViewProxy
    ) {
        let total = smartFolderStore.queryResult.count
        guard total > 0, !sections.isEmpty, colCount > 0 else { return }

        let nextID: Int64?

        switch direction {
        case .left, .right:
            // ←→ flat queryResult ±1，跨段自然连续
            let delta = direction == .left ? -1 : +1
            let current = smartFolderStore.queryResult.firstIndex(where: { $0.id == highlightedID })
                ?? (delta > 0 ? -1 : 0)
            let next = max(0, min(total - 1, current + delta))
            nextID = smartFolderStore.queryResult[next].id

        case .up, .down:
            guard let location = locate(highlightedID, in: sections) else {
                // nil/stale highlightedID：down→第一段第一项 / up→末段末项
                if direction == .down {
                    nextID = sections.first?.images.first?.id
                } else {
                    nextID = sections.last?.images.last?.id
                }
                break
            }
            let (sectionIdx, indexInSection) = location
            let curSection = sections[sectionIdx]
            let row = indexInSection / colCount
            let col = indexInSection % colCount
            let curRowCount = (curSection.images.count + colCount - 1) / colCount  // ceil

            if direction == .up {
                if row > 0 {
                    // 段内上移（同段同 col 上一行；段内每行均满，无需 clamp）
                    nextID = curSection.images[(row - 1) * colCount + col].id
                } else if sectionIdx > 0 {
                    // 跨上一段最后一行 + 同 col（clamp 到该行末 cell）
                    let prev = sections[sectionIdx - 1]
                    let prevRowCount = (prev.images.count + colCount - 1) / colCount
                    let lastRowStart = (prevRowCount - 1) * colCount
                    let lastRowMaxCol = prev.images.count - 1 - lastRowStart
                    let targetCol = min(col, lastRowMaxCol)
                    nextID = prev.images[lastRowStart + targetCol].id
                } else {
                    // 第一段第一行：原地
                    return
                }
            } else { // .down
                if row < curRowCount - 1 {
                    // 段内下移（最后一行可能不满，clamp 到该行末 cell）
                    let targetRowStart = (row + 1) * colCount
                    let targetRowMaxCol = curSection.images.count - 1 - targetRowStart
                    let targetCol = min(col, targetRowMaxCol)
                    nextID = curSection.images[targetRowStart + targetCol].id
                } else if sectionIdx < sections.count - 1 {
                    // 跨下一段第一行 + 同 col（clamp，下一段可能不足一行）
                    let nextSection = sections[sectionIdx + 1]
                    let targetCol = min(col, nextSection.images.count - 1)
                    nextID = nextSection.images[targetCol].id
                } else {
                    // 末段末行：原地
                    return
                }
            }
        }

        guard let id = nextID else { return }
        highlightedID = id
        withAnimation(DS.Anim.fast) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    /// 在 sections 数组里定位某 image id 的 (sectionIdx, indexInSection)。
    private func locate(_ id: Int64?, in sections: [TimeBucketSection]) -> (Int, Int)? {
        guard let id else { return nil }
        for (sIdx, section) in sections.enumerated() {
            if let imgIdx = section.images.firstIndex(where: { $0.id == id }) {
                return (sIdx, imgIdx)
            }
        }
        return nil
    }

    /// V2 grid 列定义：mirror V1 ImageGridView.gridColumns，min = thumbSize / max = thumbSize+20，
    /// 共享 folderStore.thumbnailSize 作 source of truth（V1 toolbar slider 调动时 V2 也跟着变）。
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(
            minimum: folderStore.thumbnailSize,
            maximum: folderStore.thumbnailSize + 20
        ), spacing: DS.Thumbnail.spacing)]
    }

    /// V2 grid LazyVGrid 列数估算：mirror V1 SwiftUI .adaptive(minimum:) 算法，
    /// floor((W + spacing) / (cellMin + spacing))。padding(DS.Spacing.sm) 两侧。
    private func computeColumnCount(width: CGFloat) -> Int {
        let gridWidth = width - 2 * DS.Spacing.sm
        let cellWidth = folderStore.thumbnailSize
        return max(1, Int((gridWidth + DS.Thumbnail.spacing) / (cellWidth + DS.Thumbnail.spacing)))
    }
}

/// mirror V1 ImageGridView.ThumbnailCell：方形 cell + scaledToFill + clipped + hover scale +
/// HiDPI 像素尺寸。共享 folderStore.thumbnailSize 让 V1 toolbar slider 同步控制 V2 cell 大小。
private struct SmartFolderImageCell: View {
    let image: IndexedImage
    var isHighlighted: Bool = false
    var size: CGFloat = DS.Thumbnail.defaultSize
    @State private var thumbnail: NSImage?
    @State private var isHovered = false
    /// 方案 3 — 缩略图加载失败（文件已删 / 解码失败 / 无权限）→ 显占位而非无限转圈。
    @State private var loadFailed = false
    /// 完整文件路径（hover tooltip 用）。loadThumb resolve root bookmark 拼出 child URL 时一并填，
    /// 复用那次 resolve 不额外开销。未填前 .help 回退 relativePath。智能文件夹跨多根聚合，
    /// 只显 relativePath（根目录层会退化成纯文件名）看不出图来自哪，故显完整路径。
    @State private var fullPath: String?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay { loadFailed ? AnyView(ImageLoadFailedView(compact: true)) : AnyView(ProgressView()) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: DS.Thumbnail.cornerRadius))
        .overlay {
            if isHovered && !isHighlighted {
                RoundedRectangle(cornerRadius: DS.Thumbnail.cornerRadius)
                    .fill(DS.Color.hoverOverlay)
            }
        }
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: DS.Thumbnail.cornerRadius)
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Thumbnail.cornerRadius)
                            .stroke(Color.accentColor, lineWidth: 2)
                    )
            }
        }
        .scaleEffect(isHovered && !isHighlighted ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(DS.Anim.fast, value: isHighlighted)
        .animation(DS.Anim.fast, value: size)
        .onHover { isHovered = $0 }
        .help(fullPath ?? image.relativePath)
        .task(id: image.id) {
            thumbnail = nil
            await loadThumb(targetSize: size)
        }
    }

    /// 解析 root bookmark → startAccessing → 拼 root + relative_path 得到 child URL → 读缩略图。
    /// (image.urlBookmark 实际是 root bookmark，不是 image 自己的 bookmark；macOS sandbox
    /// 不允许给 enumerator 出来的子文件创建 .withSecurityScope bookmark，所以子访问只能
    /// 通过 root active scope 隐式走。Slice I 重构候选：rename field / 改为 folder_id lookup。)
    private func loadThumb(targetSize: CGFloat) async {
        loadFailed = false
        var stale = false
        guard let rootURL = try? URL(
            resolvingBookmarkData: image.urlBookmark,
            options: [.withSecurityScope],
            bookmarkDataIsStale: &stale
        ) else { loadFailed = true; return }
        let didStart = rootURL.startAccessingSecurityScopedResource()
        defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }

        // root + relative_path → child file URL，通过 root active scope 隐式访问
        let fileURL = rootURL.appendingPathComponent(image.relativePath)
        await MainActor.run { self.fullPath = fileURL.path }
        // HiDPI 锐化：mirror V1 ThumbnailCell 的 maxPixelSize = size × backingScaleFactor
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let thumb = await loadThumbnail(url: fileURL, maxPixelSize: Int(targetSize * scale))
        guard !Task.isCancelled else { return }
        await MainActor.run {
            self.thumbnail = thumb
            self.loadFailed = (thumb == nil)
        }
    }
}
