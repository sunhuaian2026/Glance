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
import Combine
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
