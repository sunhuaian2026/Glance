import Foundation
import SQLite3

enum IndexDatabaseError: Error {
    case openFailed(message: String)
    case execFailed(sql: String, message: String)
    case prepareFailed(sql: String, message: String)
    case stepFailed(message: String)
    case bindFailed(index: Int, message: String)
}

/// Thin wrapper around sqlite3 C API. All ops on caller's queue
/// (caller must serialize access via dispatch queue or actor).
nonisolated final class IndexDatabase {

    private(set) var handle: OpaquePointer?

    init(at fileURL: URL) throws {
        var ptr: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(fileURL.path, &ptr, flags, nil)
        guard openResult == SQLITE_OK else {
            let msg = ptr.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(ptr)
            throw IndexDatabaseError.openFailed(message: msg)
        }
        self.handle = ptr
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
    }

    deinit {
        if let handle {
            sqlite3_close_v2(handle)
        }
    }

    /// Run a single SQL statement (no result rows).
    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(handle, sql, nil, nil, &error)
        if result != SQLITE_OK {
            let msg = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw IndexDatabaseError.execFailed(sql: sql, message: msg)
        }
    }

    /// Prepare a statement; caller binds + steps + finalizes.
    func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard result == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw IndexDatabaseError.prepareFailed(sql: sql, message: msg)
        }
        return stmt
    }

    func lastErrorMessage() -> String {
        guard let handle else { return "(no handle)" }
        return String(cString: sqlite3_errmsg(handle))
    }
}
