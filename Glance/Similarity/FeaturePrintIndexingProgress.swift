//
//  FeaturePrintIndexingProgress.swift
//  Glance
//
//  M2 Slice J — feature print indexer 进度 record。Equatable 让 .onChange 能观察。
//

import Foundation

struct FeaturePrintIndexingProgress: Equatable {
    /// 已抽取并写入 IndexStore 的图数量
    let indexed: Int
    /// 当前批次的总待抽数（initial fetch 时定值，每批 progress 都用同一 total）
    let total: Int
    /// 最近一张抽取成功的图文件名（UI 简洁展示用）
    let lastImageName: String
}
