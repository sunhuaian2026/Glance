//
//  SearchService.swift
//  Glance
//
//  M3 Slice M — 搜索 input parser + 编译成 SmartFolderPredicate。
//  D17 Silent partial: parse 永不抛错；解析失败的 modifier token 当 keyword fallback。
//  D18: compile 强制带 .managed + .hidden=false + .dedupCanonicalOrNull common filter。
//  D20: 新模块 Glance/Search/ 不污染 SmartFolderEngine；复用 SmartFolderQueryBuilder 走 SQL。
//

import Foundation

nonisolated enum SearchService {

    // MARK: - Parse

    /// 把 raw input 拆成 ParsedSearch。Silent partial 容错。
    static func parse(_ input: String) -> ParsedSearch {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .empty }

        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var modifiers: [SmartFolderAtom] = []
        var keywordTokens: [String] = []

        for token in tokens {
            if let atom = parseModifierToken(token) {
                modifiers.append(atom)
            } else {
                // 未识别 modifier OR 解析失败 → fallback 整 token 当 keyword（D17）
                keywordTokens.append(token)
            }
        }

        return ParsedSearch(
            modifiers: modifiers,
            keyword: keywordTokens.joined(separator: " ")
        )
    }

    /// 解析单个 token；返回 nil 表示不是合法 modifier（caller fallback 当 keyword）。
    private static func parseModifierToken(_ token: String) -> SmartFolderAtom? {
        // 必须含 `:` 且 `:` 前是合法 field name
        guard let colonIdx = token.firstIndex(of: ":") else { return nil }
        let field = String(token[..<colonIdx]).lowercased()
        let expr = String(token[token.index(after: colonIdx)...])
        guard !expr.isEmpty else { return nil }

        switch field {
        case "type":  return parseTypeValue(expr)
        case "size":  return parseSizeValue(expr)
        case "birth": return parseBirthValue(expr)
        default:      return nil   // unknown modifier → fallback keyword
        }
    }

    /// type:png / type:jpeg → .atom(format = ?)
    private static func parseTypeValue(_ expr: String) -> SmartFolderAtom? {
        // type: 须 case-insensitive（design § 6.1）。DB format 实际存**大写**标签（"PNG"/"WebP"，
        // 见 ImageMetadataReader.formatLabel）；这里 lowercased 仅归一，实际大小写无关匹配靠
        // SmartFolderQueryBuilder 对 format 列加 COLLATE NOCASE 实现（大写归一对 "WebP" 无效）。
        let normalized = expr.lowercased()
        // 简单 sanity check：非空 + 仅 alnum（防止 type:>png 这种带 op 的瞎用）
        guard !normalized.isEmpty,
              normalized.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return SmartFolderAtom(field: .format, op: .eq, value: .string(normalized))
    }

    /// size:>1mb / size:<500k / size:2gb → .atom(file_size [op] ?)
    private static func parseSizeValue(_ expr: String) -> SmartFolderAtom? {
        // 拆 op + value
        let (op, numericPart) = extractOp(from: expr, defaultOp: .eq)
        guard !numericPart.isEmpty else { return nil }

        // 拆 number + unit suffix
        let digits = numericPart.prefix(while: { $0.isNumber })
        let unitRaw = String(numericPart.dropFirst(digits.count))
        guard let value = Int64(digits), let unit = SearchSizeUnit.parse(unitRaw) else {
            return nil
        }
        let (bytes, overflow) = value.multipliedReportingOverflow(by: unit.multiplier)
        guard !overflow else { return nil }
        return SmartFolderAtom(field: .fileSize, op: op, value: .int(bytes))
    }

    /// birth:>2026-01-01 / birth:<2026-05-01 / birth:2026-04-15 (=eq 翻译 between [当日, 次日))
    private static func parseBirthValue(_ expr: String) -> SmartFolderAtom? {
        let (op, dateRaw) = extractOp(from: expr, defaultOp: .eq)
        guard !dateRaw.isEmpty else { return nil }

        // 接受 YYYY-MM-DD 或 ISO 8601 带时区
        guard let parsed = parseISODate(dateRaw) else { return nil }

        // eq 翻译为 betweenDuration [当日 00:00, 次日 00:00)
        // 用 addingTimeInterval(secondsPerDay) 而非 Calendar.current.date(byAdding:)：
        // (1) 不会因 Calendar 失败 fallback 到 parsed 导致 endISO == startISO 的 0 结果 bug；
        // (2) parsed 是 UTC 对齐 instant，Calendar.current 会套本地 DST 让 +1 day 变 23/25h。
        if op == .eq {
            let nextDay = parsed.addingTimeInterval(secondsPerDay)
            let startISO = isoFormatter.string(from: parsed)
            let endISO = isoFormatter.string(from: nextDay)
            return SmartFolderAtom(
                field: .birthTime,
                op: .betweenDuration,
                value: .relativeTimeRange(start: startISO, end: endISO)
            )
        }

        // >/< 用 double timestamp（已支持 emitTimeAtom .greaterThan / .lessThan with .double）
        let ts = parsed.timeIntervalSince1970
        return SmartFolderAtom(field: .birthTime, op: op, value: .double(ts))
    }

    /// 从 "<op><rest>" 拆出 op + rest；无 op 前缀返回 defaultOp + 完整 expr。
    private static func extractOp(from expr: String, defaultOp: SmartFolderOp)
        -> (op: SmartFolderOp, rest: String)
    {
        if expr.hasPrefix(">") { return (.greaterThan, String(expr.dropFirst())) }
        if expr.hasPrefix("<") { return (.lessThan,    String(expr.dropFirst())) }
        if expr.hasPrefix("=") { return (.eq,          String(expr.dropFirst())) }
        return (defaultOp, expr)
    }

    /// 接受 YYYY-MM-DD（视为 UTC 00:00）或 ISO 8601 带时区。失败返回 nil。
    private static func parseISODate(_ raw: String) -> Date? {
        // 先试 ISO 8601 full（带时区）
        if let d = isoFormatter.date(from: raw) { return d }
        // 再试 YYYY-MM-DD（视为 UTC 当日 00:00）
        if let d = dateOnlyFormatter.date(from: raw) { return d }
        return nil
    }

    /// 一天秒数常量（避免魔法数字 86400）。birth:= 翻译 [当日, 次日) 区间用。
    private static let secondsPerDay: TimeInterval = 86_400

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Compile

    /// 把 ParsedSearch 编译成 SmartFolderPredicate（D18 hide 继承 + common filter 自动加）。
    static func compile(_ parsed: ParsedSearch) -> SmartFolderPredicate {
        var atoms: [SmartFolderPredicate] = [
            .atom(.init(field: .managed, op: .eq, value: .bool(true))),
            .atom(.init(field: .hidden, op: .eq, value: .bool(false))),
            .atom(.init(field: .dedupCanonicalOrNull, op: .eq, value: .bool(true)))
        ]
        atoms.append(contentsOf: parsed.modifiers.map { .atom($0) })

        if !parsed.keyword.isEmpty {
            atoms.append(.or([
                .atom(.init(field: .filename, op: .contains, value: .string(parsed.keyword))),
                .atom(.init(field: .relativePath, op: .contains, value: .string(parsed.keyword)))
            ]))
        }

        return .and(atoms)
    }
}

#if DEBUG
extension SearchService {
    /// M.2 — inline 调试：跑 design § 6.5 表所有 case 验证 parse + compile 正确。
    /// 调用方式：GlanceApp .onAppear { SearchService._debugSelfCheck() } 临时挂；
    /// 验证完打 commit 前可删 _debugSelfCheck 调用，但函数保留留作 future regression check。
    static func _debugSelfCheck() {
        // Case 1: pure keyword
        let p1 = parse("screenshot")
        assert(p1.modifiers.isEmpty, "screenshot should have no modifiers")
        assert(p1.keyword == "screenshot", "expected 'screenshot' keyword")

        // Case 2: pure modifier type
        let p2 = parse("type:png")
        assert(p2.modifiers.count == 1, "type:png should produce 1 modifier")
        assert(p2.modifiers[0].field == .format, "expected .format field")
        assert(p2.keyword.isEmpty, "expected empty keyword")

        // Case 3: keyword + modifier
        let p3 = parse("screenshot type:png")
        assert(p3.modifiers.count == 1, "expected 1 modifier")
        assert(p3.keyword == "screenshot", "expected 'screenshot' keyword")

        // Case 4: two modifiers
        let p4 = parse("size:>1mb birth:>2026-04-01")
        assert(p4.modifiers.count == 2, "expected 2 modifiers")
        assert(p4.keyword.isEmpty, "expected empty keyword")
        if case .int(let bytes) = p4.modifiers[0].value {
            assert(bytes == 1_000_000, "expected 1mb = 1_000_000 bytes")
        } else {
            assertionFailure("size value should be .int")
        }

        // Case 5: partial fallback (invalid type)
        let p5 = parse("screen type:invalidext")
        // type:invalidext 合法字段名 + 非空 expr → parseTypeValue 校验 allSatisfy isLetter/isNumber 通过
        // 实际会成功解析（IndexStore 找不到匹配返 0 结果，是另一回事）
        // 这是 spec § 6.5 的实际行为 — 验证 D17：parser 不报错，user 看 0 结果自调
        // 如要让 invalidext fail，需在 parseTypeValue 加 allow-list；M3 不做（保 Silent partial）
        assert(p5.modifiers.count == 1, "M3: type:invalidext 当 modifier 不当 keyword（详见注释）")

        // Case 5b: partial fallback (invalid size unit)
        let p5b = parse("foo size:abc")
        assert(p5b.modifiers.isEmpty, "size:abc invalid → fallback keyword")
        assert(p5b.keyword == "foo size:abc", "expected full token fallback to keyword")

        // Case 6: unknown modifier field
        let p6 = parse("foo path:bar")
        assert(p6.modifiers.isEmpty, "path: unknown modifier → fallback keyword")
        assert(p6.keyword == "foo path:bar", "expected full token fallback")

        // Case 7: birth eq translates to betweenDuration
        let p7 = parse("birth:2026-04-15")
        assert(p7.modifiers.count == 1)
        assert(p7.modifiers[0].op == .betweenDuration, "eq birth → betweenDuration")

        // Case 8: empty input
        let p8 = parse("")
        assert(p8.isEmpty, "empty input → isEmpty=true")
        let p8b = parse("   ")
        assert(p8b.isEmpty, "whitespace-only → isEmpty=true")

        // Compile sanity
        let compiled = compile(p4)
        if case .and(let xs) = compiled {
            // 3 common filter + 2 modifier = 5 atoms; keyword 空不加 OR
            assert(xs.count == 5, "expected 5 atoms (3 common + 2 modifier)")
        } else {
            assertionFailure("compile should produce .and(...)")
        }

        print("[SearchService] _debugSelfCheck: all assertions passed")
    }
}
#endif
