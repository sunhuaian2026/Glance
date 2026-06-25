import Foundation

/// Builder 输出 + IndexStore.fetch 输入的两端契约。
/// SmartFolderQueryBuilder 编译 SmartFolder.predicate / sortBy 产出此结构；
/// IndexStore.fetch 仅接受此结构（拒绝外部 raw SQL）→ 消除 injection vector。
nonisolated struct CompiledSmartFolderQuery {
    let whereClause: String
    let parameters: [Any]
    let orderBy: String
}
