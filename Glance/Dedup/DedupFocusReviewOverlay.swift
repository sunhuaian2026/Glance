//
//  DedupFocusReviewOverlay.swift
//  Glance
//
//  重复清理 V2 任务 D.2 — 逐组审阅浮层 view。
//  D6 锁定: ZStack .overlay + .ultraThinMaterial，不是 .sheet，不是独立 NSWindow。
//  D-dedup-7: 点击对话框外部关闭浮层 (macOS Spotlight 标准模态)。
//  D-dedup-15: .focused($focusTarget, equals: .dedupOverlay) 接入既有仲裁链 (D.3 挂)。
//  D-dedup-14 SHA256 invariant: 不显示「★ 推荐/更大/更小」UI。
//

import SwiftUI

/// 逐组审阅全屏浮层。占满 mainContent ZStack，背景层捕获点击，内层对话框拦截冒泡。
struct DedupFocusReviewOverlay: View {
    @EnvironmentObject private var model: DuplicateOverviewModel
    /// D-dedup-15: 父 ContentView 持有的单仲裁焦点 (D.3 实装)
    @FocusState.Binding var focusTarget: AppFocus?

    var body: some View {
        ZStack {
            // 背景模糊层 + 暗化遮罩 — 点击外部关闭 (D-dedup-7)
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    SwiftUI.Color.black.opacity(DS.Dedup.focusOverlayBackgroundOpacity)
                )
                .ignoresSafeArea()
                .onTapGesture {
                    model.closeFocusReview()
                }

            // 内层对话框 — .contentShape 拦截点击不冒泡到背景层
            dialogCard
                .contentShape(Rectangle())
                .onTapGesture { }  // consume tap, prevent closing
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // D-dedup-15: 接入既有焦点仲裁链 (mirror SearchOverlayView .focused($focusTarget, .search))
        .focusable()
        .focused($focusTarget, equals: .dedupOverlay)
        .onKeyPress(.leftArrow)  { model.focusReviewPrev();    return .handled }
        .onKeyPress(.rightArrow) { model.focusReviewNext();    return .handled }
        .onKeyPress(.return)     { model.focusReviewConfirm(); return .handled }
        .onKeyPress(.escape)     { model.closeFocusReview();   return .handled }
    }

    // MARK: - 对话框卡片

    private var dialogCard: some View {
        VStack(spacing: DS.Spacing.zero) {
            dialogHeader
            Divider()
            dialogBody
            Divider()
            dialogFooter
        }
        .frame(width: DS.Dedup.focusDialogWidth)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: DS.Dedup.focusDialogCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Dedup.focusDialogCornerRadius)
                .strokeBorder(SwiftUI.Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: SwiftUI.Color.black.opacity(0.35), radius: 24, x: 0, y: 8)
    }

    // MARK: - 头部

    private var dialogHeader: some View {
        HStack(spacing: DS.Spacing.sm) {
            // 「逐组审阅」标签（warnBg/warn 胶囊）
            Text("逐组审阅")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, DS.Dedup.badgePaddingH)
                .padding(.vertical, DS.Dedup.badgePaddingV)
                .background(DS.Dedup.warnBgColor)
                .foregroundStyle(DS.Dedup.warnColor)
                .clipShape(Capsule())

            // 当前组标题
            Text(currentGroup?.canonical.relativePath ?? "")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 进度
            if !model.focusReviewQueue.isEmpty {
                Text("\(model.focusReviewIndex + 1)/\(model.focusReviewQueue.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // ✕ 关闭按钮
            Button {
                model.closeFocusReview()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: DS.Dedup.focusHeaderCloseSize, height: DS.Dedup.focusHeaderCloseSize)
                    .background(SwiftUI.Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.focusHeaderCloseCornerRadius))
            }
            .buttonStyle(.plain)
            .help("关闭 (Esc)")
        }
        .padding(.horizontal, DS.Dedup.focusDialogPaddingH)
        .padding(.vertical, DS.Dedup.focusHeaderPaddingV)
    }

    // MARK: - 主体（大图对比）

    private var dialogBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // 提示文字
                if let group = currentGroup {
                    Text("保留哪张？点击大图可切换保留张 · 键盘 ← → 切换组 · Enter 确认 · Esc 关闭")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DS.Dedup.focusDialogPaddingH)
                        .padding(.top, DS.Spacing.sm)

                    // 大图对比 — 横排自适应 (2 列 flex-wrap)
                    let columns = [
                        GridItem(.adaptive(minimum: DS.Dedup.focusLargeImageWidth, maximum: DS.Dedup.focusLargeImageWidth),
                                 spacing: DS.Spacing.md, alignment: .top)
                    ]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Spacing.md) {
                        ForEach(group.allMembers) { member in
                            let keepId = model.userKeepId(for: group)
                            FocusReviewMemberCell(
                                member: member,
                                isKeep: member.id == keepId,
                                onTap: {
                                    model.setUserKeep(groupId: group.id, memberId: member.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, DS.Dedup.focusDialogPaddingH)
                    .padding(.bottom, DS.Spacing.md)
                    .animation(DS.Anim.fast, value: model.userKeepId(for: group))
                    .animation(DS.Anim.fast, value: model.focusReviewIndex)
                }
            }
        }
        .frame(maxHeight: DS.Dedup.focusLargeImageHeight + 120)
    }

    // MARK: - 底部操作条

    private var dialogFooter: some View {
        HStack(spacing: DS.Spacing.sm) {
            // 上一组
            Button {
                model.focusReviewPrev()
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "chevron.left")
                    Text("上一组")
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.focusReviewIndex <= 0)

            Spacer()

            // 跳过此组
            Button {
                model.focusReviewSkip()
            } label: {
                Text("跳过此组")
            }
            .buttonStyle(.bordered)

            // 确认并继续 / 确认并完成
            Button {
                model.focusReviewConfirm()
            } label: {
                let isLast = model.focusReviewIndex >= model.focusReviewQueue.count - 1
                HStack(spacing: DS.Spacing.xs) {
                    Text(isLast ? "确认并完成" : "确认并继续")
                    if !isLast {
                        Image(systemName: "chevron.right")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.Dedup.warnColor)
        }
        .padding(.horizontal, DS.Dedup.focusDialogPaddingH)
        .padding(.vertical, DS.Dedup.focusFooterPaddingV)
    }

    // MARK: - 辅助

    private var currentGroup: DuplicateGroup? {
        guard model.focusReviewOpen,
              model.focusReviewIndex < model.focusReviewQueue.count else { return nil }
        let groupId = model.focusReviewQueue[model.focusReviewIndex]
        return model.groups.first(where: { $0.id == groupId })
    }
}

// MARK: - 大图对比单张 cell

private struct FocusReviewMemberCell: View {
    let member: DuplicateGroupMember
    let isKeep: Bool
    let onTap: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            ZStack(alignment: .bottomTrailing) {
                // 缩略图
                thumbContent
                    .frame(width: DS.Dedup.focusLargeImageWidth, height: DS.Dedup.focusLargeImageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Dedup.focusLargeImageCornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Dedup.focusLargeImageCornerRadius)
                            .stroke(
                                isKeep ? DS.Dedup.canonicalBadgeColor : SwiftUI.Color.clear,
                                lineWidth: DS.Dedup.focusKeepBorderWidth
                            )
                        if !isKeep {
                            // 待删暗罩
                            RoundedRectangle(cornerRadius: DS.Dedup.focusLargeImageCornerRadius)
                                .fill(SwiftUI.Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0.4))
                        }
                    }
                    .opacity(isKeep ? 1.0 : DS.Dedup.expandedNonKeepOpacity)

                // 右下角 badge
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
                    Text("待删")
                        .font(DS.Dedup.badgeFont)
                        .padding(.horizontal, DS.Dedup.canonicalBadgePaddingH)
                        .padding(.vertical, DS.Dedup.canonicalBadgePaddingV)
                        .background(SwiftUI.Color.secondary.opacity(0.5))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                        .padding(DS.Dedup.expandedKeepBadgeOffset)
                }
            }
            .onTapGesture { onTap() }
            .help(member.fullPath)

            // 文件名
            Text(member.relativePath)
                .font(DS.Dedup.expandedFilenameFont)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(width: DS.Dedup.focusLargeImageWidth, alignment: .leading)

            // 文件夹路径（parent directory）
            Text((member.fullPath as NSString).deletingLastPathComponent)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(width: DS.Dedup.focusLargeImageWidth, alignment: .leading)
        }
        .task(id: member.id) { await loadThumb() }
    }

    @ViewBuilder
    private var thumbContent: some View {
        if let img = thumbnail {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: DS.Dedup.focusLargeImageCornerRadius)
                .fill(SwiftUI.Color.secondary.opacity(DS.Dedup.thumbnailPlaceholderOpacity))
        }
    }

    private func loadThumb() async {
        thumbnail = nil
        let urlBookmark = member.urlBookmark
        let relativePath = member.relativePath
        let maxPixel = DS.Dedup.focusLargeImageMaxPixel
        let img: NSImage? = await Task.detached(priority: .userInitiated) {
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
