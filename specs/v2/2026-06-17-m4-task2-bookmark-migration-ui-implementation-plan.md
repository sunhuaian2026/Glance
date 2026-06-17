# Glance V2 M4 任务 2 收尾实施计划 — V1→V2 bookmark 升级引导 UI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 design `specs/v2/2026-06-17-m4-task2-bookmark-migration-ui-design.md`（commits `90ef7bf` + `91c5289`）落地成 2 任务可一气呵成 ship 的实施步骤；让 V1 时代 bookmark 用户首次点「移入废纸篓」能看到引导 sheet → NSOpenPanel 重选 → V2 重扫 → 真删除的端到端闭环。

**Architecture:** ContentView 持 `@StateObject BookmarkMigrationCoordinator` 单一权威；`DuplicateOverviewModel.trashSelected()` 入口加 `schemaVersion >= 2` guard，否则触发 Coordinator 弹 sheet；Coordinator 内部 NSOpenPanel + 持久化提交段 + 一次性 `bridge.addIndexChangedObserver` 等首次入库 → markSchemaV2。复用既有 BookmarkManager V2 + FolderStore + IndexingProgressView chip + bridge 多播。

**Tech Stack:** SwiftUI .sheet / NSOpenPanel / @MainActor ObservableObject / FolderStoreIndexBridge 多播 / DesignSystem 常量。

---

## File Structure

**新建（2 个）**：

- `Glance/Migration/BookmarkMigrationView.swift` — SwiftUI sheet 纯展示 view（标题 + 文案 + 2 按钮 + DisclosureGroup）
- `Glance/Migration/BookmarkMigrationCoordinator.swift` — `@MainActor` ObservableObject 状态机（phase enum + start/cancel + pickRoots async）

**修改（4 个）**：

- `Glance/DesignSystem.swift` — 加 `enum BookmarkMigration`（sheet 尺寸 / 文案字号 / 按钮间距常量）
- `Glance/Dedup/DuplicateOverviewModel.swift` — `attach()` 扩展 3 个新依赖（bookmarkManager / folderStore / migrationCoordinator）+ `trashSelected()` 入口加 schemaVersion guard + 新 API `replaceSelectedSha256s(_:)` + 内部「重扫中空态」展示标志
- `Glance/ContentView.swift` — 加 `@StateObject migrationCoordinator` + `@EnvironmentObject` 拿 BookmarkManager + `wireIfReady` 改 `attach` 传新依赖 + `.sheet(isPresented:)` 接 BookmarkMigrationView + `.onChange(of: groups)` prune selectedSha256s
- `Glance/Dedup/DuplicateOverviewView.swift` — 加「重扫中」专用空态分支（D4-bm-ui 拍板，区别于「没找到重复图」）

**Note**: 新建文件夹 `Glance/Migration/`（mirror 既有 `Glance/Dedup/` / `Glance/QuickViewer/` 等模块级分组模式）。xcodeproj 用 PBXFileSystemSynchronizedRootGroup，新建子目录会自动加入编译。

---

## design 偏差修正（codex review 漏掉的小错）

design 4.1.2 假设 `folderStore.bridge`，但代码现状 bridge 实际在 `ContentView @State indexBridge` 上，不在 FolderStore 上。**本 plan 修正**：BookmarkMigrationCoordinator.start() 签名加 `bridge: FolderStoreIndexBridge` 参数，由 ContentView 注入。

---

## 任务 A — 升级 UI 端到端

> 任务 A ship 后用户感知：完整端到端 — V1 用户点「移入废纸篓」弹 sheet → 「以后再说」零状态变化 / 「重新选择根目录 →」NSOpenPanel 真重选 → schemaVersion 升 → 重扫 → 总览自动 reload + selectedSha256s prune → 用户 confirm 后真 trash → banner 出。**任务 2 端到端闭环达成**。

### 步骤 A.1: `DesignSystem.swift` 加 `enum BookmarkMigration` 常量

**Files:**
- Modify: `Glance/DesignSystem.swift`（在 `enum Dedup { ... }` 后插入新 enum）

- [ ] **Step 1: 找到 `enum Dedup { }` 结尾位置**

Run: `grep -n "^    enum Dedup\|^    }$\|^    enum Icon" Glance/DesignSystem.swift | head -5`
预期: 看到 enum Dedup 起始行 + 结尾的 `}` 行 + 下方 `enum Icon` 起始行。

- [ ] **Step 2: 在 enum Dedup 结尾后、enum Icon 前插入 enum BookmarkMigration**

新增代码（插在 `enum Icon { ... }` 前）：

```swift
    // MARK: - M4 任务 2 — V1→V2 bookmark 升级引导 UI 常量

    enum BookmarkMigration {
        /// sheet 最小宽度
        static let sheetMinWidth: CGFloat = 420
        /// sheet 垂直内边距
        static let sheetVerticalPadding: CGFloat = 24
        /// sheet 水平内边距
        static let sheetHorizontalPadding: CGFloat = 28
        /// 标题字号 (.title3 weight semibold)
        static let titleFont: Font = .title3.weight(.semibold)
        /// 主文案字号
        static let bodyFont: Font = .body
        /// DisclosureGroup 「为什么」展开行字号
        static let disclosureFont: Font = .callout
        /// 主文案与按钮区垂直间距
        static let contentSpacing: CGFloat = 20
        /// 两按钮间距
        static let buttonSpacing: CGFloat = 12
        /// 「重扫中」总览专用空态字号
        static let rescanEmptyStateFont: Font = .body
    }
```

- [ ] **Step 3: build 验证**

Run: `make build 2>&1 | tail -8`
预期: `** BUILD SUCCEEDED **` + 0 warnings + version 含本次 commit hash 前缀（dirty 标 `-d` 显示）

- [ ] **Step 4: grep 验证常量存在**

Run: `grep -n "enum BookmarkMigration\|static let sheetMinWidth\|static let titleFont\|static let rescanEmptyStateFont" Glance/DesignSystem.swift`
预期: 4 行命中（enum 起始 + 3 个常量）。

- [ ] **Step 5: commit**

```bash
git add Glance/DesignSystem.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-bm-ui-A.1): DS.BookmarkMigration 加引导 sheet UI 常量

sheetMinWidth=420 / sheetVerticalPadding=24 / sheetHorizontalPadding=28
+ titleFont/bodyFont/disclosureFont 三档字号 + contentSpacing=20 / buttonSpacing=12
+ rescanEmptyStateFont (重扫中总览专用空态).

design 4.1.5 + codex review 第二轮折入 (P2 修#2 任务 A+B 合并端到端).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

**codex pre-push 预期**: 本步骤是 commit 不 push，pre-push hook 不触发。

---

### 步骤 A.2: 新建 `Glance/Migration/BookmarkMigrationView.swift`

**Files:**
- Create: `Glance/Migration/BookmarkMigrationView.swift`

- [ ] **Step 1: 新建文件夹 + 文件**

Run: `mkdir -p Glance/Migration && ls Glance/Migration/`
预期: 空目录（仅 `.`/`..`）。

- [ ] **Step 2: 写入完整 BookmarkMigrationView 代码**

```swift
//
//  BookmarkMigrationView.swift
//  Glance
//
//  M4 任务 2 收尾 — V1→V2 bookmark 升级引导 sheet 纯展示 view.
//  状态由 BookmarkMigrationCoordinator 持, 本 view 不持状态.
//  入参: onConfirm (点「重新选择根目录 →」) / onDismiss (点「以后再说」).
//  D1-bm-ui 拍 SwiftUI .sheet 形态. D6-bm-ui 拍三句话简洁 + DisclosureGroup 默认折起.
//

import SwiftUI

struct BookmarkMigrationView: View {
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    @State private var showWhy: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.BookmarkMigration.contentSpacing) {
            Text("升级清理权限")
                .font(DS.BookmarkMigration.titleFont)

            Text("Glance 早期版本使用只读授权，无法把图片移入废纸篓。请重新选择你的根目录，授予写权限。一次性操作。")
                .font(DS.BookmarkMigration.bodyFont)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup(isExpanded: $showWhy) {
                Text("macOS 沙盒授权模型限定：只读 bookmark 不能升级为读写，必须重新创建。")
                    .font(DS.BookmarkMigration.disclosureFont)
                    .foregroundStyle(.secondary)
                    .padding(.top, DS.Spacing.xs)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                Text("为什么需要重新选?")
                    .font(DS.BookmarkMigration.disclosureFont)
            }

            HStack(spacing: DS.BookmarkMigration.buttonSpacing) {
                Spacer(minLength: DS.Spacing.zero)
                Button("以后再说") { onDismiss() }
                    .buttonStyle(.bordered)
                Button("重新选择根目录 →") { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, DS.BookmarkMigration.sheetVerticalPadding)
        .padding(.horizontal, DS.BookmarkMigration.sheetHorizontalPadding)
        .frame(minWidth: DS.BookmarkMigration.sheetMinWidth)
    }
}
```

- [ ] **Step 3: build 验证**

Run: `make build 2>&1 | tail -8`
预期: `** BUILD SUCCEEDED **` + 0 warnings.

- [ ] **Step 4: grep 验证文件存在 + 关键符号**

Run: `grep -n "struct BookmarkMigrationView\|onConfirm: () -> Void\|onDismiss: () -> Void\|升级清理权限\|为什么需要重新选" Glance/Migration/BookmarkMigrationView.swift`
预期: 5 行命中。

- [ ] **Step 5: commit**

```bash
git add Glance/Migration/BookmarkMigrationView.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-bm-ui-A.2): BookmarkMigrationView SwiftUI sheet 纯展示

标题「升级清理权限」+ 三句话主文案 + 两按钮 (.bordered「以后再说」 +
.borderedProminent「重新选择根目录 →」keyboardShortcut .defaultAction) +
DisclosureGroup 默认折起「为什么需要重新选?」单行技术解释.

D1-bm-ui SwiftUI .sheet 形态 + D6-bm-ui 三句话简洁 + DisclosureGroup 折起.
本 view 不持状态, 状态由 BookmarkMigrationCoordinator 持 (步骤 A.3).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### 步骤 A.3: 新建 `Glance/Migration/BookmarkMigrationCoordinator.swift`

**Files:**
- Create: `Glance/Migration/BookmarkMigrationCoordinator.swift`

- [ ] **Step 1: 写入完整 Coordinator 代码**

注意 design 偏差修正：`start()` 签名加 `bridge: FolderStoreIndexBridge` 参数（design 假设 `folderStore.bridge` 不存在，bridge 实际在 ContentView 持）。

```swift
//
//  BookmarkMigrationCoordinator.swift
//  Glance
//
//  M4 任务 2 收尾 — V1→V2 bookmark 升级触发流状态机 (单一权威).
//  Owner: ContentView 持 @StateObject migrationCoordinator (生命周期跟主窗口一致).
//  依赖注入: DuplicateOverviewModel.trashSelected() 入口 guard 触发
//  migrationCoordinator.start(model:bookmarkManager:folderStore:bridge:).
//  weak refs 防循环引用; pickRoots() 入口三段 guard 失效降级 (codex P2 修#1).
//
//  生命周期合同:
//  - 正常使用不会失效 (所有 strong 持有方跟主窗口同生命周期)
//  - 失效场景仅作兜底, 用户感知是 sheet 关看似没反应, 下次再点会重试
//

import Foundation
import AppKit
import SwiftUI

@MainActor
final class BookmarkMigrationCoordinator: ObservableObject {
    enum MigrationPhase: Equatable {
        case idle
        case presentingSheet
        case picking
        case rescanning
        case completed
    }

    @Published private(set) var phase: MigrationPhase = .idle
    @Published var isPresenting: Bool = false   // 注: 用 var 让 SwiftUI .sheet(isPresented:) 双向绑定

    private weak var model: DuplicateOverviewModel?
    private weak var bookmarkManager: BookmarkManager?
    private weak var folderStore: FolderStore?
    private weak var bridge: FolderStoreIndexBridge?

    /// 由 DuplicateOverviewModel.trashSelected 入口 guard 触发.
    /// 不直接调 model.trashSelected (避免循环), 重选成功后由 ContentView .onChange prune
    /// selectedSha256s, 用户 confirm 后亲点按钮再走 trashSelected.
    func start(
        model: DuplicateOverviewModel,
        bookmarkManager: BookmarkManager,
        folderStore: FolderStore,
        bridge: FolderStoreIndexBridge
    ) {
        self.model = model
        self.bookmarkManager = bookmarkManager
        self.folderStore = folderStore
        self.bridge = bridge
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
        guard let bookmarkManager else {
            NSLog("[bm-migration] pickRoots: bookmarkManager 已释放, 降级 reset .idle")
            cancel()
            return
        }
        guard let folderStore else {
            NSLog("[bm-migration] pickRoots: folderStore 已释放, 降级 reset .idle")
            cancel()
            return
        }
        guard let bridge else {
            NSLog("[bm-migration] pickRoots: bridge 已释放, 降级 reset .idle")
            cancel()
            return
        }
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
                                                    //    addFolders 立即返回, 不同步拿 successCount.

        // codex P1 修#2: rescanning → completed 严格绑定 bridge.fireIndexChanged 多播首次触发.
        // 不用 sleep 魔数. bridge 多播在 FolderScanner 完成首批入库时 fire (V2 既有路径).
        phase = .rescanning
        isPresenting = false

        // 注册一次性 observer 等首次 fireIndexChanged → markSchemaV2 + phase = .completed.
        // (codex P1 修#1: markSchemaV2 不在 addFolders 后立即调, 改在确认首次入库后调)
        var observerToken: UUID?
        observerToken = bridge.addIndexChangedObserver { [weak self, weak bookmarkManager, weak bridge] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard case .rescanning = self.phase else { return }
                bookmarkManager?.markSchemaV2()      // 4. 确认有数据入库后才升 schemaVersion = 2
                self.phase = .completed
                if let token = observerToken {
                    bridge?.removeIndexChangedObserver(token)
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

    /// placeholder 工厂用于 SwiftUI #Preview / 初始 @StateObject 注入.
    static func placeholder() -> BookmarkMigrationCoordinator {
        BookmarkMigrationCoordinator()
    }
}
```

- [ ] **Step 2: build 验证**

Run: `make build 2>&1 | tail -8`
预期: `** BUILD SUCCEEDED **` + 0 warnings.

注意: 若编译报 `DuplicateOverviewModel` 未定义（顺序问题），是因为 Coordinator 引用了 DuplicateOverviewModel 类型但本步骤还没改它 — 实际不会，因为 weak ref class 类型已声明在 Glance/Dedup/。若真报错检查 import。

- [ ] **Step 3: grep 验证关键符号**

Run: `grep -n "final class BookmarkMigrationCoordinator\|enum MigrationPhase\|func start(\|func cancel()\|func pickRoots()\|addIndexChangedObserver\|markSchemaV2\|clearAllForMigration" Glance/Migration/BookmarkMigrationCoordinator.swift`
预期: 8 行命中。

- [ ] **Step 4: commit**

```bash
git add Glance/Migration/BookmarkMigrationCoordinator.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-bm-ui-A.3): BookmarkMigrationCoordinator 状态机 + 持久化提交段

MigrationPhase enum (idle / presentingSheet / picking / rescanning / completed) +
@Published phase + isPresenting; weak refs (model / bookmarkManager / folderStore /
bridge) 防循环引用; pickRoots() 入口三段 guard 失效降级 (codex P2 修#1).

start(model:bookmarkManager:folderStore:bridge:) — design 偏差修正: 加 bridge 参数
(原 design 假设 folderStore.bridge 但实际 bridge 在 ContentView @State 持).

pickRoots() 持久化提交段串行 4 步 (clearAll / reloadFromDefaults / addFolders /
一次性 observer 绑 bridge.fireIndexChanged → markSchemaV2 + phase=.completed → .idle).
无 sleep 魔数 (codex P1 修#2); addFolders 异步 fire-and-forget (codex P1 修#1);
panel 文案明示「替换全部根目录」(codex P1 修#3); 失败走 bridge.lastError banner
sheet 不重弹 (codex P1 修#4).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### 步骤 A.4: `DuplicateOverviewModel` 入口改造 + `attach` 扩展 + 新 API

**Files:**
- Modify: `Glance/Dedup/DuplicateOverviewModel.swift`

- [ ] **Step 1: 加 3 个新 weak ref 属性**

定位现有 `private weak var bridge: FolderStoreIndexBridge?`（line 39 附近），在其后加：

```swift
    private weak var bridge: FolderStoreIndexBridge?
    // M4 任务 2 收尾 — V1→V2 bookmark 升级引导 UI 依赖 (步骤 A.4 加).
    private weak var bookmarkManager: BookmarkManager?
    private weak var folderStore: FolderStore?
    private weak var migrationCoordinator: BookmarkMigrationCoordinator?
```

- [ ] **Step 2: 扩展 attach() 签名**

定位 `func attach(indexStore: IndexStore, bridge: FolderStoreIndexBridge)`（line 62 附近），改成：

```swift
    func attach(
        indexStore: IndexStore,
        bridge: FolderStoreIndexBridge,
        bookmarkManager: BookmarkManager,
        folderStore: FolderStore,
        migrationCoordinator: BookmarkMigrationCoordinator
    ) {
        self.indexStore = indexStore
        self.bridge = bridge
        self.bookmarkManager = bookmarkManager
        self.folderStore = folderStore
        self.migrationCoordinator = migrationCoordinator
        // 既有 observer 注册逻辑不变
        let token = bridge.addIndexChangedObserver { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleReload()
            }
        }
        observerToken = token
    }
```

注意: 既有 attach 内部除了赋值 + observer 注册可能还有其它代码，**保留其它行不动**，仅扩展签名 + 新依赖赋值。

- [ ] **Step 3: trashSelected() 入口加 schemaVersion guard**

定位 `func trashSelected() async` 开头 3 行 guard（line 156-159 附近）：

```swift
    func trashSelected() async {
        guard let store = indexStore else { return }
        guard let bridgeRef = bridge else { return }
        guard !selectedSha256s.isEmpty else { return }
```

之后插入新 guard：

```swift
        // M4 任务 2 收尾 — V1→V2 bookmark 升级引导 UI 入口 (步骤 A.4).
        // schemaVersion < 2 = V1 时代 bookmark, trashItem 必失败 (NSCocoa 513). 触发引导.
        guard let bookmarkManager else { return }
        guard let folderStore else { return }
        guard let migrationCoordinator else { return }
        guard bookmarkManager.currentSchemaVersion >= 2 else {
            migrationCoordinator.start(
                model: self,
                bookmarkManager: bookmarkManager,
                folderStore: folderStore,
                bridge: bridgeRef
            )
            return   // V1 路径: 引导触发, trashSelected 本次不执行, 等用户走完引导回来再点按钮
        }
        // V2 路径: 既有 trash 主流程不变 (下面代码)
```

- [ ] **Step 4: 加新 API `replaceSelectedSha256s(_:)`**

定位 `func clearSelection()`（line 133 附近）后插入：

```swift
    /// M4 任务 2 收尾 — D5-bm-ui prune 用. 一次性替换勾选集合 (避免 toggleSelection N 次调用).
    /// ContentView .onChange(of: groups) prune 后调.
    func replaceSelectedSha256s(_ newValue: Set<String>) {
        selectedSha256s = newValue
    }
```

- [ ] **Step 5: build 验证**

Run: `make build 2>&1 | tail -10`
预期: `** BUILD SUCCEEDED **`. 若报 callsite 错误（既有 `attach()` 在 ContentView line 673 调用），是步骤 A.5 的工作，本步不修。本步 build 可能因 ContentView 的旧 attach 调用报错 — 走的话先 commit 本步骤 model 改动，A.5 修 callsite。

**Note**: 若 build 报 ContentView line 673 `attach()` 参数不匹配 — 这是预期的，A.5 步骤会修。本步骤可暂跳 Step 5 build 验证，**改为 step 6 commit 后再 build 让 A.5 一并修复**。或者本步骤改为「本步骤先合并 A.5 一起 commit」。

**决策**：本 plan 选「本步骤 + A.5 合并一个 commit」更稳。**改 commit 时机**：A.4 + A.5 合并到 A.5 末尾一次 commit；本步骤 step 6 skip。

- [ ] **Step 6: grep 验证关键改动**

Run: `grep -n "private weak var bookmarkManager\|private weak var folderStore\|private weak var migrationCoordinator\|bookmarkManager.currentSchemaVersion >= 2\|migrationCoordinator.start\|func replaceSelectedSha256s" Glance/Dedup/DuplicateOverviewModel.swift`
预期: 6 行命中。

- [ ] **Step 7: 暂不 commit，等 A.5 合并**

继续 A.5 修 ContentView 的 attach callsite 让 build 通过，然后 A.5 末尾一并 commit。

---

### 步骤 A.5: `ContentView` 接 `@StateObject` Coordinator + `.sheet` + `.onChange` prune + 修 attach callsite

**Files:**
- Modify: `Glance/ContentView.swift`

- [ ] **Step 1: 加 BookmarkMigrationCoordinator `@StateObject`**

定位 `@StateObject private var duplicateOverviewModel = DuplicateOverviewModel.placeholder()`（line 115 附近），在其后加：

```swift
    @StateObject private var duplicateOverviewModel = DuplicateOverviewModel.placeholder()
    /// M4 任务 2 收尾 — V1→V2 bookmark 升级引导 Coordinator (步骤 A.5 加).
    @StateObject private var migrationCoordinator = BookmarkMigrationCoordinator.placeholder()
```

- [ ] **Step 2: 加 BookmarkManager `@EnvironmentObject`（如果还没注入）**

Run: `grep -n "@EnvironmentObject var bookmarkManager\|@EnvironmentObject var.*BookmarkManager" Glance/ContentView.swift`

若已有则跳过本 Step；若没有则定位 `@EnvironmentObject var folderStore: FolderStore`（line 110 附近），在其前后加：

```swift
    @EnvironmentObject var bookmarkManager: BookmarkManager
```

- [ ] **Step 3: 修 `wireIfReady` 里的 `attach()` callsite**

定位 `duplicateOverviewModel.attach(indexStore: store, bridge: bridge)`（line 673 附近），改成：

```swift
        // M4 任务 2 收尾 — attach 扩展 3 个新依赖 (步骤 A.5).
        duplicateOverviewModel.attach(
            indexStore: store,
            bridge: bridge,
            bookmarkManager: bookmarkManager,
            folderStore: folderStore,
            migrationCoordinator: migrationCoordinator
        )
```

- [ ] **Step 4: NavigationSplitView 外层加 `.sheet`**

定位 NavigationSplitView 整块 modifier 链上 `.overlay(alignment: .top)` 渲染 TrashUndoBanner 段（既有 step 5.4 ship），在其后链 `.sheet`：

```swift
        // 既有 .overlay(alignment: .top) { ... } TrashUndoBanner 不变
        .animation(DS.Anim.normal, value: trashUndoBanner?.id)
        // M4 任务 2 收尾 — bookmark 升级引导 sheet (步骤 A.5 加).
        .sheet(isPresented: $migrationCoordinator.isPresenting) {
            BookmarkMigrationView(
                onConfirm: { Task { await migrationCoordinator.pickRoots() } },
                onDismiss: { migrationCoordinator.cancel() }
            )
        }
```

定位提示: 现有 `.animation(DS.Anim.normal, value: trashUndoBanner?.id)` 是 banner overlay 链的最后一项, .sheet 紧跟它后.

- [ ] **Step 5: 加 `.onChange(of: groups)` prune selectedSha256s**

定位现有 `.onChange(of: duplicateOverviewModel.lastTrashOutcome?.id)`（既有 step 5.4 ship 的 banner 接线），在其后加：

```swift
        // M4 任务 2 收尾 — D5-bm-ui prune selectedSha256s (步骤 A.5).
        // 重扫完总览 reload 后, 把不在新 groups 里的 sha256 从勾选集合移除.
        .onChange(of: duplicateOverviewModel.groups) { _, newGroups in
            let validSha256s = Set(newGroups.map { $0.id })
            let pruned = duplicateOverviewModel.selectedSha256s.intersection(validSha256s)
            if pruned.count != duplicateOverviewModel.selectedSha256s.count {
                duplicateOverviewModel.replaceSelectedSha256s(pruned)
            }
        }
```

- [ ] **Step 6: 确认 BookmarkManager 在 GlanceApp 已注入 environment**

Run: `grep -n "\.environmentObject(.*[Bb]ookmarkManager" Glance/GlanceApp.swift Glance/MainWindow/MainWindowController.swift 2>&1 | head -5`
预期: ≥1 个命中（App level / WindowController level 任一处都行）。

若**没有**命中，需在 `MainWindowController.swift` 加 `.environmentObject(bookmarkManager)` 注入（mirror 其它 envObject 模式）。

- [ ] **Step 7: build 全链验证（A.4 + A.5 合并验）**

Run: `make build 2>&1 | tail -10`
预期: `** BUILD SUCCEEDED **` + 0 warnings.

若报错，先看是否 BookmarkManager 没正确注入 environment (Step 6 没做)。

- [ ] **Step 8: grep 验证关键改动**

Run: `grep -n "@StateObject private var migrationCoordinator\|@EnvironmentObject var bookmarkManager\|migrationCoordinator: migrationCoordinator\|.sheet(isPresented:.*migrationCoordinator.isPresenting\|replaceSelectedSha256s" Glance/ContentView.swift`
预期: 5 行命中。

- [ ] **Step 9: commit（A.4 + A.5 合并）**

```bash
git add Glance/Dedup/DuplicateOverviewModel.swift Glance/ContentView.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-bm-ui-A.5): DuplicateOverviewModel + ContentView 接 Coordinator 端到端

DuplicateOverviewModel 改动 (步骤 A.4 合并):
- 加 3 weak ref (bookmarkManager / folderStore / migrationCoordinator)
- attach() 扩展签名加 3 新依赖
- trashSelected() 入口加 schemaVersion >= 2 guard, V1 路径触发
  migrationCoordinator.start(model:bookmarkManager:folderStore:bridge:)
- 新 API replaceSelectedSha256s(_:) (D5-bm-ui prune 用)

ContentView 改动 (步骤 A.5):
- @StateObject migrationCoordinator (placeholder 初始化)
- @EnvironmentObject bookmarkManager 注入
- wireIfReady 修 attach() callsite 传新依赖
- NavigationSplitView 外层加 .sheet(isPresented:) 接 BookmarkMigrationView
- .onChange(of: groups) prune selectedSha256s (D5-bm-ui)

design 偏差修正: start() 加 bridge 参数 (原 design 假设 folderStore.bridge 不存在).

端到端可跑: V1 用户点「移入废纸篓」首次 → 弹 sheet → 「以后再说」零状态变化 /
「重新选择根目录 →」NSOpenPanel 多选 → schemaVersion 升 → 重扫 → 总览自动 reload +
selectedSha256s prune → 用户 confirm 后点按钮真 trash → banner 出.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### 步骤 A.6: `DuplicateOverviewView` 加「重扫中」专用空态

**Files:**
- Modify: `Glance/Dedup/DuplicateOverviewView.swift`

D4-bm-ui 拍板: 重扫期间总览 swap 到「重扫中」专用空态，区别于既有「没找到重复图」空态。**codex review verdict (P1)**: 不能降级成沿用 emptyState — 用户会误读「正在重扫」为「没找到重复图」，是用户可见行为回退。本步骤必做。

- [ ] **Step 1: 加 `@EnvironmentObject migrationCoordinator` 到 DuplicateOverviewView**

定位 `struct DuplicateOverviewView: View { @EnvironmentObject var model: DuplicateOverviewModel` (line 14 附近)，在 model 后加：

```swift
struct DuplicateOverviewView: View {
    @EnvironmentObject var model: DuplicateOverviewModel
    @EnvironmentObject var migrationCoordinator: BookmarkMigrationCoordinator
```

- [ ] **Step 2: mainContent 加 rescanning 分支（最优先于 emptyState）**

定位 `private var mainContent: some View` computed（line 25 附近）现状：

```swift
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
```

改成（加 rescanning 分支，最优先级，区分自 emptyState）：

```swift
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
```

- [ ] **Step 3: 加 `rescanningState` computed**

定位 `private var emptyState: some View` 后加新 computed：

```swift
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
```

- [ ] **Step 4: ContentView 给 DuplicateOverviewView 注入 migrationCoordinator environmentObject**

定位 ContentView mainContent ZStack 里 `if showDuplicateOverview { DuplicateOverviewView() }` 分支（line 359 附近），mirror 既有 `.environmentObject(duplicateOverviewModel)` 模式确认 migrationCoordinator 也在 detail 区注入链里。

实际上 A.5 step 1 加的 `@StateObject migrationCoordinator` 已经在 ContentView scope，需要在 NavigationSplitView detail closure 内 `.environmentObject(migrationCoordinator)` 注入，让 DuplicateOverviewView 能拿到。

定位 detail 块的 `.environmentObject(smartFolderStore)` / `.environmentObject(duplicateOverviewModel)`（既有 line 245-246 附近）后加：

```swift
            .environmentObject(smartFolderStore)
            .environmentObject(duplicateOverviewModel)
            .environmentObject(migrationCoordinator)
```

- [ ] **Step 5: build 验证**

Run: `make build 2>&1 | tail -8`
预期: `** BUILD SUCCEEDED **` + 0 warnings.

- [ ] **Step 6: grep 验证**

Run: `grep -n "@EnvironmentObject var migrationCoordinator\|case .rescanning = migrationCoordinator.phase\|private var rescanningState\|重新扫描中" Glance/Dedup/DuplicateOverviewView.swift`
预期: 4 行命中。

Run: `grep -n ".environmentObject(migrationCoordinator)" Glance/ContentView.swift`
预期: 1 行命中。

- [ ] **Step 7: commit**

```bash
git add Glance/Dedup/DuplicateOverviewView.swift Glance/ContentView.swift
git commit -m "$(cat <<'EOF'
feat(M4-task2-bm-ui-A.6): DuplicateOverviewView 加重扫中专用空态 (D4-bm-ui)

加 @EnvironmentObject migrationCoordinator + mainContent 加 rescanning 分支
(case .rescanning = migrationCoordinator.phase) 最优先于 emptyState.

rescanningState computed: ProgressView 圆形 + 「重新扫描中…」 主文案 + 「重选根目录后
正在重建图像索引,扫完会自动显示重复组。」副文案. 区别于 emptyState 「没找到重复图」
+ checkmark.seal icon — 用户不再误读「重扫中」为「没找到」.

ContentView NavigationSplitView detail 内加 .environmentObject(migrationCoordinator)
让 DuplicateOverviewView 拿到 Coordinator phase.

codex review verdict P1 修: 不能降级沿用 emptyState (行为回退).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### 步骤 A.7: `make build` 全链 + CC 主 agent 自闭环验证

- [ ] **Step 1: build 全链**

Run: `make build 2>&1 | tail -8`
预期: `** BUILD SUCCEEDED **` + 0 warnings.

- [ ] **Step 2: 杀旧 Glance 进程 + 起 app**

```bash
pkill -9 -f "Glance.app/Contents/MacOS" 2>&1 || true
sleep 2
open -a /Users/sunerpang/projects/claude/glance-v2/build/Glance.app
sleep 5
```

- [ ] **Step 3: 验「sheet 渲染」(项 1)**

前置: sync root 是 V1 时代 bookmark (UserDefaults bookmarkSchemaVersion 键不存在 — 上一 session 已确认)。

```bash
# 找窗口 + 进重复清理总览
swift /tmp/list_glance_window.swift 2>&1 | head -3
# 用 AX 找「重复清理」入口位置 (上一 session: x=400 y=269)
swift /tmp/click.swift 400 269
sleep 1
# 勾第一组 checkbox (上一 session: x=588 y=222)
swift /tmp/click.swift 588 222
sleep 1
# 点「移入废纸篓」按钮 (上一 session: x=1400 y=142)
swift /tmp/click.swift 1400 142
sleep 1
# 验 sheet 出现
osascript <<'EOF' 2>&1
tell application "System Events"
    tell process "Glance"
        set sheetList to every sheet of (first window)
        repeat with s in sheetList
            log "SHEET: pos=" & (position of s as text) & " size=" & (size of s as text)
        end repeat
    end tell
end tell
EOF
# 截图存证
screencapture -l "$(swift /tmp/list_glance_window.swift | grep '一眼' | head -1 | awk -F= '{print $2}' | awk '{print $1}')" /tmp/glance-bm-ui-01-sheet.png 2>&1
```
预期: AX 拿到 sheet + 文案匹配「升级清理权限」+ 截图存证。

- [ ] **Step 4: 验「DisclosureGroup 折起/展开」(项 2)**

```bash
# AX 找 DisclosureGroup
osascript <<'EOF' 2>&1
tell application "System Events"
    tell process "Glance"
        set elList to entire contents of (first window)
        repeat with el in elList
            try
                if role of el is "AXDisclosureTriangle" or role of el is "AXDisclosureRow" then
                    set posList to position of el
                    log "DisclosureGroup: x=" & (item 1 of posList) & " y=" & (item 2 of posList)
                end if
            end try
        end repeat
    end tell
end tell
EOF
# 拿到坐标后 swift /tmp/click.swift <x> <y> 验展开
```
预期: DisclosureGroup 展开后看到「macOS 沙盒授权模型限定...」一行文字。

- [ ] **Step 5: 验「以后再说」(项 3)**

```bash
# AX 找「以后再说」按钮位置 + 点击
osascript <<'EOF' 2>&1
tell application "System Events"
    tell process "Glance"
        set btnList to every button of (first sheet of (first window))
        repeat with b in btnList
            try
                if title of b contains "以后" then
                    set posList to position of b
                    log "Later button: x=" & (item 1 of posList) & " y=" & (item 2 of posList)
                end if
            end try
        end repeat
    end tell
end tell
EOF
# 拿到坐标后 swift /tmp/click.swift <x> <y>
sleep 1
# 验 sheet 关 + schemaVersion 仍 < 2
defaults read com.sunhongjun.glance bookmarkSchemaVersion 2>&1 || echo "schemaVersion 仍未设置 (V1)"
# 验侧边栏 root 未变
osascript -e 'tell application "System Events" to tell process "Glance" to get title of (first window)'
```
预期: sheet 关, `defaults read` 报「does not exist」(schemaVersion 仍 < 2), 侧边栏 sync root 仍在.

- [ ] **Step 6: 验「NSOpenPanel 取消」(项 4)**

```bash
# 再点「移入废纸篓」让 sheet 再弹 (selectedSha256s 仍保留, 上一步 cancel 后不清)
swift /tmp/click.swift 1400 142
sleep 1
# AX 找「重新选择根目录」按钮 + 点击
osascript <<'EOF' 2>&1
tell application "System Events"
    tell process "Glance"
        set btnList to every button of (first sheet of (first window))
        repeat with b in btnList
            try
                if title of b contains "重新选择" then
                    set posList to position of b
                    log "Confirm button: x=" & (item 1 of posList) & " y=" & (item 2 of posList)
                end if
            end try
        end repeat
    end tell
end tell
EOF
# 拿到坐标后 swift /tmp/click.swift <x> <y>
sleep 2
# NSOpenPanel 出现, 找 Cancel 按钮点击
osascript <<'EOF' 2>&1
tell application "System Events"
    tell process "Glance"
        set winList to every window
        repeat with w in winList
            log "Window: " & (name of w)
        end repeat
    end tell
end tell
EOF
# 然后用 AX 点 NSOpenPanel 的 Cancel
```
预期: NSOpenPanel 关 + sheet 也关 + schemaVersion 仍未升 + 侧边栏未变.

**Note**: NSOpenPanel modal 用 AX 驱动是未验能力。若 AX 不稳定卡住，**降级**到 PENDING 让军哥本地点 panel。CC 自闭环不强求此项 100% 通过。

- [ ] **Step 7: 自闭环验完关 Glance**

```bash
pkill -9 -f "Glance.app/Contents/MacOS" 2>&1 || true
sleep 1
echo "self-loop done"
```

- [ ] **Step 8: 截图归集到 ~/sync/**

```bash
mv /tmp/glance-bm-ui-*.png ~/sync/ 2>&1 || true
ls -la ~/sync/glance-bm-ui-*.png 2>&1 | tail -5
```

---

### 步骤 A.8: 写 PENDING + commit + push

**Files:**
- Modify: `specs/PENDING-USER-ACTIONS.md`

- [ ] **Step 1: 在 M4 任务 2 段更新 PENDING (a2)/(e)/(f) 标 Done/CC-验**

定位 `specs/PENDING-USER-ACTIONS.md` 的 M4 任务 2 段（既有「step 5 CC 主 agent 自闭环验」段后）添加：

```markdown
**任务 A 升级 UI 端到端 CC 主 agent 自闭环验** (2026-06-17, build `<本次 commit hash>`, Mac mini 解锁 + Ghostty/tmux/screencapture/AX 工具链):

✅ **项 1 PASS** sheet 渲染 — V1 时代 sync root 当 bench, 勾组点「移入废纸篓」→ AX 验 sheet 出现 + 文案匹配「升级清理权限」+ 截图存证 `~/sync/glance-bm-ui-01-sheet.png`

✅ **项 2 PASS** DisclosureGroup 折起/展开 — AX 找 DisclosureGroup + click 展开 + 文案匹配「macOS 沙盒授权模型限定...」

✅ **项 3 PASS** 「以后再说」按钮 — click → sheet 关 + `defaults read com.sunhongjun.glance bookmarkSchemaVersion` 仍报 does not exist + 侧边栏 sync root 仍在 + selectedSha256s 保留

⏸ **项 4** NSOpenPanel 取消 — CC AX 驱动 NSOpenPanel modal 是未验能力, 实测若卡住降级到军哥本机补验 (M4 任务 2 PENDING (e) 引导 UI 真机走一遍)

⏸ **项 5** 重扫期间 chip + 总览空态 — 需 NSOpenPanel 成功完成才能验, 同项 4 视实测情况降级

**军哥本机补验** (PENDING (a2) 端到端 trashItem + (e) 引导 UI + (f) 重选 root 后 trashItem):
- [ ] (2026-06-17 / `<commit>`) **端到端 trashItem 成功**: 真机点引导 sheet「重新选择根目录 →」→ 选 sync root → schemaVersion 切 2 → 总览自动 reload + selectedSha256s prune → 点按钮真 trash → ~/.Trash 看到副本 → DB row 没了 → banner「已移 N 张 [撤销] [×]」出 → 点撤销 → 文件回原位
- [ ] (2026-06-17 / `<commit>`) **跨视图持久 banner**: 触发 banner 后切 V1 folder / 智能文件夹 / 搜索 → banner 一直可见可点
- [ ] (2026-06-17 / `<commit>`) **「以后再说」session 持久**: 点「以后再说」关 sheet → 关 app → 重启 app → 进总览再点「移入废纸篓」→ 应再弹引导
```

- [ ] **Step 2: commit + push (两段式, codex P2 修)**

```bash
git add specs/PENDING-USER-ACTIONS.md
git commit -m "$(cat <<'EOF'
feat(M4-task2-bm-ui-A.8): CC 自闭环验结果 + 军哥本机补验 PENDING

CC 主 agent 自闭环 (Mac mini 解锁 + Ghostty/tmux/screencapture/AX):
- 项 1 PASS sheet 渲染 (AX 验 + 截图)
- 项 2 PASS DisclosureGroup 折起/展开
- 项 3 PASS「以后再说」schemaVersion 仍 < 2 + 侧边栏未变 + selectedSha256s 保留
- 项 4 + 5 NSOpenPanel modal AX 驱动卡住降级 PENDING (军哥本机补验)

军哥本机补验 3 项: 端到端 trashItem + 撤销 / 跨视图持久 banner /
「以后再说」session 持久.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"

# codex review verdict P2 修: 两段式 push, 先正常 push 让 codex pre-push 评审,
# 命中已知 「异物 reset」 backlog bug 才走 --no-verify 兜底.
git push
# 若上一行成功 → push 完成, 跳过下面.
# 若上一行报 codex 异物 reset 错误 (refs/codex/curated-sync rejected non-fast-forward
# 之类) → 用 --no-verify 兜底 + 汇报里明示「触发异物 reset, 用 --no-verify 绕过」:
#
#   git push --no-verify
```

**codex pre-push 预期**: A.1-A.5 + A.6 + A.8 这些 commit 含 `.swift` 改动，pre-push hook 会触发 codex review。**两段式 push 决策（codex review verdict P2 修）**: 先正常 `git push` 让 codex 评审，若命中已知「异物 reset」backlog bug（上一 session 沉淀）才走 `--no-verify` 兜底，B.5 汇报里**明示**触发了 fallback。这样既不绕过 codex 评审，又对已知 bug 有兜底路径。

- [ ] **Step 3: 验证 push 成功**

Run: `git status && git log --oneline origin/v2/dev..HEAD`
预期: working tree clean, `origin/v2/dev..HEAD` 为空（全部 push 完）.

---

## 任务 B — /go 收尾

> 任务 B 不含代码改动，只走 `/go` 五步收尾（verify + 文档同步 + PENDING + commit + 汇报）。

### 步骤 B.1: `./scripts/verify.sh` 三段

- [ ] **Step 1: 跑 verify.sh**

Run: `./scripts/verify.sh 2>&1 | tail -15`
预期: `=== summary: 13 passed, 0 failed ===` + Stage 2 BUILD SUCCEEDED 0 warnings.

- [ ] **Step 2: 若红, 5 轮内修复重跑**

按 CLAUDE.md `/go` 五步约束: 最多 5 轮 self-fix，5 轮仍红停下来问军哥.

---

### 步骤 B.2: 文档同步（Roadmap / CLAUDE.md / 本 plan 实施记录）

**Files:**
- Modify: `specs/Roadmap.md`
- Modify: `CLAUDE.md`
- Modify: `specs/v2/2026-06-17-m4-task2-bookmark-migration-ui-implementation-plan.md`（本 plan 末尾加实施记录段）

- [ ] **Step 1: 更新 `specs/Roadmap.md` M4 任务 2 状态**

定位「**V2 M4 任务 2 状态（2026-06-17）**」长段，**追加**任务 A commit hash + 任务 2 端到端闭环达成态：

```markdown
+ 任务 A bookmark 升级引导 UI ship: A.1 DS.BookmarkMigration `<A.1 commit>` + A.2 BookmarkMigrationView `<A.2 commit>` + A.3 BookmarkMigrationCoordinator `<A.3 commit>` + A.5 model+ContentView 接 Coordinator `<A.5 commit>` + A.6 重扫中专用空态 `<A.6 commit>` + A.8 CC 自闭环 + PENDING `<A.8 commit>`. **任务 2 端到端闭环达成 (代码层 + 引导 UI 全 ship)** — V1 用户点「移入废纸篓」→ 引导 sheet → NSOpenPanel 重选 → V2 重扫 (总览显「重新扫描中…」专用空态) → 真删 + 撤销 全流程可走. 剩军哥本机真机补验 3 项 (端到端 trashItem + 跨视图持久 banner + 「以后再说」session 持久) + 卷类型矩阵 PENDING (b)(c)(d).
```

- [ ] **Step 2: 更新 `CLAUDE.md` 文件结构段加 2 新文件 + 1 新目录**

定位 `Glance/` 树结构，在 `Glance/MainWindow/` 后插入新分支：

```markdown
    ├── Migration/                  ← M4 任务 2 收尾 — V1→V2 bookmark 升级引导 UI
    │   ├── BookmarkMigrationView.swift       ← SwiftUI sheet 纯展示 (标题「升级清理权限」+ 三句话主文案 + 两按钮 「以后再说」/「重新选择根目录 →」 + DisclosureGroup 默认折起「为什么需要重新选?」单行技术解释); 入参 onConfirm + onDismiss, 不持状态
    │   └── BookmarkMigrationCoordinator.swift ← @MainActor ObservableObject 状态机单一权威 (phase: idle/presentingSheet/picking/rescanning/completed); weak refs (model/bookmarkManager/folderStore/bridge); start(model:bookmarkManager:folderStore:bridge:) + cancel() + pickRoots() async; pickRoots 持久化提交段 4 步串行 (clearAllForMigration + reloadFromDefaults + addFolders + 一次性 bridge.addIndexChangedObserver 等首次入库 → markSchemaV2 + phase=.completed → .idle); NSOpenPanel allowsMultipleSelection=true + 文案明示「替换全部根目录漏选会丢失」(codex P1 修#3); 无 sleep 魔数 (codex P1 修#2); 失效降级三段 guard (codex P2 修#1); 失败走 V2 既有 bridge.lastError banner sheet 不重弹 (codex P1 修#4)
```

并改 `DuplicateOverviewModel.swift` 行的描述, 加任务 A.4 改动:

```markdown
**M4 任务 2 收尾 step A.4 增量**: attach 扩展加 3 weak ref 依赖 (bookmarkManager / folderStore / migrationCoordinator) + trashSelected 入口加 schemaVersion >= 2 guard 触发 migrationCoordinator.start (V1 路径) + 新 API replaceSelectedSha256s(_:) 一次性替换 (D5-bm-ui prune 用)
```

并改 `ContentView.swift` 行的描述, 加任务 A.5 改动:

```markdown
**M4 任务 2 收尾 step A.5 集成**: 加 @StateObject migrationCoordinator + @EnvironmentObject bookmarkManager + wireIfReady 修 attach() callsite 传新依赖; NavigationSplitView 外层 .sheet(isPresented:) 接 BookmarkMigrationView; .onChange(of: groups) prune selectedSha256s (D5-bm-ui)
```

- [ ] **Step 3: 本 plan 末尾加「## 实施记录」段**

在本 plan 文件末尾追加（commit hash 留待真实施时填回）:

```markdown
## 实施记录

### 任务 A — 升级 UI 端到端

- A.1 DS.BookmarkMigration 常量, commit `<pending>` (2026-06-17)
- A.2 BookmarkMigrationView.swift, commit `<pending>` (2026-06-17)
- A.3 BookmarkMigrationCoordinator.swift, commit `<pending>` (2026-06-17)
- A.4 + A.5 DuplicateOverviewModel + ContentView 接 Coordinator (合并 commit), commit `<pending>` (2026-06-17)
- A.6 DuplicateOverviewView 重扫中专用空态 (codex review P1 修, 不降级), commit `<pending>` (2026-06-17)
- A.7 make build + CC 自闭环验 5 项 (无 commit, 验证步骤)
- A.8 CC 自闭环结果 + PENDING 写入 + 两段式 push, commit `<pending>` (2026-06-17)

self-fix 轮次 `<待填>`. codex pre-push 两段式 push 结果 `<待填>`.

### 任务 B — /go 收尾

- B.1 verify.sh 三段, 结果 `<待填: passed/failed 数字>`
- B.2 文档同步 (Roadmap / CLAUDE.md / 本 plan), commit `<pending>` (2026-06-17)
- B.3 PENDING 确认 (任务 A.8 已写)
- B.4 docs-only commit + push, commit `<pending>` (2026-06-17)
- B.5 一段话汇报

**总结**: 任务 2 端到端闭环达成 (代码层 16 commit + 引导 UI X commit = 共 Y commit).
```

---

### 步骤 B.3: PENDING 确认（任务 A.8 已写）

- [ ] **Step 1: 验证 PENDING 已包含任务 A 自闭环结果**

Run: `grep -n "任务 A 升级 UI 端到端 CC 主 agent 自闭环验\|端到端 trashItem 成功\|跨视图持久 banner\|「以后再说」session 持久" specs/PENDING-USER-ACTIONS.md`
预期: 4 行命中（A.8 step 1 已写入）.

若没命中说明 A.8 漏写, 回去补.

---

### 步骤 B.4: docs-only commit + push

- [ ] **Step 1: 添加 docs-only 改动 + 两段式 push (codex P2 修)**

```bash
git add specs/Roadmap.md CLAUDE.md specs/v2/2026-06-17-m4-task2-bookmark-migration-ui-implementation-plan.md
git commit -m "$(cat <<'EOF'
docs(M4-task2-bm-ui-B): 收尾 — Roadmap / CLAUDE.md / 本 plan 实施记录

Roadmap M4 任务 2 状态切「端到端闭环达成 (代码层 16 commit + 引导 UI 实施 ship)」
+ 列任务 A 6 个 commit hash + 剩军哥本机真机补验 3 项 + 卷类型矩阵 PENDING.

CLAUDE.md 文件结构加 Glance/Migration/ 新子目录 (BookmarkMigrationView +
BookmarkMigrationCoordinator) + DuplicateOverviewModel.swift 描述加 step A.4
增量 + ContentView.swift 描述加 step A.5 集成 + DuplicateOverviewView 描述加
step A.6 重扫中专用空态.

本 plan 末尾加实施记录段 (commit hash + self-fix 轮次 + 结果数字回填).

[docs-only]
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
# 两段式 push: 先正常评审, 命中 backlog bug 才 --no-verify
git push
# 若 fail → git push --no-verify (汇报里明示)
```

- [ ] **Step 2: 验证 push 成功**

Run: `git status && git log --oneline origin/v2/dev..HEAD`
预期: working tree clean, `origin/v2/dev..HEAD` 为空.

---

### 步骤 B.5: 一段话汇报

按 CLAUDE.md `/go` Step 5 + feedback_always_report_build_version 要求, 汇报模板:

```
BUILD SUCCEEDED — 0 errors, 0 code warnings  (version: <最新 commit hash>-d.<MMDD-HHMM>)
verify.sh: 13 passed, 0 failed

M4 任务 2 端到端闭环达成 — V1→V2 bookmark 升级引导 UI ship 完整 (任务 A 5 commit + 任务 B 1 docs commit = 共 6 commit 本 session).

任务 A 步骤:
- A.1 DS.BookmarkMigration 常量 (commit <hash>)
- A.2 BookmarkMigrationView 纯展示 sheet (commit <hash>)
- A.3 BookmarkMigrationCoordinator 状态机 + 持久化提交段 (commit <hash>)
- A.4+A.5 DuplicateOverviewModel 入口 + ContentView 接 Coordinator (合并 commit <hash>)
- A.8 CC 自闭环 + PENDING (commit <hash>)

CC 主 agent 自闭环验 5 项: 项 1+2+3 PASS (sheet 渲染 / DisclosureGroup / 「以后再说」),
项 4+5 NSOpenPanel modal AX 驱动卡住降级 PENDING.

self-fix 轮次 <N>. commit-msg hook <M> 次拦字典禁用词.
codex pre-push: <两段式 push 结果 — 「全部正常 push 评审通过」 OR 「触发异物 reset
backlog bug, X 次用 --no-verify 兜底」>.

军哥本机真机补验 3 项 (PENDING M4 任务 2 段):
- (a2) 端到端 trashItem + 撤销
- 跨视图持久 banner (D33)
- 「以后再说」session 持久

下一步: 等军哥真机本机验 3 项, 任务 2 100% closeout.
```

---

## Self-Review

### Spec coverage 核对（design 章节 → plan 步骤映射）

| design 章节 | 范围 | plan 覆盖 |
|---|---|---|
| 4.1.1 BookmarkMigrationView | 范围 | 步骤 A.2 |
| 4.1.2 BookmarkMigrationCoordinator | 范围 | 步骤 A.3 (含 codex 全 4 P1 + P2#1 折入) |
| 4.1.3 trashSelected 入口改造 | 范围 | 步骤 A.4 (合并 A.5 一并 commit) |
| 4.1.4 ContentView 接 sheet + prune | 范围 | 步骤 A.5 |
| 4.1.5 DS.BookmarkMigration | 范围 | 步骤 A.1 |
| 4.2 复用既有 API | 范围 | 步骤 A.3 + A.5 引用 |
| 5 数据流时序 T0-T7 | 范围 | 步骤 A.3 + A.5 实现全覆盖 |
| 6.1 7 类错误 | 范围 | 步骤 A.3 内部代码注释覆盖 |
| 6.2 6 条不变量 | 范围 | 步骤 A.3 代码实现锁死 |
| 6.3 5 类不处理场景 | 范围 | 步骤 A.3 内部 guard + 注释 |
| 7.1 三层验收 | 范围 | 步骤 A.7 (CC 自闭环) + B.1 (verify.sh) + A.8 PENDING (真机) |
| 8.1 范围 | 范围 | 全 plan |
| 8.3 任务粒度 (codex P2 修#2 合并 A+B) | 范围 | 任务 A + 任务 B (B 是 /go 收尾) |

### Placeholder scan

- ✅ 无 TBD/TODO/「implement later」/「add validation」等占位符
- ✅ 每个步骤含完整代码片段（A.1 enum / A.2 view / A.3 coordinator / A.4 model / A.5 ContentView）
- ✅ 每个 grep / build / commit 命令含完整 shell 内容
- ✅ commit message 全用 HEREDOC 完整写出
- ⚠️ `<commit hash>` 占位是 plan 模板必要项（实施时回填）— 接受

### Type consistency 核对

- ✅ `BookmarkMigrationCoordinator` 在 A.3 定义 + A.4 model 引用 + A.5 ContentView 引用 — 命名一致
- ✅ `MigrationPhase` enum 案例 (idle / presentingSheet / picking / rescanning / completed) — A.3 定义全部使用
- ✅ `migrationCoordinator.start(model:bookmarkManager:folderStore:bridge:)` 签名 — A.3 定义 + A.4 trashSelected guard 调用 — 4 参数一致
- ✅ `migrationCoordinator.pickRoots() async` — A.3 定义 + A.5 ContentView .sheet onConfirm 调用一致
- ✅ `migrationCoordinator.cancel()` — A.3 定义 + A.5 ContentView .sheet onDismiss 调用一致
- ✅ `replaceSelectedSha256s(_ newValue: Set<String>)` — A.4 定义 + A.5 ContentView .onChange 调用一致
- ✅ `attach(indexStore:bridge:bookmarkManager:folderStore:migrationCoordinator:)` — A.4 改 + A.5 callsite 改 — 5 参数一致

### Ambiguity check

- ✅ A.4 step 5 build 验证标注「**Note**：若报错跳到 A.5 一并修」明确处理 callsite 不匹配场景
- ✅ A.5 step 6 BookmarkManager environment 注入位置「不确定就先 grep 验证」明确处理
- ✅ A.6 重扫中空态 no-op 决策明确写出（D4 简化方案）
- ✅ A.7 step 4-6 CC 自闭环 NSOpenPanel modal AX 卡住降级 PENDING 明确路径

### 术语字典

- ✅ 全程用 V2 / M4 / 任务 A / 任务 B（三层方法论）
- ✅ 用「快速看图器 / 重复清理 / 智能文件夹 / 索引仓 / 侧边栏 / 缩略图」规范名
- ✅ 无禁用词（按 CONTEXT.md 字典 A/E 段对照清）
- ⚠️ commit message 含「V2 索引错误 banner 任务」/「V2 索引进度任务」等长名是规范命名，符合术语字典新文档强约束

### Scope check

- ✅ 任务 A 8 个子步骤（A.1 DS / A.2 view / A.3 coordinator / A.4 model / A.5 ContentView / A.6 重扫中专用空态 / A.7 验证 / A.8 PENDING + push）符合「6 个子步骤起」要求
- ✅ 任务 B 5 步 /go 收尾（B.1 verify / B.2 文档 / B.3 PENDING / B.4 commit+push / B.5 汇报）符合 `/go` 五步约束
- ✅ 总 commit 数约 7 个（A.1 / A.2 / A.3 / A.5(含 A.4) / A.6 / A.8 / B.4），符合 design 8.3 「7-9 commit」预估

### codex review (plan 第一轮) 折入

codex review 第三轮跑通（plan 阶段第一轮 review）, 无 P0, 1 P1 + 1 P2 全收:

| 级别 | codex 抓的问题 | 折入位置 |
|---|---|---|
| P1 | A.6 重扫中空态降级 — 违反 D4-bm-ui 拍板「专用空态」, 是用户可见行为回退 | A.6 改为正经实现: @EnvironmentObject migrationCoordinator + mainContent 加 rescanning 分支 + rescanningState computed (ProgressView + 「重新扫描中…」+ 副文案) |
| P2 | A.8 `git push --no-verify` 写死 — 绕过正常 pre-push 评审违反「不可逆操作先确认」 | A.8 / B.4 改两段式 push: 先正常 `git push` 让 codex 评审, 命中已知「异物 reset」backlog bug 才 `--no-verify` 兜底; B.5 汇报里明示是否触发 fallback |

Self-review 通过. plan 进 codex review.

---

## 实施记录（2026-06-17 实施完成回填）

### 任务 A — 升级 UI 端到端

- A.1 DS.BookmarkMigration 9 常量, commit `4da5817` (16:10)
- A.2 BookmarkMigrationView.swift, commit `fcee86c` (16:11)
- A.3 BookmarkMigrationCoordinator.swift, commit `99d3d51` (16:14) — 1 轮 self-fix（首轮报 `@Published` 需 Combine 模块，补 `import Combine` 后第二轮 SUCCEEDED）
- A.4 + A.5 DuplicateOverviewModel + ContentView 接 Coordinator (合并 commit), commit `1daed1f` (16:18) — 0 self-fix 单轮 SUCCEEDED, BookmarkManager 已在 `MainWindowController.swift:77` 注入 environment 无需改 controller
- A.6 DuplicateOverviewView 重扫中专用空态 (codex review P1 修, 不降级), commit `162a522` (16:21)
- A.7 make build + CC 自闭环验 5 项 (无 commit, 验证步骤):
  - 项 1 sheet 渲染 ✅ PASS（AX `SHEET_COUNT=1, x=725 y=366 w=470 h=207`, 文案完整, 截图 `~/sync/glance-bm-ui-01-sheet.png`）
  - 项 2 DisclosureGroup 展开 ⏸ partial（渲染存在但 CGEvent click triangle 没触发, AX 找不到「为什么需要重新选?」AXStaticText 精确点, 降级 PENDING）
  - 项 3 「以后再说」 ✅ PASS（sheet 关 + `schemaVersion does not exist` 未升 + sync root 仍在 + checkbox 仍勾 + selectedSha256s 保留 D5 验通）
  - 项 4 NSOpenPanel Cancel ✅ PASS atomicity 完美（panel + sheet 都关 + V1 bookmark 不动 + schemaVersion 未升, D3-bm-ui 拍板验通）
  - 项 5 重扫期间专用空态 ⏸ PENDING（需真选 root 触发 V2 重扫, CC 不能跑会真改 bookmark）
- A.8 CC 自闭环结果 + PENDING 写入 + 两段式 push, commit `650722a` (16:30) — 两段式 push 第一次 `git push` 命中 codex pre-push P2 (DEBUG inline self-check 非项目惯例非阻塞建议) + 紧接着触发已知 codex broker 「异物 reset」backlog bug HEAD 被 reset 到 `refs/codex/curated-sync` codex 自仓库 #335 无关 commit; 修复路径 `git reset --hard 650722a` + `pkill -f codex.*app-server` 杀 broker 清 stale 内部状态 + `git push --no-verify` 三连击成功; reflog 永远在 0 数据丢失
- A.9 GroupKey nonisolated 修 Swift 6 mode warning, commit `eb80ebb` (16:44) — verify.sh Stage 2 报 4 warning (`main actor-isolated conformance of 'GroupKey' to 'Hashable' cannot be used in nonisolated context`); 修法 = 给 `struct GroupKey` 加 `nonisolated` 修饰符让 Hashable 综合 conformance 跳出项目 default main-actor isolation

**self-fix 轮次** = 1 轮（A.3 import Combine）。**codex pre-push 两段式 push** 结果 = 触发已知「异物 reset」backlog bug, `--no-verify` 兜底成功 + 杀 broker 防再次复发。**verify.sh** Stage 2 build SUCCEEDED 0 code warnings（A.9 修后）+ 13 passed 0 failed。

### 任务 B — /go 收尾

- B.1 verify.sh 三段, 结果 13 passed, 0 failed, Stage 2 BUILD SUCCEEDED 0 code warnings（A.9 修后）
- B.2 文档同步 (Roadmap M4 任务 2 状态扩展 + CLAUDE.md 加 Glance/Migration/ 子目录 + 2 个新文件描述 + Dedup/DuplicateOverviewModel/DuplicateOverviewView 描述加 step A.4/A.6 增量 + ContentView 描述加 step A.5 集成 + 本 plan 实施记录回填), commit `6cd1f3c` (2026-06-17)
- B.3 PENDING 确认 (任务 A.8 已写完，含 4 项军哥本机补验)
- B.4 docs-only commit + 两段式 push, commit `6cd1f3c` (2026-06-17)
- B.5 一段话汇报

**总结**: 任务 2 端到端闭环达成 (代码层 16 commit + 引导 UI 7 commit = 共 23 commit 跨多 session)。剩军哥本机真机补验 4 项 → 任务 2 100% closeout。
