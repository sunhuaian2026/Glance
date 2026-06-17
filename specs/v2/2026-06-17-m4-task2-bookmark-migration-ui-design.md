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
| D3-bm-ui | 取消语义（atomicity） | 延迟 `clearAllForMigration` / `reloadFromDefaults` 到 NSOpenPanel 成功返回后；取消零数据丢失 |
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
    func cancel() {
        phase = .cancelled
        isPresenting = false
        // 一次性状态: 自动 reset 回 idle, 下次入口再 start
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            if case .cancelled = phase { phase = .idle }
        }
    }

    /// 用户点「重新选择根目录 →」.
    /// NSOpenPanel 成功后才走 atomicity 提交 (clear / reload / addFolders / markSchemaV2).
    func pickRoots() async {
        guard let bookmarkManager else { return }
        guard let folderStore else { return }
        phase = .picking

        // NSOpenPanel modal 必须 main thread
        let urls = await MainActor.run { () -> [URL] in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.prompt = "选择所有要清理的根目录"
            panel.message = "重新授权 Glance 访问这些文件夹（含写权限）"
            return panel.runModal() == .OK ? panel.urls : []
        }

        guard !urls.isEmpty else {
            // 用户在 NSOpenPanel Cancel 或选 0 个 → 同 cancel 路径
            cancel()
            return
        }

        // === atomicity 提交段 (串行, 顺序锁死) ===
        bookmarkManager.clearAllForMigration()      // 1. 清旧 bookmark + reset schemaVersion
        folderStore.reloadFromDefaults()            // 2. 内存状态清空 + currentFolderWatcher.stop
        folderStore.addFolders(from: urls)          // 3. 内部循环 saveBookmark V2 + bridge.sync 启重扫
        bookmarkManager.markSchemaV2()              // 4. schemaVersion = 2, 下次入口放行

        // 注: addFolders 内部失败处理由 step 4 errorBoundary 4.4 段定义.
        // 这里假设至少 1 个 url 成功 saveBookmark (V2 path 几乎不可能失败).

        phase = .rescanning
        isPresenting = false

        // rescanning 自动转 completed 由 ContentView .onChange(of: model.groups) 兜底.
        // 重扫完 model.load() 自动跑 (indexChangedObservers 多播), Coordinator 不需要轮询.
        // 一次性状态: completed 自动 reset 回 idle.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if case .rescanning = phase { phase = .completed }
            try? await Task.sleep(nanoseconds: 200_000_000)
            if case .completed = phase { phase = .idle }
        }
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
     分支 A (点「以后再说」): coordinator.cancel() → phase = .cancelled
       → isPresenting = false → sheet 关
       → schemaVersion 仍 < 2, V1 root 不动, selectedSha256s 保留
       → 用户回总览, 下次点「移入废纸篓」再弹
     分支 B (点「重新选择根目录 →」): coordinator.pickRoots() async

[T4] pickRoots() 主路径
     a. phase = .picking
     b. NSOpenPanel runModal (allowsMultipleSelection=true)
     c. 分支 B1 (panel Cancel 或 选 0 个): coordinator.cancel() → 同分支 A
     d. 分支 B2 (panel 选 ≥1 个 url):
        === atomicity 提交段 (串行) ===
        1. bookmarkManager.clearAllForMigration()
        2. folderStore.reloadFromDefaults()
        3. folderStore.addFolders(from: urls)
           [internal] saveBookmark V2 (无 flag) + discoverTree + countImages
           [internal] bridge.sync(with:managedRootPaths:) 自动触发 FolderScanner 重扫
        4. bookmarkManager.markSchemaV2()
        → phase = .rescanning → isPresenting = false (sheet 关)

[T5] 重扫期间 (异步, 跨视图, 用户可切其他视图)
     - 主区顶部 IndexingProgressView chip 「扫描中... X/Y 张」(V2 既有)
     - 「重复清理」总览主区: 显「重扫中」专用空态文案
     - duplicateOverviewModel.scheduleReload 在 indexChangedObservers 多播下自动 reload
     - 用户可点侧边栏切其他视图

[T6] 重扫完 (IndexingProgressView chip 消失 + bridge.fireIndexChanged 触发)
     - duplicateOverviewModel.load() 自动跑
     - groups 重新有值
     - ContentView .onChange(of: groups) → prune selectedSha256s
     - coordinator: rescanning → completed → idle (一次性状态)

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

### 6.1 6 类错误场景 + 处理策略

| # | 错误场景 | 触发时机 | 处理策略 | 用户感知 |
|---|---|---|---|---|
| 1 | NSOpenPanel 用户 Cancel | T4.c | `coordinator.cancel()` → phase = .cancelled | sheet 关，零状态变化 |
| 2 | NSOpenPanel 返回空 urls | T4.c | 等同 Cancel | 同上 |
| 3 | `saveBookmark` 抛错 (V2 path 几乎不可能但兜底) | T4.d.3 内部 `addFolders` 循环 | part-fail-not-all：循环里 catch 单 url 错误 → 累积到 `failedURLs` → 跳过该 url 继续 → 全失败 (successCount == 0) 则 phase = .error 弹错误态 | 错误态 sheet 重弹显「N 个文件夹保存失败」 |
| 4 | `reloadFromDefaults` 抛错 | T4.d.2 | 不接错 (内部已 try? + nil 兜底) | 透明 |
| 5 | 重扫过程中部分目录权限 / IO 错 | T5 异步 | 沿用 V2 既有 `bridge.lastError` 错误 banner (V2 索引错误 banner 任务 已 ship) | 主区顶部红色错误 banner (既有 UX) |
| 6 | 重扫期间用户再次点「移入废纸篓」 | T5 异步窗口 | trashSelected 入口 guard 放行 (schemaVersion=2 已 mark) + 但 groups 可能为空 → 按钮 disabled (selectedDuplicateCount=0) 软阻塞 | 按钮 disabled |

### 6.2 关键不变量（合同语义）

1. **`clearAllForMigration` 不可单独调用**：仅由 `BookmarkMigrationCoordinator` 在 T4.d 段串行调用。
2. **`markSchemaV2` 时机锁死**：必须在 `addFolders` 之后。否则 schemaVersion=2 但持久化空 bookmark，下次启动用户看到「侧边栏空」+ trashSelected 入口放行但拿不到 root 去 trash。
3. **part-fail-not-all 但全失败回滚**：addFolders 内部 N 个 url 里 saveBookmark 部分失败 → 保留成功的、失败的累积到错误 banner；**successCount == 0** 时不调 `markSchemaV2`，phase = .error，用户重试或关。
4. **sheet 不会同时弹两次**：`isPresenting` 是单一权威，phase 状态机保证不会双触发。
5. **重扫期间 trashSelected 不阻塞**：T5 期间用户切到其他视图、回来再点也不强制等。按钮 disabled (selectedDuplicateCount=0) 软阻塞。

### 6.3 不处理的场景（明确说明）

- **UserDefaults write fail / 磁盘满**：clearAllForMigration / markSchemaV2 内部 `UserDefaults.standard.set/removeObject` 失败属 OS 级灾难，整 app 不可用，不在本任务 scope
- **重扫卡死 / 超时**：V2 既有 FolderScanner + DedupPass 跑，本任务不引入超时机制。用户可手动 cancel（既有 IndexingProgressView chip X 按钮）
- **panel.runModal 期间 app crash**：进程级灾难
- **schemaVersion=2 但持久化空**（万一 markSchemaV2 先于 addFolders 调）：靠不变量 2 锁死

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

### 8.3 任务级拆解预告（按 tracer-bullet 三标准：端到端可跑 / 用户可感知 / 独立可 ship）

**任务 A — Coordinator + sheet 框架**
- 新建 `BookmarkMigrationCoordinator.swift` 状态机（phase enum + start/cancel + pickRoots() 空实现）
- 新建 `BookmarkMigrationView.swift` SwiftUI sheet（标题 + 文案 + 2 按钮 + DisclosureGroup）
- `DesignSystem.swift` 加 `enum BookmarkMigration`
- `ContentView` 接 sheet + `@StateObject` Coordinator
- `DuplicateOverviewModel.trashSelected` 入口加 schemaVersion guard + 新依赖
- 任务 A ship 后用户感知：点「移入废纸篓」首次弹 sheet，可点「以后再说」关，可点「重新选择根目录 →」但不真重选（NSOpenPanel 调用是任务 B）。验收等价 = sheet 渲染 + 文案 + 取消路径

**任务 B — NSOpenPanel + atomicity 提交**
- `pickRoots() async` 实现（NSOpenPanel + atomicity 提交段）
- phase 状态机扩展（picking / rescanning / completed / error）
- ContentView `.onChange(of: model.groups)` prune selectedSha256s
- `DuplicateOverviewModel.replaceSelectedSha256s(_:)` 新 API
- 任务 B ship 后用户感知：完整重选 → schemaVersion 升 → 重扫触发 → 总览自动 reload + selectedSha256s prune → 用户 confirm 后点按钮真 trash → banner 出。任务 2 端到端闭环达成

**任务 C — /go 收尾**
- verify.sh 三段
- Roadmap 切「任务 2 端到端闭环达成」
- CLAUDE.md 文件结构加 2 新文件
- PENDING M4 任务 2 段 (a2)/(e)/(f) 标 Done
- 一段话汇报

**总预估**：任务 A + B + C 合起来约 8-10 commit，一 session 内可一气呵成 ship（GUI 解锁前提下）。

---

## 9. Self-Review（写完后审）

- ✅ **Placeholder scan**：无 TBD / TODO；DS 常量数值具体；文案具体
- ✅ **Internal consistency**：架构（4）/ 时序（5）/ 错误（6）/ 测试（7）/ 范围（8）相互指向，phase 状态机 4 个组件都引用一致
- ✅ **Scope check**：3 任务粒度，每个端到端可跑 + 用户可感知 + 独立可 ship — 符合 tracer-bullet 三标准
- ✅ **Ambiguity check**：「重扫中」空态文案具体（不是模糊的「自定义文案」）；atomicity 段 4 步顺序锁死；不变量 5 条明确写出；不处理的场景 4 个明确列出
- ✅ **术语字典**：全程 V2/M4/任务/快速看图器/重复清理/侧边栏/智能文件夹/索引仓 — 无禁用词（按 CONTEXT.md 术语字典 A/E 段对照清）
