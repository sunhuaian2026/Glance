//
//  SearchInput.swift
//  Glance
//
//  M3 Slice M — SearchService.parse 输出 + compile 输入的中间表示。
//  Silent partial 容错：解析失败的 token 自动落入 keyword 字段（不抛错）。
//

import Foundation

/// SearchService.parse 的结构化输出。
/// nonisolated：纯值类型，被 nonisolated SearchService.parse/compile 及 runSearch 的
/// Task.detached（非 MainActor）访问 isEmpty。项目开了 default main-actor isolation，
/// 不标 nonisolated 会令 isEmpty 默认 @MainActor，在 detached 上下文访问触发隔离 warning。
nonisolated struct ParsedSearch: Equatable {
    /// 成功解析的 modifier 列表（D17：解析失败的 modifier 不进这里，落入 keyword）。
    var modifiers: [SmartFolderAtom]
    /// 剩余 token 拼成的 keyword 串（用空格 join）。空串表示无 keyword（query 只有 modifier）。
    var keyword: String

    /// 空查询的便捷构造：input 全空白 → modifiers/keyword 都空。
    static var empty: ParsedSearch {
        ParsedSearch(modifiers: [], keyword: "")
    }

    /// query 完全无内容（modifiers + keyword 都空）→ caller 跳查询（避免空 query 返全部受管图）。
    var isEmpty: Bool {
        modifiers.isEmpty && keyword.isEmpty
    }
}

/// Size modifier 的单位枚举（decimal 1000^n，跟 macOS Finder 文件大小显示一致）。
/// nonisolated：理由同 ParsedSearch，被 nonisolated SearchService.parseSizeValue 访问。
nonisolated enum SearchSizeUnit: String, CaseIterable {
    case b   // 1
    case k   // 1_000
    case m   // 1_000_000
    case g   // 1_000_000_000

    var multiplier: Int64 {
        switch self {
        case .b: return 1
        case .k: return 1_000
        case .m: return 1_000_000
        case .g: return 1_000_000_000
        }
    }

    /// 解析后缀字符串（case-insensitive；"kb"/"k"/"K" 都识别）。无后缀视为 .b。
    static func parse(_ raw: String) -> SearchSizeUnit? {
        let lower = raw.lowercased()
        if lower.isEmpty { return .b }
        if lower == "b" { return .b }
        if lower == "k" || lower == "kb" { return .k }
        if lower == "m" || lower == "mb" { return .m }
        if lower == "g" || lower == "gb" { return .g }
        return nil
    }
}
