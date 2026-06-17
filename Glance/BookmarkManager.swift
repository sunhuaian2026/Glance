//
//  BookmarkManager.swift
//  Glance
//

import Foundation
import Combine

class BookmarkManager: ObservableObject {
    private let defaultsKey = "savedBookmarks"

    /// UserDefaults int key, 标记当前持久化 bookmark 的 schema 版本.
    /// V1 (read-only) = 0 或 missing; V2 (read-write) = 2.
    /// 用于 M4 任务 2 「移入废纸篓」入口判别是否需要清旧 bookmark + 引导用户重选
    /// (D-M4-1 + design 4.5.4, 2026-06-17 codex review 第五轮 A 方向).
    private static let schemaVersionKey = "bookmarkSchemaVersion"

    /// 当前已持久化 bookmark 的 schema 版本 (0 = V1 read-only, 2 = V2 read-write).
    var currentSchemaVersion: Int {
        UserDefaults.standard.integer(forKey: Self.schemaVersionKey)
    }

    /// 标记当前持久化 bookmark 已升级到 V2.
    /// 触发时机: 用户走 NSOpenPanel grant 流程重选 >= 1 个 root 后,
    /// 在第一个 saveBookmark 成功后立即调.
    func markSchemaV2() {
        UserDefaults.standard.set(2, forKey: Self.schemaVersionKey)
    }

    /// V2 升级触发点用 — 一次性清空 V1 持久化 bookmark + 重置 schema version 为 0.
    /// 调用方拿到返回后立刻调 FolderStore.reloadFromDefaults() 同步内存 + 弹引导 UI.
    ///
    /// 调用约束: 仅在 V2 升级触发点 (M4 删除入口首次) 由 DuplicateOverviewModel.trashSelected
    /// 入口前置调一次, 之后流程内的 currentSchemaVersion == 2 判别会让本 API 不重复触发.
    func clearAllForMigration() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UserDefaults.standard.set(0, forKey: Self.schemaVersionKey)
    }

    /// 为用户选择的文件夹创建 bookmark 并持久化
    /// V2 起去掉 .securityScopeAllowOnlyReadAccess flag, 让 scope 携带写权限
    /// (trashItem 必需; D-M4-1 + design 4.5.4.1).
    /// V1 既有 bookmark 走 clearAllForMigration + 用户重选迁移路径.
    func saveBookmark(for url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        var bookmarks = loadRawBookmarks()
        bookmarks[url.absoluteString] = data
        UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
    }

    /// 恢复所有已保存的 bookmark，返回可访问的 URL 列表
    func restoreBookmarks() -> [URL] {
        var bookmarks = loadRawBookmarks()
        var validURLs: [URL] = []
        var staleKeys: [String] = []

        for (key, data) in bookmarks {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    staleKeys.append(key)
                } else {
                    validURLs.append(url)
                }
            } catch {
                staleKeys.append(key)
            }
        }

        if !staleKeys.isEmpty {
            for key in staleKeys {
                bookmarks.removeValue(forKey: key)
            }
            UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
        }

        return validURLs
    }

    /// 开始访问指定 URL，返回是否成功
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    /// 停止访问指定 URL
    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    /// 当前持久化的受管根文件夹路径集（standardizedFileURL.path，与 IndexStore root_path 对齐）。
    /// 同步读 UserDefaults，是"受管根"的真权威来源——不像 FolderStore.rootFolders 那样异步滞后
    /// （loadSavedFolders 在 Task 内才赋值 rootFolders）。索引对账删除以此为准，避免启动瞬态空集误删整库。
    func managedRootPaths() -> Set<String> {
        Set(loadRawBookmarks().keys.compactMap { URL(string: $0)?.standardizedFileURL.path })
    }

    /// 删除指定 URL 对应的 bookmark
    func removeBookmark(for url: URL) {
        var bookmarks = loadRawBookmarks()
        bookmarks.removeValue(forKey: url.absoluteString)
        UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
    }

    // MARK: - Private

    private func loadRawBookmarks() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }
}
