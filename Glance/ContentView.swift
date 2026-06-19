//
//  ContentView.swift
//  ISeeImageViewer
//

import SwiftUI
import SQLite3
import AppKit
import Combine

/// 焦点目标 enum（D15 终态：父持有 @FocusState 单仲裁者）。
/// grid case 由 V1 ImageGridView / V2 SmartFolderGridView 互斥共用（同层 baseGrid 二选一）。
/// QuickViewerOverlay 独立持本地 @FocusState（overlay 结构上跟 detail ZStack 平行无 race）。
enum AppFocus: Hashable {
    case grid
    case preview
    case ephemeral
    /// M3 Slice M 加：⌘F 触发的 SearchOverlayView input field 拿焦点时此 case 激活；
    /// modal layer 顺序：QV > search > preview > ephemeral > baseGrid（D16）
    case search
    /// 重复清理 V2 任务 D 加：逐组审阅浮层打开时激活（D-dedup-15 接入既有仲裁链）。
    /// modal layer 顺序：QV > dedupOverlay > search > preview > ephemeral > baseGrid
    case dedupOverlay
}

// QV 入口来源：用 enum 而非裸 Bool/Optional 让 dismiss 路由按 provenance 走，不依赖
// selectedImageIndex 是否 nil 当哨兵 — 这样 QV 方向键写 selectedImageIndex 同步 grid
// highlight + preview 时不会反向破坏 6da903c 修过的"双击 cell 进 QV 后退出回 grid 不进 preview"
// File-level internal (not private): MainQuickViewerWindowController references it across files.
enum QuickViewerEntry {
    case grid       // 路径 1: grid 双击 cell 直接进 QV
    case preview    // 路径 2: grid → preview → 双击 → QV
    case ephemeral  // 路径 3 (M2 Slice J): EphemeralResultView 双击 cell 进 QV → 退出直接回 baseGrid，不卡在 ephemeral 无焦点态
}

/// M2 Slice J — 临时结果视图请求。M2 .similar；M3 加 .search。
/// banner 由 caller 计算（D14 部分库提示），nil = 不显示 banner。
private enum EphemeralRequest: Equatable {
    case similar(sourceUrl: URL, results: [URL], banner: String?)
    /// M3 Slice M — 全局搜索结果。images 携带 birth_time 给 EphemeralResultView 做时间分段。
    case search(query: String, images: [IndexedImage], urls: [URL])

    var title: String {
        switch self {
        case .similar(let url, _, _):
            return "类似于 \(url.lastPathComponent)"
        case .search(let q, _, _):
            return q.isEmpty ? "搜索" : "搜索: \(q)"
        }
    }

    var urls: [URL] {
        switch self {
        case .similar(_, let r, _): return r
        case .search(_, _, let urls): return urls
        }
    }

    var banner: String? {
        switch self {
        case .similar(_, _, let b): return b
        case .search: return nil   // D19 搜索不带 banner
        }
    }

    /// D19 toggle：search → true 启用 sectioned；similar → false flat。
    var showTimeBuckets: Bool {
        switch self {
        case .similar: return false
        case .search:  return true
        }
    }

    /// caller 控空态文案。M3 search 区分空 input vs 0 结果。
    var emptyStateText: String {
        switch self {
        case .similar:
            return "无结果"
        case .search(let q, _, _):
            return q.isEmpty
                ? "输入关键字或 modifier 搜索"
                : "未找到匹配项 · 检查拼写或减少 modifier"
        }
    }

    /// 跟 urls 平行的 birth_time 数组。M3 search 才有；M2 similar nil。
    var datesForBuckets: [Date]? {
        switch self {
        case .similar: return nil
        case .search(_, let images, _):
            return images.map { $0.birthTime }
        }
    }

    /// EphemeralResultView mount 时是否自动抢 .ephemeral 焦点。
    /// search：false（焦点归 overlay input）；similar：true（无 overlay，进结果即聚焦）。
    var autoFocusOnAppear: Bool {
        switch self {
        case .similar: return true
        case .search:  return false
        }
    }

    /// 焦点进 .ephemeral 且无高亮时是否默认高亮第一张。search：true；similar：false（保 M2 不变）。
    var defaultHighlightFirst: Bool {
        switch self {
        case .similar: return false
        case .search:  return true
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var folderStore: FolderStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var indexStoreHolder: IndexStoreHolder
    @EnvironmentObject var bookmarkManager: BookmarkManager
    /// D-mb-9.1 — 菜单栏「查找…」trigger token, .onReceive(dropFirst) 调原 openSearch().
    @EnvironmentObject var searchOverlayState: SearchOverlayState
    /// D-mb-9.1 — 菜单栏「显示信息/隐藏信息」共享态, .onChange 双向 sync 到 @State showInspector.
    @EnvironmentObject var inspectorState: InspectorState
    @StateObject private var smartFolderStore = SmartFolderStore.placeholder()
    /// M4 任务 1 — 重复清理总览 model(mirror smartFolderStore placeholder/attach 模式)
    @StateObject private var duplicateOverviewModel = DuplicateOverviewModel.placeholder()
    /// M4 任务 2 收尾 — V1→V2 bookmark 升级引导 Coordinator (步骤 A.5 加).
    @StateObject private var migrationCoordinator = BookmarkMigrationCoordinator.placeholder()
    /// 任务 C.11 — 快速看图器单张删除适配 Coordinator (URL → TrashService 桥)。schema gate
    /// 在 Coordinator 入口 (V1 老 bookmark return nil 让 Overlay toast 提示)。
    @StateObject private var quickViewerTrashCoordinator = QuickViewerTrashCoordinator()
    /// M4 任务 1 — 是否切换到重复清理总览(五态互斥的第五态)
    @State private var showDuplicateOverview: Bool = false
    @State private var indexBridge: FolderStoreIndexBridge?
    @State private var didWire: Bool = false
    /// V2 mode 下 preview / QuickViewer 的图片源（cell 单击/双击时从 queryResult 重建）。
    /// 不复用 folderStore.images，避免触发 .onChange(of: folderStore.images) 的保护性
    /// 关 QV 逻辑（那条 onChange 是给 V1 排序场景设计的）。
    @State private var v2Urls: [URL] = []
    /// M2 Slice J — 类似图查找结果视图状态。non-nil 时主区域换 EphemeralResultView 替代 baseGrid。
    @State private var currentEphemeral: EphemeralRequest?
    @State private var showInspector = false
    /// QV 已迁到独立 NSWindow（controller 持窗 + 退出仲裁），ContentView 仅观察 isPresenting
    /// 决定底层 hit-testing / previewOverlay 渲染条件，进出 QV 走 presentQuickViewer / handleQVDismiss。
    @ObservedObject private var qvController = MainQuickViewerWindowController.shared
    /// M3 Slice M — search overlay 显隐控制
    @State private var showSearchOverlay: Bool = false
    /// M3 Slice M — 当前搜索后台 Task（cancel 用，避免 stale 覆盖）
    @State private var searchTask: Task<Void, Never>? = nil
    /// M3 chips — chip 选中态（D22 独立筛选状态）。openSearch 重置、closeSearch 清空（D27）。
    @State private var searchFilterState = SearchFilterState()
    /// M4 任务 2 — 撤销 banner 全局 state (D33 跨视图持久, 不绑 showDuplicateOverview 生命周期).
    /// duplicateOverviewModel.lastTrashOutcome.id .onChange 触发拷贝 (codex P2(轻量 UUID 比对避深比 BLOB)).
    /// 用户点 banner [×] 或 [撤销] 完成 → onDismiss 清回 nil.
    @State private var trashUndoBanner: TrashOutcomeEvent? = nil
    /// 重复清理 V2 任务 D.1 — 浮层打开前的焦点快照（关闭时恢复，D-dedup-15 仲裁链）。
    @State private var previousAppFocus: AppFocus? = nil
    /// banner 30s auto-dismiss timer (cancellable; 进快速看图器 / 切视图不暂停 — D33 简化:
    /// banner 状态保留 30s 内有效, 过期视作用户已忽略)
    @State private var bannerDismissTask: Task<Void, Never>? = nil
    /// D15 终态：父持有的单一 @FocusState，向所有可聚焦子 view（grid / preview / ephemeral）
    /// 通过 FocusState.Binding 下发。替代原 3 个 UUID trigger（gridFocusTrigger /
    /// previewFocusTrigger / ephemeralFocusTrigger）+ 子 view 各自 @FocusState 模式 —
    /// 那套模式在 ZStack 同层多焦点持有者时存在 race（codex:rescue 5b29600 / 59a9d86 / J 阶段已多次复发）。
    @FocusState private var focusTarget: AppFocus?
    // vm 由 ContentView @StateObject 持有，prefetchCache 跨 navigate 持续，方向键命中即时显示
    // 无 spinner。历史上配合 ImagePreviewView 上的 .id(idx) 重建；D15 refactor 后已删 .id，
    // 但 parent-owned 模式继续保留（不增成本，且未来 .id 若复活仍稳）
    @StateObject private var previewVM = ImagePreviewViewModel()

    private var inspectorURL: URL? {
        // mirror previewOverlay / QuickViewer .overlay 的 image source 选择：V2 mode 用
        // 本地 v2Urls，V1 mode 用 folderStore.images。前者是 commit 26c457a 拆出来的本地
        // @State，避免 V1 排序保护逻辑误关 V2 QV
        let images = (currentEphemeral != nil || smartFolderStore.selected != nil) ? v2Urls : folderStore.images
        guard let idx = folderStore.selectedImageIndex,
              idx < images.count else { return nil }
        return images[idx]
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                SmartFolderListView(
                    isDuplicateOverviewSelected: showDuplicateOverview,
                    onSelectDuplicates: {
                        showDuplicateOverview = true
                    }
                )
                    .padding(.top, DS.Spacing.sm)
                    .padding(.horizontal, DS.Spacing.xs)

                Divider()
                    .padding(.vertical, DS.Spacing.xs)

                FolderSidebarView(
                    onToggleHide: { rootURL, nodeURL in
                        toggleHide(rootURL: rootURL, nodeURL: nodeURL)
                    },
                    isEffectivelyHidden: { rootURL, nodeURL in
                        effectivelyHidden(rootURL: rootURL, nodeURL: nodeURL)
                    },
                    isExplicitlyHidden: { rootURL, nodeURL in
                        explicitlyHidden(rootURL: rootURL, nodeURL: nodeURL)
                    }
                )
            }
            .navigationSplitViewColumnWidth(
                min: DS.Sidebar.minWidth,
                ideal: DS.Sidebar.width,
                max: DS.Sidebar.maxWidth
            )
            .environmentObject(smartFolderStore)
        } detail: {
            HStack(spacing: 0) {
                mainContent
                    // QV 是全屏 modal overlay：激活时底层 grid 不该再响应鼠标。顺带让底层
                    // cell 的 .help tooltip tracking area 失活，修复 V2 smart folder cell 的
                    // relativePath tooltip 串到 QV 工具栏的串扰（V1 cell 无显式 .help 故不受影响）。
                    .allowsHitTesting(!qvController.isPresenting)
                if showInspector {
                    // V1 已删独立 Divider（commit 086ade2 改用 Inspector 自带 leading overlay）
                    ImageInspectorView(
                        url: inspectorURL,
                        duplicatesProvider: { url in
                            guard let store = indexStoreHolder.store else { return [] }
                            return (try? store.fetchDuplicatesByFullPath(url.path)) ?? []
                        }
                    )
                        .frame(width: DS.Inspector.width)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(DS.Anim.normal, value: showInspector)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showInspector.toggle()
                    } label: {
                        Label("信息", systemImage: showInspector ? DS.Icon.infoFilled : DS.Icon.info)
                    }
                    .keyboardShortcut("i", modifiers: .command)
                    .disabled(folderStore.selectedImageIndex == nil)
                }
                // 工具栏查找按钮 — 点击 = ⌘F 同效果(开搜索 overlay), 让不熟键盘用户也能发现。
                // 不挂 .keyboardShortcut("f") 避免与下方 .onKeyPress(.init("f")) 双绑触发两次,
                // ⌘F 仍走 .onKeyPress 唯一处理, button 仅当点击入口 + help tooltip 显示快捷键
                ToolbarItem(placement: .automatic) {
                    Button {
                        openSearch()
                    } label: {
                        Label("查找 (⌘F)", systemImage: DS.Icon.search)
                    }
                    .help("查找 (⌘F)")
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Button {
                                appState.appearanceMode = mode
                            } label: {
                                if appState.appearanceMode == mode {
                                    Label(mode.label, systemImage: "checkmark")
                                } else {
                                    Text(mode.label)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "circle.lefthalf.filled")
                    }
                }
            }
            .environmentObject(smartFolderStore)
            .environmentObject(duplicateOverviewModel)
            .environmentObject(migrationCoordinator)
            // M4 任务 2 — 撤销 banner overlay (D33 跨视图持久, 五态 detail 内全在).
            // 挂在 detail closure 内 HStack 上, 让 banner 在 detail 区横向居中而非
            // 整 NavigationSplitView 横向居中(避开侧栏宽度让 banner 视觉偏左).
            // 快速看图器是独立 NSWindow 物理不可见但 trashUndoBanner state 保留, 关 QV 后回归.
            .overlay(alignment: .top) {
                if let event = trashUndoBanner {
                    TrashUndoBanner(
                        event: event,
                        onUndo: {
                            bannerDismissTask?.cancel()
                            // 不立即清 trashUndoBanner — undo 完成后 model.lastTrashOutcome 重 publish
                            // 触发 .onChange 重赋 event (含 undoResult) 让 banner 切「撤销完成」展示
                            Task { await duplicateOverviewModel.undo(outcome: event.trash) }
                        },
                        onDismiss: {
                            bannerDismissTask?.cancel()
                            trashUndoBanner = nil
                        }
                    )
                    .padding(.top, DS.Dedup.bannerTopPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // codex P2(深比 BLOB): animation value 用 UUID 不用整 event
            .animation(DS.Anim.normal, value: trashUndoBanner?.id)
        }
        // M4 任务 2 收尾 — bookmark 升级引导 sheet (步骤 A.5 加).
        .sheet(isPresented: $migrationCoordinator.isPresenting) {
            BookmarkMigrationView(
                onConfirm: { Task { await migrationCoordinator.pickRoots() } },
                onDismiss: { migrationCoordinator.cancel() }
            )
        }
        // QV 已迁到独立 NSWindow（MainQuickViewerWindowController）。退出路由由 controller
        // 经 onDismiss(reason, entry) 回调到 handleQVDismiss 仲裁，不再走 .overlay + onChange。
        // M3 Slice M：body 级 ⌘F → openSearch（QV 不在场景下生效；QV 在时焦点在 QV，
        // QV 自己的 .onKeyPress(F) 处理 ⌘F，分支调 onCommandF 走 ContentView.openSearch）
        .onKeyPress(.init("f"), phases: .down) { event in
            if event.modifiers.contains(.command) {
                openSearch()
                return .handled
            }
            return .ignored
        }
        // 隐藏 window toolbar 的 background material 绘制层，让 toolbar items（文件名 / ⓘ /
        // 外观切换）直接坐在 NSWindow title bar 上，避免 NavigationSplitView 默认 separated
        // 浅灰底色横条跟下方 ImagePreviewView 紫黑底色 (appBackground #121217) 断层。
        // 绘制层 ≠ NSWindow.toolbarStyle 布局层，AppKit 桥设 toolbarStyle 不生效（已验证）
        .toolbarBackground(.hidden, for: .windowToolbar)
        // 切换文件夹或取消图片选择时，自动关闭 Inspector
        .onChange(of: folderStore.selectedFolder) { _, _ in
            withAnimation(DS.Anim.normal) { showInspector = false }
            previewVM.clearCache()
        }
        .onChange(of: folderStore.selectedImageIndex) { _, newValue in
            if newValue == nil {
                withAnimation(DS.Anim.normal) { showInspector = false }
                previewVM.clearCache()
                // preview 关闭归 nil 时若 QV 不在 → 焦点回上一层：ephemeral 还显示则回 ephemeral，
                // 否则回 baseGrid。!qvController.isPresenting 保护避开 preview→QV 路径的 spurious fire
                // （那条路径由 controller onDismiss → handleQVDismiss 的 .preview 分支单独仲裁焦点）
                if !qvController.isPresenting {
                    focusTarget = currentEphemeral != nil ? .ephemeral : .grid
                }
            }
        }
        // codex Option 3 加强版修 — QV 误关 bug: 之前的"任意 images 变化就关 QV"是 V1 排序时代
        // 设的(QV-toolbar Slice1 已迁独立 NSWindow + viewModel 持自己 images snapshot), FSEvents
        // 检测到删图 → folderStore.images 变化 → 误关 QV(撤销 toast 跟着销毁)。修法: 仅当 QV 当前
        // 看的图不在新 images 列表里(切文件夹 / 外部删 QV 当前图 / 全清) 才关 QV; 排序 / 单张删除
        // 其它图 / FSEvents 增删其它图 等场景 QV 当前图仍在新列表, 保持 QV 不动。
        .onChange(of: folderStore.images) { _, newImages in
            if qvController.isPresenting {
                if let qvURL = qvController.currentImageURL {
                    if !newImages.contains(qvURL) {
                        qvController.close(reason: .normal)
                    }
                    // else: 当前 QV 图仍在新列表, 保持 QV (修 14 张删 1 张误关 bug)
                } else {
                    // currentImageURL nil = QV isPresenting=true 但 Overlay closure registry
                    // 还没注册到 / 已 clearCommandHandlers; 防御性关 QV 兜底.
                    qvController.close(reason: .normal)
                }
            }
            previewVM.clearCache()
        }
        // V2 wire-up：IndexStore async ready 后挂载 engine + bridge + 默认选中"全部最近"
        .onAppear {
            Task { await wireIfReady() }
        }
        .onChange(of: indexStoreHolder.isReady) { _, ready in
            guard ready else { return }
            Task { await wireIfReady() }
        }
        // V2 受管文件夹增删 → bridge sync。bridge 内部 registerAndScan / unregister 末尾
        // 都跑 triggerDedupFullPass → onIndexChanged → refreshSelected，所以这里不再
        // 主动 refreshSelected，避免启动时 rootFolders 异步还原触发的"双 loading 闪屏"。
        .onChange(of: folderStore.rootFolders) { _, newRoots in
            guard let bridge = indexBridge else { return }
            let managed = folderStore.managedRootPaths
            Task { await bridge.sync(with: newRoots, managedRootPaths: managed) }
        }
        // V2 selection 互斥：smart folder 选中 → 清 V1；反之亦然
        // M4 任务 1 — 五态互斥扩展（V1 folder / 智能文件夹 / 临时结果 / 搜索 overlay / 重复清理总览）
        .onChange(of: folderStore.selectedFolder) { _, newFolder in
            if newFolder != nil {
                if smartFolderStore.selected != nil {
                    Task { await smartFolderStore.select(nil) }
                }
                showDuplicateOverview = false  // M4
                duplicateOverviewModel.closeFocusReview()  // V2 AB.4 五态互斥 closeFocusReview 兜底
            }
        }
        .onChange(of: smartFolderStore.selected) { _, newSF in
            if newSF != nil {
                if folderStore.selectedFolder != nil {
                    folderStore.selectedFolder = nil
                    folderStore.images = []
                    folderStore.selectedImageIndex = nil
                }
                showDuplicateOverview = false  // M4
                duplicateOverviewModel.closeFocusReview()  // V2 AB.4 五态互斥 closeFocusReview 兜底
            }
        }
        .onChange(of: showDuplicateOverview) { _, newValue in
            if newValue {
                // M4 任务 1 — 进入总览：清其它四态(V1 folder / 智能文件夹 / 临时结果 / 搜索 overlay)
                if smartFolderStore.selected != nil {
                    Task { await smartFolderStore.select(nil) }
                }
                folderStore.selectedFolder = nil
                folderStore.images = []
                folderStore.selectedImageIndex = nil
                currentEphemeral = nil
                showSearchOverlay = false  // M4：搜索 overlay 与总览互斥
                // M4 codex P1：取消 in-flight searchTask 防其完成后把 currentEphemeral 写回
                // 强行顶回主区（搜索 keystroke debounce 期间用户切走时的 race）
                searchTask?.cancel()
                searchTask = nil
                // 主动 trigger load —— load 唯一 owner(删 DuplicateOverviewView.onAppear 触发,
                // 避免与 model.scheduleReload 并发 stale-write)
                Task { await duplicateOverviewModel.load() }
            }
        }
        // M4 任务 2 — 撤销 banner 接线 (D33 跨视图持久).
        // codex P2(深比 BLOB): 比 id (UUID) 不比整 outcome; 同 id 不触发动画.
        // V2 重设计 (任务 AB) — prune 块全量扩展 (design v2 §3 codex P1 修复).
        // 重扫完总览 reload 后, 把不在新 groups 里的临时态 entry 全部 prune.
        .onChange(of: duplicateOverviewModel.groups) { _, newGroups in
            let validSha256s = Set(newGroups.map { $0.id })

            // prune skippedGroupIds (原 selectedSha256s, AB.2 改名后)
            let prunedSkipped = duplicateOverviewModel.skippedGroupIds.intersection(validSha256s)
            if prunedSkipped.count != duplicateOverviewModel.skippedGroupIds.count {
                duplicateOverviewModel.replaceSkippedGroupIds(prunedSkipped)
            }

            // prune userKeepIdByGroup — (groupId 仍在 validSha256s ∧ memberId 仍在 group.allMembers) 才保留
            let keepDict = duplicateOverviewModel.userKeepIdByGroup
            var prunedKeepIds: [String: Int64] = [:]
            for (groupId, memberId) in keepDict {
                guard validSha256s.contains(groupId),
                      let group = newGroups.first(where: { $0.id == groupId }),
                      group.allMembers.contains(where: { $0.id == memberId })
                else { continue }
                prunedKeepIds[groupId] = memberId
            }
            if prunedKeepIds.count != keepDict.count {
                // userKeepIdByGroup private(set): 通过 setUserKeep 逐条重建
                // 先清再重设 (prune 场景 entry 数量少, 可接受)
                for groupId in keepDict.keys where prunedKeepIds[groupId] == nil {
                    _ = groupId  // entry 已 prune, 不调 setUserKeep
                }
                // 把保留的 entry 写回: 已有 setUserKeep 会 unskip, 但 prune 场景 group 还在
                // 不改 skip 状态; 直接构造新 dict 需要内部访问; 改用 replaceUserKeepIds (新增 API)
                duplicateOverviewModel.replaceUserKeepIds(prunedKeepIds)
            }

            // prune reviewedGroupIds / expandedGroupIds — 组不在新 groups 就移除
            let prunedReviewed = duplicateOverviewModel.reviewedGroupIds.intersection(validSha256s)
            if prunedReviewed.count != duplicateOverviewModel.reviewedGroupIds.count {
                duplicateOverviewModel.replaceReviewedGroupIds(prunedReviewed)
            }
            let prunedExpanded = duplicateOverviewModel.expandedGroupIds.intersection(validSha256s)
            if prunedExpanded.count != duplicateOverviewModel.expandedGroupIds.count {
                duplicateOverviewModel.replaceExpandedGroupIds(prunedExpanded)
            }

            // 浮层 stale: focusReviewOpen 时, queue 重算 + 当前组失效自动推进 / 关 (任务 E).
            if duplicateOverviewModel.focusReviewOpen {
                duplicateOverviewModel.recomputeFocusReviewAfterReload(newGroups: newGroups)
            }
        }
        .onChange(of: duplicateOverviewModel.lastTrashOutcome?.id) { _, _ in
            guard let event = duplicateOverviewModel.lastTrashOutcome else { return }
            // 显示条件: trash 阶段成功 ≥1 或 undo 阶段 (无论成败都要 surface)
            let trashHasContent = event.undoResult == nil && event.trash.successCount > 0
            let undoHasContent = event.undoResult != nil
            guard trashHasContent || undoHasContent else { return }
            trashUndoBanner = event
            // 取消上一次 timer (若 banner 接连出现)
            bannerDismissTask?.cancel()
            bannerDismissTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(DS.Dedup.bannerAutoDismissSeconds * 1_000_000_000))
                if !Task.isCancelled {
                    await MainActor.run { trashUndoBanner = nil }
                }
            }
        }
        // D15 终态：删除原 ContentView 兜底 ESC 状态机。子 view 各自持 ESC handler
        // （preview / ephemeral），共享 @FocusState 单仲裁者保证焦点可靠，race 消除。
        // D-OW16：WindowAccessor 已移除，NSWindow 挂接改由 MainWindowController 自任 delegate 接管。
        // D-mb-9.1 — 菜单栏「查找…」trigger event: dropFirst 跳过初始 UUID, 仅响应 requestOpen() 触发的换新.
        .onReceive(searchOverlayState.$triggerToken.dropFirst()) { _ in
            openSearch()
        }
        // D-mb-9.1 — Inspector 双向 sync: ContentView showInspector 改 → InspectorState.isShown 同步; guard 避免循环.
        .onChange(of: showInspector) { _, newValue in
            if inspectorState.isShown != newValue {
                inspectorState.isShown = newValue
            }
        }
        .onChange(of: inspectorState.isShown) { _, newValue in
            // InspectorState.isShown 改(菜单栏触发) → showInspector 同步; guard 避免循环.
            if showInspector != newValue {
                showInspector = newValue
            }
        }
        // 重复清理 V2 任务 D.1 — 逐组审阅浮层焦点仲裁 (D-dedup-15).
        // 浮层打开: 记录打开前焦点 → 切到 .dedupOverlay；浮层关闭: 还原之前焦点.
        .onChange(of: duplicateOverviewModel.focusReviewOpen) { _, isOpen in
            if isOpen {
                previousAppFocus = focusTarget
                focusTarget = .dedupOverlay
            } else {
                focusTarget = previousAppFocus ?? .grid
                previousAppFocus = nil
            }
        }
    }

    // MARK: - Main Content

    /// 主区 = baseGrid（V1 ImageGridView 或 V2 SmartFolderGridView，互斥）+ previewOverlay
    /// （共享给两种 grid 模式，selectedImageIndex 非 nil 时 fade in）。
    /// V1 / V2 共享同一个 ImagePreviewView + folderStore.images 数组：
    /// - V1 模式：V1 selectFolder 把 folder 内图 URL 灌进 folderStore.images
    /// - V2 模式：cell 单击/双击时 populateImagesFromV2() 从 queryResult 重建 URL 灌进
    @ViewBuilder
    private var mainContent: some View {
        ZStack(alignment: .top) {
            if showDuplicateOverview {
                // V2 重设计 (任务 AB) — 新 DedupCleanupV2View 替代旧 DuplicateOverviewView
                DedupCleanupV2View()
            } else if let req = currentEphemeral {
                EphemeralResultView(
                    title: req.title,
                    urls: req.urls,
                    bannerText: req.banner,
                    emptyStateText: req.emptyStateText,
                    showTimeBuckets: req.showTimeBuckets,
                    datesForBuckets: req.datesForBuckets,
                    autoFocusOnAppear: req.autoFocusOnAppear,
                    defaultHighlightFirst: req.defaultHighlightFirst,
                    onClose: {
                        switch req {
                        case .similar:
                            withAnimation(DS.Anim.normal) { currentEphemeral = nil }
                            // 清 selectedImageIndex 防止 ephemeral 关闭后 preview 残留重现
                            folderStore.selectedImageIndex = nil
                            // baseGrid 即将 swap in，下一帧其 onAppear 会 set .grid；这里显式
                            // 写一笔避免依赖 onAppear 时序，多次设同值 SwiftUI 自动 dedupe
                            focusTarget = .grid
                        case .search:
                            // M3 Slice M：search ephemeral 由 closeSearch 同时 cancel task / 收 overlay / 切焦点
                            closeSearch()
                        }
                    },
                    onSingleClick: { idx in
                        // 类似图结果单击 → 进 preview（v2Urls 路径，复用 V2 mode）；
                        // previewOverlay 现在挂在 ZStack 外层（修复 1），ephemeral 上方 fade in
                        v2Urls = req.urls
                        folderStore.selectedImageIndex = idx
                    },
                    onDoubleClick: { idx in
                        v2Urls = req.urls
                        folderStore.selectedImageIndex = nil
                        // 用 .ephemeral provenance，QV 关闭时回 ephemeral（D8 amendment 分层 modal 模型）
                        presentQuickViewer(images: req.urls, startIndex: idx, entry: .ephemeral)
                    },
                    focusTarget: $focusTarget
                )
            } else {
                baseGrid
            }
            // previewOverlay 始终渲染（ephemeral 模式也用 → ephemeral 单击进 preview 才看得见）
            previewOverlay
            VStack(spacing: DS.Spacing.xs) {
                // Slice I.1 — 扫描进度 chip overlay（仅 V2 mode 扫描进行中显示，扫完自动消失）
                if let progress = indexStoreHolder.progress {
                    IndexingProgressView(progress: progress, onCancel: {
                        indexStoreHolder.cancelCurrentScan?()
                    })
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                // M2 Slice J — feature print 索引进度 chip（紫色调区分扫描 chip）
                if let fpProgress = indexStoreHolder.featurePrintProgress {
                    FeaturePrintProgressView(progress: fpProgress, onCancel: {
                        indexStoreHolder.cancelFeaturePrintIndexing?()
                    })
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                // Slice I.2 — 错误 banner（扫描失败 / dedup 失败 → holder.lastError 非 nil）
                if let err = indexStoreHolder.lastError {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(DS.Color.errorAccent)
                        Text(err)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Spacer(minLength: DS.Spacing.xs)
                        Button {
                            indexStoreHolder.lastError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(DS.Color.secondaryText)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(.thickMaterial, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(
                            DS.Color.errorAccent.opacity(DS.IndexingProgress.errorBorderOpacity),
                            lineWidth: DS.SectionHeader.chipBorderWidth
                        )
                    )
                    .padding(.horizontal, DS.Spacing.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.top, DS.Spacing.sm)
            // M3 Slice M — search overlay top z-index（QV > search > preview > ephemeral > baseGrid）
            if showSearchOverlay {
                SearchOverlayView(
                    focusTarget: $focusTarget,
                    onInputChange: { input, skipDebounce in
                        runSearch(keyword: input, filterState: searchFilterState, skipDebounce: skipDebounce)
                    },
                    onClose: { closeSearch() },
                    onSubmit: { submitSearch(input: $0) },
                    filterState: $searchFilterState,
                    onChipChange: { keyword in
                        runSearch(keyword: keyword, filterState: searchFilterState, skipDebounce: true)
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .frame(maxWidth: .infinity, alignment: .center)
                .zIndex(100)
            }
            // 重复清理 V2 任务 D.2 — 逐组审阅浮层（D6: ZStack overlay + ultraThinMaterial，非 .sheet）.
            // 任务 E — 进出动画 + trashing 期 disabled + reload stale 推进.
            // zIndex 高于 search overlay (100) → modal 层顺序: QV > dedupOverlay > search > ...
            if duplicateOverviewModel.focusReviewOpen {
                let isTrashing: Bool = {
                    if case .trashing = duplicateOverviewModel.trashState { return true }
                    return false
                }()
                DedupFocusReviewOverlay(focusTarget: $focusTarget)
                    .environmentObject(duplicateOverviewModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .allowsHitTesting(!isTrashing)
                    .opacity(isTrashing ? 0.5 : 1.0)
                    .zIndex(200)
            }
        }
        .animation(DS.Anim.fast, value: indexStoreHolder.progress)
        .animation(DS.Anim.fast, value: indexStoreHolder.lastError)
        .animation(DS.Anim.fast, value: indexStoreHolder.featurePrintProgress)
        .animation(DS.Anim.normal, value: showSearchOverlay)
        .animation(.easeOut(duration: DS.Dedup.focusOverlayInTransitionDuration), value: duplicateOverviewModel.focusReviewOpen)
    }

    @ViewBuilder
    private var baseGrid: some View {
        if smartFolderStore.selected != nil {
            SmartFolderGridView(
                onSingleClick: { idx in
                    v2Urls = computeV2Urls()
                    folderStore.selectedImageIndex = idx
                },
                onDoubleClick: { idx in
                    let urls = computeV2Urls()
                    v2Urls = urls
                    // 双击时单击 handler 也会触发并设置 selectedImageIndex，此处清除，确保 QuickViewer
                    // 关闭后回到列表页而非预览页（同 V1 ImageGridView onDoubleClick 逻辑）
                    folderStore.selectedImageIndex = nil
                    presentQuickViewer(images: urls, startIndex: idx, entry: .grid)
                },
                focusTarget: $focusTarget
            )
        } else {
            // V1 ImageGridView 始终保留在层级里，避免返回时缩略图全部重载
            ImageGridView(
                focusTarget: $focusTarget,
                onDoubleClick: { index in
                    folderStore.selectedImageIndex = nil
                    presentQuickViewer(images: folderStore.images, startIndex: index, entry: .grid)
                }
            )
        }
    }

    @ViewBuilder
    private var previewOverlay: some View {
        // 收紧渲染条件：QV 期间 (qvController.isPresenting) 不渲染 ImagePreviewView，
        // 避免 QV 内方向键写 selectedImageIndex 时 preview 在后台 loadImage
        if let idx = folderStore.selectedImageIndex, !qvController.isPresenting {
            ImagePreviewView(
                vm: previewVM,
                images: (currentEphemeral != nil || smartFolderStore.selected != nil) ? v2Urls : folderStore.images,
                startIndex: idx,
                focusTarget: $focusTarget,
                onDismiss: {
                    folderStore.selectedImageIndex = nil
                },
                onQuickView: { index in
                    presentQuickViewer(
                        images: (currentEphemeral != nil || smartFolderStore.selected != nil) ? v2Urls : folderStore.images,
                        startIndex: index,
                        entry: .preview
                    )
                }
            )
            // D15 refactor 后删 .id(idx)：rebuild 会让 .focused($focusTarget, equals: .preview)
            // 在 binding 已 = .preview 时不 transition → 第二次方向键失焦（codex:rescue 验证：
            // 时序层 race，非"same-value dedupe"机制）。ImagePreviewView 已有
            // onChange(of: startIndex) → currentIndex/loadImage 自反应（行 136-138），不依赖 .id 重建。
            .transition(.asymmetric(
                insertion: .scale(scale: 0.97).combined(with: .opacity),
                removal:   .scale(scale: 0.97).combined(with: .opacity)
            ))
        }
    }

    /// 把当前 SmartFolderStore.queryResult 转成 V1 风格的 URL 数组（snapshot 在 cell 单击/
    /// 双击时计算），让 ImagePreviewView / QuickViewerOverlay 两条 V1 通路复用。
    /// URL = resolve(image.urlBookmark = root bookmark) + appendingPathComponent(relative_path)。
    /// 子 URL 通过 V1 BookmarkManager 已 startAccessing 的 root scope 隐式访问，NSImage /
    /// CGImageSourceCreateWithURL 都能读。**返回数组而非写入 folderStore.images**，避免触发
    /// `.onChange(of: folderStore.images)` 的保护性 close-QV 逻辑（那条是给 V1 排序场景设的）。
    private func computeV2Urls() -> [URL] {
        smartFolderStore.queryResult.compactMap { image in
            var stale = false
            guard let rootURL = try? URL(
                resolvingBookmarkData: image.urlBookmark,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &stale
            ) else { return nil }
            return rootURL.appendingPathComponent(image.relativePath)
        }
    }

    // MARK: - QuickViewer present / dismiss（独立 NSWindow 入口 + 退出仲裁）

    /// 统一进 QV 入口：所有 grid / preview / ephemeral 双击都经此打开独立 QV 窗。
    /// images 由 caller 计算好传入（V1 folderStore.images / V2 v2Urls），与原 overlay 取源一致。
    private func presentQuickViewer(images: [URL], startIndex: Int, entry: QuickViewerEntry) {
        guard let mainWindow = appState.window else { return }
        qvController.show(
            images: images,
            startIndex: startIndex,
            entry: entry,
            mainWindow: mainWindow,
            currentSupportsFeaturePrint: currentSupportsFeaturePrint(at: startIndex),
            // QV 内 nav button / filmstrip / 方向键切图上报 → 写 selectedImageIndex，
            // ESC 退出后 grid highlight / preview 都跟到当前位（同原 overlay onIndexChange）。
            onIndexChange: { folderStore.selectedImageIndex = $0 },
            // 同步清非焦点状态（windowWillClose 第 0 步，isPresenting 翻 false 之前）：
            // 防 previewOverlay 用 stale selectedImageIndex remount 显旧图。focusTarget 设置仍留
            // 延迟的 onDismiss（需主 hosting become key）。
            onPrepareDismiss: { reason, entry in
                switch reason {
                case .normal:
                    // grid / ephemeral 退出不回 preview → 清；preview 退出要回 preview → 保留 selectedImageIndex。
                    if entry == .grid || entry == .ephemeral { folderStore.selectedImageIndex = nil }
                case .findSimilar, .commandF:
                    folderStore.selectedImageIndex = nil
                }
            },
            onDismiss: { reason, entry in handleQVDismiss(reason: reason, entry: entry) },
            // 任务 C.11 — 单张删除入口：Overlay 按 Delete/⌘⌫/右键废纸篓时回调，转给 Coordinator
            onTrash: { [quickViewerTrashCoordinator] url in
                await quickViewerTrashCoordinator.trash(url: url)
            },
            // 任务 C.11 — toast「撤销」按钮触发，转给 Coordinator.restore
            onUndoTrash: { [quickViewerTrashCoordinator] outcome in
                _ = await quickViewerTrashCoordinator.restore(outcome: outcome)
            }
        )
    }

    /// QV 退出仲裁（迁自原 .onChange(of: quickViewerIndex) 路由）。
    /// controller 在主窗重新 become key 后回调，此时设 focusTarget 才生效。
    private func handleQVDismiss(reason: QVDismissalReason, entry: QuickViewerEntry) {
        switch reason {
        case .normal:
            // selectedImageIndex 的清理已移到 onPrepareDismiss 同步阶段（防 stale preview remount）。
            // 此处只设 focusTarget（延迟到主窗 become key 后才生效）。
            switch entry {
            case .grid:
                // 路径 1：双击 grid cell 进 QV → 退出回 grid（保 6da903c 行为）。
                focusTarget = .grid
            case .preview:
                // 路径 2：preview 进 QV → 退回 preview（selectedImageIndex 仍 = 当前位，onPrepareDismiss 不清）。
                focusTarget = .preview
            case .ephemeral:
                // 路径 3：EphemeralResultView 双击进 QV → 退回 ephemeral。
                focusTarget = .ephemeral
            }
        case .findSimilar(let url):
            // 原 .none 分支的"QV 内点找类似"路径：现由 controller close(.findSimilar) 显式表达，
            // handleFindSimilar 内部设 currentEphemeral + 清 selectedImageIndex（不再自关 QV）。
            handleFindSimilar(sourceUrl: url)
        case .commandF:
            // 原 ⌘F-from-QV 路径：QV 已由 controller close(.commandF) 关闭，openSearch 浮 overlay。
            openSearch()
        }
    }

    // MARK: - V2 Wire-up

    /// 幂等 wire-up：IndexStore ready 后初始化 engine + bridge + 默认选中"全部最近"。
    /// 同时被 .onAppear 和 .onChange(of: indexStoreHolder.isReady) 调，
    /// didWire flag 守卫防重入；任何一条到达都成功 — race 消除。
    private func wireIfReady() async {
        guard !didWire, let store = indexStoreHolder.store else { return }
        didWire = true

        let engine = SmartFolderEngine(store: store)
        smartFolderStore.attach(engine: engine)
        let bridge = FolderStoreIndexBridge(indexStore: store)
        // M4 任务 1 — 把 indexStore + bridge 装配给 dup overview model(mirror smartFolderStore.attach)
        // 顺序：dup.attach 在 smartFolder observer 注册之前(多播容器无顺序依赖,按 plan 顺序方便阅读)
        // M4 任务 2 收尾 — attach 扩展 3 个新依赖 (步骤 A.5).
        duplicateOverviewModel.attach(
            indexStore: store,
            bridge: bridge,
            bookmarkManager: bookmarkManager,
            folderStore: folderStore,
            migrationCoordinator: migrationCoordinator
        )
        // M4 D35 — bridge.onIndexChanged 单播 var 升级为 indexChangedObservers UUID dict
        // 多播容器（M4 task 1 prerequisite）。smartFolder observer 是历史第一注册者，
        // DuplicateOverviewModel 是上方刚注册的第二 observer。
        // token 寿命：当前 wireIfReady 由 didWire 标志保证只 wire 一次，bridge 由
        // @State indexBridge 持有寿命跟 ContentView 一致，smartFolder observer
        // 永远在线即合理 → 暂忽略 token。未来若 ContentView 重建场景出现需要 detach，
        // 再加 token 持久化到 @State 并按 token 调 bridge.removeIndexChangedObserver。
        let storeRef = smartFolderStore  // class 引用 capture 安全
        let smartFolderObserverToken = bridge.addIndexChangedObserver {
            Task { await storeRef.refreshSelected() }
        }
        _ = smartFolderObserverToken
        // Slice I.1 — 扫描进度推到 IndexStoreHolder 让 ContentView overlay 显示
        let holderRef = indexStoreHolder
        bridge.onScanProgress = { progress in
            holderRef.progress = progress
        }
        // Slice I.2 — 扫描错误回调 → holder.lastError → ContentView banner
        bridge.onScanError = { msg in
            holderRef.lastError = msg
        }
        // Slice I.2 — holder.cancelCurrentScan 转发给 bridge（progress chip X 按钮点击时调）
        let bridgeRef = bridge
        holderRef.cancelCurrentScan = {
            bridgeRef.cancelCurrentScan()
        }
        indexBridge = bridge
        // 任务 C.11 — 装配 QV 单张删除 Coordinator (三依赖注入, schema gate 在 Coordinator 入口)
        quickViewerTrashCoordinator.attach(
            indexStore: store,
            bridge: bridge,
            bookmarkManager: bookmarkManager
        )
        await bridge.sync(with: folderStore.rootFolders, managedRootPaths: folderStore.managedRootPaths)

        // M4 任务 1 — wireIfReady race 补偿：用户在 indexStoreHolder ready 前点了「重复清理」入口。
        // 必须先判断再决定是否 select allRecent：select() 触发 .onChange(smartFolderStore.selected)
        // 里的 showDuplicateOverview = false，先 select 再判断的话补偿条件永远为 false。
        if showDuplicateOverview {
            await duplicateOverviewModel.load()
        } else if smartFolderStore.selected == nil {
            await smartFolderStore.select(BuiltInSmartFolders.allRecent)
        } else {
            await smartFolderStore.refreshSelected()
        }

        // K.1 — Vision revision 迁移：启动期对比已存 fp 的 revision vs 当前 Vision revision，
        // 不一致 row 清回 NULL 让 indexer 自然重抽。macOS 升级触发；通常 0 row 受影响秒级返回。
        let currentRev = SimilarityService.currentRevision
        let holderRefRev = indexStoreHolder
        do {
            let resetCount = try store.resetFeaturePrintsWithStaleRevision(currentRevision: currentRev)
            if resetCount > 0 {
                holderRefRev.lastError = "ℹ️ Vision 模型已更新，正在重新索引 \(resetCount) 张图片的相似特征"
            }
        } catch {
            // 不阻塞主索引器启动；revision migration 失败 = 用户继续用老 fp（结果可能略偏）
            holderRefRev.lastError = "相似特征版本迁移失败，可继续使用但 macOS 升级后结果可能不准确：\(error.localizedDescription)"
        }

        // M2 Slice J — feature print indexer 启动 + 回调挂载
        let indexer = FeaturePrintIndexer(store: store)
        let holderRef2 = indexStoreHolder  // shadow capture（指针不变 capture 安全）
        indexer.onProgress = { progress in
            holderRef2.featurePrintProgress = progress
        }
        indexer.onError = { msg in
            holderRef2.lastError = msg
        }
        holderRef2.featurePrintIndexer = indexer
        holderRef2.cancelFeaturePrintIndexing = { [weak indexer] in
            indexer?.cancel()
        }
        bridge.setFeaturePrintIndexer(indexer)
        indexer.start()
    }

    // MARK: - M2 Slice J — Similarity query

    /// M2 Slice J — 触发"找类似"：源 URL → IndexStore 反查 fp → SimilarityService 算 top-30
    /// → fetch URLs → 切 EphemeralResultView。
    /// D14：feature print 全库未抽完 → banner 提示已索引 X / Y。
    private func handleFindSimilar(sourceUrl: URL) {
        guard let store = indexStoreHolder.store else { return }
        let holderRef = indexStoreHolder
        Task {
            // 1. 反查源图 fp
            guard let (sourceId, sourceArchive) = try? store.fetchFeaturePrintByFullPath(sourceUrl.path) else {
                await MainActor.run {
                    holderRef.lastError = "「\(sourceUrl.lastPathComponent)」尚未索引或不支持类似图查找"
                }
                return
            }
            // 2. 反序列化源 observation
            guard let sourceObs = try? SimilarityService.unarchive(sourceArchive) else {
                await MainActor.run {
                    holderRef.lastError = "源图特征向量损坏，请稍后重试"
                }
                return
            }
            // 3. 拉所有候选 fp（D14: 部分库 ok）
            guard let candidates = try? store.fetchAllFeaturePrintsForCosine() else {
                await MainActor.run {
                    holderRef.lastError = "类似图查找数据库读取失败"
                }
                return
            }
            // 4. cosine top-30 (D13)
            let topN = SimilarityService.queryTopN(
                source: sourceObs,
                candidates: candidates,
                excludingId: sourceId,
                n: DS.Similarity.topNResults
            )
            let topIds = topN.map { $0.id }
            // 5. ids → URLs
            let urls = (try? store.fetchUrlsByIds(topIds)) ?? []

            // 6. D14 banner：检查 fp 索引覆盖率
            let banner = ContentView.computeBanner(
                store: store,
                indexedCount: candidates.count
            )

            await MainActor.run {
                // M4 codex P1：查询期间用户已切到重复清理总览，丢弃结果，不强行踢回找相似区
                guard !showDuplicateOverview else { return }
                self.currentEphemeral = .similar(sourceUrl: sourceUrl, results: urls, banner: banner)
                // 修复 2：清 selectedImageIndex 防止 QV 关闭后 previewOverlay 渲染条件成立，
                // preview 弹回压在 ephemeral 上方（Scenario 1 根因）。
                // QV 已由 controller close(.findSimilar) 关闭（本函数经 onDismiss 触发），不再自关。
                self.folderStore.selectedImageIndex = nil
            }
        }
    }

    /// 算 D14 部分库 banner 字符串。100% 覆盖 → nil；否则返回提示。
    private static func computeBanner(store: IndexStore, indexedCount: Int) -> String? {
        let total = (try? store.sync { db -> Int in
            let stmt = try db.prepare("SELECT COUNT(*) FROM images WHERE supports_feature_print = 1;")
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }) ?? 0
        guard total > 0 else { return nil }
        if indexedCount >= total { return nil }
        return "已索引 \(indexedCount) / \(total) 张，结果为部分库"
    }

    /// M2 Slice J — 查 idx 处图片的 supports_feature_print。读不到（idx 越界 / 行不存在）→ true 默认（不主动 disable，让用户点了再失败提示）。
    private func currentSupportsFeaturePrint(at idx: Int) -> Bool {
        let images = (currentEphemeral != nil || smartFolderStore.selected != nil) ? v2Urls : folderStore.images
        guard idx < images.count, let store = indexStoreHolder.store else { return true }
        let url = images[idx]
        return (try? store.sync { db -> Bool in
            let stmt = try db.prepare("""
                SELECT i.supports_feature_print FROM images i
                JOIN folders f ON i.folder_id = f.id
                WHERE f.root_path || '/' || i.relative_path = ? LIMIT 1;
            """)
            defer { sqlite3_finalize(stmt) }
            _ = sqlite3_bind_text(stmt, 1, (url.path as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            guard sqlite3_step(stmt) == SQLITE_ROW else { return true }
            return sqlite3_column_int(stmt, 0) == 1
        }) ?? true
    }

    // MARK: - M3 Slice M — Search

    /// ⌘F 入口。从任意 layer（baseGrid / preview / ephemeral / QV）触发。
    private func openSearch() {
        // QV 内按 ⌘F 走 controller close(.commandF) → onDismiss → 本函数（QV 已关），
        // body / preview / ephemeral 入口 QV 本不在场，故此处不再处理关 QV。
        // ⌘F-from-preview：无条件清 selectedImageIndex 关掉在途 preview，否则其图源会被下方
        // `currentEphemeral != nil` 条件误切到 stale v2Urls（codex 二审 Q3，必须无条件、不能嵌 if）。
        folderStore.selectedImageIndex = nil
        showSearchOverlay = true
        showDuplicateOverview = false  // M4：开搜索 overlay 时清重复清理总览态
        duplicateOverviewModel.closeFocusReview()  // V2 AB.4 五态互斥 closeFocusReview 兜底
        // 初始化空 query 的 ephemeral 让 EphemeralResultView 显示 hint 空态文案
        currentEphemeral = .search(query: "", images: [], urls: [])
        searchFilterState = SearchFilterState()   // D27：进入即空白
        // 焦点延迟一拍设（codex review Q1）：overlay + 空 ephemeral 同帧 mount，TextField 这帧
        // 还没进 view tree，同帧设 @FocusState 失效；ephemeral 现在 autoFocusOnAppear=false 不竞争，
        // 延迟到下一 runloop 由本函数单点设。每次 ⌘F 都跑，覆盖重复 ⌘F（overlay 已 mount，onAppear 不再 fire）场景。
        Task { @MainActor in
            await Task.yield()
            focusTarget = .search
        }
    }

    /// ESC / × button 关闭路径。清 currentEphemeral 让 baseGrid 回来。
    private func closeSearch() {
        searchTask?.cancel()
        searchTask = nil
        withAnimation(DS.Anim.normal) {
            showSearchOverlay = false
            currentEphemeral = nil
        }
        searchFilterState = SearchFilterState()   // D27：清空
        folderStore.selectedImageIndex = nil
        focusTarget = .grid
    }

    /// 回车提交（Enter 路径）：收起 overlay + 结果留为 ephemeral + 焦点移结果网格。
    private func submitSearch(input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !(trimmed.isEmpty && searchFilterState.isEmpty) else { return }   // codex：chip-only Enter 也生效
        runSearch(keyword: input, filterState: searchFilterState, skipDebounce: true)
        withAnimation(DS.Anim.normal) { showSearchOverlay = false }
        focusTarget = .ephemeral
    }

    /// chips + keyword 合并查询。chip 点选 skipDebounce=true 即时；keyword onChange debounce。
    private func runSearch(keyword: String, filterState: SearchFilterState, skipDebounce: Bool) {
        searchTask?.cancel()
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        // codex 修正：chip-only（keyword 空但有 chip）不能被挡，条件改双空。
        guard !(trimmed.isEmpty && filterState.isEmpty) else {
            currentEphemeral = .search(query: "", images: [], urls: [])
            return
        }
        guard let store = indexStoreHolder.store else { return }
        // 一致快照：debounce 期间 chip tap 可能改 filterState（codex R3）。
        let snapKeyword = keyword
        let snapFilter = filterState
        let snapNow = Date()
        searchTask = Task.detached(priority: .userInitiated) {
            if !skipDebounce {
                try? await Task.sleep(for: .milliseconds(DS.Search.debounceMs))
                guard !Task.isCancelled else { return }
            }
            let predicate = SearchService.compile(filterState: snapFilter, keyword: snapKeyword, now: snapNow)
            let folder = SmartFolder(id: "ephemeral-search", displayName: "搜索",
                                     predicate: predicate, sortBy: .birthTime, sortDescending: true, isBuiltIn: false)
            let images: [IndexedImage]
            do {
                let compiled = try SmartFolderQueryBuilder.compile(folder, now: snapNow)
                images = try store.fetch(compiled, limit: nil)
            } catch {
                await MainActor.run { indexStoreHolder.lastError = "搜索失败：\(error.localizedDescription)" }
                return
            }
            guard !Task.isCancelled else { return }
            let resolvedPairs: [(IndexedImage, URL)] = images.compactMap { img in
                var stale = false
                guard let rootURL = try? URL(resolvingBookmarkData: img.urlBookmark,
                                             options: [.withSecurityScope], bookmarkDataIsStale: &stale) else { return nil }
                return (img, rootURL.appendingPathComponent(img.relativePath))
            }
            let resolvedImages = resolvedPairs.map { $0.0 }
            let urls = resolvedPairs.map { $0.1 }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                // query 文案：keyword 优先，否则示意 chip 生效
                let q = snapKeyword.isEmpty ? "筛选" : snapKeyword
                self.currentEphemeral = .search(query: q, images: resolvedImages, urls: urls)
            }
        }
    }

    // MARK: - Slice D — hide toggle 路由（ContentView 拼桥：sidebar URL → IndexStore id+relativePath）

    /// 把 V1 (rootURL, nodeURL) 翻译成 IndexStore 的 (rootId, relativePath)。
    /// nodeURL == rootURL → root 节点，relativePath = ""；否则 nodeURL.path 去掉 rootURL.path 前缀。
    private func resolveFolderCoord(rootURL: URL, nodeURL: URL) -> (rootId: Int64, relativePath: String)? {
        guard let store = indexStoreHolder.store else { return nil }
        let rootPath = rootURL.standardizedFileURL.path
        let nodePath = nodeURL.standardizedFileURL.path
        guard let rootId = try? store.folderIdForRootPath(rootPath) else { return nil }

        if rootPath == nodePath {
            return (rootId, "")
        }
        let prefix = rootPath + "/"
        guard nodePath.hasPrefix(prefix) else { return nil }
        let relativePath = String(nodePath.dropFirst(prefix.count))
        return (rootId, relativePath)
    }

    private func toggleHide(rootURL: URL, nodeURL: URL) {
        guard let store = indexStoreHolder.store,
              let coord = resolveFolderCoord(rootURL: rootURL, nodeURL: nodeURL) else { return }
        let currentlyHidden = (try? store.effectiveHidden(rootId: coord.rootId, relativePath: coord.relativePath)) ?? false
        let target = !currentlyHidden
        do {
            if coord.relativePath.isEmpty {
                try store.setRootHidden(rootId: coord.rootId, hidden: target)
            } else {
                try store.upsertSubfolderHide(rootId: coord.rootId, relativePath: coord.relativePath, hidden: target)
            }
        } catch {
            print("[Slice D] toggleHide FAILED: \(error)")
            return
        }
        Task { await smartFolderStore.refreshSelected() }
    }

    private func effectivelyHidden(rootURL: URL, nodeURL: URL) -> Bool {
        guard let store = indexStoreHolder.store,
              let coord = resolveFolderCoord(rootURL: rootURL, nodeURL: nodeURL) else { return false }
        return (try? store.effectiveHidden(rootId: coord.rootId, relativePath: coord.relativePath)) ?? false
    }

    /// 仅当 row 自己显式 hide=1 才返 true（不含继承）。给 sidebar 决定显 eye.slash 图标。
    private func explicitlyHidden(rootURL: URL, nodeURL: URL) -> Bool {
        guard let store = indexStoreHolder.store,
              let coord = resolveFolderCoord(rootURL: rootURL, nodeURL: nodeURL) else { return false }
        return (try? store.isExplicitlyHidden(rootId: coord.rootId, relativePath: coord.relativePath)) ?? false
    }
}

#Preview {
    ContentView()
        .environmentObject(FolderStore(bookmarkManager: BookmarkManager()))
        .environmentObject(AppState())
        .environmentObject(IndexStoreHolder())
}
