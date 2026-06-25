import Foundation

struct SmartFolder: Identifiable, Equatable {
    let id: String                           // stable id (built-ins use slug like "all-recent")
    let displayName: String                  // "全部最近"
    let predicate: SmartFolderPredicate
    let sortBy: SmartFolderSortKey
    let sortDescending: Bool
    let isBuiltIn: Bool

    static func == (lhs: SmartFolder, rhs: SmartFolder) -> Bool {
        lhs.id == rhs.id
    }
}

enum SmartFolderSortKey: String {
    case birthTime = "birth_time"
    case filename
    case fileSize = "file_size"
}
