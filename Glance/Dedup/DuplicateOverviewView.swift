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
    @EnvironmentObject var migrationCoordinator: BookmarkMigrationCoordinator

    var body: some View {
        // ZStack + background 独立层 ignoresSafeArea: 让 detail 区背景延伸到
        // toolbar 之下融合窗口 titlebar 圆角(消除"重复清理"标题左上角方形).
        // 颜色换 DS.Color.gridBackground 跟 SmartFolderGridView 统一项目风格.
        ZStack {
            DS.Color.gridBackground
                .ignoresSafeArea()
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("重复清理")
    }
    // 注：本 view 不持 .onAppear 触发 load —— load 单一 owner = ContentView
    // .onChange(of: showDuplicateOverview)（双触发会让先返回的旧结果反向覆盖后返回的新结果，
    // stale-write guard 无 generation token 防不住）。

    @ViewBuilder
    private var mainContent: some View {
        if let err = model.errorMessage {
            errorState(message: err)
        } else if case .rescanning = migrationCoordinator.phase {
            // M4 任务 2 收尾 — D4-bm-ui 重扫中专用空态 (区别于 emptyState)
            rescanningState
        } else if model.groupCount == 0 && !model.isLoading {
            emptyState
        } else {
            groupsList
        }
    }

    private var groupsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Dedup.groupRowSpacing) {
                statsBar
                ForEach(model.groups) { group in
                    DuplicateGroupRowView(
                        group: group,
                        isSelected: model.selectedSha256s.contains(group.id),
                        onToggleSelection: { model.toggleSelection(sha256: group.id) }
                    )
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
            Spacer(minLength: DS.Spacing.zero)
            trashAction
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    @ViewBuilder
    private var trashAction: some View {
        switch model.trashState {
        case .idle, .completed:
            Button {
                Task { await model.trashSelected() }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: DS.Icon.trash)
                    Text("移入废纸篓 (\(model.selectedDuplicateCount) 张)")
                }
                .frame(height: DS.Dedup.trashButtonHeight)
                .padding(.horizontal, DS.Spacing.md)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.selectedSha256s.isEmpty)
        case .trashing(let done, let total):
            HStack(spacing: DS.Spacing.sm) {
                ProgressView(value: Double(done), total: Double(total))
                    .progressViewStyle(.linear)
                    .tint(DS.Dedup.progressBarTint)
                    .frame(width: 120)
                Text("\(done)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("取消") { Task { await model.cancelTrash() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: DS.Dedup.stateIconSize))
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

    /// M4 任务 2 收尾 — D4-bm-ui 重扫中专用空态
    /// 区别于 emptyState 「没找到重复图」, 这是「等扫描结果」的中间态.
    private var rescanningState: some View {
        VStack(spacing: DS.Spacing.md) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.regular)
            Text("重新扫描中…")
                .font(DS.BookmarkMigration.rescanEmptyStateFont)
                .foregroundStyle(.secondary)
            Text("重选根目录后正在重建图像索引,扫完会自动显示重复组。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: DS.Dedup.stateIconSize))
                .foregroundStyle(DS.Dedup.errorIconColor)
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

/// 单一组渲染：组级 checkbox（D28 整组勾选） + 保留张缩略图（badge「保留」）+ 副本缩略图 + 路径信息 + 组可省空间。
private struct DuplicateGroupRowView: View {
    let group: DuplicateGroup
    let isSelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // M4 任务 2 — 组级 checkbox（D28 整组勾选，不给单文件 checkbox）
            // 自绘 checkbox + Button 包整行: native Toggle(.checkbox) 在
            // LazyVStack item 复用场景下 hit area 漂移(个别 cell 死透), 改 Button
            // 自己控 hit area 稳定 (a2.png 实测撞到 + 上轮 contentShape 仅修了 label
            // 撑满但 Toggle 内部 Button hit 仍是 SwiftUI 黑盒).
            Button {
                onToggleSelection()
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isSelected ? SwiftUI.Color.accentColor : SwiftUI.Color.secondary)
                    Text("选择此组清掉 \(group.duplicates.count) 张副本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: DS.Spacing.zero)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: DS.Dedup.checkboxRowHeight)

            HStack(alignment: .top, spacing: DS.Spacing.md) {
                DuplicateMemberCell(member: group.canonical, isCanonical: true)
                ForEach(group.duplicates) { dup in
                    DuplicateMemberCell(member: dup, isCanonical: false)
                }
                Spacer(minLength: DS.Spacing.zero)
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
        .background(SwiftUI.Color.secondary.opacity(DS.Dedup.groupCardBackgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.groupCardCornerRadius, style: .continuous))
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
                    .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.thumbnailCornerRadius, style: .continuous))
                    .opacity(isCanonical ? 1.0 : DS.Dedup.duplicateThumbnailOpacity)
                if isCanonical {
                    Text("保留")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, DS.Dedup.canonicalBadgePaddingH)
                        .padding(.vertical, DS.Dedup.canonicalBadgePaddingV)
                        .background(DS.Dedup.canonicalBadgeColor)
                        .foregroundStyle(DS.Dedup.canonicalBadgeForeground)
                        .clipShape(Capsule())
                        .padding(DS.Dedup.canonicalBadgeOffset)
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
            RoundedRectangle(cornerRadius: DS.Dedup.thumbnailCornerRadius)
                .fill(SwiftUI.Color.secondary.opacity(DS.Dedup.thumbnailPlaceholderOpacity))
        }
    }

    /// resolve root bookmark + 拼 child URL + loadThumbnail(顶层 nonisolated 函数)。
    /// mirror DedupPass.computeSha 的 scope 模式。
    private func loadThumb() async {
        thumbnail = nil  // 立即清旧缩略图，防止 member.id 变化时短暂显示错位图
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
        guard !Task.isCancelled else { return }
        await MainActor.run {
            self.thumbnail = img
        }
    }
}
