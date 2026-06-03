//
//  BookmarkManager.swift
//  Glance
//

import Foundation
import Combine

class BookmarkManager: ObservableObject {
    private let defaultsKey = "savedBookmarks"

    /// 为用户选择的文件夹创建 bookmark 并持久化
    func saveBookmark(for url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
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
