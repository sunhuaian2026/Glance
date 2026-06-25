//
//  DuplicateOverviewState.swift
//  Glance
//
//  M4 任务 1 — 总览状态机。mirror SmartFolderState（SmartFolder/SmartFolderState.swift）：
//  单一 @Published state 替代多独立字段，无效组合从结构上不可表达。
//

import Foundation

enum DuplicateOverviewState: Equatable {
    /// 初始 / 入口未激活
    case idle
    /// 加载中（staleGroups 在 reload 时 carry 旧数据避免清空闪屏）
    case loading(staleGroups: [DuplicateGroup])
    /// 已加载（含空数组 = 真无重复 → view 走空态）
    case loaded(groups: [DuplicateGroup])
    /// load 出错（SQL fail / IndexStore 异常）
    case error(message: String)
}
