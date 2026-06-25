//
//  SearchFilterState.swift
//  Glance
//
//  M3 chips — chip 选中态值类型（D22 独立筛选状态）。与 keyword 分离，
//  SearchService.compile(filterState:keyword:) 合并。nonisolated：被 nonisolated
//  compile 及 Task.detached 访问。
//

import Foundation

nonisolated struct SearchFilterState: Equatable {
    var selectedFormats: Set<String> = []      // 值 = ImageMetadataReader.canonicalFormatLabels 子集
    var selectedSize: SearchSizeBucket? = nil
    var selectedTime: SearchTimeBucket? = nil

    var isEmpty: Bool { selectedFormats.isEmpty && selectedSize == nil && selectedTime == nil }

    /// 转成 SmartFolderAtom（类型 inSet / 大小 > / 时间 between）。now 注入便于测试与一致快照。
    func toAtoms(now: Date) -> [SmartFolderAtom] {
        var atoms: [SmartFolderAtom] = []
        if !selectedFormats.isEmpty {
            // D23：inSet + 同源大写标签精确匹配，无需 NOCASE。sorted 让输出稳定（测试/缓存友好）。
            atoms.append(.init(field: .format, op: .inSet, value: .stringArray(selectedFormats.sorted())))
        }
        if let size = selectedSize {
            atoms.append(.init(field: .fileSize, op: .greaterThan, value: .int(size.bytes)))
        }
        if let time = selectedTime {
            atoms.append(.init(field: .birthTime, op: .betweenDuration,
                               value: .relativeTimeRange(start: time.startToken(now: now), end: "now")))
        }
        return atoms
    }
}

/// 大小档（decimal，与 size: modifier 一致；1MB=1_000_000）。
/// Hashable：SearchFilterState Equatable + ForEach(id:\.self) 需要（codex）。
nonisolated enum SearchSizeBucket: CaseIterable, Hashable {
    case mb1, mb5, mb10
    var bytes: Int64 { switch self { case .mb1: return 1_000_000; case .mb5: return 5_000_000; case .mb10: return 10_000_000 } }
    var label: String { switch self { case .mb1: return ">1MB"; case .mb5: return ">5MB"; case .mb10: return ">10MB" } }
}

/// 时间档。各档 = 自然边界（今天 00:00 / 本周起始日 / 本月 1 日 / 今年 1.1）预计算 ISO 绝对时间戳，
/// 走 resolveRelativeTime 的 ISO8601 分支（builder 无自然周/年 token，故 startToken 直接 Calendar 预计算）。
/// label「本周/本月/今年」与实现自然边界一致（P2 codex review：避免滚动窗 -Nd 与 label 语义不符）；timezone 跟随
/// device local，与 D4 时间分段同源。命名 SearchTimeBucket 避开 Glance/FolderBrowser/TimeBucket.swift（codex 编译冲突）。
/// Hashable：同 SearchSizeBucket。
nonisolated enum SearchTimeBucket: CaseIterable, Hashable {
    case today, week, month, year
    var label: String { switch self { case .today: return "今天"; case .week: return "本周"; case .month: return "本月"; case .year: return "今年" } }

    /// betweenDuration 的 start token = 各档自然边界预计算 ISO（device local），end 统一 "now"。
    /// dateInterval 返回 optional，nil 时兜底当日午夜（理论不发生，?? 非 force unwrap）。
    func startToken(now: Date) -> String {
        let cal = Calendar.current
        let start: Date
        switch self {
        case .today:
            start = cal.startOfDay(for: now)                                                    // 今天 00:00
        case .week:
            start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)  // 本周起始日 00:00（locale 决定周一/周日）
        case .month:
            start = cal.dateInterval(of: .month, for: now)?.start ?? cal.startOfDay(for: now)        // 本月 1 日 00:00
        case .year:
            start = cal.dateInterval(of: .year, for: now)?.start ?? cal.startOfDay(for: now)         // 今年 1 月 1 日 00:00
        }
        return Self.isoFormatter.string(from: start)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
}

#if DEBUG
extension SearchFilterState {
    /// inline 验证 toAtoms 映射正确。调用方式：临时挂 GlanceApp.onAppear。
    static func _debugSelfCheck() {
        let now = Date()
        // 空态
        assert(SearchFilterState().isEmpty, "default should be empty")
        // 类型多选 → inSet
        var s = SearchFilterState(); s.selectedFormats = ["PNG", "JPEG"]
        let a = s.toAtoms(now: now)
        assert(a.count == 1 && a[0].field == .format && a[0].op == .inSet, "formats → 1 inSet atom")
        if case .stringArray(let xs) = a[0].value { assert(xs == ["JPEG", "PNG"], "sorted") } else { assertionFailure("stringArray") }
        // 大小 → file_size >
        var s2 = SearchFilterState(); s2.selectedSize = .mb5
        let a2 = s2.toAtoms(now: now)
        assert(a2.count == 1 && a2[0].field == .fileSize && a2[0].op == .greaterThan)
        if case .int(let b) = a2[0].value { assert(b == 5_000_000) } else { assertionFailure("int") }
        // 时间「今天」→ between，start 是 ISO（含 'T'），不是 "-Nd"
        var s3 = SearchFilterState(); s3.selectedTime = .today
        let a3 = s3.toAtoms(now: now)
        assert(a3.count == 1 && a3[0].op == .betweenDuration)
        if case .relativeTimeRange(let start, let end) = a3[0].value {
            assert(start.contains("T") && end == "now", "today start = ISO midnight, end = now")
        } else { assertionFailure("relativeTimeRange") }
        // 时间「本周」→ 自然周起始 ISO（含 'T'），不再是滚动窗 "-7d"
        var s4 = SearchFilterState(); s4.selectedTime = .week
        if case .relativeTimeRange(let start, _) = s4.toAtoms(now: now)[0].value { assert(start.contains("T"), "week start = ISO 自然周边界") }
        // 组合 3 维 → 3 atoms
        var s5 = SearchFilterState(); s5.selectedFormats = ["PNG"]; s5.selectedSize = .mb1; s5.selectedTime = .month
        assert(s5.toAtoms(now: now).count == 3, "3 dims → 3 atoms")
        print("[SearchFilterState] _debugSelfCheck: all passed")
    }
}
#endif
