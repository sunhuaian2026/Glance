//
//  ImageGridView.swift
//  ISeeImageViewer
//

import SwiftUI
import ImageIO

struct ImageGridView: View {
    @EnvironmentObject var folderStore: FolderStore
    @EnvironmentObject var appState: AppState
    /// D15 终态：父持有的 @FocusState binding。本 view 通过
    /// `.focused($focusTarget, equals: .grid)` 申请焦点；onAppear / dismiss 路径由父 view 写值。
    @FocusState.Binding var focusTarget: AppFocus?
    var onDoubleClick: (Int) -> Void = { _ in }

    @State private var highlightedURL: URL? = nil

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(
            minimum: folderStore.thumbnailSize,
            maximum: folderStore.thumbnailSize + 20
        ), spacing: DS.Thumbnail.spacing)]
    }

    var body: some View {
        Group {
            if folderStore.selectedFolder == nil {
                // empty state 用 Color.clear 让 NavigationSplitView 默认内容区背景
                // （NSColor.controlBackgroundColor / windowBackgroundColor）透出
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        ContentUnavailableView(
                            "选择文件夹",
                            systemImage: DS.Icon.folder,
                            description: Text("从左侧添加并选择一个文件夹来浏览图片")
                        )
                    }
                    .contextMenu {
                        Button("添加文件夹…") { folderStore.addFolder() }
                    }
            } else if folderStore.isLoadingImages {
                ProgressView("加载中…")
            } else if folderStore.images.isEmpty {
                ContentUnavailableView(
                    "无图片",
                    systemImage: "photo",
                    description: Text("此文件夹中没有支持的图片格式")
                )
            } else {
                gridContent
            }
        }
        .navigationTitle({
            if let idx = folderStore.selectedImageIndex,
               folderStore.images.indices.contains(idx) {
                return folderStore.images[idx].lastPathComponent
            }
            return folderStore.selectedFolder?.lastPathComponent ?? ""
        }())
        .onChange(of: folderStore.images) { _, _ in
            highlightedURL = nil
        }
        .toolbar {
            if folderStore.selectedImageIndex == nil {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.3x3")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Slider(
                            value: $folderStore.thumbnailSize,
                            in: DS.Thumbnail.minSize...DS.Thumbnail.maxSize,
                            step: 10
                        )
                        .labelsHidden()
                        .frame(width: 140)
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .help("调整缩略图大小")
                }
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 4) {
                        Picker("", selection: Binding<SortKey>(
                            get: { folderStore.sortKey },
                            set: { key in folderStore.applySortKey(key, direction: .asc) }
                        )) {
                            ForEach(SortKey.allCases, id: \.self) { key in
                                Text(key.rawValue).tag(key)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .help("排序方式")
                        Button {
                            folderStore.applySortKey(folderStore.sortKey, direction: folderStore.sortDirection.toggled)
                        } label: {
                            Image(systemName: folderStore.sortDirection == .asc ? "arrow.up" : "arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .help(folderStore.sortDirection == .asc ? "升序（点击切换降序）" : "降序（点击切换升序）")
                    }
                }
            }
        }
    }

    // MARK: - Grid

    private var gridContent: some View {
        let images = folderStore.images

        return GeometryReader { geo in
            // colCount 用 grid 实际可用宽度算（geo.size.width 反映 mainContent 区，
            // 不含 sidebar / inspector），上下方向键步长才与 LazyVGrid 实际列数一致
            let colCount = computeColumnCount(width: geo.size.width)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: DS.Thumbnail.spacing) {
                        ForEach(images, id: \.self) { url in
                            VStack(spacing: DS.Spacing.xs) {
                                ThumbnailCell(url: url, isHighlighted: highlightedURL == url, size: folderStore.thumbnailSize)
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
                                guard let idx = folderStore.images.firstIndex(of: url) else { return }
                                highlightedURL = url
                                onDoubleClick(idx)
                            }
                            .onTapGesture(count: 1) {
                                highlightedURL = url
                                folderStore.selectedImageIndex = folderStore.images.firstIndex(of: url)
                            }
                        }
                    }
                    .animation(DS.Anim.fast, value: folderStore.thumbnailSize)
                    .padding(DS.Spacing.sm)
                }
                // 删除 .background(DS.Color.gridBackground)：让 NavigationSplitView 默认
                // 内容区背景（NSColor.controlBackgroundColor / windowBackgroundColor）接管，
                // dark 跟 Finder 一致（~#1E1E1E 中性灰，不再偏冷蓝紫）。light 模式视觉无变化
                .focusable()
                .focusEffectDisabled()
                .focused($focusTarget, equals: .grid)
                .onAppear { focusTarget = .grid }
                // preview 方向键 navigate 已写回 selectedImageIndex（ImagePreviewView.swift navigate(by:)），
                // grid 这边监听 non-nil 分支同步 highlightedURL → ESC 退回 grid 时 highlight 跟到 preview
                // 浏览到的图，对齐 Finder Cover Flow / Photos.app 行为（Bug 4 真解）。
                // focus 仲裁由父 view 单点持有，本 view 不再需要 selectedImageIndex == nil 时主动 refocus。
                .onChange(of: folderStore.selectedImageIndex) { _, newValue in
                    if let idx = newValue, folderStore.images.indices.contains(idx) {
                        highlightedURL = folderStore.images[idx]
                    }
                }
                // Space：进入全窗口查看器
                .onKeyPress(.space) {
                    guard !images.isEmpty else { return .ignored }
                    let target = highlightedURL.flatMap({ folderStore.images.firstIndex(of: $0) }) ?? 0
                    onDoubleClick(target)
                    return .handled
                }
                // F：切换全屏（跟 QuickViewer / preview 一致，spec AppState.md 全局 F 键设计）
                .onKeyPress(.init("f"), phases: .down) { _ in
                    appState.toggleFullScreen()
                    return .handled
                }
                // 方向键导航
                .onKeyPress(.leftArrow)  { moveHighlight(by: -1,        colCount: colCount, total: images.count, proxy: scrollProxy); return .handled }
                .onKeyPress(.rightArrow) { moveHighlight(by: +1,        colCount: colCount, total: images.count, proxy: scrollProxy); return .handled }
                .onKeyPress(.upArrow)    { moveHighlight(by: -colCount, colCount: colCount, total: images.count, proxy: scrollProxy); return .handled }
                .onKeyPress(.downArrow)  { moveHighlight(by: +colCount, colCount: colCount, total: images.count, proxy: scrollProxy); return .handled }
            }
        }
    }

    // MARK: - Helpers

    private func moveHighlight(by delta: Int, colCount: Int, total: Int, proxy: ScrollViewProxy) {
        guard total > 0 else { return }
        let current = highlightedURL.flatMap({ folderStore.images.firstIndex(of: $0) })
            ?? (delta > 0 ? -1 : 0)
        let next = max(0, min(total - 1, current + delta))
        highlightedURL = folderStore.images[next]
        withAnimation(DS.Anim.fast) {
            proxy.scrollTo(folderStore.images[next], anchor: .center)
        }
    }

    private func computeColumnCount(width: CGFloat) -> Int {
        // grid 真实宽度 = 容器宽度 - LazyVGrid 上的左右 padding(DS.Spacing.sm)
        // SwiftUI .adaptive(minimum:) 列数算法：floor((W + spacing) / (cellWidth + spacing))
        let gridWidth = width - 2 * DS.Spacing.sm
        let cellWidth = folderStore.thumbnailSize
        let spacing = DS.Thumbnail.spacing
        return max(1, Int((gridWidth + spacing) / (cellWidth + spacing)))
    }

}

// MARK: - ThumbnailCell

struct ThumbnailCell: View {
    let url: URL
    var isHighlighted: Bool = false
    var size: CGFloat = DS.Thumbnail.defaultSize
    @State private var thumbnail: NSImage? = nil
    @State private var isHovered = false

    var body: some View {
        ZStack {
            if let image = thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay { ProgressView() }
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
        .task(id: url) {
            thumbnail = nil
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let result = await loadThumbnail(url: url, maxPixelSize: Int(size * scale))
            guard !Task.isCancelled else { return }
            thumbnail = result
        }
    }
}

// MARK: - Thumbnail Loading（internal，供 FilmstripCell 复用）

/// 加载完整 NSImage（preview / QuickViewer 大图用）。SVG 走 NSImage(contentsOf:)
/// 让 macOS CoreSVG rasterize；raster 格式走 CGImageSource → CGImage → NSImage。
/// 必须在 detached task 内调用（IO + 解码）。
/// nonisolated：项目 default main-actor isolation 下，全局函数默认 @MainActor，会令本应离主线程的
/// 解码在 Task.detached 里 hop 回主线程跑（UI 卡）。标 nonisolated 恢复真·后台解码 + 消隔离 warning。
nonisolated func loadFullNSImage(url: URL) -> NSImage? {
    if url.pathExtension.lowercased() == "svg" {
        return NSImage(contentsOf: url)
    }
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

nonisolated func loadThumbnail(url: URL, maxPixelSize: Int) async -> NSImage? {
    await Task.detached(priority: .userInitiated) {
        // SVG: vector 无内嵌 raster thumbnail，CGImageSourceCreateThumbnailAtIndex 常 return
        // nil → spinner 永卡。走 NSImage 让 macOS CoreSVG rasterize；通过 size 控制目标尺寸，
        // SwiftUI 渲染时按 vector 数据重新栅格化无糊。
        if url.pathExtension.lowercased() == "svg" {
            guard let img = NSImage(contentsOf: url),
                  img.size.width > 0, img.size.height > 0 else { return nil }
            let scale = min(CGFloat(maxPixelSize) / img.size.width,
                            CGFloat(maxPixelSize) / img.size.height,
                            1.0)
            img.size = NSSize(width: img.size.width * scale, height: img.size.height * scale)
            return img
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }.value
}
