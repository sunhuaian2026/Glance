import Foundation

enum SmartFolderQueryError: Error {
    case unsupportedFieldOpCombo(field: SmartFolderField, op: SmartFolderOp)
    case typeMismatch(field: SmartFolderField, value: SmartFolderValue)
}

// `CompiledSmartFolderQuery` lives in `Glance/IndexStore/CompiledSmartFolderQuery.swift`
// (it's the contract between this builder's output and IndexStore.fetch's input).

nonisolated enum SmartFolderQueryBuilder {

    static func compile(_ folder: SmartFolder, now: Date = Date()) throws -> CompiledSmartFolderQuery {
        var params: [Any] = []
        let whereSQL = try emit(folder.predicate, params: &params, now: now)
        let orderSQL = "\(folder.sortBy.rawValue) \(folder.sortDescending ? "DESC" : "ASC")"
        return CompiledSmartFolderQuery(whereClause: whereSQL, parameters: params, orderBy: orderSQL)
    }

    private static func emit(_ p: SmartFolderPredicate, params: inout [Any], now: Date) throws -> String {
        switch p {
        case .and(let xs):
            let parts = try xs.map { try emit($0, params: &params, now: now) }
            return "(" + parts.joined(separator: " AND ") + ")"
        case .or(let xs):
            let parts = try xs.map { try emit($0, params: &params, now: now) }
            return "(" + parts.joined(separator: " OR ") + ")"
        case .atom(let atom):
            return try emitAtom(atom, params: &params, now: now)
        }
    }

    private static func emitAtom(_ a: SmartFolderAtom, params: inout [Any], now: Date) throws -> String {
        switch a.field {
        case .managed:
            // Slice A: 所有 indexed images 都已属于已注册的 managed root，无需额外过滤
            return "1"
        case .hidden:
            // Slice D: walk path 上溯最具体 explicit hide row（稀疏 explicit 模型）。
            // root 行 LENGTH(relative_path)=0；subfolder 行 length>0 → DESC 排序后
            // subfolder 优先于 root 命中 → 实现"hide root + unhide 子目录"语义。
            // 未匹配（路径上无 explicit hide row）→ COALESCE 默认 0 (visible)。
            guard case .bool(let v) = a.value else {
                throw SmartFolderQueryError.typeMismatch(field: a.field, value: a.value)
            }
            guard a.op == .eq else {
                throw SmartFolderQueryError.unsupportedFieldOpCombo(field: a.field, op: a.op)
            }
            params.append(v ? 1 : 0)
            return """
            COALESCE((
                SELECT f.hide_in_smart_view FROM folders f
                WHERE (f.id = images.folder_id AND f.parent_root_id IS NULL)
                   OR (f.parent_root_id = images.folder_id AND
                       (images.relative_path = f.relative_path
                        OR images.relative_path LIKE f.relative_path || '/%'))
                ORDER BY LENGTH(f.relative_path) DESC
                LIMIT 1
            ), 0) = ?
            """
        case .dedupCanonicalOrNull:
            return "(dedup_canonical IS NULL OR dedup_canonical = 1)"
        case .filename, .relativePath:
            return try emitStringAtom(a, column: a.field.rawValue, params: &params)
        case .format:
            // type: modifier 须 case-insensitive（design § 6.1）；DB format 存大写标签
            // （"PNG"/"WebP"，见 ImageMetadataReader.formatLabel），用户输入 lowercase，
            // 靠 COLLATE NOCASE 在 SQL 层匹配（大写归一对 "WebP" 混合大小写无效）。
            return try emitStringAtom(a, column: a.field.rawValue, params: &params, caseInsensitive: true)
        case .fileSize, .dimensionsWidth, .dimensionsHeight:
            return try emitIntAtom(a, column: a.field.rawValue, params: &params)
        case .birthTime:
            return try emitTimeAtom(a, column: "birth_time", params: &params, now: now)
        }
    }

    private static func emitStringAtom(_ a: SmartFolderAtom, column: String, params: inout [Any], caseInsensitive: Bool = false) throws -> String {
        // caseInsensitive 仅作用于 eq/ne（type: 的精确比对）；contains/startsWith 走 LIKE，
        // SQLite LIKE 对 ASCII 默认已 case-insensitive，无需 COLLATE。
        let collate = caseInsensitive ? " COLLATE NOCASE" : ""
        switch a.op {
        case .eq:
            guard case .string(let v) = a.value else { throw SmartFolderQueryError.typeMismatch(field: a.field, value: a.value) }
            params.append(v)
            return "\(column) = ?\(collate)"
        case .ne:
            guard case .string(let v) = a.value else { throw SmartFolderQueryError.typeMismatch(field: a.field, value: a.value) }
            params.append(v)
            return "\(column) != ?\(collate)"
        case .contains:
            guard case .string(let v) = a.value else { throw SmartFolderQueryError.typeMismatch(field: a.field, value: a.value) }
            params.append("%\(v)%")
            return "\(column) LIKE ?"
        case .startsWith:
            guard case .string(let v) = a.value else { throw SmartFolderQueryError.typeMismatch(field: a.field, value: a.value) }
            params.append("\(v)%")
            return "\(column) LIKE ?"
        case .inSet:
            guard case .stringArray(let xs) = a.value else { throw SmartFolderQueryError.typeMismatch(field: a.field, value: a.value) }
            let placeholders = xs.map { _ in "?" }.joined(separator: ",")
            params.append(contentsOf: xs as [Any])
            return "\(column) IN (\(placeholders))"
        default:
            throw SmartFolderQueryError.unsupportedFieldOpCombo(field: a.field, op: a.op)
        }
    }

    private static func emitIntAtom(_ a: SmartFolderAtom, column: String, params: inout [Any]) throws -> String {
        guard case .int(let v) = a.value else { throw SmartFolderQueryError.typeMismatch(field: a.field, value: a.value) }
        switch a.op {
        case .greaterThan: params.append(v); return "\(column) > ?"
        case .lessThan: params.append(v); return "\(column) < ?"
        case .eq: params.append(v); return "\(column) = ?"
        case .ne: params.append(v); return "\(column) != ?"
        default: throw SmartFolderQueryError.unsupportedFieldOpCombo(field: a.field, op: a.op)
        }
    }

    private static func emitTimeAtom(_ a: SmartFolderAtom, column: String, params: inout [Any], now: Date) throws -> String {
        switch a.op {
        case .betweenDuration:
            guard case .relativeTimeRange(let s, let e) = a.value else {
                throw SmartFolderQueryError.typeMismatch(field: a.field, value: a.value)
            }
            let startTs = resolveRelativeTime(s, now: now)
            let endTs = resolveRelativeTime(e, now: now)
            params.append(startTs)
            params.append(endTs)
            return "(\(column) >= ? AND \(column) <= ?)"
        case .greaterThan:
            guard case .double(let v) = a.value else { throw SmartFolderQueryError.typeMismatch(field: a.field, value: a.value) }
            params.append(v); return "\(column) > ?"
        case .lessThan:
            guard case .double(let v) = a.value else { throw SmartFolderQueryError.typeMismatch(field: a.field, value: a.value) }
            params.append(v); return "\(column) < ?"
        default:
            throw SmartFolderQueryError.unsupportedFieldOpCombo(field: a.field, op: a.op)
        }
    }

    /// 月偏移量：往回一个月（Calendar.date(byAdding: .month, value:)）。
    /// 命名常量满足 CLAUDE.md "禁止魔法数字" 规则。
    private static let oneMonthBack: Int = -1
    /// 时间偏移量：往回一秒（用于构造 inclusive end timestamp，从 next-period-start - 1s）。
    private static let oneSecondBack: TimeInterval = -1

    private static func resolveRelativeTime(_ token: String, now: Date) -> Double {
        if token == "now" { return now.timeIntervalSince1970 }
        // M3.L — 自然月边界 token：last-month-start = 上月 1 日 00:00（inclusive），
        // last-month-end = 本月 1 日 00:00 - 1s（inclusive end）。timezone 走 device local
        // 跟 D4 时间分段同源；NSCalendar dateInterval(of: .month) 自动处理跨年（1 月→上年 12 月）
        if token == "last-month-start" {
            let cal = Calendar.current
            guard let thisMonthStart = cal.dateInterval(of: .month, for: now)?.start,
                  let lastMonthStart = cal.date(byAdding: .month, value: oneMonthBack, to: thisMonthStart) else {
                return now.timeIntervalSince1970
            }
            return lastMonthStart.timeIntervalSince1970
        }
        if token == "last-month-end" {
            let cal = Calendar.current
            guard let thisMonthStart = cal.dateInterval(of: .month, for: now)?.start else {
                return now.timeIntervalSince1970
            }
            return thisMonthStart.addingTimeInterval(oneSecondBack).timeIntervalSince1970
        }
        if let last = token.last, last == "d",
           let n = Int(token.dropLast()) {
            return now.addingTimeInterval(TimeInterval(n) * 86400).timeIntervalSince1970
        }
        let fmt = ISO8601DateFormatter()
        if let d = fmt.date(from: token) {
            return d.timeIntervalSince1970
        }
        return now.timeIntervalSince1970
    }
}
