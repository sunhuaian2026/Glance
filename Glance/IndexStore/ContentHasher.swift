//
//  ContentHasher.swift
//  Glance
//
//  Slice H — 文件 SHA256 计算（dedup 用）。CryptoKit + Data(.mappedIfSafe) 让大图
//  通过 mmap 而非全量加载到 RAM；典型图片 < 50MB，10s 内可全部 hash 完。
//

import Foundation
import CryptoKit

// ContentHasher.sha256 由 nonisolated DedupPass 在 detached task 调用，标 nonisolated 避免 actor isolation warning。
nonisolated enum ContentHasher {

    /// 计算文件 SHA256 hex 字符串（小写）。失败返回 nil（caller 决定 retry / 跳过）。
    /// caller 必须先 startAccessingSecurityScopedResource (sandbox)；本函数仅读 file。
    static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
