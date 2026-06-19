//
//  DedupListFilter.swift
//  Glance
//
//  重复清理 V2 — 工具条筛选 pills 三档值类型 (design v2 §2.1 + §4.3)
//  联动 needsReview (D3 = duplicateCount >= 3) + reviewedGroupIds 判断
//

import Foundation

enum DedupListFilter: String, CaseIterable, Equatable {
    case all
    case needsReview
    case auto
}
