//
//  DuplicateOverviewView.swift
//  Glance
//
//  M4 任务 1 — 重复清理总览只读 view。
//  顶部统计条「X 组重复 · 可省 Y」+ 组列表（每组保留张 badge + 副本展示 + reclaimableBytes）
//  + 空态 + 错误态。跟随全局外观（非快速看图器场景不强制深色）。
//  注：不渲染索引 chip —— ContentView.mainContent 已全局 overlay IndexingProgressView。
//

import SwiftUI

struct DuplicateOverviewView: View {
    @EnvironmentObject var model: DuplicateOverviewModel

    var body: some View {
        mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
    }
    // 注：本 view 不持 .onAppear 触发 load —— load 单一 owner = ContentView
    // .onChange(of: showDuplicateOverview)（双触发会让先返回的旧结果反向覆盖后返回的新结果，
    // stale-write guard 无 generation token 防不住）。

    @ViewBuilder
    private var mainContent: some View {
        if let err = model.errorMessage {
            errorState(message: err)
        } else if model.groupCount == 0 && !model.isLoading {
            emptyState
        } else {
            groupsList
        }
    }

    private var groupsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Dedup.groupRowSpacing) {
                statsBar
                ForEach(model.groups) { group in
                    DuplicateGroupRowView(group: group)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
        }
    }

    private var statsBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text("\(model.groupCount) 组重复")
                .font(DS.Dedup.statsBarFont)
            Text("·")
                .foregroundStyle(.secondary)
            Text("可省 \(formattedReclaimable)")
                .font(DS.Dedup.statsBarFont)
                .foregroundStyle(SwiftUI.Color.accentColor)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("没找到重复图")
                .font(DS.Dedup.emptyStateFont)
                .foregroundStyle(.secondary)
            Text("Glance 会在后台持续监控,发现重复立即显示。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("加载失败")
                .font(DS.Dedup.emptyStateFont)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DS.Spacing.lg)
    }

    private var formattedReclaimable: String {
        ByteCountFormatter.string(
            fromByteCount: model.totalReclaimableBytes,
            countStyle: .file
        )
    }
}

/// 单一组渲染：保留张缩略图（badge「保留」）+ 副本缩略图 + 路径信息 + 组可省空间。
private struct DuplicateGroupRowView: View {
    let group: DuplicateGroup

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                DuplicateMemberCell(member: group.canonical, isCanonical: true)
                ForEach(group.duplicates) { dup in
                    DuplicateMemberCell(member: dup, isCanonical: false)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "scalemass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("组可省 \(formattedReclaimable)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.md)
        .background(SwiftUI.Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var formattedReclaimable: String {
        ByteCountFormatter.string(
            fromByteCount: group.reclaimableBytes,
            countStyle: .file
        )
    }
}

/// 单张图缩略图渲染。保留张加「保留」badge + 不弱化；副本 opacity 0.7 视觉弱化(无 badge)。
/// hover 显完整路径 tooltip(mirror SmartFolderGridView 做法)。
private struct DuplicateMemberCell: View {
    let member: DuplicateGroupMember
    let isCanonical: Bool

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            ZStack(alignment: .topTrailing) {
                thumbnailContent
                    .frame(
                        width: DS.Dedup.groupCellThumbnailSize,
                        height: DS.Dedup.groupCellThumbnailSize
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .opacity(isCanonical ? 1.0 : DS.Dedup.duplicateThumbnailOpacity)
                if isCanonical {
                    Text("保留")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.Dedup.canonicalBadgeColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(4)
                }
            }
            Text(member.relativePath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: DS.Dedup.groupCellThumbnailSize, alignment: .leading)
        }
        .help(member.fullPath)
        .task(id: member.id) {
            await loadThumb()
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let img = thumbnail {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(SwiftUI.Color.secondary.opacity(0.15))
        }
    }

    /// resolve root bookmark + 拼 child URL + loadThumbnail(顶层 nonisolated 函数)。
    /// mirror DedupPass.computeSha 的 scope 模式。
    private func loadThumb() async {
        let urlBookmark = member.urlBookmark
        let relativePath = member.relativePath
        let maxPixel = DS.Dedup.groupCellThumbnailMaxPixel
        let img: NSImage? = await Task.detached(priority: .utility) {
            var stale = false
            guard let rootURL = try? URL(
                resolvingBookmarkData: urlBookmark,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &stale
            ) else { return nil }
            let didStart = rootURL.startAccessingSecurityScopedResource()
            defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }
            let fileURL = rootURL.appendingPathComponent(relativePath)
            return await loadThumbnail(url: fileURL, maxPixelSize: maxPixel)
        }.value
        await MainActor.run {
            self.thumbnail = img
        }
    }
}
