//
//  SimilarityService.swift
//  Glance
//
//  Vision VNFeaturePrintObservation 包装。两个职责：
//  1. extract(url:) — 单图抽 feature print，返回 (archived Data, revision Int) 给 IndexStore 存
//  2. queryTopN(sourceArchive:candidates:n:) — 给定一张源图 + 候选 list → 算 distance 取 top-N
//
//  序列化：VNFeaturePrintObservation 没有从 raw bytes 重建 observation 的 init，
//  只能走 NSKeyedArchiver/Unarchiver（NSSecureCoding 路径）。所以 IndexStore 存的
//  feature_print blob = NSKeyedArchiver.archivedData(observation, secureCoding: true)。
//
//  距离指标：用 Apple 自带 VNFeaturePrintObservation.computeDistance(_:to:) Float（越小越相似）。
//  CONTEXT.md「俗称余弦距离」是行业速记说法，实际指标以 Apple API 返回值为准。
//

import Foundation
import Vision

nonisolated enum SimilarityService {

    enum SimilarityError: Error {
        case extractFailed(String)
        case unsupportedFormat
        case archiveFailed
        case unarchiveFailed
    }

    /// K.1 — 当前 OS 提供的 Vision feature print 算法版本。VNGenerateImageFeaturePrintRequest()
    /// 默认 init 即取最新支持的 revision。macOS 升级带来 Vision 版本切换时本值会变，
    /// 已存 row 的 feature_print_revision != 当前值即"过期"，需要 reset 重抽（IndexStore.resetFeaturePrintsWithStaleRevision）。
    static var currentRevision: Int {
        VNGenerateImageFeaturePrintRequest().revision
    }

    /// 单图抽 feature print。返回 (archivedData, revision)。读图失败 / Vision 不支持
    /// 该格式 → 抛 .unsupportedFormat（caller 标 supports_feature_print=false 跳过）。
    /// 调用方所在 task 应已 startAccessing root scoped resource（FeaturePrintIndexer 负责）。
    static func extract(url: URL) throws -> (archived: Data, revision: Int) {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(url: url, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw SimilarityError.extractFailed(error.localizedDescription)
        }

        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw SimilarityError.unsupportedFormat
        }

        let archived: Data
        do {
            archived = try NSKeyedArchiver.archivedData(
                withRootObject: observation,
                requiringSecureCoding: true
            )
        } catch {
            throw SimilarityError.archiveFailed
        }

        let revision = request.revision
        return (archived, revision)
    }

    /// 反序列化 archived blob → VNFeaturePrintObservation（cosine 用）。失败抛 .unarchiveFailed。
    static func unarchive(_ data: Data) throws -> VNFeaturePrintObservation {
        guard let observation = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: VNFeaturePrintObservation.self, from: data
        ) else {
            throw SimilarityError.unarchiveFailed
        }
        return observation
    }

    /// Batch top-N 查询。给定源 observation + 候选 [(id, archivedData)] → 算 distance →
    /// 按距离升序取前 n 个 id（不含源 id 自身）。
    /// D13：n 写死 30；caller 传 30 即可。
    /// 性能：10k 候选 unarchive + computeDistance 估算 < 1s（Vision computeDistance 优化过）。
    static func queryTopN(
        source: VNFeaturePrintObservation,
        candidates: [(id: Int64, archivedData: Data)],
        excludingId: Int64,
        n: Int
    ) -> [(id: Int64, distance: Float)] {
        var scored: [(Int64, Float)] = []
        scored.reserveCapacity(candidates.count)

        for (id, data) in candidates {
            guard id != excludingId else { continue }
            guard let candidateObs = try? unarchive(data) else { continue }
            var distance: Float = 0
            do {
                try source.computeDistance(&distance, to: candidateObs)
                scored.append((id, distance))
            } catch {
                continue
            }
        }

        scored.sort { $0.1 < $1.1 }
        return Array(scored.prefix(n))
    }
}
