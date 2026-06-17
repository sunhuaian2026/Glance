//
//  ImagePreviewView.swift
//  Glance
//
//  单击图片后显示的内嵌预览。双击图片进入 QuickViewerOverlay 全窗口模式。
//

import SwiftUI

struct ImagePreviewView: View {
    @EnvironmentObject var folderStore: FolderStore
    @EnvironmentObject var appState: AppState

    let images: [URL]
    let startIndex: Int
    let onDismiss: () -> Void
    let onQuickView: (Int) -> Void

    /// D15 终态：父持有的 @FocusState binding（参考 ContentView.AppFocus）。
    @FocusState.Binding var focusTarget: AppFocus?
    @State private var currentIndex: Int
    // vm 由 ContentView 通过 @StateObject 持有并注入：ContentView.body 上有 .id(idx)
    // 会让 ImagePreviewView 在每次方向键切换时整个重建，若 vm 用 @StateObject 跟视图
    // 生命周期绑定，cache 会被一并销毁。提到 ContentView 后 cache 跨重建持续。
    @ObservedObject var vm: ImagePreviewViewModel

    init(vm: ImagePreviewViewModel, images: [URL], startIndex: Int,
         focusTarget: FocusState<AppFocus?>.Binding,
         onDismiss: @escaping () -> Void,
         onQuickView: @escaping (Int) -> Void) {
        self._vm = ObservedObject(wrappedValue: vm)
        self.images = images
        self.startIndex = startIndex
        self._focusTarget = focusTarget
        _currentIndex = State(initialValue: max(0, min(startIndex, images.count - 1)))
        self.onDismiss = onDismiss
        self.onQuickView = onQuickView
    }

    var body: some View {
        ZStack {
            // appBackground 不带 .ignoresSafeArea(): 背景只填 safe area 内遮住底层 grid
            // (预览是 overlay 在 grid 之上不替代), toolbar 区透明让 NavigationSplitView
            // 默认 material 接管, 跟 sidebar vibrancy 融合, 消除标题栏左上角方形.
            DS.Color.appBackground

            // 青绿光晕（右下角）
            RadialGradient(
                colors: [DS.Color.glowSecondary.opacity(0.12), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // 图片
            if let img = vm.nsImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding(DS.Spacing.xl)
                    .onTapGesture(count: 2) {
                        onQuickView(currentIndex)
                    }
            } else if vm.loadFailed {
                ImageLoadFailedView()
            } else {
                ProgressView()
                    .controlSize(.large)
            }

            // 关闭按钮（左上角浮动）
            VStack {
                HStack {
                    Button(action: dismissPreview) {
                        Image(systemName: DS.Icon.close)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary.opacity(0.8))
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    // n/m 进度（右上角浮动）
                    Text("\(currentIndex + 1) / \(images.count)")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xs)
                        .padding(.vertical, DS.Spacing.xs + 2)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Spacing.sm))
                }
                .padding(DS.Spacing.md)
                Spacer()
            }

            // 左右导航
            HStack {
                navButton(systemImage: DS.Icon.previous, enabled: currentIndex > 0) {
                    navigate(by: -1)
                }
                Spacer()
                navButton(systemImage: DS.Icon.next, enabled: currentIndex < images.count - 1) {
                    navigate(by: +1)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)

            // 底部提示
            VStack {
                Spacer()
                Text("双击图片进入全屏查看")
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.35))
                    .padding(.bottom, DS.Spacing.md)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focusTarget, equals: .preview)
        .onAppear { loadImage(); focusTarget = .preview }
        .onKeyPress(.escape) { dismissPreview(); return .handled }
        .onKeyPress(.leftArrow)  { navigate(by: -1); return .handled }
        .onKeyPress(.rightArrow) { navigate(by: +1); return .handled }
        .onKeyPress(.space) { onQuickView(currentIndex); return .handled }
        // F：切换全屏（跟 QuickViewer / grid 一致，spec AppState.md 全局 F 键设计）
        .onKeyPress(.init("f"), phases: .down) { _ in
            appState.toggleFullScreen()
            return .handled
        }
        // cache clearCache 由 ContentView 统一在 selectedFolder / selectedImageIndex==nil /
        // images 变化时触发；这里只做 currentIndex 的 URL 重映射，避免与 ContentView 重复
        .onChange(of: images) { oldImages, newImages in
            guard oldImages.indices.contains(currentIndex) else { return }
            let currentURL = oldImages[currentIndex]
            if let newIdx = newImages.firstIndex(of: currentURL) {
                currentIndex = newIdx
                folderStore.selectedImageIndex = newIdx
            }
        }
        .onChange(of: startIndex) { _, newValue in
            currentIndex = newValue
            loadImage()
        }
    }

    // MARK: - Dismiss

    // 统一 dismiss 入口（ESC + 关闭按钮）：先撤焦点再 onDismiss，避免 transition 退场期
    // 残留 onKeyPress 把方向键接走（Y-2 race，见 commit 5b29600）。
    // D15 终态：focusTarget = nil 让单仲裁者撤销 preview 焦点；父 view onChange(of: selectedImageIndex)
    // 会随后写回 .grid / .ephemeral。
    private func dismissPreview() {
        focusTarget = nil
        onDismiss()
    }

    // MARK: - Navigation

    private func navigate(by delta: Int) {
        let next = currentIndex + delta
        guard next >= 0, next < images.count else { return }
        currentIndex = next
        folderStore.selectedImageIndex = next
        loadImage()
    }

    // MARK: - Image Loading

    private func loadImage() {
        guard images.indices.contains(currentIndex) else { return }
        vm.load(images: images, index: currentIndex)
    }

    // MARK: - Nav Button

    @ViewBuilder
    private func navButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(.primary.opacity(enabled ? 0.9 : 0.25))
                .frame(width: 44, height: 44)
                .background(enabled ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
