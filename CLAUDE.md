这是一个 macOS 本地看图 app（**Glance · 一眼**，原名 ISeeImageViewer，2026-04-27 重命名），SwiftUI 开发。
核心功能是本地文件夹浏览和图片查看。
需要遵守 App Sandbox 限制，使用 Security Scoped Bookmark 处理文件权限。

> Bundle ID: `com.sunhongjun.glance`；CFBundleDisplayName 走 i18n（zh-Hans 显示「一眼」/ en 显示「Glance」）。
> 注意：项目根目录磁盘路径仍是 `~/Documents/projects/claude/ISeeImageViewer/`（保 auto-memory 路径不断），仓库内部全部统一为 Glance。GitHub 仓库名暂未改。

---

## 项目文件结构

```
ISeeImageViewer/                    ← 磁盘路径未改，repo 内部一切都已是 Glance
├── CLAUDE.md                        ← 本文件（开发规范 + 上下文）
├── CONTEXT.md                       ← 领域术语表 + 架构总览（决策不在此，走 specs/Roadmap.md）
├── Makefile                         ← make build / run / clean / hooks-install / verify / verify-codex / release / release-dry
├── Glance.xcodeproj/
├── .githooks/
│   └── pre-push                     ← codex 自动 review 待推 .swift+.md diff，[P1] 阻塞
├── scripts/
│   ├── verify.sh                    ← /go Step 1 三段 oracle（grep + xcodebuild + 单测占位）
│   ├── release.sh                   ← 公开分发打包（archive + Developer ID 签 + create-dmg + notarize + staple）
│   └── ExportOptions.plist          ← exportArchive 配置（method=developer-id, manual signing）
├── .claude/
│   └── commands/
│       └── go.md                    ← /go 五步收尾命令（CC slash command）
├── .verify-logs/                    ← gitignored，verify.sh 完整 log 留存
├── build/                           ← gitignored，xcodebuild 产物（make run 和 verify.sh 共用）
├── dist/                            ← gitignored，make release 产物（.xcarchive + export/.app + Glance-X.X.X.dmg）
├── assets/
│   └── icon-1024.png                ← AppIcon master（Claude Design 出，眼睛 Cool Violet 方向）
│                                       10 个尺寸由 sips 派生到 Assets.xcassets/AppIcon.appiconset/
├── specs/                           ← 所有模块规范文档
│   ├── UI.md                        ← UI 设计规范（唯一来源），含颜色自适应方案
│   ├── Roadmap.md                   ← 总体进度 + Bug Fix 记录 + 关键架构决策
│   ├── PENDING-USER-ACTIONS.md      ← 不能自动验证的人工测试项 durable 队列（Pending / Done 两段）
│   ├── AppState.md                  ← ✅ 全屏 + 外观模式（AppState / WindowAccessor）
│   ├── BookmarkManager.md           ← ✅ 已完成
│   ├── FolderStore.md               ← ✅ 已完成
│   ├── FolderBrowserView.md         ← ✅ 已完成（含 Finder 拖拽添加文件夹 子节）
│   ├── QuickViewer.md               ← ✅ 已完成
│   ├── SortFilter.md                ← ✅ 已完成
│   ├── KeyboardShortcuts.md         ← ✅ 已完成
│   ├── Inspector.md                 ← ✅ 已完成
│   ├── TrafficLightHide.md          ← ✅ 已完成
│   ├── ThumbnailSizeSlider.md       ← ✅ 已完成
│   ├── Prefetch.md                  ← 已完成
│   └── v2/                          ← V2 milestone-level 设计 + plan 文档（per-milestone，非 per-module）
│       ├── 2026-05-06-v2-design.md                ← V2 整体 brainstorming 落地（D1-D10 决策源）
│       ├── 2026-05-06-m1-implementation-plan.md   ← M1 task 级 plan（Slice A-I 共 9 slice）
│       ├── 2026-05-10-m2-design.md                ← M2 类似图查找设计（D11-D14）
│       ├── 2026-05-10-m2-implementation-plan.md   ← M2 task 级 plan（Slice J-K）
│       ├── <YYYY-MM-DD>-m3-design.md              ← M3 搜索设计（D16+），待写
│       └── <YYYY-MM-DD>-m3-implementation-plan.md ← M3 task 级 plan，待写
├── docs/
│   └── archive/                     ← 已归档的历史规范文档
│       ├── UIRefresh.md             ← 已归档
│       ├── FullScreen.md            ← 已归档（内容合并入 AppState.md）
│       ├── ImageViewerView.md       ← 已归档（已被 QuickViewer 替代）
│       ├── 2026-03-24-appearance-mode-design.md  ← 已归档（合并入 AppState.md + UI.md）
│       └── 2026-03-24-appearance-mode-plan.md    ← 已归档（实施记录）
└── Glance/                         ← Swift 源码（PBXFileSystemSynchronizedRootGroup，新文件自动加入编译）
    ├── GlanceApp.swift              ← App 入口（struct GlanceApp）。**方向2 Slice2：移除 Window scene，body 只留 `Settings { EmptySettingsView() }` 挂 .commands（About 菜单）**（真机验过菜单栏存活，D-OW13）；图库主窗改由 AppDelegate + MainWindowController 自建（D-OW9）。`@MainActor AppDelegate` 持 4 对象 ownership（BookmarkManager/FolderStore/AppState/IndexStoreHolder，原 GlanceApp @StateObject 迁来，D-OW12）+ lifecycle：applicationDidFinishLaunching 按 launchedForFileOpen 决定首窗（cold open 只 viewer / 普通 launch 建 main）+ applicationShouldHandleReopen 无主窗则重建 + application(_:open:) cold/warm 分流（`terminateOnClose=!hasFinishedLaunching`，cold 看完即走 / warm 不退，D-OW14）+ applicationShouldTerminateAfterLastWindowClosed=false（关窗驻留像 Photos，cold 看完即走由 viewer terminateOnClose 控，D-OW15）
    ├── Glance.entitlements          ← sandbox entitlements（当前未被 pbxproj 引用，由 build settings 自动生成）
    ├── Info.plist                   ← 手写 Info.plist（CFBundleDocumentTypes=public.image Viewer / LSHandlerRank=Alternate）让 Glance 进 Finder「打开方式」；GENERATE_INFOPLIST_FILE=YES 合并注入版本/DisplayName/BundleID。pbxproj 用 PBXFileSystemSynchronizedBuildFileExceptionSet 把它从 Copy Bundle Resources 排除（否则与 INFOPLIST_FILE 双引用报 warning）
    ├── ContentView.swift            ← NavigationSplitView (sidebar VStack: SmartFolderListView + V1 FolderSidebarView) + mainContent ZStack(baseGrid + previewOverlay) + QuickViewer（**QV-toolbar Slice1 2026-06-08：从 .overlay 迁到 MainQuickViewerWindowController 独立无装饰窗**，盖主窗修 toolbar regression；ContentView 仅 @ObservedObject 观察 isPresenting 决定 allowsHitTesting/previewOverlay 渲染，进出走 presentQuickViewer/handleQVDismiss，退出按 QVDismissalReason{normal/findSimilar/commandF} 仲裁）；mainContent .allowsHitTesting(QV 不在时) 让底层 grid tooltip tracking 在 QV 期失活。**方向2 Slice2 已删整套 OpenWith externalOpen 残留机器**（externalOpenUrls/handleExternalOpen/scheduleActivation/waitForAppActivation/QuickViewerEntry.externalOpen/onChange(pendingOpen,windowIdentity,isWindowKey)/handleBrowseFolder）——外部打开改走 ExternalViewerWindowController 独立看图窗，ContentView 不再参与；**WindowAccessor 也移除**（图库主窗 NSWindow 挂接改由 MainWindowController 自任 delegate 接管，D-OW16）
    ├── DesignSystem.swift           ← DS.Spacing / DS.Color / DS.Anim 等所有 UI 常量
    ├── BookmarkManager.swift
    ├── en.lproj/InfoPlist.strings   ← 英文 locale 显示名 "Glance"
    ├── zh-Hans.lproj/InfoPlist.strings ← 中文 locale 显示名「一眼」
    ├── FolderBrowser/
    │   ├── FolderStore.swift            ← V1 状态管理（FolderNode 树形结构、图片列表、排序、thumbnailSize 共享给 V2）
    │   ├── FolderSidebarView.swift      ← V1 侧边栏（树形展开/折叠、badge、右键菜单）
    │   ├── ImageGridView.swift          ← V1 缩略图网格 + ThumbnailCell + loadThumbnail() / loadFullNSImage() 顶层函数（均标 nonisolated：项目 default main-actor isolation 否则离主线程解码会 hop 回主线程卡 UI）
    │   ├── SmartFolderListView.swift    ← V2 sidebar 智能文件夹区（M1 "全部最近" + 后续 "本周新增"）
    │   ├── SmartFolderGridView.swift    ← V2 跨文件夹 grid（cell mirror V1 ThumbnailCell + Slice B-α 时间分段 sticky）；cell hover tooltip 显完整路径（复用 loadThumb 已 resolve 的 child URL.path 存 @State，跨多根聚合看图来自哪）
    │   └── TimeBucket.swift             ← V2 D4 时间分段算法（5 段：今天/昨天/本周/本月/更早）+ groupedByTimeBucket helper
    ├── ImageViewer/
    │   ├── ImagePreviewView.swift       ← 单击后内嵌预览（简单展示，双击触发 QuickViewer）
    │   ├── ImagePreviewViewModel.swift  ← 预览页 ±1 预加载缓存，方向键切换零延迟（+ loadFailed 标志：加载失败显占位）
    │   └── ImageLoadFailedView.swift    ← 方案 3 共享加载失败占位（photo.badge.exclamationmark + 文字，compact 模式 grid cell 仅图标）；三处复用
    ├── QuickViewer/
    │   ├── QuickViewerViewModel.swift  ← ZoomMode + 缩放/导航逻辑 + deinit 取消在途 imageLoadTask/prefetch（.id 重建 teardown 卫生）
    │   ├── ZoomScrollView.swift        ← NSViewRepresentable（滚轮/双击/拖拽）
    │   ├── QuickViewerOverlay.swift    ← 全窗口覆盖层（TopBar + NavButtons + BottomToolbar + Filmstrip）+ 加载失败 ImageLoadFailedView + Slice 2「浏览所在文件夹」按钮（onBrowseFolder，仅外部打开场景传）
    │   └── MainQuickViewerWindowController.swift ← QV-toolbar Slice1：主窗 QV 独立无装饰窗单例（mirror ExternalViewer 砍 ViewerSession/scope）+ 专属 viewerAppState + QVDismissalReason enum + show/close + 同框 frame 跟随 + windowWillClose focus 4 步时序（runAfterNextBecomeKey 延迟设 focusTarget + I1 已-key fallback + I2 generation guard）；全屏4态状态机（windowedCover/qvNativeFullScreen/inheritedMainFullScreen/transitioning + fullScreenAuxiliary 继承主窗全屏 + 首ESC退全屏次ESC关 + 主窗 didExitFullScreen observer + I1/I3/M1 防御）Slice2 已实现；边界硬化 Slice3 TODO
    ├── Inspector/
    │   ├── ImageInspectorViewModel.swift  ← ImageInfo struct + EXIF 读取
    │   └── ImageInspectorView.swift       ← Form + Section 布局
    ├── ExternalOpen/                ← OpenWith：Finder「打开方式」/ Dock 拖放接收图片
    │   ├── ExternalViewerWindowController.swift ← 方向2 Slice1：@MainActor 纯 AppKit 单例，自建 NSWindow + **NSHostingView**(QuickViewerOverlay.environmentObject(viewerAppState).id(session.id)) 当 `contentView`（**不用** `contentViewController=NSHostingController`——AppKit 会忽略 contentRect、改用 hosting fittingSize 把窗口压成 1×1 看不到图；mirror AboutWindowController）+ autoresizingMask 跟随 resize/全屏 + 自任 NSWindowDelegate（不接 WindowAccessor 避 delegate 被抢，复刻 fullscreen/key 跟踪）+ 持 viewerAppState 看图窗专属 AppState + retiredSessions（二次打开旧 session 不立即 end、关窗统一 end 避 scope 竞态）+ deferred 置顶 reassert（guard session.id+isVisible）；统一 close path reset isFullScreen + 按 terminateOnClose 决定 NSApp.terminate/只关窗
    │   └── ViewerSession.swift            ← 方向2 Slice1：@MainActor 一次看图会话，持 security-scope token（start 仅记成功 URL，end 幂等配平）+ terminateOnClose flag（冷启动 true 看完即走 / warm false）
    │                                        （ExternalOpenCoordinator.swift 旧桥已于方向2 Slice2 删除——AppDelegate 直接调 ExternalViewerWindowController）
    ├── MainWindow/                  ← 方向2 Slice2：图库主窗 + Settings 占位（从 SwiftUI Window scene 收回自建）
    │   ├── MainWindowController.swift     ← @MainActor 单例，自建图库主窗 NSWindow + NSHostingView(ContentView+4注入)，mirror AboutWindowController 骨架 + 自任 NSWindowDelegate 接管 attach/detach/fullscreen/key/close 驱动 appState（D-OW16 单一 delegate 归属，取代删掉的 WindowAccessor）；hasWindow 供 AppDelegate 查首窗/reopen（禁扫 NSApp.windows）；首建时 folderStore.loadSavedFolders()；**QV-toolbar Slice1 加 runAfterNextBecomeKey(_:)**：注册主窗下次 become key 后一次性回调（QV 关闭归还焦点时序地基），I1 fallback 若主窗已是 key 则直接 Task.yield 调度不入队
    │   └── EmptySettingsView.swift        ← Settings scene 占位（App body 移除 Window scene 后需 ≥1 非主窗 scene 挂 .commands；Glance 暂无设置项故最小占位）
    ├── FullScreen/
    │   └── AppState.swift           ← isFullScreen + isWindowKey + windowIdentity(@Published，换窗换 UUID) + appearanceMode + toggleFullScreen() + attachWindow/detachWindow（isWindowKey 给 QV 焦点 assert）。**方向2 Slice2：WindowAccessor.swift 已删**——图库主窗 NSWindow 挂接改由 MainWindowController 自任 NSWindowDelegate 接管、看图窗由 ExternalViewerWindowController 接管，都直接调 attachWindow/detachWindow，不再走 NSViewRepresentable
    ├── About/
    │   ├── AboutView.swift                ← 自定义"关于一眼"窗口内容（点击 contact 复制 + toast 提示）
    │   └── AboutWindowController.swift    ← 纯 AppKit NSWindow + NSHostingView 单例，先定位再 makeKeyAndOrderFront 避免显示后跳跃
    ├── IndexStore/                  ← V2 跨文件夹索引层（SQLite-backed，无第三方依赖）
    │   ├── IndexDatabase.swift              ← sqlite3 C API 包装（open/close/exec/prepare/bind/step）+ PRAGMA foreign_keys=ON / journal_mode=WAL
    │   ├── IndexStoreSchema.swift           ← v1 forward-looking schema（M1+M2+M3 字段）+ migration（PRAGMA user_version）
    │   ├── IndexStore.swift                 ← 高层入口（DispatchQueue 串行）+ auto-migrate；DB 路径走 sandbox container Application Support
    │   ├── IndexedImage.swift                ← images 表 record struct + 幂等 SELECT-first INSERT + Slice G.3 deleteImage / updateImageMetadata + Slice H SHA256/canonical CRUD（setContentSHA256/setDedupCanonical/resetSHA256AndCanonical/promoteOrphanDuplicates/fetchCandidateGroups/fetchImagesInGroup/fetchDuplicates/fetchDuplicatesByFullPath）
    │   ├── ContentHasher.swift              ← V2 Slice H 文件 SHA256 hex 计算（CryptoKit + Data .mappedIfSafe mmap）
    │   ├── DedupPass.swift                  ← V2 Slice H cheap-first dedup 算法（runFullPass + reEvaluateGroup + orphan cleanup）；canonical = earliest birth_time + 最小 id tie-breaker
    │   ├── ManagedFolder.swift              ← folders 表 record struct + registerRoot 幂等 + Slice D hide CRUD（setRootHidden/upsertSubfolderHide/effectiveHidden）+ Slice G.1 deleteRoot（FK CASCADE）+ Slice I.2 last_processed_path CRUD（resume from cursor）+ fetchRootPaths（对账）/ deleteOrphanImages（NOT EXISTS 防御性孤儿清扫）
    │   ├── CompiledSmartFolderQuery.swift   ← Builder → Engine 之间的 SQL injection-safe contract
    │   ├── ImageMetadataReader.swift        ← URL → birth_time / file_size / format / dimensions（ImageIO，不解码像素）；Slice N formatLabel 公开化（internal）+ canonicalFormatLabels（chip 类型选项唯一权威，与 formatLabel 输出逐字符同源大写标签）
    │   ├── FolderScanner.swift              ← 递归 enumerator + INSERT OR IGNORE 幂等 + Slice I.2 Task.isCancelled 检测 + resumeFrom 字典序 skip + 每 100 张写 cursor
    │   ├── IndexingProgress.swift           ← V2 Slice I.1 进度 record（rootName/scanned/indexed）
    │   ├── IndexingProgressView.swift       ← V2 Slice I.1 chip 形态进度 UI（mirror Slice B chip：Capsule+thickMaterial+strokeBorder + Slice I.2 X 取消按钮）
    │   ├── FSEvent.swift                    ← V2 Slice G FSEvents 单 event record struct（path + flags + isFile/isCreated/isRemoved/... computed flags）
    │   ├── FSEventsWatcher.swift            ← V2 Slice G FSEvents Swift wrapper（CoreServices FSEventStreamCreate / 每 root 一 stream / file-level events / defaultLatency 1s static let）
    │   ├── IndexStoreHolder.swift           ← 异步 init holder（@Published store + isReady Bool 让 .onChange 可观察）+ Slice I.1/I.2 progress / lastError / cancelCurrentScan 钩子
    │   └── FolderStoreIndexBridge.swift     ← rootFolders diff → registerRoot/deleteRoot + 启动 FolderScanner + Slice G.2/3 watcher lifecycle + handle Created/Removed/Modified/Renamed events + Slice H dedup hooks + Slice I.1/I.2 progress 回调 / cancel 转发 / error 回调 + scan resume from cursor；sync(with:managedRootPaths:) 移除段 DB+bookmark 权威对账（Guard B：删 DB 里不在 managedRootPaths 的 root，不用异步滞后的 rootFolders 防启动瞬态误删整库）+ 孤儿清扫
    ├── Similarity/                  ← V2 M2 类似图查找（feature print + Vision）
    │   ├── SimilarityService.swift           ← Vision VNFeaturePrintObservation 包装 + computeDistance batch top-N
    │   ├── FeaturePrintIndexer.swift          ← 后台 fp 索引 pipeline（batch 50 + cancel + enqueueIfNeeded）
    │   ├── FeaturePrintIndexingProgress.swift ← progress record（indexed/total/lastImageName）
    │   ├── FeaturePrintProgressView.swift     ← chip 形态进度 UI（mirror Slice I 紫色调区分）
    │   └── EphemeralResultView.swift          ← 临时结果视图（layout + ThumbnailCell 复用 + banner 槽）
    ├── Search/                      ← V2 M3 全局搜索（Slice M）+ 筛选 chips（Slice N）
    │   ├── SearchInput.swift                ← ParsedSearch struct + SearchSizeUnit enum
    │   ├── SearchService.swift              ← parser (Silent partial) + compile → SmartFolderPredicate；Slice N 加 compile(filterState:keyword:now:) 单一出口（chip + keyword 合并，common filter 单点注入，全 AND）
    │   ├── SearchFilterState.swift          ← V2 Slice N chip 选中态值类型（D22 独立筛选态）+ SearchSizeBucket/SearchTimeBucket enum + toAtoms（类型 inSet / 大小 > / 时间 between；各档自然边界预计算 ISO：今天午夜/本周起始日/本月1号/今年1.1，device local）+ _debugSelfCheck
    │   ├── SearchChipBar.swift              ← V2 Slice N chip 行 UI（三组 chip + 原生 .popover；类型 checkbox 多选 / 大小·时间单选 + .onExitCommand ESC 两段）；透传 @FocusState.Binding，popover dismiss 时 returnFocusToSearch 弹焦点回搜索框（根因修复：关 popover 后能继续打字/回车提交，绕过 @FocusState 值不变不重聚焦）
    │   └── SearchOverlayView.swift          ← 顶部 Spotlight 式 overlay + ⌘F 入口 + ESC dismiss；Slice N 在 inputRow/hintRow 间插 SearchChipBar（searchInput 保持 local @State 避 closeSearch close-loop）
    └── SmartFolder/                 ← V2 智能文件夹规则与查询
        ├── SmartFolder.swift                ← struct（id/displayName/predicate/sortBy/builtIn）
        ├── SmartFolderRule.swift            ← Predicate enum (AND/OR/ATOM) + Atom struct + Op + Value（D6 Spotlight-like 平铺）
        ├── SmartFolderQueryBuilder.swift    ← Predicate → SQL WHERE + parameters（snake_case 列名对齐 DB schema）
        ├── SmartFolderEngine.swift          ← 编译 SmartFolder 成 CompiledSmartFolderQuery 后调 IndexStore.fetch
        ├── BuiltInSmartFolders.swift        ← M1 内置 allRecent + thisWeekAdded（Slice B-β）
        ├── SmartFolderState.swift           ← V2 Slice I.3 状态机 enum（.idle / .loading / .loaded / .error）
        └── SmartFolderStore.swift           ← @MainActor ObservableObject 单一 @Published state（Slice I.3 重构）+ computed accessors 兼容旧 view 调用（selected/queryResult/isQuerying/lastError）+ stale-write guard 走 state pattern match
```

---

## 开发规范

- **V1 模块**开发前必须有对应的 `specs/<模块名>.md` 文件（per-module spec，V1 既有约定）。
- **V2 milestone 工作**（M1/M2/M3）走 `specs/v2/<date>-<milestone>-{design,implementation-plan}.md` 两文档配对（per-milestone，**非 per-module**）。design 经 `superpowers:brainstorming` skill 产出，plan 经 `superpowers:writing-plans` skill 产出。Slice 级追溯 doc 直接 append 到对应 implementation-plan.md 末尾的"Slice X 完成详细"表（mirror Slice J 完成详细 pattern）。
- **新开 session 第一步**：
  1. 读 `CLAUDE.md`（高层概述）
  2. 读 `specs/Roadmap.md`（进度 + Bug Fix + 决策）
  3. `ls -la specs/v2/`（验证 milestone-level plan 实物，跨 session 防止 workflow 假设漂移）
  4. 当前主线若是 V2 milestone 工作，read 该 milestone 最新 design + implementation-plan
- 开发环境是远程 Mac mini（已装 Xcode，平时用命令行；GUI 仅作 pbxproj 损坏救场用）。所有编译和验证使用命令行。
- 构建命令：`make build`（Debug，日常开发）
- 运行命令：`make run`
- 清理命令：`make clean`
- **公开分发打包**：`make release`（详见 specs/Roadmap.md > Distribution 段）
- **构建产物自动同步**：`make build` 和 `./scripts/verify.sh` 编译成功后会把 `./build/Glance.app` 复制到 `~/sync/Glance.app`（先 `rm -rf` 旧的再 `cp -R`），用户本地测试机通过 Syncthing 拉取。两条 build 路径行为一致。
- **版本号注入**（用户对比"刚才编的是不是这版"的真值）：build 时 xcodebuild 用 `CURRENT_PROJECT_VERSION="<commit short>[-d].<MMDD-HHMM>"` override，关于面板显示 `版本 1.0 (fb7f900-d.0504-2318)`；`-d` 后缀表示 working tree 有未 commit 改动（避免误读为 commit 真值）。同时写 sidecar `~/sync/Glance.app.BuildInfo.txt`（含 commit / dirty / version / commit_time / commit_msg / built_at / host），`cat` 即可详细查看。Makefile + verify.sh 两条 build 路径同步该逻辑。
- **关于面板 Copyright** 注入：`INFOPLIST_KEY_NSHumanReadableCopyright="© 2026 孙红军 · 16414766@qq.com · 小红书 382336617"`，单行紧凑格式（macOS NSAboutPanel 的 copyright 字段 truncate-by-tail，多行 `\n` 不折行渲染）。同样 Makefile + verify.sh 两条路径同步。
- **macOS 部署目标 14.0**（Sonoma+，覆盖 ~85% 用户）+ **Bundle ID `com.sunhongjun.glance`** + **Team ID `8KW8Z92GRA`**（Apple Developer Program 个人账号）。pbxproj 字段已设，无需重复注入。
- **公开分发签名链路**：Release 配置 + `ENABLE_HARDENED_RUNTIME=YES`（脚本注入）+ `Developer ID Application: Hongjun Sun (8KW8Z92GRA)` 签名 → exportArchive (`scripts/ExportOptions.plist`, method=developer-id, manual signing) → create-dmg → notarytool submit --wait → stapler staple → `dist/Glance-1.0.0.dmg`。

## UI 规范

- **所有 UI 常量必须引用 DesignSystem.swift（DS.*）**，禁止硬编码颜色、间距、动画。
- 详细规范见 specs/UI.md。
- 核心原则：内容优先、克制、原生、深色优先。
- `QuickViewerOverlay`（全窗口看图）强制深色（`.preferredColorScheme(.dark)`）；`ImagePreviewView`（内嵌预览）跟随全局外观，前景色使用 `Color.primary`。
- 禁止在看图界面使用 `.spring` 动画，用 `DS.Anim.normal / fast`。

## 持久化规范

- 每次计划生成后，立刻将计划追加到对应的 specs/[模块名].md 的「实现步骤」章节。
- 每个模块完成后立刻 git commit，commit message 格式：「完成 [模块名]」，然后执行 `git push` 同步到 GitHub（remote: git@github.com:sunhuaian2026/ISeeImageViewer.git，仓库名暂未跟随重命名为 Glance）。
- **模块完成后必须同步更新文档**：
  1. 更新 specs/[模块名].md 里的「当前进度：第 X 步已完成」
  2. 更新 specs/Roadmap.md：将该模块移入「已完成」表格，标注 commit hash
  3. 如涉及新文件或目录，同步更新 CLAUDE.md 的文件结构
- xcodeproj 使用 PBXFileSystemSynchronizedRootGroup，在 `Glance/` 目录下新建 .swift 文件会自动被编译，无需手改 xcodeproj。

## ⚠️ 文档同步强制规则（每次必须执行，不得跳过）

### 禁止单独提交代码

**代码变更和文档更新必须在同一个 commit 里。不允许先提交代码、事后补文档。**

git commit 前的强制 checklist，逐条检查，全部通过才能提交：

| 变更类型 | 必须更新的文档 |
|---------|-------------|
| Bug fix | `specs/Roadmap.md` Bug Fix 记录（含 commit hash、文件、问题、修复方式） |
| 新增/删除/移动文件 | `CLAUDE.md` 文件结构 |
| V1 模块或子功能完成 | 对应 `specs/<模块名>.md` 的「当前进度」 |
| V2 Slice / milestone 完成 | `specs/v2/<date>-<milestone>-implementation-plan.md` 末尾"Slice X 完成详细"表 + `specs/Roadmap.md` M 段 slice 表 |
| 模块进入已完成 | `specs/Roadmap.md` 已完成表格（含 commit hash） |
| 架构或交互逻辑变化 | `specs/Roadmap.md` 关键架构决策 |

**判断标准：任何让"下一个 session 读文档会产生误解"的变更，都必须同步更新文档。**

## 验证与 Review 规范

- 每个模块实现完成后，必须先执行 `make build`，确认零错误零警告再提交。
- 编译通过后，对照 specs/[模块名].md 逐条检查接口和边界条件是否都已实现。
- 发现与 spec 不符的地方，先修复再 commit，不允许带问题提交。
- 每次 commit 前做一次自我 review：检查有没有硬编码、未处理的错误、遗漏的边界条件。

### 任务收尾：`/go` 五步

任务涉及 `.swift` 改动时，收尾前必须跑 `/go`（定义在 `.claude/commands/go.md`）。纯文档 / scripts / specs 改动 → 跳 Step 1，commit message 末尾加 `[docs-only]`。

`/go` 五步：

1. **三段式 verify**（`./scripts/verify.sh`，成本递增、遇红即停）：
   - Stage 1 静态规则（ms）：grep/awk + 文档同步 + git hygiene
   - Stage 2 编译（30-60s）：`xcodebuild build -quiet`，0 error 才过；warning 非阻塞但必须修
   - Stage 3 单测（暂 skip，项目无 XCTest target）
   - 红 → 修 → 重跑，**最多 5 轮**。5 轮仍红就停下来问用户
2. **文档同步**：对照 `.swift` diff 按「⚠️ 文档同步强制规则」补 Roadmap / CLAUDE.md / specs/<module>.md
3. **PENDING 人工清单**：追加到 `specs/PENDING-USER-ACTIONS.md`（durable 文件，入库累积），只加本次改动相关项
4. **commit + push**：`git add` 逐文件明确；push 触发 pre-push hook 做第二道 codex 评审
5. **一段话汇报**：**第一行必须独立显示编译结果**（`BUILD SUCCEEDED — 0 errors, 0 code warnings`），不得仅用 verify 的汇总数字替代；其后 self-fix 几轮 / 文档动了啥 / PENDING 加几项 / commit hash / hook 结果

可选 `./scripts/verify.sh --with-codex` 在 verify 后追加 codex 全项目审查（跨 3+ 模块或架构重构时才跑）。

`make verify` / `make verify-codex` 便捷入口。完整 log 留 `.verify-logs/`（gitignored）。

## Pre-Push Codex Review Hook

`.githooks/pre-push` 在 `git push` 时调用 codex（read-only sandbox + high reasoning）审查待推 diff（`.swift` + `*.md`），发现 `[P1]` 阻塞 push，`[P2]` 仅告警。

**安装一次**：`make hooks-install`（设 `core.hooksPath=.githooks`）

**绕过方式**：
- 单次紧急：`git push --no-verify`
- 本次 session：`SKIP_CODEX_REVIEW=1 git push`
- 按 commit 跳过：commit message 含 `[skip-codex]` 或 `[wip]`

**规则覆盖**（见 `.githooks/pre-push` 的 PROMPT）：通用代码规则 + UI 硬编码/DS.* / `.spring` 禁用 / QuickViewerOverlay 深色 / 文档同步硬规则。

**缓存**：通过的 `local_sha` 写入 `.git/codex-reviewed-<sha>`，retry 不重复审。

## Skill 行为约束

- **grill-with-docs / improve-codebase-architecture 等 skill 默认写 `docs/adr/`，本项目不建该目录**：ADR 等价物落在 `specs/Roadmap.md`「关键架构决策」段（单文件好扫好搜，避免决策碎片）；`CONTEXT.md` 仅放领域术语 + 架构总览，**不放决策**。skill 触发时按此目标写，CLAUDE.md 优先级高于 skill 默认行为，无需每次手动提醒。
- **新术语必须先登记 `CONTEXT.md` 术语表，再用于代码 / specs / commit message**：避免同一概念在不同模块用不同名字漂移。命名冲突时以 `CONTEXT.md` 为准。

## 术语用法（强制，2026-06-16 起）

写新 spec / plan / design / PR 描述 / commit message 时:

- ✅ **必须用三层方法论命名**: **阶段 → 里程碑 → 任务**(查 `CONTEXT.md`「术语字典表」D 段)
  - 阶段 = V1 / V2 / V3 项目大版本
  - 里程碑 = V2 M1 / M2 / M3 / M4 等(M = milestone 国际通用缩写)
  - 任务 = M 内细分独立交付单元(原 Slice A-N / Slice 1-3 改任务 A-N / 任务 1-3)
- ❌ **禁用旧名**: Slice / slice / vertical slice / VS / 切片 / 片
- ✅ **独立子系统**(快速看图器 toolbar 修复 / OpenWith 子系统 / 快速看图器看图增强) 不塞 M 序号,各自顶层命名,内部按"任务"拆
- ❌ **禁用自造简写**: QV / SF / IS / OW(裸写) / QVT — 查 `CONTEXT.md` A 段
- ❌ **禁用裸 codex 编号**: P1-1 / P1-2 / I-1 / M-1 等必须带含义("codex P1(delegate 双持地雷)")
- ✅ 通用同义词统一中文规范(快速看图器 / 重复清理 / 保留张 / 找相似图 / 图像指纹 / 缩略图 / 侧边栏 / 工具栏 等)

**调用 superpowers skill 时**:
- 调用 `brainstorming` / `writing-plans` 前在 prompt 里**显式提醒**: "用 CONTEXT.md 术语字典命名,禁用 Slice/VS/切片/QV/SF 等弃用别名"
- skill 产出后 `./scripts/verify.sh` 检查是否含禁用词(verify Stage 1d 自动跑),报红就修
- 不照办的产出**不许直接 commit**(commit-msg hook 也会拦)

**老 plan / 老 spec / 历史 commit** 保留旧名(只读,不批量改 — 改了破坏 git blame + commit 引用关系)。看老文档时心里查 `CONTEXT.md` E 段「旧名 → 新名映射对照表」翻译。

**豁免**: `CONTEXT.md`(字典自身)+ `AGENTS.md`(superpowers 会话历史日志)+ fenced code block (```` ``` ````) 内 + inline backtick `` `...` `` 内。

---

## 事件档案（incidents 索引）

事件级 detail 记录，**Why 段从全局 `~/.claude/CLAUDE.md` 下沉到此**。不自动加载详情，需要时主动 Read。按时间倒序：

- [2026-05-11 milestone 必走 skill chain](.claude/memory/incidents/2026-05-11-milestone-skill-chain.md) — M3 连续 3 次跳 brainstorming→writing-plans→execution
- [2026-05-11 会话开始 ls 子目录](.claude/memory/incidents/2026-05-11-session-start-ls-subdirs.md) — M3 只 trust CLAUDE.md 摘要，忽略 `specs/v2/` 已有 M1/M2 design+plan
- [2026-05-06 多方案推荐必须先摆完整候选](.claude/memory/incidents/2026-05-06-slice-a-options-naming.md) — Slice A 只写 "Mode C"，A/B 未出现，用户无从选择
- [2026-05-06 plan 引用已有代码先 Read](.claude/memory/incidents/2026-05-06-plan-symbol-reality-check.md) — M1 plan A.13-A.17 脑补 V1 API（FolderStore / DS.Spacing.s / 三栏 NSV）全错
- [2026-05-06 ADR 措辞擅自修改](.claude/memory/incidents/2026-05-06-adr-rewording-no-action-without-verb.md) — 用户陈述句"没 ADR 目录了吧"被吃成"请改"
