import Foundation

/// JSON-backed rule predicate. Tree shape (forward-compatible with future nesting),
/// but D6 V2 GUI only produces 2-layer AND/OR + atom leaves.
indirect enum SmartFolderPredicate: Codable, Equatable {
    case and([SmartFolderPredicate])
    case or([SmartFolderPredicate])
    case atom(SmartFolderAtom)

    private enum CodingKeys: String, CodingKey { case op, children, field, value }
    private enum OpTag: String, Codable { case AND, OR, ATOM }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .and(let xs):
            try c.encode(OpTag.AND, forKey: .op)
            try c.encode(xs, forKey: .children)
        case .or(let xs):
            try c.encode(OpTag.OR, forKey: .op)
            try c.encode(xs, forKey: .children)
        case .atom(let a):
            try c.encode(OpTag.ATOM, forKey: .op)
            try c.encode(a, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let op = try c.decode(OpTag.self, forKey: .op)
        switch op {
        case .AND:
            let xs = try c.decode([SmartFolderPredicate].self, forKey: .children)
            self = .and(xs)
        case .OR:
            let xs = try c.decode([SmartFolderPredicate].self, forKey: .children)
            self = .or(xs)
        case .ATOM:
            let a = try c.decode(SmartFolderAtom.self, forKey: .value)
            self = .atom(a)
        }
    }
}

struct SmartFolderAtom: Codable, Equatable {
    let field: SmartFolderField
    let op: SmartFolderOp
    let value: SmartFolderValue
}

/// D6 验证（Spotlight-like AND/OR 限制）：M1 只对**用户自定义** predicate 应用，
/// 内置 SmartFolder（M1 全部 + M3 部分）由开发者编写信任跳过。M4 用户规则编辑器
/// 必须调 `validateD6UserRule()` 才能保存。
///
/// 当前 strict 定义：max 3 层（root 1 + 中间 OR/AND group 1 + atom 1），
/// 配合 alternation（AND 内不能直接嵌 AND；OR 内不能直接嵌 OR）。
/// 依据：Spotlight / Finder 智能文件夹 UI 的"任一/全部"切换 + 单层"组"嵌入。
enum SmartFolderRuleError: Error {
    case unsupportedNesting(reason: String)
    case unsupportedOperator(String)
}

extension SmartFolderPredicate {
    /// 仅 M4 用户规则编辑器调；M1 内置 predicates 不调。
    func validateD6UserRule() throws {
        try validate(parent: nil, depth: 0, maxDepth: 3)
    }

    private func validate(parent: NodeOp?, depth: Int, maxDepth: Int) throws {
        if depth >= maxDepth {
            if case .atom = self { return }
            throw SmartFolderRuleError.unsupportedNesting(reason: "D6 max \(maxDepth) 层；超过仅允许 atom 叶节点")
        }
        switch self {
        case .atom:
            return
        case .and(let xs):
            if parent == .and {
                throw SmartFolderRuleError.unsupportedNesting(reason: "D6 alternation：AND 不能直接嵌 AND（合并到外层）")
            }
            for child in xs { try child.validate(parent: .and, depth: depth + 1, maxDepth: maxDepth) }
        case .or(let xs):
            if parent == .or {
                throw SmartFolderRuleError.unsupportedNesting(reason: "D6 alternation：OR 不能直接嵌 OR（合并到外层）")
            }
            for child in xs { try child.validate(parent: .or, depth: depth + 1, maxDepth: maxDepth) }
        }
    }

    private enum NodeOp { case and, or }
}

/// 字段 raw value **必须**对应 IndexStore 真实 column name（snake_case）。
/// virtual 字段（managed / hidden / dedupCanonicalOrNull）不在 DB schema，由 QueryBuilder 翻译成具体 SQL。
enum SmartFolderField: String, Codable {
    case managed
    case hidden
    case dedupCanonicalOrNull = "dedup_canonical_or_null"
    case format
    case filename
    case relativePath = "relative_path"
    case fileSize = "file_size"
    case birthTime = "birth_time"
    case dimensionsWidth = "dimensions_width"
    case dimensionsHeight = "dimensions_height"
}

enum SmartFolderOp: String, Codable {
    case eq = "="
    case ne = "!="
    case contains = "CONTAINS"
    case startsWith = "STARTS_WITH"
    case greaterThan = ">"
    case lessThan = "<"
    case betweenDuration = "BETWEEN_DURATION"  // value: relative time range like ["-7d", "now"]
    case inSet = "IN"
}

enum SmartFolderValue: Codable, Equatable {
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case stringArray([String])
    case relativeTimeRange(start: String, end: String)  // e.g. ("-7d", "now")

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .stringArray(let v): try c.encode(v)
        case .relativeTimeRange(let s, let e): try c.encode(["start": s, "end": e])
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int64.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode([String: String].self), let s = v["start"], let e = v["end"] {
            self = .relativeTimeRange(start: s, end: e); return
        }
        if let v = try? c.decode([String].self) { self = .stringArray(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        throw DecodingError.typeMismatch(SmartFolderValue.self, .init(codingPath: c.codingPath, debugDescription: "unknown value type"))
    }
}
