//
//  ContentView.swift
//  ISeeImageViewer
//

import SwiftUI
import SQLite3
import AppKit

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
}

// QV 入口来源：用 enum 而非裸 Bool/Optional 让 dismiss 路由按 provenance 走，不依赖
// selectedImageIndex 是否 nil 当哨兵 — 这样 QV 方向键写 selectedImageIndex 同步 grid
// highlight + preview 时不会反向破坏 6da903c 修过的"双击 cell 进 QV 后退出回 grid 不进 preview"
private enum QuickViewerEntry {
    case grid       // 路径 1: grid 双击 cell 直接进 QV
    case preview    // 路径 2: grid → preview → 双击 → QV
    case ephemeral  // 路径 3 (M2 Slice J): EphemeralResultView 双击 cell 进 QV → 退出直接回 baseGrid，不卡在 ephemeral 无焦点态
    case externalOpen  // 路径 5 (OpenWith): Finder「打开方式」进 QV → 退出回 app 之前状态，清 externalOpenUrls
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
}

struct ContentView: View {
    @EnvironmentObject var folderStore: FolderStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var indexStoreHolder: IndexStoreHolder
    @StateObject private var smartFolderStore = SmartFolderStore.placeholder()
    @State private var indexBridge: FolderStoreIndexBridge?
    @State private var didWire: Bool = false
    /// V2 mode 下 preview / QuickViewer 的图片源（cell 单击/双击时从 queryResult 重建）。
    /// 不复用 folderStore.images，避免触发 .onChange(of: folderStore.images) 的保护性
    /// 关 QV 逻辑（那条 onChange 是给 V1 排序场景设计的）。
    @State private var v2Urls: [URL] = []
    /// OpenWith — Finder「打开方式」临时图源。non-nil 时 QV 图源走它（不碰 folderStore.images / IndexStore）。
    @State private var externalOpenUrls: [URL]? = nil
    /// OpenWith — AppDelegate→SwiftUI 桥，观察 pendingOpen 触发外部打开。
    @ObservedObject private var externalOpen = ExternalOpenCoordinator.shared
    /// OpenWith — warm 激活请求标记（非 nil = 有外部打开待把窗口带到前台）。窗口稳定 + 成功抢到 key 后清。
    @State private var externalOpenActivationRequest: UUID?
    /// 激活重试 task（窗口在单 Window scene 瞬态期可能 nil，需等 windowIdentity 变化重试）。
    @State private var externalOpenActivationTask: Task<Void, Never>?
    /// M2 Slice J — 类似图查找结果视图状态。non-nil 时主区域换 EphemeralResultView 替代 baseGrid。
    @State private var currentEphemeral: EphemeralRequest?
    @State private var showInspector = false
    @State private var quickViewerIndex: Int? = nil
    // QV 入口来源：onDoubleClick / onQuickView 设值，QV onDismiss 仲裁后清回 nil
    @State private var quickViewerEntry: QuickViewerEntry? = nil
    /// M3 Slice M — search overlay 显隐控制
    @State private var showSearchOverlay: Bool = false
    /// M3 Slice M — 当前搜索后台 Task（cancel 用，避免 stale 覆盖）
    @State private var searchTask: Task<Void, Never>? = nil
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
        let images = smartFolderStore.selected != nil ? v2Urls : folderStore.images
        guard let idx = folderStore.selectedImageIndex,
              idx < images.count else { return nil }
        return images[idx]
    }

    /// OpenWith — 外部打开图片：临时图源驱动 QuickViewer，不持久化、不进 IndexStore。
    private func handleExternalOpen(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        externalOpenUrls = urls
        quickViewerEntry = .externalOpen
        quickViewerIndex = 0
        externalOpen.pendingOpen = nil  // 消费掉，防重复触发
        // warm 场景：把窗口带到前台（cold 启动本就在前台，重试无害）。窗口可能正处于单 Window
        // scene 的瞬态 close/reopen，故走 windowIdentity 驱动的重试而非此处一次性 activate。
        externalOpenActivationRequest = UUID()
        scheduleActivation()
    }

    /// 启动一轮激活重试 task（取消上一轮）。窗口未就绪时轮询等 appState.window 非 nil。
    /// OpenWith warm 场景 best-effort 把窗口带到前台。
    /// ⚠️ 已知局限（backlog）：macOS 14 下 app 自己消费 Finder open 事件 + 单 Window scene 瞬态，
    /// 系统常拒绝该 app 抢前台，窗口会留在 Finder 之后（多种 activate API 实测均无法可靠置顶）。
    /// 此处尽力：NSRunningApplication.activate 请求激活，成则 makeKeyAndOrderFront；被拒则
    /// orderFrontRegardless 至少抬升窗口可见性。功能不受影响（QV 已显示），仅自动置顶不保证。
    private func scheduleActivation() {
        externalOpenActivationTask?.cancel()
        externalOpenActivationTask = Task { @MainActor in
            await Task.yield()  // 让出一拍，给 SwiftUI 完成 QV 状态写入 + 可能的窗口 reopen
            guard externalOpenActivationRequest != nil, let window = appState.window else { return }
            NSApp.unhide(nil)
            if window.isMiniaturized { window.deminiaturize(nil) }
            _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
            let becameActive = await waitForAppActivation(
                timeoutMilliseconds: DS.ExternalOpen.activationBecomeActiveTimeoutMilliseconds
            )
            guard externalOpenActivationRequest != nil else { return }
            if becameActive {
                window.makeKeyAndOrderFront(nil)
                if window.isKeyWindow { finalizeActivation() }
            } else {
                window.orderFrontRegardless()
                finalizeActivation()
            }
        }
    }

    /// 等 app 变 active（NSRunningApplication.activate 是请求式，不保证同步生效）。
    /// 已 active 立即返回；否则等 didBecomeActive 通知 vs 超时 race。
    private func waitForAppActivation(timeoutMilliseconds: Int64) async -> Bool {
        if NSApp.isActive { return true }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                    return true
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private func finalizeActivation() {
        externalOpenActivationRequest = nil
        externalOpenActivationTask?.cancel()
        externalOpenActivationTask = nil
    }

    /// OpenWith Slice 2 — 浏览外部打开图的所在文件夹。
    /// 父文件夹已添加（是某 root 或在某 root 子树下）→ 直接 selectFolder 浏览；
    /// 未添加 → NSOpenPanel 预定位父目录，用户选中授权后 addFolder（沙盒铁律：单文件
    /// 打开不含父目录权限，必须经 NSOpenPanel 主动授权）。两路径都清临时态 + 关 QV。
    private func handleBrowseFolder(_ imageURL: URL) {
        let parent = imageURL.deletingLastPathComponent()
        let alreadyManaged = folderStore.rootFolders.contains { root in
            parent == root.url || parent.path.hasPrefix(root.url.path + "/")
        }
        if alreadyManaged {
            folderStore.selectFolder(parent)
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = parent
            panel.prompt = "浏览此文件夹"
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            folderStore.addFolder(from: chosen)  // 持久化 bookmark + discoverTree + selectFolder
        }
        externalOpenUrls = nil
        quickViewerEntry = nil
        quickViewerIndex = nil
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                SmartFolderListView()
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
                    .allowsHitTesting(quickViewerIndex == nil)
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
        }
        // QuickViewerOverlay 用 .overlay 挂在 NavigationSplitView 上，确保铺满整个内容区
        .overlay {
            if let idx = quickViewerIndex {
                QuickViewerOverlay(
                    images: externalOpenUrls ?? (smartFolderStore.selected != nil ? v2Urls : folderStore.images),
                    startIndex: idx,
                    onDismiss: {
                        withAnimation(DS.Anim.normal) {
                            quickViewerIndex = nil
                        }
                        // 关闭后焦点路由迁移到 onChange(of: quickViewerIndex)，统一覆盖
                        // onDismiss + onChange(of: images) 强制关闭 两条路径
                    },
                    onIndexChange: { newIdx in
                        // QV 内 nav button / filmstrip / 方向键 任意路径切图都触发 viewModel.currentIndex 变 →
                        // QuickViewerOverlay 一处 onChange(of: viewModel.currentIndex) 上报这里
                        // → 写 selectedImageIndex → ImageGridView b44a175 onChange non-nil 分支自动同步 highlightedURL
                        // → ESC 退 QV 后 grid highlight (路径 1) / preview (路径 2) 都跟到 Z
                        folderStore.selectedImageIndex = newIdx
                    },
                    onFindSimilar: { sourceUrl in
                        handleFindSimilar(sourceUrl: sourceUrl)
                    },
                    currentSupportsFeaturePrint: currentSupportsFeaturePrint(at: idx),
                    onCommandF: { openSearch() },
                    // OpenWith Slice 2：仅外部打开场景显示「浏览所在文件夹」按钮（管理中文件夹 QV 内冗余）
                    onBrowseFolder: quickViewerEntry == .externalOpen ? { url in handleBrowseFolder(url) } : nil
                )
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
        .animation(DS.Anim.normal, value: quickViewerIndex)
        // OpenWith — AppDelegate 写 coordinator.pendingOpen 后 ContentView 已 mount 的运行期路径
        .onChange(of: externalOpen.pendingOpen) { _, newValue in
            if let urls = newValue { handleExternalOpen(urls) }
        }
        // OpenWith warm 激活：窗口 reopen（identity 变）后重试 activate；成功抢到 key 即收尾。
        // 窗口 reopen（identity 变）后重试激活；抢到 key 即收尾（best-effort，见 scheduleActivation 注释）。
        .onChange(of: appState.windowIdentity) { _, _ in
            guard externalOpenActivationRequest != nil else { return }
            scheduleActivation()
        }
        .onChange(of: appState.isWindowKey) { _, isKey in
            guard externalOpenActivationRequest != nil, isKey else { return }
            finalizeActivation()
        }
        // QuickViewer 关闭的真源出口：按 quickViewerEntry provenance 仲裁焦点路由，不依赖
        // selectedImageIndex 是否 nil 当哨兵 — 因为 QV 方向键已经在写 selectedImageIndex
        .onChange(of: quickViewerIndex) { oldValue, newValue in
            guard oldValue != nil, newValue == nil else { return }
            switch quickViewerEntry {
            case .grid:
                // 路径 1：双击 grid cell 进 QV → ESC 后回 grid（保 6da903c 行为）
                // QV 期间方向键写过的 selectedImageIndex 这里清回 nil 防止 preview 反弹 mount。
                folderStore.selectedImageIndex = nil
                focusTarget = .grid
            case .preview:
                // 路径 2：preview 进 QV → ESC 退回 preview（selectedImageIndex 仍 = Z，
                // ImagePreviewView 通过 onChange(of: startIndex) 自反应显示 Z）
                focusTarget = .preview
            case .ephemeral:
                // M2 Slice J 路径 3：EphemeralResultView 双击进 QV → ESC 退 QV 回 ephemeral
                // QV 期间方向键写过的 selectedImageIndex 这里清回 nil 防止 previewOverlay 反弹
                folderStore.selectedImageIndex = nil
                focusTarget = .ephemeral
            case .externalOpen:
                // 路径 5 (OpenWith)：清临时图源退回 app 之前状态；selectedImageIndex 清 nil
                // 防 baseGrid 反弹（QV 方向键写过），focus 回 grid（无内容时无害）
                externalOpenUrls = nil
                folderStore.selectedImageIndex = nil
                focusTarget = .grid
            case .none:
                // 路径 4（M2 Slice J）：handleFindSimilar 在 QV 内点找类似时主动清 entry，
                // QV 关闭走这里。currentEphemeral 已 set 时回 ephemeral，否则回 grid
                focusTarget = currentEphemeral != nil ? .ephemeral : .grid
            }
            quickViewerEntry = nil
        }
        // M3 Slice M：body 级 ⌘F → openSearch（QV 不在场景下生效；QV 在时焦点在 QV，
        // QV 自己的 .onKeyPress(F) 处理 ⌘F，分支调 onCommandF 走 ContentView.openSearch）
        .onKeyPress(.init("f"), phases: .down) { event in
            if event.modifiers.contains(.command) {
                openSearch()
                return .handled
            }
            return .ignored
        }
        .toolbar(quickViewerIndex != nil ? .hidden : .visible, for: .windowToolbar)
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
                // 否则回 baseGrid。quickViewerIndex == nil 保护避开 preview→QV 路径的 spurious fire
                // （那条路径走 .onChange(of: quickViewerIndex) 的 .preview 分支单独仲裁焦点）
                if quickViewerIndex == nil {
                    focusTarget = currentEphemeral != nil ? .ephemeral : .grid
                }
            }
        }
        // 排序导致 images 数组变化时，关闭 QuickViewer 防止旧索引错位
        .onChange(of: folderStore.images) { _, _ in
            if quickViewerIndex != nil {
                quickViewerIndex = nil
            }
            previewVM.clearCache()
        }
        // V2 wire-up：IndexStore async ready 后挂载 engine + bridge + 默认选中"全部最近"
        .onAppear {
            Task { await wireIfReady() }
            // OpenWith 冷启动兜底：app 启动时 application(_:open:) 可能已写 pendingOpen，
            // 但 ContentView 还没 mount → onChange 漏触发，onAppear 补一次消费。
            if let urls = externalOpen.pendingOpen { handleExternalOpen(urls) }
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
        .onChange(of: folderStore.selectedFolder) { _, newFolder in
            if newFolder != nil && smartFolderStore.selected != nil {
                Task { await smartFolderStore.select(nil) }
            }
        }
        .onChange(of: smartFolderStore.selected) { _, newSF in
            if newSF != nil && folderStore.selectedFolder != nil {
                folderStore.selectedFolder = nil
                folderStore.images = []
                folderStore.selectedImageIndex = nil
            }
        }
        // D15 终态：删除原 ContentView 兜底 ESC 状态机。子 view 各自持 ESC handler
        // （preview / ephemeral），共享 @FocusState 单仲裁者保证焦点可靠，race 消除。
        // D-OW16：WindowAccessor 已移除，NSWindow 挂接改由 MainWindowController 自任 delegate 接管。
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
            if let req = currentEphemeral {
                EphemeralResultView(
                    title: req.title,
                    urls: req.urls,
                    bannerText: req.banner,
                    emptyStateText: req.emptyStateText,
                    showTimeBuckets: req.showTimeBuckets,
                    datesForBuckets: req.datesForBuckets,
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
                        quickViewerEntry = .ephemeral
                        quickViewerIndex = idx
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
                        runSearch(input: input, skipDebounce: skipDebounce)
                    },
                    onClose: { closeSearch() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .frame(maxWidth: .infinity, alignment: .center)
                .zIndex(100)
            }
        }
        .animation(DS.Anim.fast, value: indexStoreHolder.progress)
        .animation(DS.Anim.fast, value: indexStoreHolder.lastError)
        .animation(DS.Anim.fast, value: indexStoreHolder.featurePrintProgress)
        .animation(DS.Anim.normal, value: showSearchOverlay)
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
                    v2Urls = computeV2Urls()
                    // 双击时单击 handler 也会触发并设置 selectedImageIndex，此处清除，确保 QuickViewer
                    // 关闭后回到列表页而非预览页（同 V1 ImageGridView onDoubleClick 逻辑）
                    folderStore.selectedImageIndex = nil
                    quickViewerEntry = .grid
                    quickViewerIndex = idx
                },
                focusTarget: $focusTarget
            )
        } else {
            // V1 ImageGridView 始终保留在层级里，避免返回时缩略图全部重载
            ImageGridView(
                focusTarget: $focusTarget,
                onDoubleClick: { index in
                    folderStore.selectedImageIndex = nil
                    quickViewerEntry = .grid
                    quickViewerIndex = index
                }
            )
        }
    }

    @ViewBuilder
    private var previewOverlay: some View {
        // 收紧渲染条件：QV 期间 (quickViewerIndex != nil) 不渲染 ImagePreviewView，
        // 避免 QV 内方向键写 selectedImageIndex 时 preview 在后台 loadImage
        if let idx = folderStore.selectedImageIndex, quickViewerIndex == nil {
            ImagePreviewView(
                vm: previewVM,
                images: smartFolderStore.selected != nil ? v2Urls : folderStore.images,
                startIndex: idx,
                focusTarget: $focusTarget,
                onDismiss: {
                    folderStore.selectedImageIndex = nil
                },
                onQuickView: { index in
                    quickViewerEntry = .preview
                    quickViewerIndex = index
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
        // Slice G.2 — FSEvents 派发的索引更新（add/remove/modify）触发 grid 重 query
        let storeRef = smartFolderStore  // class 引用 capture 安全
        bridge.onIndexChanged = {
            Task { await storeRef.refreshSelected() }
        }
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
        await bridge.sync(with: folderStore.rootFolders, managedRootPaths: folderStore.managedRootPaths)

        if smartFolderStore.selected == nil {
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
                self.currentEphemeral = .similar(sourceUrl: sourceUrl, results: urls, banner: banner)
                // 修复 2：清 selectedImageIndex 防止 QV 关闭后 previewOverlay 渲染条件成立，
                // preview 弹回压在 ephemeral 上方（Scenario 1 根因）
                self.folderStore.selectedImageIndex = nil
                // 修复 D：清 quickViewerEntry，让 QV close onChange 走 .none 分支不动 currentEphemeral
                // （否则若上一次 entry == .ephemeral，新设的 currentEphemeral 会被抹掉）
                self.quickViewerEntry = nil
                // 关闭 QV（让 ephemeral 视图占主区）
                self.quickViewerIndex = nil
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
        let images = smartFolderStore.selected != nil ? v2Urls : folderStore.images
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
        // 路径 1：QV 内按 ⌘F → 同帧关 QV + 浮 overlay（D16）。
        // 顺序：先清 entry 再清 quickViewerIndex，让 onChange(of: quickViewerIndex) 走 .none
        // 分支不动 currentEphemeral；随后我们覆写 focusTarget = .search 优先。
        if quickViewerIndex != nil {
            quickViewerEntry = nil
            quickViewerIndex = nil
        }
        showSearchOverlay = true
        // 初始化空 query 的 ephemeral 让 EphemeralResultView 显示 hint 空态文案
        currentEphemeral = .search(query: "", images: [], urls: [])
        focusTarget = .search
    }

    /// ESC / × button 关闭路径。清 currentEphemeral 让 baseGrid 回来。
    private func closeSearch() {
        searchTask?.cancel()
        searchTask = nil
        withAnimation(DS.Anim.normal) {
            showSearchOverlay = false
            currentEphemeral = nil
        }
        folderStore.selectedImageIndex = nil
        focusTarget = .grid
    }

    /// debounce + cancel + SearchService 调用。skipDebounce=true 跳 200ms timer（Enter 路径）。
    private func runSearch(input: String, skipDebounce: Bool) {
        searchTask?.cancel()
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // 空输入 → 立即 reset 到 hint 状态（不查 SQL）
        guard !trimmed.isEmpty else {
            currentEphemeral = .search(query: "", images: [], urls: [])
            return
        }

        guard let store = indexStoreHolder.store else { return }
        let holderRef = indexStoreHolder

        searchTask = Task.detached(priority: .userInitiated) {
            // ① debounce sleep
            if !skipDebounce {
                try? await Task.sleep(for: .milliseconds(DS.Search.debounceMs))
                guard !Task.isCancelled else { return }
            }

            // ② parse + compile + fetch
            let parsed = SearchService.parse(input)
            guard !parsed.isEmpty else { return }
            let predicate = SearchService.compile(parsed)
            let folder = SmartFolder(
                id: "ephemeral-search",
                displayName: "搜索",
                predicate: predicate,
                sortBy: .birthTime,
                sortDescending: true,
                isBuiltIn: false
            )
            let images: [IndexedImage]
            do {
                let compiled = try SmartFolderQueryBuilder.compile(folder, now: Date())
                images = try store.fetch(compiled, limit: nil)
            } catch {
                await MainActor.run {
                    holderRef.lastError = "搜索失败：\(error.localizedDescription)"
                }
                return
            }

            guard !Task.isCancelled else { return }

            // ③ resolve URL：images 跟 urls 必须 codomain 同构（同长度 + 同 idx 对齐），
            // 否则 EphemeralResultView 的 datesForBuckets.count == urls.count guard 不通过 →
            // 静默退化成 flat grid 丢失时间分段；用 (image, url) pair 一起 compactMap 保两数组同步过滤
            let resolvedPairs: [(IndexedImage, URL)] = images.compactMap { img in
                var stale = false
                guard let rootURL = try? URL(
                    resolvingBookmarkData: img.urlBookmark,
                    options: [.withSecurityScope],
                    bookmarkDataIsStale: &stale
                ) else { return nil }
                return (img, rootURL.appendingPathComponent(img.relativePath))
            }
            let resolvedImages = resolvedPairs.map { $0.0 }
            let urls = resolvedPairs.map { $0.1 }

            // ④ 写状态（MainActor + cancel guard）
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.currentEphemeral = .search(query: input, images: resolvedImages, urls: urls)
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
