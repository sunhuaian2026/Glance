# Glance V2 M4 任务 2 收尾设计 — V1→V2 bookmark 升级引导 UI

> 本设计将 `specs/v2/2026-06-10-m4-design.md` 4.5.4.4 段「升级触发时机 UI 草图」细化到能 ship 的级别。承接 M4 任务 2 step 1-6 已 ship 的代码层（16 commit），补上唯一缺失的「触发流 UI」，让任务 2 端到端闭环达成。

---

## 1. 一句话定位

V1 时代 `BookmarkManager.saveBookmark` 用 `.securityScopeAllowOnlyReadAccess` flag 创的 bookmark 不能 trashItem。BookmarkManager V2 升级已 ship（step 2.0.5），但「让用户重新选择根目录」的 modal sheet 引导 UI 尚未实现，导致用户点「移入废纸篓」无任何反馈（banner 设计上沉默 — D33 防御正确）。本任务补这一环。

---

## 2. 既定约束（不重新讨论）

- **D-M4-1 走 A 方向已拍板**（不讨论 A/A2/B），见 `specs/v2/2026-06-10-m4-design.md` 4.5.4
- **BookmarkManager V2 已 ship**：`currentSchemaVersion` / `markSchemaV2()` / `clearAllForMigration()` / `saveBookmark` 去 flag / `FolderStore.reloadFromDefaults()` 全在
- **任务 2 代码层 step 1-6 已 ship**（16 commit，`origin/v2/dev = ea3044e`）
- **触发时机 = M4 删除入口首次（A1.5 变体）**：design 4.5.4.4 拍，单点入口，不在 app 首启 / 设置面板里

---

## 3. brainstorming 决策（D1-bm-ui ~ D6-bm-ui，2026-06-17 拍板）

| ID | 决策 | 选项 |
|---|---|---|
| D1-bm-ui | modal 形态 | SwiftUI .sheet（原生焦点锁 + 足够展开 + macOS HIG 一致） |
| D2-bm-ui | NSOpenPanel 流程 | `allowsMultipleSelection = true` 一次多选（复用 `FolderStore.addFolders(from:)` 既有批量入口） |
| D3-bm-ui | 取消语义（持久化提交段） | 延迟 `clearAllForMigration` / `reloadFromDefaults` 到 NSOpenPanel 成功返回后；取消零数据丢失。codex P1 修#1：原标「atomicity」措辞不准 — addFolders 内部 fire-and-forget 异步 Task，提交段非原子；markSchemaV2 改绑 `bridge.fireIndexChanged` 首次触发 |
| D4-bm-ui | 重扫期间 UX | sheet 立刻关 + 复用既有 `IndexingProgressView` chip + 「重复清理」总览主区显「重扫中」专用空态 |
| D5-bm-ui | selectedSha256s 处理 | 保留 + reload 后 prune 不在 model.groups 里的 sha256 + 不自动重启 `trashSelected`（用户 confirm 后亲点） |
| D6-bm-ui | 文案 + 「为什么」展开 | 三句话简洁 + DisclosureGroup 默认折起，点开一句技术解释 |

---

## 4. 架构 + 组件

### 4.1 新增组件

#### 4.1.1 `BookmarkMigrationView.swift`（新建）

SwiftUI sheet 纯展示 view，状态由 Coordinator 持。

**结构**：
- 顶部标题：「升级清理权限」
- 主文案（3 行）：「Glance 早期版本使用只读授权，无法把图片移入废纸篓。请重新选择你的根目录，授予写权限。一次性操作。」
- 两个按钮：
  - `.borderedProminent` 「重新选择根目录 →」 → callback `onConfirm`
  - `.bordered` 「以后再说」 → callback `onDismiss`
- `DisclosureGroup` 默认折起 「为什么需要重新选?」单行展开：
  「macOS 沙盒授权模型限定：只读 bookmark 不能升级为读写，必须重新创建。」

**入参**：`onConfirm: () -> Void` + `onDismiss: () -> Void`，本 view 不持状态。

#### 4.1.2 `BookmarkMigrationCoordinator.swift`（新建）

`@MainActor` ObservableObject 状态机，单一权威。

**生命周期合同**（codex P2 修#1 补充）：
- **Owner**：`ContentView` 持 `@StateObject migrationCoordinator`，生命周期跟 ContentView 一致（即跟主窗口一致）
- **依赖注入路径**：`DuplicateOverviewModel.trashSelected()` 入口 guard 触发 `migrationCoordinator.start(model:bookmarkManager:folderStore:)`；Coordinator 持 weak refs 防循环引用
- **失效降级策略**：`pickRoots()` 入口三段 guard（bookmarkManager / folderStore / bridge），任一 weak ref nil 则 log + reset phase = .idle 静默 return；用户感知是 sheet 关看似没反应，下次再点会重试
- **正常使用不会失效**：所有 weak ref 的 strong 持有方（BookmarkManager / FolderStore 由 App 单例持 / bridge 由 FolderStore 持）都跟主窗口同生命周期

```swift
@MainActor
final class BookmarkMigrationCoordinator: ObservableObject {
    enum MigrationPhase: Equatable {
        case idle
        case presentingSheet
        case picking
        case rescanning
        case completed
        case cancelled
        case error(message: String, failedURLNames: [String])
    }

    @Published private(set) var phase: MigrationPhase = .idle
    @Published private(set) var isPresenting: Bool = false

    private weak var model: DuplicateOverviewModel?
    private weak var bookmarkManager: BookmarkManager?
    private weak var folderStore: FolderStore?

    /// 由 DuplicateOverviewModel.trashSelected 入口 guard 触发.
    /// 注: 不直接调 model.trashSelected (避免循环), 重选成功后由 ContentView .onChange prune
    /// selectedSha256s, 用户 confirm 后亲点按钮再走 trashSelected.
    func start(
        model: DuplicateOverviewModel,
        bookmarkManager: BookmarkManager,
        folderStore: FolderStore
    ) {
        self.model = model
        self.bookmarkManager = bookmarkManager
        self.folderStore = folderStore
        phase = .presentingSheet
        isPresenting = true
    }

    /// 用户点「以后再说」或 NSOpenPanel Cancel.
    /// 立即重置 phase 到 idle (无 sleep 魔数 — codex P1 修#2).
    func cancel() {
        phase = .idle
        isPresenting = false
    }

    /// 用户点「重新选择根目录 →」.
    /// NSOpenPanel 成功后走「持久化提交段」(codex P1 修#1: 不是 atomicity, addFolders 内部 fire-and-forget 异步).
    /// markSchemaV2 时机绑定到 bridge.fireIndexChanged 多播首次触发 (codex P1 修#1+#2: 不靠 sleep 魔数).
    func pickRoots() async {
        guard let bookmarkManager else { return }
        guard let folderStore else { return }
        guard let bridge = folderStore.bridge else { return }   // codex P2 修#1: 失效降级
        phase = .picking

        // NSOpenPanel modal 必须 main thread
        // codex P1 修#3: panel 文案明示「替换全部根目录」防漏选数据丢失
        let urls = await MainActor.run { () -> [URL] in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.prompt = "替换所有根目录"
            panel.message = "重新授权 Glance 访问根目录（含写权限）。当前所有 V1 根目录将被替换 — 请一次性选齐你需要的所有根目录，漏选的会丢失。"
            return panel.runModal() == .OK ? panel.urls : []
        }

        guard !urls.isEmpty else {
            // 用户在 NSOpenPanel Cancel 或选 0 个 → 同 cancel 路径
            cancel()
            return
        }

        // === 持久化提交段 (串行, 顺序锁死; codex P1 修#1: 不叫 atomicity 因为 addFolders 异步) ===
        bookmarkManager.clearAllForMigration()      // 1. 清旧 bookmark + reset schemaVersion
        folderStore.reloadFromDefaults()            // 2. 内存状态清空 + currentFolderWatcher.stop
        folderStore.addFolders(from: urls)          // 3. fire-and-forget — 内部 Task 跑 saveBookmark V2 +
                                                    //    discoverTree + countImages + bridge.sync 启重扫.
                                                    //    addFolders 立即返回, **不**同步拿 successCount.

        // codex P1 修#2: rescanning → completed 严格绑定 bridge.fireIndexChanged 多播首次触发.
        // 不用 sleep 魔数. bridge 多播在 FolderScanner 完成首批入库时 fire (V2 既有路径).
        phase = .rescanning
        isPresenting = false

        // 注册一次性 observer 等首次 fireIndexChanged → markSchemaV2 + phase = .completed.
        // (codex P1 修#1: markSchemaV2 不在 addFolders 后立即调, 改在确认首次入库后调)
        var observerToken: UUID?
        observerToken = bridge.addIndexChangedObserver { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard case .rescanning = self.phase else { return }
                bookmarkManager.markSchemaV2()      // 4. 确认有数据入库后才升 schemaVersion = 2
                self.phase = .completed
                if let token = observerToken {
                    bridge.removeIndexChangedObserver(token)
                }
                // 一次性 .completed → .idle (无 sleep 魔数, 立即 reset)
                self.phase = .idle
            }
        }

        // codex P1 修#4: 部分失败 / 全失败 处理: 重扫期间 saveBookmark 失败的 URL
        // 由 bridge.lastError 弹既有 V2 索引错误 banner (V2 索引错误 banner 任务路径).
        // sheet 不重弹错误态 (避免与 banner 路径并存).
        // 全失败 (0 个 root 入库) 时 bridge.fireIndexChanged 永不触发 → markSchemaV2 不调 → 下次入口仍引导.
        // 用户感知: banner 错误提示 + 侧边栏空 + 总览空, 自然重试.
    }

    /// placeholder 工厂用于 SwiftUI #Preview / 初始注入.
    static func placeholder() -> BookmarkMigrationCoordinator {
        BookmarkMigrationCoordinator()
    }
}
```

#### 4.1.3 `DuplicateOverviewModel.trashSelected` 入口改造

在既有 `guard !selectedSha256s.isEmpty else { return }` 之后插入：

```swift
guard bookmarkManager.currentSchemaVersion >= 2 else {
    migrationCoordinator.start(
        model: self,
        bookmarkManager: bookmarkManager,
        folderStore: folderStore
    )
    return   // V1 路径: 引导触发, trashSelected 本次不执行, 等用户走完引导回来再点按钮
}
// V2 路径: 既有 4.5.2 + 4.5.3 trash 主流程不变
```

**新增依赖**：`bookmarkManager: BookmarkManager` + `folderStore: FolderStore` + `migrationCoordinator: BookmarkMigrationCoordinator` 三个属性，由 `attach()` 入口扩展注入。

#### 4.1.4 `ContentView` 接 sheet + prune

```swift
@StateObject private var migrationCoordinator = BookmarkMigrationCoordinator.placeholder()

var body: some View {
    NavigationSplitView { ... } detail: { ... }
        .sheet(isPresented: $migrationCoordinator.isPresenting) {
            BookmarkMigrationView(
                onConfirm: { Task { await migrationCoordinator.pickRoots() } },
                onDismiss: { migrationCoordinator.cancel() }
            )
            .frame(minWidth: DS.BookmarkMigration.sheetMinWidth)
        }
        .onChange(of: duplicateOverviewModel.groups) { _, newGroups in
            // D5-bm-ui: reload 后 prune selectedSha256s 掉不在新 groups 里的 sha256
            let validSha256s = Set(newGroups.map { $0.id })
            let pruned = duplicateOverviewModel.selectedSha256s.intersection(validSha256s)
            if pruned.count != duplicateOverviewModel.selectedSha256s.count {
                duplicateOverviewModel.replaceSelectedSha256s(pruned)
            }
        }
        // 既有 .overlay(banner) + .onChange(lastTrashOutcome) 等不变
}
```

**新增 model API**：`DuplicateOverviewModel.replaceSelectedSha256s(_:Set<String>)` 一次性替换（避免 toggleSelection N 次调用）。

#### 4.1.5 `DesignSystem.swift` 加 `enum BookmarkMigration`

```swift
enum BookmarkMigration {
    static let sheetMinWidth: CGFloat = 420
    static let sheetVerticalPadding: CGFloat = 24
    static let sheetHorizontalPadding: CGFloat = 28
    static let titleFont: Font = .title3.weight(.semibold)
    static let bodyFont: Font = .body
    static let disclosureFont: Font = .callout
    static let buttonSpacing: CGFloat = 12
    static let rescanEmptyStateFont: Font = .body
}
```

加「重扫中」总览专用空态文案常量（区别于既有「没找到重复图」）：写在 `DuplicateOverviewView` 内部，不进 DS。

### 4.2 复用既有 API（零新增）

- `BookmarkManager.{currentSchemaVersion, markSchemaV2, clearAllForMigration, saveBookmark}` — step 2.0.5 已 ship
- `FolderStore.{reloadFromDefaults, addFolders(from:)}` — step 2.0.5 + V1 既有
- `FolderStoreIndexBridge.sync(with:managedRootPaths:)` — V2 既有，addFolders 内部 indirectly 触发
- `IndexingProgressView` chip — V2 既有 V2 索引进度任务 全局 chip overlay 模式
- `IndexingProgressView` 错误 banner — V2 V2 索引错误 banner 任务 已 ship

---

## 5. 数据流（端到端时序）

```
[T0] 用户进「重复清理」总览 → 勾 N 组 → 点「移入废纸篓」

[T1] DuplicateOverviewModel.trashSelected() 入口 guard
     guard !selectedSha256s.isEmpty else { return }
     guard bookmarkManager.currentSchemaVersion >= 2 else {
       migrationCoordinator.start(model: self, bookmarkManager:..., folderStore:...)
       return   // 不走 trash 主流程
     }
     [V2 路径] → 走既有 4.5.2 + 4.5.3 trash 主流程

[T2] BookmarkMigrationCoordinator.start(...)
     phase = .presentingSheet → isPresenting = true → ContentView .sheet 触发

[T3] sheet 显示, 两分支:
     分支 A (点「以后再说」): coordinator.cancel() → phase = .idle (codex P1 修#2 无 sleep)
       → isPresenting = false → sheet 关
       → schemaVersion 仍 < 2, V1 root 不动, selectedSha256s 保留
       → 用户回总览, 下次点「移入废纸篓」再弹
     分支 B (点「重新选择根目录 →」): coordinator.pickRoots() async

[T4] pickRoots() 主路径
     a. phase = .picking
     b. NSOpenPanel runModal (allowsMultipleSelection=true)
        panel.message 「替换所有根目录 — 漏选会丢失」(codex P1 修#3 防漏选)
     c. 分支 B1 (panel Cancel 或 选 0 个): coordinator.cancel() → 同分支 A
     d. 分支 B2 (panel 选 ≥1 个 url):
        === 持久化提交段 (串行; codex P1 修#1: 不叫 atomicity 因为 addFolders 异步) ===
        1. bookmarkManager.clearAllForMigration()
        2. folderStore.reloadFromDefaults()
        3. folderStore.addFolders(from: urls)
           [fire-and-forget 异步 Task] saveBookmark V2 (无 flag) + discoverTree + countImages
           [fire-and-forget 异步 Task] bridge.sync(with:managedRootPaths:) 触发 FolderScanner 重扫
        4. bridge.addIndexChangedObserver { 一次性 closure } (codex P1 修#2: 不用 sleep 魔数)
        → phase = .rescanning → isPresenting = false (sheet 关)
        注: markSchemaV2 不在这里调; 等步骤 4 注册的 observer 在 T6 fire 时才调.

[T5] 重扫期间 (异步, 跨视图, 用户可切其他视图)
     - 主区顶部 IndexingProgressView chip 「扫描中... X/Y 张」(V2 既有)
     - 「重复清理」总览主区: 显「重扫中」专用空态文案
     - duplicateOverviewModel.scheduleReload 在 indexChangedObservers 多播下自动 reload
     - 用户可点侧边栏切其他视图
     - 若 addFolders 内部全失败: bridge.fireIndexChanged 永不触发 → markSchemaV2 不调
       → 错误显在 bridge.lastError 既有 banner → 下次点「移入废纸篓」仍引导 (自然重试, codex P1 修#4)

[T6] 重扫完 (IndexingProgressView chip 消失 + bridge.fireIndexChanged 触发首次)
     - coordinator 注册的一次性 observer 触发 → bookmarkManager.markSchemaV2() (codex P1 修#1+#2)
       → phase = .completed → 立即 → phase = .idle (codex P1 修#2 无 sleep)
       → bridge.removeIndexChangedObserver(token) 注销
     - duplicateOverviewModel.load() 由既有 indexChangedObservers 多播路径自动跑
     - groups 重新有值
     - ContentView .onChange(of: groups) → prune selectedSha256s

[T7] 用户回「重复清理」总览
     - 看到组列表 (含 prune 后 selectedSha256s 仍勾选)
     - 看到「移入废纸篓 (N 张)」按钮 (N = prune 后)
     - 用户 confirm 后再次点按钮
     - trashSelected() 入口 guard 检查 schemaVersion >= 2 通过
     - 走 V2 主流程 → 真删除 + banner 显示
     - 端到端闭环达成 ✓
```

---

## 6. 错误处理边界

### 6.1 7 类错误场景 + 处理策略

| # | 错误场景 | 触发时机 | 处理策略 | 用户感知 |
|---|---|---|---|---|
| 1 | NSOpenPanel 用户 Cancel | T4.c | `coordinator.cancel()` → phase = .idle | sheet 关，零状态变化 |
| 2 | NSOpenPanel 返回空 urls | T4.c | 等同 Cancel | 同上 |
| 3 | `saveBookmark` 抛错（V2 path 几乎不可能但兜底） | T4.d.3 内部 `addFolders` Task | 沿用 V2 既有 `bridge.lastError` 错误 banner（codex P1 修#4：sheet 不重弹错误态避免与 banner 路径并存）；全失败时 `bridge.fireIndexChanged` 永不触发 → `markSchemaV2` 不调 → 下次入口仍引导 | 主区顶部红色错误 banner（既有 UX） |
| 4 | `reloadFromDefaults` 抛错 | T4.d.2 | 不接错（内部已 try? + nil 兜底） | 透明 |
| 5 | 重扫过程中部分目录权限 / IO 错 | T5 异步 | 沿用 V2 既有 `bridge.lastError` 错误 banner（V2 索引错误 banner 任务 已 ship） | 主区顶部红色错误 banner（既有 UX） |
| 6 | 重扫期间用户再次点「移入废纸篓」 | T5 异步窗口 | trashSelected 入口 guard 放行（schemaVersion=2 已 mark）+ groups 可能为空 → 按钮 disabled（selectedDuplicateCount=0）软阻塞 | 按钮 disabled |
| 7 | **用户漏选部分原 V1 roots（codex P1 修#3 新增）** | T4.d.b NSOpenPanel `.OK` 但选的 root 少于原 V1 集合 | **设计接受**：D3-bm-ui 拍板的「替换」语义。panel.message 文案明示「替换所有根目录 — 漏选会丢失」让用户知情；不增二次确认；漏掉的 root 数据不在 DB 里也不影响 trashItem | 选完后侧边栏少了原本有的 root，用户须知情后果 |

### 6.2 关键不变量（合同语义）

1. **`clearAllForMigration` 不可单独调用**：仅由 `BookmarkMigrationCoordinator` 在 T4.d 段调用。
2. **`markSchemaV2` 时机绑定 `bridge.fireIndexChanged` 多播首次触发（codex P1 修#1+#2）**：不在 `addFolders` 之后立即调（addFolders 是 fire-and-forget 异步 Task，立即调会让 schemaVersion=2 但持久化里可能还没成功入库的 bookmark）。改成注册一次性 `addIndexChangedObserver`，首次 fire 时确认有数据入库后才 `markSchemaV2` + `removeIndexChangedObserver`。
3. **持久化提交段不是 atomicity（codex P1 修#1）**：`addFolders` 异步内部部分 / 全部失败由 V2 既有 `bridge.lastError` 错误 banner 路径处理（既有 UX），sheet 不接错误态。全失败时 `fireIndexChanged` 永不触发 → `markSchemaV2` 不调 → 下次入口仍引导，用户自然重试。
4. **sheet 不会同时弹两次**：`isPresenting` 是单一权威，phase 状态机保证不会双触发。
5. **重扫期间 trashSelected 不阻塞**：T5 期间用户切到其他视图、回来再点也不强制等。按钮 disabled（selectedDuplicateCount=0）软阻塞。
6. **「替换」而非「补充」（codex P1 修#3）**：本任务语义是「替换所有 V1 根目录为 V2 重新授权的根目录集合」。panel 文案明示，用户漏选的后果是该 root 不再在管理中。

### 6.3 不处理的场景（明确说明）

- **UserDefaults write fail / 磁盘满**：clearAllForMigration / markSchemaV2 内部 `UserDefaults.standard.set/removeObject` 失败属 OS 级灾难，整 app 不可用，不在本任务 scope
- **重扫卡死 / 超时**：V2 既有 FolderScanner + DedupPass 跑，本任务不引入超时机制。用户可手动 cancel（既有 IndexingProgressView chip X 按钮）
- **panel.runModal 期间 app crash**：进程级灾难
- **schemaVersion=2 但持久化空**：靠不变量 2（`markSchemaV2` 绑 `bridge.fireIndexChanged` 多播）锁死，addFolders 全失败时永不触发 markSchemaV2
- **Coordinator 持有的 weak ref 失效**：codex P2 修#1 — `pickRoots()` 入口 `guard let bookmarkManager / folderStore / bridge` 三段 guard，任一失效则静默 return（log + reset phase = .idle），用户感知是 sheet 关 + 看似没反应，下次再点会重试（owner = ContentView 持 `@StateObject` 生命周期跟 ContentView 一致，正常使用不会失效；本兜底只为防 ContentView 意外销毁场景）

---

## 7. 测试策略

### 7.1 三层验收手段

#### 层 1 — 编译层（verify.sh Stage 1+2，自动）

- Stage 1 静态检查：术语字典禁用词扫（`BookmarkMigrationView.swift` / `BookmarkMigrationCoordinator.swift` 命名合规）
- Stage 2 `xcodebuild build`：0 errors + 0 warnings

#### 层 2 — CC 主 agent 自闭环（Mac mini 解锁 + Ghostty/tmux/screencapture/AX 工具链）

5 项自闭环可验：

1. **sheet 渲染** — 起 app → 进「重复清理」总览（V1 时代 sync root 当 bench，schemaVersion<2）→ 勾组 → 点「移入废纸篓」→ AX 验 sheet 出现 + 文案匹配「升级清理权限」+ 截图存证
2. **DisclosureGroup 折起/展开** — AX 找 DisclosureGroup → click → 验展开行可见 + 再 click 折起
3. **「以后再说」按钮** — click → 验 sheet 关 + schemaVersion 仍 < 2 (`defaults read com.sunhongjun.glance bookmarkSchemaVersion` 仍空) + 侧边栏 root 未变 + selectedSha256s 保留
4. **NSOpenPanel 取消** — click「重新选择根目录 →」→ NSOpenPanel 出 → click Cancel → 验 sheet 也关 + 同 3 的状态零变化
5. **重扫期间 chip + 总览空态** — NSOpenPanel 选 ≥1 个 root → 验 sheet 关 + 主区顶部 IndexingProgressView chip 出现 + 总览主区显「重扫中」专用空态

**CC 自闭环未知可行性的项**：NSOpenPanel modal 用 AX 驱动是未验能力，若卡住降级到 PENDING（你本机点 panel）。

#### 层 3 — 真机 PENDING（你本机补验）

3 项必须真机跑：

1. **端到端 trashItem 成功**（覆盖 PENDING M4 任务 2 (a2) + (f)）
   - 重选完 sync root → schemaVersion 切 2 → 总览自动 reload + selectedSha256s prune 后保留 → 点「移入废纸篓」→ 真删 → ~/.Trash 看到副本 → DB row 没了 → banner「已移 N 张 [撤销] [×]」出
   - 点撤销 → 文件回原位 → 总览组 reEvaluate 后副本数对
2. **跨视图持久 banner**（V2 D33 要求）— 触发 banner 后切 V1 folder / 智能文件夹 / 搜索 → banner 一直可见可点
3. **「以后再说」session 持久** — 点「以后再说」关 sheet → 关 app → 重启 app → 进总览再点「移入废纸篓」→ 应再弹引导（schemaVersion 仍 < 2）

### 7.2 不验的项

- 单元测试：项目无 XCTest target（CLAUDE.md 项目 + 全局都说明）
- 性能验收：重扫时长属 V2 既有 PENDING (V2 性能验收任务 deferred)
- 卷类型矩阵：PENDING (b)(c)(d) 是 M4 任务 2 step 5 留下的

---

## 8. 范围 + 任务粒度预告（writing-plans 输入）

### 8.1 本任务范围

- 新建 `BookmarkMigrationView.swift` + `BookmarkMigrationCoordinator.swift`
- 改 `DuplicateOverviewModel.trashSelected()` 入口加 schemaVersion guard + 新依赖注入
- 改 `ContentView` 接 sheet + .environmentObject coordinator + .onChange prune selectedSha256s
- `DesignSystem.swift` 加 `enum BookmarkMigration` 常量

### 8.2 不做

- 不动 `BookmarkManager` V2 API（step 2.0.5 已 ship）
- 不动 `FolderStore.{reloadFromDefaults, addFolders}`（已 ship）
- 不动 `TrashService` / V2 既有 4.5.2 + 4.5.3 主流程
- 不引入设置面板手动入口（design 4.5.4.4 A1.5 单点）
- 不引入「跳过这次」session 持久化
- 不引入 V1 兼容快照 / 双 bookmark slot 并存
- 不引入 NSOpenPanel modal AX 自动化测试基建

### 8.3 任务级拆解预告（codex P2 修#2：合并 A+B 成「升级 UI 端到端」单任务）

**codex P2 修#2 折入说明**：原拆分把任务 A 定为「Coordinator + sheet 框架（pickRoots() 空实现）」，CTA「重新选择根目录」是占位实现 → 不符合 tracer-bullet 三标准（独立 ship 时 CTA 不真工作）。改合并 A+B 成单任务「升级 UI 端到端」让首个可 ship 点真正端到端可跑可感知。

**任务 A — 升级 UI 端到端**
- 新建 `BookmarkMigrationCoordinator.swift` 状态机完整（phase enum + start/cancel + pickRoots() 完整实现含 NSOpenPanel + 持久化提交段 + bridge.addIndexChangedObserver 绑定）
- 新建 `BookmarkMigrationView.swift` SwiftUI sheet（标题 + 文案 + 2 按钮 + DisclosureGroup）
- `DesignSystem.swift` 加 `enum BookmarkMigration`
- `ContentView` 接 sheet + `@StateObject` Coordinator + `.onChange(of: model.groups)` prune selectedSha256s
- `DuplicateOverviewModel.trashSelected` 入口加 schemaVersion guard + 新依赖（bookmarkManager / folderStore / migrationCoordinator）
- `DuplicateOverviewModel.replaceSelectedSha256s(_:)` 新 API
- 任务 A ship 后用户感知：完整端到端 — 点「移入废纸篓」首次弹 sheet → 点「以后再说」关零状态变化 / 点「重新选择根目录 →」弹 NSOpenPanel 选 root 真重选 → schemaVersion 升 → 重扫触发 → 总览自动 reload + selectedSha256s prune → 用户 confirm 后点按钮真 trash → banner 出。**任务 2 端到端闭环达成**（独立可 ship + 端到端可跑 + 用户可感知三标准全过）。

**任务 B — /go 收尾**
- verify.sh 三段
- Roadmap 切「任务 2 端到端闭环达成」
- CLAUDE.md 文件结构加 2 新文件
- PENDING M4 任务 2 段 (a2)/(e)/(f) 标 Done
- 一段话汇报

**总预估**：任务 A + B 约 7-9 commit，一 session 内可一气呵成 ship（GUI 解锁前提下）。

---

## 9. Self-Review（写完后审）

### 9.1 brainstorming 自审

- ✅ **Placeholder scan**：无 TBD / TODO；DS 常量数值具体；文案具体
- ✅ **Internal consistency**：架构（4）/ 时序（5）/ 错误（6）/ 测试（7）/ 范围（8）相互指向，phase 状态机 4 个组件都引用一致
- ✅ **Scope check**：codex P2 修#2 折入后改 2 任务粒度（升级 UI 端到端 + /go 收尾），任务 A 端到端可跑 + 用户可感知 + 独立可 ship — 符合 tracer-bullet 三标准
- ✅ **Ambiguity check**：「重扫中」空态文案具体（不是模糊的「自定义文案」）；持久化提交段 4 步顺序锁死；不变量 6 条明确写出；7 类错误场景明确列出；不处理的场景 5 个明确列出
- ✅ **术语字典**：全程 V2/M4/任务/快速看图器/重复清理/侧边栏/智能文件夹/索引仓 — 无禁用词（按 CONTEXT.md 术语字典 A/E 段对照清）

### 9.2 codex review 折入（2026-06-17 第二轮）

第一轮 codex（PID 80511 / cxc-E2pQbl broker socket）跑 21 分钟后 broker 死了无 verdict。第二轮重启 codex broker + `--effort medium` 后跑通，4 P1 + 2 P2，本 design 已全收：

| 级别 | codex 抓的问题 | 折入位置 |
|---|---|---|
| P1#1 | 「atomicity」语义虚假（addFolders 异步 fire-and-forget，successCount==0 同步看不到） | 改名「持久化提交段」(D3 表 + 4.1.2 + 5.T4.d + 6.2#3)；markSchemaV2 绑 `bridge.fireIndexChanged` 多播首次触发（4.1.2 + 5.T4.d 步骤 4 + 5.T6 + 6.2#2） |
| P1#2 | magic sleep 200/500ms 与索引完成信号并列两套不一致 | 去掉所有 sleep（cancel + pickRoots 末尾）；rescanning→completed→idle 走 observer closure 立即流转 |
| P1#3 | 漏选部分 roots 未列错误类 — clearAllForMigration 先于 addFolders，漏选会丢未选 root | 加 6.1#7「替换」语义错误类；panel.message 文案明示「替换所有根目录 — 漏选会丢失」；6.2 加不变量 6「替换而非补充」 |
| P1#4 | 部分失败时序落不下来 — 主时序立即 .rescanning 但 addFolders 何时返回失败摘要没说 | 改靠 V2 既有 `bridge.lastError` banner 路径，sheet 不重弹；全失败时 `fireIndexChanged` 永不触发 → `markSchemaV2` 不调 → 下次入口仍引导自然重试（5.T5 + 6.1#3 + 6.2#3） |
| P2#1 | 生命周期合同不完整 — start() 后依赖失效 pickRoots() 静默 no-op 没说 | 4.1.2 加「生命周期合同」段：owner = ContentView + weak refs + 失效降级（log + reset .idle）；6.3 加第 5 项不处理场景 |
| P2#2 | 任务 A tracer-bullet 偏弱 — CTA「重新选择根目录」占位实现，独立 ship 不真工作 | 8.3 合并 A+B 成单任务「升级 UI 端到端」，任务 B 单独留 /go 收尾 — 总数从 3 任务降到 2 |
