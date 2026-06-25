//
//  DedupCleanupV2View.swift
//  Glance
//
//  重复清理 V2 重设计 — 主视图 (design v2 §4)
//  顶栏 + 汇总条 + 工具条 + 列表区 4 区域;浮层挂在 ContentView .overlay (任务 D)。
//  跟随全局 AppearanceMode (D4 锁定,无独立深/浅切换)。
//

import SwiftUI

struct DedupCleanupV2View: View {
    @EnvironmentObject var model: DuplicateOverviewModel
    @EnvironmentObject var migrationCoordinator: BookmarkMigrationCoordinator

    var body: some View {
        VStack(spacing: DS.Spacing.zero) {
            topBar
            mainContent
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let err = model.errorMessage {
            errorState(message: err)
        } else if case .rescanning = migrationCoordinator.phase {
            rescanningState
        } else if model.groupCount == 0 && !model.isLoading {
            emptyState
        } else {
            VStack(spacing: DS.Spacing.zero) {
                summaryStrip
                toolbar
                groupsList
            }
        }
    }

    // MARK: - 顶栏 (AB.6)

    private var topBar: some View {
        HStack {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "trash.fill")
                    .frame(width: DS.Dedup.topBarTrashIconSize, height: DS.Dedup.topBarTrashIconSize)
                    .background(DS.Dedup.dangerBgColor)
                    .foregroundStyle(DS.Dedup.dangerColor)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.topBarTrashIconCornerRadius))
                Text("重复清理")
                    .font(DS.Dedup.topBarTitleFont)
            }
            Spacer()
            trashAction
        }
        .frame(height: DS.Dedup.topBarHeight)
        .padding(.horizontal, DS.Spacing.lg)
        .background(SwiftUI.Color.secondary.opacity(0.05))
        .overlay(alignment: .bottom) {
            Rectangle().fill(SwiftUI.Color.secondary.opacity(0.1)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var trashAction: some View {
        switch model.trashState {
        case .idle, .completed:
            Button {
                Task { await model.trashPending() }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: DS.Icon.trash)
                    Text("移入废纸篓 (\(model.pendingTrashCount))")
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.Dedup.dangerColor)
            .disabled(!model.trashEnabled)
            .opacity(model.trashEnabled ? 1.0 : 0.45)
        case .trashing(let done, let total):
            HStack(spacing: DS.Spacing.sm) {
                ProgressView(value: Double(done), total: Double(total))
                    .progressViewStyle(.linear)
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

    // MARK: - 汇总条 (AB.6)

    private var summaryStrip: some View {
        HStack(spacing: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("扫描结果")
                    .font(DS.Dedup.summaryLabelFont)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                    Text("\(model.groupCount) 组重复")
                        .font(DS.Dedup.summaryBigNumberFont)
                    Text("·")
                        .foregroundStyle(.secondary)
                }
                Text("可释放约 \(formattedReclaimable)")
                    .font(DS.Dedup.summarySubFont)
                    .foregroundStyle(DS.Dedup.reviewedColor)
            }
            Rectangle()
                .fill(SwiftUI.Color.secondary.opacity(0.2))
                .frame(width: DS.Dedup.summaryDividerWidth, height: DS.Dedup.summaryDividerHeight)
            HStack(spacing: DS.Spacing.lg) {
                summaryBadge(icon: "checkmark.seal.fill",
                            iconColor: DS.Dedup.reviewedColor,
                            iconBgColor: DS.Dedup.reviewedBgColor,
                            count: model.autoCount,
                            label: "已自动留最优")
                summaryBadge(icon: "exclamationmark.triangle.fill",
                            iconColor: DS.Dedup.warnColor,
                            iconBgColor: DS.Dedup.warnBgColor,
                            count: model.reviewCount,
                            label: "建议你确认")
            }
            Spacer()
            reviewButton
        }
        .padding(.horizontal, DS.Dedup.summaryCardPaddingH)
        .padding(.vertical, DS.Dedup.summaryCardPaddingV)
        .background(SwiftUI.Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.summaryCardCornerRadius))
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.md)
    }

    private func summaryBadge(
        icon: String,
        iconColor: SwiftUI.Color,
        iconBgColor: SwiftUI.Color,
        count: Int,
        label: String
    ) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .frame(width: DS.Dedup.summaryBadgeIconSize, height: DS.Dedup.summaryBadgeIconSize)
                .background(iconBgColor)
                .foregroundStyle(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.summaryBadgeIconCornerRadius))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count) 组")
                    .font(DS.Dedup.summaryBadgeCountFont)
                Text(label)
                    .font(DS.Dedup.summaryLabelFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var reviewButton: some View {
        Button {
            model.openFocusReview()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text("逐组审阅")
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .padding(.horizontal, DS.Spacing.md)
            .frame(height: DS.Dedup.summaryReviewButtonHeight)
        }
        .buttonStyle(.borderedProminent)
        .tint(DS.Dedup.warnColor)
        // D1 (2026-06-25): 不再依赖 reviewCount, 只在 trashing 期间 disable.
        // queue = 所有未跳过组, 让用户能逐组眼审任何场景 (含 2 张组).
        .disabled(model.pendingGroupCount == 0 || isTrashingNow)
        .opacity((model.pendingGroupCount == 0 || isTrashingNow) ? 0.5 : 1.0)
    }

    private var isTrashingNow: Bool {
        if case .trashing = model.trashState { return true }
        return false
    }

    // MARK: - 工具条 (AB.7)

    private var toolbar: some View {
        HStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                filterPill(.all, label: "全部")
                filterPill(.needsReview, label: "待确认")
                filterPill(.auto, label: "已自动")
            }
            Spacer()
            HStack(spacing: DS.Spacing.xs) {
                Text("排序").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $model.sortOption) {
                    Text("可省").tag(DedupSortOption.reclaimableDesc)
                    Text("张数").tag(DedupSortOption.countDesc)
                    Text("名称").tag(DedupSortOption.nameAsc)
                }
                .pickerStyle(.segmented)
                .frame(width: DS.Dedup.sortSegmentWidth)
            }
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("搜索文件名…", text: $model.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(SwiftUI.Color.secondary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.searchBoxCornerRadius))
            .frame(width: DS.Dedup.searchBoxWidth)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    private func filterPill(_ filter: DedupListFilter, label: String) -> some View {
        let count = countFor(filter)
        let isSelected = model.filter == filter
        return Button {
            model.filter = filter
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text(label).font(DS.Dedup.filterPillFont)
                Text("\(count)").font(DS.Dedup.filterPillCountFont).opacity(0.7)
            }
            .padding(.horizontal, DS.Dedup.filterPillPaddingH)
            .padding(.vertical, DS.Dedup.filterPillPaddingV)
            .background(isSelected ? SwiftUI.Color.primary : SwiftUI.Color.secondary.opacity(0.07))
            .foregroundStyle(isSelected ? SwiftUI.Color(NSColor.windowBackgroundColor) : SwiftUI.Color.secondary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(SwiftUI.Color.secondary.opacity(0.2), lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func countFor(_ filter: DedupListFilter) -> Int {
        switch filter {
        case .all:         return model.groupCount
        case .needsReview: return model.reviewCount
        case .auto:        return model.autoCount
        }
    }

    // MARK: - 列表区 (AB.8)

    private var groupsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Dedup.rowGap) {
                ForEach(model.filteredSortedGroups) { group in
                    DedupGroupRow(
                        group: group,
                        keepId: model.userKeepId(for: group),
                        isSkipped: model.isSkipped(groupId: group.id),
                        isExpanded: model.isExpanded(groupId: group.id),
                        isNeedsReview: model.needsReview(group: group),
                        isReviewed: model.isReviewed(groupId: group.id),
                        onToggleSkip: { model.toggleSkip(groupId: group.id) },
                        onToggleExpand: { model.toggleExpand(groupId: group.id) },
                        onSetKeep: { memberId in model.setUserKeep(groupId: group.id, memberId: memberId) },
                        onTrashGroup: { Task { await model.trashGroup(group.id) } }
                    )
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
        }
    }

    // MARK: - 状态 view

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
        ByteCountFormatter.string(fromByteCount: model.pendingReclaimableBytes, countStyle: .file)
    }
}

// MARK: - 单行卡片 (AB.8)

private struct DedupGroupRow: View {
    let group: DuplicateGroup
    let keepId: Int64
    let isSkipped: Bool
    let isExpanded: Bool
    let isNeedsReview: Bool
    let isReviewed: Bool
    let onToggleSkip: () -> Void
    let onToggleExpand: () -> Void
    let onSetKeep: (Int64) -> Void
    let onTrashGroup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.zero) {
            rowHeader
            if isExpanded {
                expandedArea
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(SwiftUI.Color.secondary.opacity(DS.Dedup.groupCardBackgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.rowCornerRadius, style: .continuous))
        .opacity(isSkipped ? DS.Dedup.rowSkippedOpacity : 1.0)
        .animation(.easeInOut(duration: DS.Dedup.chevronAnimationDuration), value: isExpanded)
        // C3 — 右键 contextMenu「立即删除此组」(destructive 红色, 老手快捷; 跳过组不显)
        .contextMenu {
            if !isSkipped {
                Button(role: .destructive) {
                    onTrashGroup()
                } label: {
                    Label("立即删除此组 (\(group.duplicateCount) 张)", systemImage: "trash")
                }
            }
        }
    }

    private var rowHeader: some View {
        HStack(spacing: DS.Spacing.sm) {
            // 叠放缩略图 (点击展开/收起)
            Button {
                withAnimation(.easeInOut(duration: DS.Dedup.chevronAnimationDuration)) {
                    onToggleExpand()
                }
            } label: {
                StackedThumbnail(canonical: group.canonical, firstDup: group.duplicates.first)
            }
            .buttonStyle(.plain)

            // 中间信息
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(group.canonical.relativePath)
                    .font(DS.Dedup.rowTitleFont)
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusBadge
                let keepMember = group.allMembers.first(where: { $0.id == keepId }) ?? group.canonical
                Text("保留 \(keepMember.relativePath)")
                    .font(DS.Dedup.rowSubFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("可省 \(formattedReclaimable)")
                    .font(DS.Dedup.rowSubFont)
                    .foregroundStyle(DS.Dedup.reviewedColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧: 徽章 + 跳过按钮 + chevron
            HStack(spacing: DS.Spacing.xs) {
                if isSkipped {
                    Text("已跳过")
                        .font(DS.Dedup.badgeFont)
                        .padding(.horizontal, DS.Dedup.badgePaddingH)
                        .padding(.vertical, DS.Dedup.badgePaddingV)
                        .background(SwiftUI.Color.secondary.opacity(0.15))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                } else {
                    Text("删 \(group.duplicateCount)")
                        .font(DS.Dedup.badgeFont)
                        .padding(.horizontal, DS.Dedup.badgePaddingH)
                        .padding(.vertical, DS.Dedup.badgePaddingV)
                        .background(DS.Dedup.dangerBgColor)
                        .foregroundStyle(DS.Dedup.dangerForegroundColor)
                        .clipShape(Capsule())
                }
                Button(isSkipped ? "恢复" : "跳过") {
                    onToggleSkip()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(height: DS.Dedup.skipButtonHeight)

                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: DS.Dedup.chevronAnimationDuration), value: isExpanded)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: DS.Dedup.chevronSize, height: DS.Dedup.chevronSize)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: DS.Dedup.chevronAnimationDuration)) {
                            onToggleExpand()
                        }
                    }
            }
        }
        .padding(.horizontal, DS.Dedup.rowPaddingH)
        .padding(.vertical, DS.Dedup.rowPaddingV)
        .frame(minHeight: DS.Dedup.rowHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isNeedsReview && !isReviewed {
            Text("待确认")
                .font(DS.Dedup.badgeFont)
                .padding(.horizontal, DS.Dedup.badgePaddingH)
                .padding(.vertical, DS.Dedup.badgePaddingV)
                .background(DS.Dedup.warnBgColor)
                .foregroundStyle(DS.Dedup.warnColor)
                .clipShape(Capsule())
        } else if isReviewed {
            Text("已确认")
                .font(DS.Dedup.badgeFont)
                .padding(.horizontal, DS.Dedup.badgePaddingH)
                .padding(.vertical, DS.Dedup.badgePaddingV)
                .background(DS.Dedup.reviewedBgColor)
                .foregroundStyle(DS.Dedup.reviewedColor)
                .clipShape(Capsule())
        }
    }

    private var expandedArea: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.zero) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Dedup.expandedAreaGap) {
                    ForEach(group.allMembers) { member in
                        DedupMemberCell(
                            member: member,
                            isKeep: member.id == keepId,
                            onTap: { onSetKeep(member.id) }
                        )
                    }
                }
                .padding(.horizontal, DS.Dedup.expandedAreaPaddingH)
                .padding(.vertical, DS.Dedup.expandedAreaPaddingV)
            }
            // C4 — 展开区底部「删除这组」红按钮 (主入口, 看完缩略图视觉确认才点 = 克制 + 误删低)
            if !isSkipped {
                HStack {
                    Spacer()
                    Button {
                        onTrashGroup()
                    } label: {
                        Label("删除这组 (\(group.duplicateCount) 张)", systemImage: "trash")
                            .font(DS.Dedup.badgeFont)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Dedup.dangerBgColor)
                    .controlSize(.small)
                }
                .padding(.horizontal, DS.Dedup.expandedAreaPaddingH)
                .padding(.bottom, DS.Dedup.expandedAreaPaddingV)
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(SwiftUI.Color.secondary.opacity(0.1)).frame(height: 1)
        }
    }

    private var formattedReclaimable: String {
        ByteCountFormatter.string(fromByteCount: group.reclaimableBytes, countStyle: .file)
    }
}

// MARK: - 叠放缩略图占位

private struct StackedThumbnail: View {
    let canonical: DuplicateGroupMember
    let firstDup: DuplicateGroupMember?

    @State private var canonicalThumb: NSImage?
    @State private var dupThumb: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 后层 (副本)
            if let dup = firstDup {
                thumbContent(dupThumb)
                    .frame(width: DS.Dedup.stackedThumbnailWidth, height: DS.Dedup.stackedThumbnailHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.stackedThumbnailFrontCornerRadius))
                    .opacity(0.6)
                    .offset(x: 4, y: -4)
                    .task(id: dup.id) { await loadThumb(member: dup, assign: { dupThumb = $0 }) }
            }
            // 前层 (保留张)
            thumbContent(canonicalThumb)
                .frame(width: DS.Dedup.stackedThumbnailFrontWidth, height: DS.Dedup.stackedThumbnailFrontHeight)
                .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.stackedThumbnailFrontCornerRadius))
                .task(id: canonical.id) { await loadThumb(member: canonical, assign: { canonicalThumb = $0 }) }
        }
        .frame(width: DS.Dedup.stackedThumbnailWidth + 4, height: DS.Dedup.stackedThumbnailHeight + 4)
    }

    @ViewBuilder
    private func thumbContent(_ img: NSImage?) -> some View {
        if let img {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: DS.Dedup.stackedThumbnailFrontCornerRadius)
                .fill(SwiftUI.Color.secondary.opacity(DS.Dedup.thumbnailPlaceholderOpacity))
        }
    }

    private func loadThumb(member: DuplicateGroupMember, assign: @MainActor @escaping (NSImage?) -> Void) async {
        let urlBookmark = member.urlBookmark
        let relativePath = member.relativePath
        let maxPixel = DS.Dedup.expandedThumbnailMaxPixel
        let img: NSImage? = await Task.detached(priority: .utility) {
            var stale = false
            guard let rootURL = try? URL(
                resolvingBookmarkData: urlBookmark,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &stale
            ) else { return nil }
            let didStart = rootURL.startAccessingSecurityScopedResource()
            defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }
            return await loadThumbnail(url: rootURL.appendingPathComponent(relativePath), maxPixelSize: maxPixel)
        }.value
        guard !Task.isCancelled else { return }
        await MainActor.run { assign(img) }
    }
}

// MARK: - 展开区单张缩略图 (AB.8)

private struct DedupMemberCell: View {
    let member: DuplicateGroupMember
    let isKeep: Bool
    let onTap: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            ZStack(alignment: .topTrailing) {
                thumbContent
                    .frame(width: DS.Dedup.expandedThumbnailWidth, height: DS.Dedup.expandedThumbnailHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.expandedThumbnailCornerRadius, style: .continuous))
                    .overlay {
                        if isKeep {
                            RoundedRectangle(cornerRadius: DS.Dedup.expandedThumbnailCornerRadius, style: .continuous)
                                .stroke(DS.Dedup.canonicalBadgeColor, lineWidth: DS.Dedup.expandedKeepBorderWidth)
                        } else {
                            // 待删暗罩
                            RoundedRectangle(cornerRadius: DS.Dedup.expandedThumbnailCornerRadius, style: .continuous)
                                .fill(SwiftUI.Color.black.opacity(DS.Dedup.expandedTrashOverlayOpacity))
                        }
                    }
                    .opacity(isKeep ? 1.0 : DS.Dedup.expandedNonKeepOpacity)

                if isKeep {
                    Text("✓ 保留")
                        .font(DS.Dedup.badgeFont)
                        .padding(.horizontal, DS.Dedup.canonicalBadgePaddingH)
                        .padding(.vertical, DS.Dedup.canonicalBadgePaddingV)
                        .background(DS.Dedup.canonicalBadgeColor)
                        .foregroundStyle(DS.Dedup.canonicalBadgeForeground)
                        .clipShape(Capsule())
                        .padding(DS.Dedup.expandedKeepBadgeOffset)
                } else {
                    // 右上 ✕ 角标 (待删)
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: DS.Dedup.expandedTrashIconSize))
                        .foregroundStyle(DS.Dedup.dangerForegroundColor)
                        .padding(DS.Dedup.expandedKeepBadgeOffset)
                }
            }
            .onTapGesture { onTap() }

            Text(member.relativePath)
                .font(DS.Dedup.expandedFilenameFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: DS.Dedup.expandedThumbnailWidth, alignment: .leading)
        }
        .help(member.fullPath)
        .task(id: member.id) { await loadThumb() }
    }

    @ViewBuilder
    private var thumbContent: some View {
        if let img = thumbnail {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: DS.Dedup.expandedThumbnailCornerRadius)
                .fill(SwiftUI.Color.secondary.opacity(DS.Dedup.thumbnailPlaceholderOpacity))
        }
    }

    private func loadThumb() async {
        thumbnail = nil
        let urlBookmark = member.urlBookmark
        let relativePath = member.relativePath
        let maxPixel = DS.Dedup.expandedThumbnailMaxPixel
        let img: NSImage? = await Task.detached(priority: .utility) {
            var stale = false
            guard let rootURL = try? URL(
                resolvingBookmarkData: urlBookmark,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &stale
            ) else { return nil }
            let didStart = rootURL.startAccessingSecurityScopedResource()
            defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }
            return await loadThumbnail(url: rootURL.appendingPathComponent(relativePath), maxPixelSize: maxPixel)
        }.value
        guard !Task.isCancelled else { return }
        await MainActor.run { self.thumbnail = img }
    }
}
