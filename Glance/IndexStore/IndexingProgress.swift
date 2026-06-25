//
//  IndexingProgress.swift
//  Glance
//
//  Slice I.1 — IndexStoreHolder.progress 的 record struct。从 FolderScanner.ScanProgress
//  (内部 callback 类型) 升级，加 rootPath（root 显示名）+ Equatable 让 .onChange 能观察。
//

import Foundation

struct IndexingProgress: Equatable {
    /// 当前扫描中的 root 显示名（last path component；UI 简洁展示）。
    let rootName: String
    /// 已枚举的文件数（scanned > indexed，因为非图片文件也计 scanned）。
    let scanned: Int
    /// 已写入 IndexStore 的图片行数。
    let indexed: Int
}
