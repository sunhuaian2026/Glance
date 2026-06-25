//
//  SmartFolderState.swift
//  Glance
//
//  Slice I.3 — SmartFolderStore 状态机重构。原 selected/queryResult/isQuerying/
//  lastError 四个独立 @Published 容易 race（query 跑过程中切 SF / refresh 重入）；
//  合并为单一 state enum 让无效组合不可表达（"isQuerying=true && queryResult 非空"等）。
//

import Foundation

enum SmartFolderState: Equatable {
    /// 初始 / 用户清 selection / IndexStore 未就绪
    case idle
    /// query 进行中。`staleImages` carry 上一次 .loaded 的结果（同 SF refresh 场景），
    /// 让 grid 在 loading 期间继续渲染旧数据避免视觉闪烁；切到新 SF 时传 `[]`。
    case loading(SmartFolder, staleImages: [IndexedImage])
    /// query 成功（grid 显示结果，可能为空数组 = 无图）
    case loaded(SmartFolder, [IndexedImage])
    /// query 失败（grid 显示错误占位 + lastError 文案）
    case error(SmartFolder, String)
}
