import Foundation
import SQLite3

// SQLite copies bound text/blob only when the destructor is SQLITE_TRANSIENT; the symbol isn't
// imported into Swift, so reconstruct it.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteError: Error, CustomStringConvertible {
	case open(String)
	case prepare(String)
	case step(String)
	public var description: String {
		switch self {
		case .open(let m): return "sqlite open: \(m)"
		case .prepare(let m): return "sqlite prepare: \(m)"
		case .step(let m): return "sqlite step: \(m)"
		}
	}
}

/// A thin wrapper over the system `sqlite3` C API — just enough for the usage index. The connection
/// is opened `FULLMUTEX`; `UsageIndex` adds a higher-level lock around multi-statement operations.
public final class SQLiteDatabase {
	fileprivate var handle: OpaquePointer?

	public init(path: String) throws {
		let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
		guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
			let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
			sqlite3_close_v2(handle)
			throw SQLiteError.open(message)
		}
		// WAL keeps reads non-blocking during the ingest write; NORMAL is durable enough for a cache.
		try execute("PRAGMA journal_mode=WAL;")
		try execute("PRAGMA synchronous=NORMAL;")
		try execute("PRAGMA busy_timeout=5000;")
	}

	/// Opens an EXISTING, foreign, third-party database strictly read-only — never creates the file,
	/// never mutates its journal mode/pragmas (the source app, e.g. OpenCode, already owns those).
	/// Used for read-only ingestion of another app's own SQLite store; distinct from the read/write
	/// cache-DB path above.
	public init(readOnlyPath path: String) throws {
		let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
		guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
			let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
			sqlite3_close_v2(handle)
			throw SQLiteError.open(message)
		}
		// A connection-local setting only; safe on a read-only handle and harmless if the foreign DB
		// is mid-write under WAL (we just wait up to 5s rather than failing immediately with SQLITE_BUSY).
		try execute("PRAGMA busy_timeout=5000;")
	}

	deinit { sqlite3_close_v2(handle) }

	public func execute(_ sql: String) throws {
		var error: UnsafeMutablePointer<CChar>?
		if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
			let message = error.map { String(cString: $0) } ?? "unknown"
			sqlite3_free(error)
			throw SQLiteError.step(message)
		}
	}

	public func prepare(_ sql: String) throws -> SQLiteStatement {
		var stmt: OpaquePointer?
		guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
			throw SQLiteError.prepare(String(cString: sqlite3_errmsg(handle)))
		}
		return SQLiteStatement(stmt: stmt, db: self)
	}

	/// Runs `body` inside a single transaction; rolls back if it throws.
	public func transaction(_ body: () throws -> Void) throws {
		try execute("BEGIN;")
		do {
			try body()
			try execute("COMMIT;")
		} catch {
			try? execute("ROLLBACK;")
			throw error
		}
	}
}

/// A prepared statement. Bind indices are 1-based; column indices are 0-based (SQLite convention).
public final class SQLiteStatement {
	private var stmt: OpaquePointer?
	private let db: SQLiteDatabase

	fileprivate init(stmt: OpaquePointer?, db: SQLiteDatabase) {
		self.stmt = stmt
		self.db = db
	}

	deinit { sqlite3_finalize(stmt) }

	public func bind(_ index: Int32, _ value: Int) { sqlite3_bind_int64(stmt, index, Int64(value)) }
	public func bind(_ index: Int32, _ value: Double) { sqlite3_bind_double(stmt, index, value) }

	public func bind(_ index: Int32, _ value: String?) {
		if let value {
			sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
		} else {
			sqlite3_bind_null(stmt, index)
		}
	}

	/// Advances one row. Returns true while rows remain (`SQLITE_ROW`), false at `SQLITE_DONE`.
	public func step() throws -> Bool {
		switch sqlite3_step(stmt) {
		case SQLITE_ROW: return true
		case SQLITE_DONE: return false
		default: throw SQLiteError.step(String(cString: sqlite3_errmsg(db.dbHandle)))
		}
	}

	public func reset() {
		sqlite3_reset(stmt)
		sqlite3_clear_bindings(stmt)
	}

	public func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(stmt, column)) }
	public func double(_ column: Int32) -> Double { sqlite3_column_double(stmt, column) }
	public func text(_ column: Int32) -> String? {
		guard let c = sqlite3_column_text(stmt, column) else { return nil }
		return String(cString: c)
	}
}

extension SQLiteDatabase {
	fileprivate var dbHandle: OpaquePointer? { handle }
}
