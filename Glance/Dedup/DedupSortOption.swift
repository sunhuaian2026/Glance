//
//  DedupSortOption.swift
//  Glance
//
//  重复清理 V2 — 工具条排序分段三档值类型 (design v2 §4.3)
//  · reclaimableDesc: SQL group.reclaimableBytes DESC (默认)
//  · countDesc: group.duplicates.count DESC
//  · nameAsc: canonical.relativePath localeCompare 升序
//

import Foundation

enum DedupSortOption: String, CaseIterable, Equatable {
    case reclaimableDesc
    case countDesc
    case nameAsc
}
