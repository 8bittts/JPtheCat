import Foundation

public struct UsageWindowSummary: Sendable {
	public let rollup: UsageRollup
	public let dailyCostSeries: [Double]
	public let dailyTokenSeries: [Double]

	public init(rollup: UsageRollup, dailyCostSeries: [Double], dailyTokenSeries: [Double] = []) {
		self.rollup = rollup
		self.dailyCostSeries = dailyCostSeries
		self.dailyTokenSeries = dailyTokenSeries
	}
}

public struct UsageWindowSummaries: Sendable {
	public let aggregate: UsageWindowSummary
	public let providers: [ProviderID: UsageWindowSummary]

	public init(aggregate: UsageWindowSummary, providers: [ProviderID: UsageWindowSummary]) {
		self.aggregate = aggregate
		self.providers = providers
	}
}

/// Every requested day-count's `UsageWindowSummaries`, keyed by day-count — computed by
/// `multiWindowSummaries` from a SINGLE scan bounded by the largest requested window, not one scan
/// per day-count. Feeds `WidgetSnapshot.windows` so each widget instance can pick its own timeframe.
public struct UsageMultiWindowSummaries: Sendable {
	public let byDays: [Int: UsageWindowSummaries]

	public init(byDays: [Int: UsageWindowSummaries]) {
		self.byDays = byDays
	}
}

/// One un-aggregated (provider, model, local calendar day) row inside a `modelDaySummaries` window —
/// the Advanced Analytics tray's per-model/per-day breakdown, including the raw token-type split
/// (cache create 5m/1h vs cache read vs input/output) that the rolled-up `UsageRollup`/`CostBucket`
/// types intentionally discard.
public struct ModelDaySummary: Sendable, Equatable {
	public let provider: ProviderID
	public let model: String
	public let day: Date
	public var eventCount: Int
	public var inputTokens: Int
	public var outputTokens: Int
	public var cache5mTokens: Int
	public var cache1hTokens: Int
	public var cacheReadTokens: Int
	public var cost: Double

	public init(
		provider: ProviderID, model: String, day: Date, eventCount: Int, inputTokens: Int,
		outputTokens: Int, cache5mTokens: Int, cache1hTokens: Int, cacheReadTokens: Int, cost: Double
	) {
		self.provider = provider
		self.model = model
		self.day = day
		self.eventCount = eventCount
		self.inputTokens = inputTokens
		self.outputTokens = outputTokens
		self.cache5mTokens = cache5mTokens
		self.cache1hTokens = cache1hTokens
		self.cacheReadTokens = cacheReadTokens
		self.cost = cost
	}

	/// Buckets already-loaded `UsageEvent`s into `(provider, model, day)` rows — the SAME shape and
	/// aggregation rule as `UsageIndex.modelDaySummaries`, but for a provider whose events never pass
	/// through `UsageIndexer`/`UsageIndex` at all (Copilot: `DashboardViewModel.refresh()` builds its
	/// `ProviderRow` directly from `CopilotProvider.loadEvents()`, bypassing the SQLite index — see
	/// AGENTS.md's "Provider Catalog & Live Data"). Pure, no I/O, so it's usable from any provider's
	/// `loadEvents()` output without a second on-disk index.
	public static func bucketed(
		events: [UsageEvent],
		calculator: CostCalculator,
		calendar: Calendar = .current
	) -> [ModelDaySummary] {
		var accumulator = ModelDayAccumulator()
		for event in events {
			accumulator.add(
				provider: event.provider, model: event.model,
				day: calendar.startOfDay(for: event.timestamp), usage: event.usage,
				cost: calculator.cost(model: event.model, usage: event.usage) ?? 0)
		}
		return accumulator.finish()
	}
}

/// The ONE `(provider, model, local day)` bucketing rule behind BOTH `ModelDaySummary.bucketed` (an
/// in-memory `[UsageEvent]`, for a provider that bypasses the index) and `UsageIndex.modelDaySummaries`
/// (a SQLite cursor). They differ only in row source, and they feed the SAME Advanced Analytics table
/// and the SAME CSV export.
/// Guard: `UsageIndexModelDayAccumulatorParityTests` keeps the two callers' bucketing byte-identical.
private struct ModelDayAccumulator {
	/// Keyed by (provider, presentation model, day) so repeated events for the same slot accumulate
	/// rather than producing one row per event. The model is `ModelIdentity.presentationID`: each event
	/// is priced under its emitted id first, then a gateway route, snapshot date, or `[1m]` selector
	/// folds into the one model the dashboard shows, so the table, heatmap, drill-down, and export agree.
	private struct Key: Hashable {
		let provider: ProviderID
		let model: String
		let day: Date
	}

	private var accumulators: [Key: ModelDaySummary] = [:]
	/// First-seen key order, kept so `finish()`'s sort has a deterministic, insertion-stable input
	/// rather than `Dictionary`'s per-process-random iteration order.
	private var order: [Key] = []

	mutating func add(
		provider: ProviderID, model: String, day: Date, usage: TokenUsage, cost: Double
	) {
		let key = Key(provider: provider, model: ModelIdentity.presentationID(model), day: day)
		guard let slot = accumulators.index(forKey: key) else {
			accumulators[key] = ModelDaySummary(
				provider: provider, model: key.model, day: day, eventCount: 1,
				inputTokens: usage.input, outputTokens: usage.output,
				cache5mTokens: usage.cacheCreate5m, cache1hTokens: usage.cacheCreate1h,
				cacheReadTokens: usage.cacheRead, cost: cost)
			order.append(key)
			return
		}
		// Mutate in place through `values[slot]`'s `_modify` accessor rather than
		// extract-copy-mutate-reinsert: one lookup, no second hash of the key, and no temporary copy
		// of the summary per event. The index stays valid because nothing here inserts or removes.
		accumulators.values[slot].accumulate(usage, cost: cost)
	}

	/// Stable, chart/CSV-friendly order: oldest day first, then provider, then model. This is a TOTAL
	/// order over `Key`, which is what lets the two callers' differing first-seen insertion order (array
	/// walk versus SQLite cursor) never leak into the result.
	func finish() -> [ModelDaySummary] {
		order
			.compactMap { accumulators[$0] }
			.sorted { lhs, rhs in
				if lhs.day != rhs.day { return lhs.day < rhs.day }
				if lhs.provider.rawValue != rhs.provider.rawValue {
					return lhs.provider.rawValue < rhs.provider.rawValue
				}
				return lhs.model < rhs.model
			}
	}
}

extension ModelDaySummary {
	/// Folds ONE more event into an existing `(provider, model, day)` row. Deliberately not public:
	/// `ModelDaySummary` is a finished value everywhere outside `ModelDayAccumulator`.
	fileprivate mutating func accumulate(_ usage: TokenUsage, cost: Double) {
		eventCount += 1
		inputTokens += usage.input
		outputTokens += usage.output
		cache5mTokens += usage.cacheCreate5m
		cache1hTokens += usage.cacheCreate1h
		cacheReadTokens += usage.cacheRead
		self.cost += cost
	}
}

private struct MutableUsageWindowSummary {
	var today = CostBucket()
	var window = CostBucket()
	var byModel: [String: CostBucket] = [:]
	var dailyCostSeries: [Double]
	var dailyTokenSeries: [Double]
	let windowDays: Int

	init(days: Int) {
		windowDays = max(days, 0)
		dailyCostSeries = [Double](repeating: 0, count: windowDays)
		dailyTokenSeries = [Double](repeating: 0, count: windowDays)
	}

	mutating func add(
		_ event: UsageEvent,
		timestamp: Date,
		cost: Double?,
		todayEpoch: Double,
		windowEpoch: Double,
		windowStart: Date?,
		calendar: Calendar
	) {
		let eventEpoch = timestamp.timeIntervalSince1970
		if eventEpoch >= todayEpoch { today.add(event, cost: cost) }
		// The window bucket + per-model breakdown span the SELECTED timeframe (not a fixed 7 days) so
		// widening the dropdown updates every window-derived figure, not just the chart.
		if eventEpoch >= windowEpoch {
			window.add(event, cost: cost)
			byModel[event.model, default: CostBucket()].add(event, cost: cost)
		}
		guard let windowStart, !dailyCostSeries.isEmpty else { return }
		let day = calendar.startOfDay(for: timestamp)
		let index = calendar.dateComponents([.day], from: windowStart, to: day).day ?? -1
		if index >= 0 && index < dailyCostSeries.count {
			dailyCostSeries[index] += cost ?? 0
			dailyTokenSeries[index] += Double(event.usage.total)
		}
	}

	/// Grouped-scan sibling of `add`: folds in an already-aggregated `(model, local-day, tier)` group.
	/// `dayIndex` is the group's 0-based offset from the window start (`nil` = outside this bucket's
	/// window), `isToday` marks the today bucket. Membership is decided by LOCAL DAY (identical to the
	/// per-event path's `eventEpoch >= todayEpoch` / `>= windowEpoch` tests, since every returned row is
	/// `<= now`), so the two paths produce identical buckets.
	mutating func addGrouped(
		model: String, usage: TokenUsage, cost: Double?, count: Int, isToday: Bool, dayIndex: Int?
	) {
		if isToday { today.addGrouped(model: model, usage: usage, cost: cost, count: count) }
		if dayIndex != nil {
			window.addGrouped(model: model, usage: usage, cost: cost, count: count)
			byModel[model, default: CostBucket()].addGrouped(
				model: model, usage: usage, cost: cost, count: count)
		}
		guard let dayIndex, dayIndex >= 0, dayIndex < dailyCostSeries.count else { return }
		dailyCostSeries[dayIndex] += cost ?? 0
		dailyTokenSeries[dayIndex] += Double(usage.total)
	}

	func summary() -> UsageWindowSummary {
		UsageWindowSummary(
			rollup: UsageRollup(
				today: today, last7d: window, byModel7d: byModel, windowDays: max(windowDays, 1)),
			dailyCostSeries: dailyCostSeries, dailyTokenSeries: dailyTokenSeries)
	}
}

/// The persistent usage index at `~/Library/Application Support/JPtheCat/usage.sqlite`.
///
/// It exists to turn cold start from a full-corpus JSONL walk (~13s over GBs) into an indexed
/// `SELECT` over just the current window. Events upsert on `UNIQUE(provider, msg_id, req_id)` with
/// keep-max-output semantics — identical to the in-memory `Deduplicator` — so re-reading a file is
/// idempotent and safe. A materialized `daily` token table (recomputed only for days touched by an
/// ingest) backs history charts without re-aggregating the whole corpus.
/// `@unchecked Sendable`: the single `SQLiteDatabase` connection is opened `FULLMUTEX`, and this
/// type also serializes whole high-level operations with `connectionLock`. FULLMUTEX protects
/// individual sqlite3 calls, but it does not make overlapping multi-statement transactions safe.
public final class UsageIndex: @unchecked Sendable {
	private let db: SQLiteDatabase
	private let connectionLock = NSRecursiveLock()
	/// Retained so `compactIfNeeded` can check free space on the volume the database actually lives on.
	private let path: String

	/// True while this database still carries the pre-interning `events.source_path` column — i.e.
	/// between an upgrade launch and the moment `migrateSourcePathIndexIfNeeded()` finishes off-main.
	///
	/// [Load-bearing] Every `source_path` reader and writer branches on this, so the transition window
	/// stays CORRECT rather than merely eventually-correct: during it the upsert writes BOTH
	/// `source_path` and `path_id`, and `deleteEvents` still matches on `source_path`. Writing only
	/// `path_id` while deletes matched only `source_path` (or the reverse) would silently strand rows a
	/// `.reset` re-read was supposed to replace, for as long as the window lasts.
	///
	/// Written at `init` (single-threaded) and once more inside the migration's connection-lock
	/// critical section; read only under `connectionLock`.
	private var legacySourcePathColumn = false

	/// Bumped whenever `ingest`/`deleteEvents` actually mutates the `events` table (never on a no-op
	/// call). Lets callers like `DashboardWidgetPublisher` cache an expensive derived computation (e.g.
	/// `multiWindowSummaries`) and skip recomputing it when nothing in the index has changed since the
	/// last call.
	///
	/// [Lock split 2026-07-26] Reading it through `withConnectionLock` made a one-word read BLOCK behind
	/// whatever else held the connection — including a multi-hundred-millisecond scan holding it across
	/// its whole `while try stmt.step()` loop. `DashboardWidgetPublisher.makeWindows` reads `generation`
	/// as its very first act, so a publish parked for the length of an in-flight dashboard scan before it
	/// could even check its cache. It gets its own lock; mutators bump it while still inside their
	/// existing connection-lock critical section.
	///
	/// This weakens no TOCTOU property, because none existed: the publisher already took the connection
	/// lock twice (once here, once for the scan), so an ingest could always land between them.
	/// `generationValue` is monotonic, so a result stored under a superseded key is simply never served.
	private let generationLock = NSLock()
	private var generationValue = 0
	public var generation: Int {
		generationLock.lock()
		defer { generationLock.unlock() }
		return generationValue
	}

	private func bumpGeneration() {
		generationLock.lock()
		generationValue += 1
		generationLock.unlock()
	}

	public init(path: String) throws {
		self.path = path
		db = try SQLiteDatabase(path: path)
		try createSchema()
	}

	/// Test-only: both fail on the SAME connection while any statement sits parked in `SQLITE_ROW`, so
	/// they are the honest probe for a leaked prepared-statement cursor.
	func checkpointForTesting() throws {
		try withConnectionLock { try db.execute("PRAGMA wal_checkpoint(TRUNCATE);") }
	}

	func vacuumForTesting() throws {
		try withConnectionLock { try db.execute("VACUUM;") }
	}

	/// Test-only: lets a guard hold the CONNECTION lock (the one a long scan holds) so it can prove a
	/// `generation` read no longer blocks behind it.
	func withConnectionLockForTesting<T>(_ body: () throws -> T) rethrows -> T {
		try withConnectionLock(body)
	}

	private func withConnectionLock<T>(_ body: () throws -> T) rethrows -> T {
		connectionLock.lock()
		defer { connectionLock.unlock() }
		return try body()
	}

	/// `~/Library/Application Support/JPtheCat/usage.sqlite` (creating the directory).
	public static func defaultURL() throws -> URL {
		let dir = try FileManager.default.url(
			for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
		).appendingPathComponent("JPtheCat", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir.appendingPathComponent("usage.sqlite")
	}

	private func createSchema() throws {
		try db.execute(
			"""
			CREATE TABLE IF NOT EXISTS events (
			  provider TEXT NOT NULL, msg_id TEXT NOT NULL, req_id TEXT NOT NULL,
			  model TEXT NOT NULL, ts REAL NOT NULL, project TEXT,
			  input INTEGER NOT NULL, output INTEGER NOT NULL,
			  cache5m INTEGER NOT NULL, cache1h INTEGER NOT NULL, cache_read INTEGER NOT NULL,
			  path_id INTEGER,
			  PRIMARY KEY (provider, msg_id, req_id)
			) WITHOUT ROWID;
			CREATE TABLE IF NOT EXISTS paths (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE);
			CREATE TABLE IF NOT EXISTS cursors (
			  path TEXT NOT NULL, provider TEXT NOT NULL DEFAULT '', size INTEGER NOT NULL,
			  mtime REAL NOT NULL, offset INTEGER NOT NULL, fingerprint TEXT NOT NULL DEFAULT '',
			  ctime REAL NOT NULL DEFAULT 0, parser_revision INTEGER NOT NULL DEFAULT 1,
			  parser_state TEXT NOT NULL DEFAULT '',
			  PRIMARY KEY (path, provider)
			) WITHOUT ROWID;
			""")
		// A pre-interning database still carries the wide `source_path TEXT` column and no `path_id`;
		// this is the one-line half of the upgrade, the row rewrite happens off-main in
		// `migrateSourcePathIndexIfNeeded`. Deliberately NOT paired with an `ADD COLUMN source_path` —
		// re-adding the interned-away column to a current-shape database is exactly the 87 MB regression
		// this schema exists to remove.
		try? db.execute("ALTER TABLE events ADD COLUMN path_id INTEGER;")
		try? db.execute("ALTER TABLE cursors ADD COLUMN fingerprint TEXT NOT NULL DEFAULT '';")
		// Persisting ctime lets a FRESH launch reuse the same safe (size, mtime, ctime) stat-only skip
		// check that `verifiedFileStateCache` already does within one session — without it, every cold
		// launch had to open+read up to 8KB from EVERY historical file just to compute a fingerprint,
		// even for files that hadn't changed since the app last quit. See `UsageIndexer.refresh`.
		try? db.execute("ALTER TABLE cursors ADD COLUMN ctime REAL NOT NULL DEFAULT 0;")
		// `provider` scopes the durable-retention stale-file sweep to ONE provider's cursors. Legacy
		// rows default to '' and get backfilled by `UsageIndexer.refresh` the next time each file is
		// seen — see `cursorPaths(provider:)` and the retention loop there.
		try? db.execute("ALTER TABLE cursors ADD COLUMN provider TEXT NOT NULL DEFAULT '';")
		try? db.execute("ALTER TABLE cursors ADD COLUMN parser_revision INTEGER NOT NULL DEFAULT 1;")
		try? db.execute("ALTER TABLE cursors ADD COLUMN parser_state TEXT NOT NULL DEFAULT '';")
		try db.execute("CREATE INDEX IF NOT EXISTS idx_cursors_provider ON cursors(provider);")
		// Migrate cursors table from single-column PK (path) to composite PK (path, provider)
		// for shared-source-path providers (MiMo, Nemotron, Big Pickle, DeepSeek all use opencode.db).
		try migrateCursorsTableIfNeeded()
		// Retired schema from the original materialized-rollup implementation. All charts and totals
		// query `events` directly; keeping these objects would add write amplification for no reader.
		try db.execute("DROP INDEX IF EXISTS idx_events_project_ts;")
		try db.execute("DROP TABLE IF EXISTS daily;")
		// Which shape this connection is talking to RIGHT NOW. Every `source_path` reader/writer below
		// branches on it, so the window between launch and the off-main interning migration stays
		// correct instead of silently writing `path_id` while deletes still match on `source_path`.
		legacySourcePathColumn = try eventsCarriesSourcePathColumn()
		// A brand-new database is empty, so building the scan index here costs nothing and every scan
		// is covered from the very first refresh. An EXISTING database must NOT build it here —
		// `init` runs on the main thread at launch and the build measured 1.6 s on a real 390 MB
		// corpus, which is precisely the launch stall this workstream exists to remove. Those go
		// through `migrateScanIndexIfNeeded()` off-main instead.
		if try isEventsTableEmpty() {
			try db.execute(Self.createScanIndexSQL)
			try db.execute(Self.createPathIDIndexSQL)
			// An empty legacy-shaped database can finish the interning inline: there are no rows to
			// rewrite, so this is a schema edit, not the row-rewrite that must stay off-main. No
			// `compactIfNeeded` here — there is nothing to reclaim, and VACUUM must never run at init.
			if legacySourcePathColumn {
				_ = try withConnectionLock { try internSourcePathsIfNeeded() }
			}
		}
	}

	private func isEventsTableEmpty() throws -> Bool {
		let stmt = try db.prepare("SELECT 1 FROM events LIMIT 1;")
		return try !stmt.step()
	}

	/// True while this database still carries the pre-interning `events.source_path` column.
	private func eventsCarriesSourcePathColumn() throws -> Bool {
		let stmt = try db.prepare("SELECT 1 FROM pragma_table_info('events') WHERE name = 'source_path';")
		let present = try stmt.step()
		// Single-row probe: reset on the way OUT so it can never sit parked in `SQLITE_ROW` and block
		// VACUUM / WAL checkpointing (see `cursor(for:)`).
		stmt.reset()
		return present
	}

	/// Covers every column the five shared `forEachEvent` projections read, so the grouped money scans
	/// stop re-descending the main `WITHOUT ROWID` B-tree (which is ordered by `msg_id`, i.e. random
	/// with respect to `ts`).
	private static let createScanIndexSQL = """
		CREATE INDEX IF NOT EXISTS idx_events_scan
		  ON events(provider, ts, model, input, output, cache5m, cache1h, cache_read);
		"""

	/// Reclaims free pages left behind by ingest churn and by the two index migrations. Returns true
	/// only when it actually ran.
	///
	/// `auto_vacuum` is 0 and the database has never been VACUUMed, so freed pages are retained in the
	/// file forever, and each drop-then-create adds more.
	///
	/// Three gates, all deliberate:
	/// - **Freelist share.** Below `minFreelistPercent` there is nothing worth the rewrite.
	/// - **Free disk space.** `VACUUM` builds a full second copy, so it needs > 2× the file size free.
	///   Short on space is a SKIP, never a failure — a half-finished VACUUM on a full disk is exactly
	///   the scenario worth avoiding.
	/// - **Caller-supplied recency** (see `StatusBarController`), so it cannot run launch after launch.
	///
	/// **Must run OFF the main thread**, and must NOT be inside a transaction — SQLite rejects that.
	///
	/// [CRITICAL] Requires `cursor(for:)` to reset its statement on exit or `VACUUM` fails inside a
	/// `try?` and silently no-ops.
	@discardableResult
	public func compactIfNeeded(minFreelistPercent: Int = 15) throws -> Bool {
		try withConnectionLock {
			let stats = try db.prepare(
				"SELECT (SELECT freelist_count FROM pragma_freelist_count), (SELECT page_count FROM pragma_page_count), (SELECT page_size FROM pragma_page_size);")
			guard try stats.step() else { return false }
			let free = stats.int(0)
			let total = stats.int(1)
			let pageSize = stats.int(2)
			stats.reset()
			guard total > 0, free * 100 / total >= minFreelistPercent else { return false }
			guard Self.hasRoomToVacuum(fileBytes: total * pageSize, at: path) else { return false }
			try db.execute("VACUUM;")
			return true
		}
	}

	/// `VACUUM` materializes a complete second copy before swapping, so anything less than ~2× the
	/// current file size free is a skip. Unknown capacity is also a skip — never guess in favour of
	/// running a whole-file rewrite.
	private static func hasRoomToVacuum(fileBytes: Int, at path: String) -> Bool {
		let values = try? URL(fileURLWithPath: path).resourceValues(
			forKeys: [.volumeAvailableCapacityForImportantUsageKey])
		guard let available = values?.volumeAvailableCapacityForImportantUsage else { return false }
		return available > Int64(fileBytes) * 2
	}

	/// The one index `deleteEvents` needs once paths are interned: a 8-byte integer key per event
	/// instead of the ~119-character absolute path the old `idx_events_source_path` /
	/// `idx_events_source_tail` pair indexed.
	///
	/// Dropping the index outright was REJECTED, not merely deferred: `deleteEvents` fires from the
	/// `.reset` branch several times a minute (`canTailAppend == false` for Codex, Gemini, OpenCode,
	/// Copilot and Muse Spark), and an unindexed scan measured ~80× slower on the real DB.
	private static let createPathIDIndexSQL = """
		CREATE INDEX IF NOT EXISTS idx_events_path_id ON events(path_id);
		"""

	/// Interns `events.source_path` into the `paths` table and reclaims the freed pages. Idempotent
	/// and safe to call every launch. **Must run OFF the main thread** (same rule as
	/// `migrateScanIndexIfNeeded`) — it rewrites every row, then VACUUMs.
	///
	/// Path interning + `DROP COLUMN` + the narrow `idx_events_path_id` + `VACUUM` shrinks the database
	/// by ~30% on a real corpus; this is why the one-time rewrite is worth it.
	///
	/// [Crash safety] Every schema and row edit runs in ONE `BEGIN IMMEDIATE` transaction, so an
	/// interrupted run (SIGKILL, power loss, or a mid-string `sqlite3_exec` failure) leaves the
	/// database in its pre-migration shape — readable, correct, and re-migratable — never half-interned.
	/// The name is retained because `StatusBarController.migrateScanIndexOffMain` already schedules it
	/// off-main; it has always meant "get `source_path` into its final storage shape".
	public func migrateSourcePathIndexIfNeeded() throws {
		let migrated = try withConnectionLock { try internSourcePathsIfNeeded() }
		guard migrated else { return }
		// `auto_vacuum` is 0, so nothing shrinks until a VACUUM. Run it HERE rather than waiting for
		// `StatusBarController`'s weekly-gated call, or the reclaimed space stays on disk for up to a
		// week.
		//
		// [Load-bearing] `ALTER TABLE … DROP COLUMN` rewrites each row IN PLACE, causing internal
		// fragmentation rather than free pages, so the default 15% freelist gate can skip the VACUUM
		// entirely. Overriding the gate is safe precisely because this runs once, on the migration
		// launch.
		//
		// `compactIfNeeded` still SKIPS (never fails, never half-writes) when the volume lacks the >2x
		// headroom VACUUM needs, and it must not be inside a transaction — it is not. A failed VACUUM
		// is not a failed migration: the interning is already committed and correct.
		_ = try? compactIfNeeded(minFreelistPercent: 0)
	}

	/// The interning transaction itself. Returns true only when it actually did work.
	/// Caller must hold `connectionLock`.
	@discardableResult
	private func internSourcePathsIfNeeded() throws -> Bool {
		// The end-state fact is the COLUMN being gone, not an index existing: `ALTER TABLE DROP COLUMN`
		// is the irreversible step, so keying on it makes a re-run after any earlier-aborted attempt a
		// full, correct re-run rather than a silent partial skip.
		guard try eventsCarriesSourcePathColumn() else {
			legacySourcePathColumn = false
			return false
		}
		do {
			try db.execute(
				"""
				BEGIN IMMEDIATE;
				INSERT OR IGNORE INTO paths (path)
				  SELECT DISTINCT source_path FROM events WHERE source_path IS NOT NULL;
				UPDATE events SET path_id = (SELECT id FROM paths WHERE paths.path = events.source_path)
				  WHERE path_id IS NULL AND source_path IS NOT NULL;
				DROP INDEX IF EXISTS idx_events_source_path;
				DROP INDEX IF EXISTS idx_events_source_tail;
				ALTER TABLE events DROP COLUMN source_path;
				\(Self.createPathIDIndexSQL)
				COMMIT;
				""")
		} catch {
			// [CRITICAL] `sqlite3_exec` halts mid-string and RETURNS WITH THE TRANSACTION STILL OPEN —
			// see `migrateScanIndexIfNeeded` for the full rationale. Without this the connection wedges
			// and the app silently stops recording spend for the rest of the process.
			try? db.execute("ROLLBACK;")
			throw error
		}
		legacySourcePathColumn = false
		return true
	}

	/// Replaces `idx_events_provider_ts` with the wider covering index. Idempotent, and safe to call
	/// on every launch — it returns immediately once the new index exists.
	///
	/// **Must be called OFF the main thread** — it rewrites a whole-index migration and takes seconds
	/// on a real corpus. The payoff is that the dashboard and analytics scans become covering-index
	/// scans (`USING COVERING INDEX idx_events_scan`) instead of `idx_events_provider_ts` lookups.
	///
	/// Disk cost is only +9.92 MiB (+2.7%), NOT the +54 MB an add-only `CREATE` would cost:
	/// `idx_events_provider_ts` is a strict key PREFIX of the new index, so it becomes dead weight and
	/// reclaiming it pays for most of the build. **The drop-then-create ORDER is load-bearing** —
	/// `auto_vacuum` is 0, so creating first and dropping second would permanently keep the +54 MB of
	/// file growth. Both statements run in ONE transaction so a crash mid-migration can never leave the
	/// database with neither index (which would degrade every scan to a full table scan).
	public func migrateScanIndexIfNeeded() throws {
		try withConnectionLock {
			// The early-out must require BOTH end-state facts, not just "the new index exists". Keying
			// only on the new index would leave `idx_events_provider_ts` in place forever on any database
			// that ends up carrying both (e.g. the empty-table inline create running against a schema
			// that already had the legacy index) — which is precisely the +54 MB this migration exists to
			// avoid paying.
			let probe = try db.prepare(
				"SELECT name FROM sqlite_master WHERE type='index' AND name IN ('idx_events_scan', 'idx_events_provider_ts');")
			var hasScan = false
			var hasLegacy = false
			while try probe.step() {
				switch probe.text(0) {
				case "idx_events_scan": hasScan = true
				case "idx_events_provider_ts": hasLegacy = true
				default: break
				}
			}
			if hasScan, !hasLegacy { return }
			do {
				try db.execute(
					"""
					BEGIN IMMEDIATE;
					DROP INDEX IF EXISTS idx_events_provider_ts;
					\(Self.createScanIndexSQL)
					COMMIT;
					""")
			} catch {
				// [CRITICAL] Every multi-statement `db.execute` needs this explicit ROLLBACK — see the
				// `sqlite3_exec` rule in `mac/AGENTS.md`. Disk-full is the realistic trigger, and it takes
				// exactly this in-process path — NOT the kill -9 path where SQLite's own recovery applies.
				try? db.execute("ROLLBACK;")
				throw error
			}
		}
	}

	/// Migrates the `cursors` table from single-column PK (path) to composite PK (path, provider).
	/// Required for shared-source-path providers (MiMo, Nemotron, Big Pickle, DeepSeek all read opencode.db).
	/// Runs on every launch but returns immediately once the composite PK exists.
	private func migrateCursorsTableIfNeeded() throws {
		// Inspect SQLite's key metadata; inline and table-level PRIMARY KEY syntax are equivalent.
		let probe = try db.prepare(
			"""
			SELECT 1 FROM pragma_table_info('cursors')
			WHERE name = 'provider' AND pk = 0;
			""")
		let needsMigration = try probe.step()
		probe.reset()
		guard needsMigration else { return }

		do {
			try db.execute(
				"""
				BEGIN IMMEDIATE;
				CREATE TABLE cursors_new (
					path TEXT NOT NULL,
					provider TEXT NOT NULL DEFAULT '',
					size INTEGER NOT NULL,
					mtime REAL NOT NULL,
					offset INTEGER NOT NULL,
					fingerprint TEXT NOT NULL DEFAULT '',
					ctime REAL NOT NULL DEFAULT 0,
					parser_revision INTEGER NOT NULL DEFAULT 1,
					parser_state TEXT NOT NULL DEFAULT '',
					PRIMARY KEY (path, provider)
				) WITHOUT ROWID;
				INSERT INTO cursors_new (path, provider, size, mtime, offset, fingerprint, ctime, parser_revision, parser_state)
				SELECT path, provider, size, mtime, offset, fingerprint, ctime, parser_revision, parser_state FROM cursors;
				DROP TABLE cursors;
				ALTER TABLE cursors_new RENAME TO cursors;
				CREATE INDEX IF NOT EXISTS idx_cursors_provider ON cursors(provider);
				COMMIT;
				""")
		} catch {
			try? db.execute("ROLLBACK;")
			throw error
		}
	}

	/// Drops `idx_events_ts`, a timestamp-only index no production query uses.
	///
	/// First paint and per-provider rollups are covered by `idx_events_scan`. The only reader was the
	/// unused `provider: nil` branch of `rollup` / `dailyCostSeries` (tests only). On a live 325 MB /
	/// 934k-event corpus the index was 62 MB (~20% of the file) and added ~1.3× insert amplification.
	///
	/// **Must run OFF the main thread.** `DROP INDEX` is milliseconds; reclaiming the pages is a VACUUM
	/// (~0.7 s on that corpus) gated by `compactIfNeeded`'s freelist share and disk-space checks.
	public func dropUnusedTimestampIndexIfNeeded() throws {
		let dropped = try withConnectionLock { () -> Bool in
			let probe = try db.prepare(
				"SELECT 1 FROM sqlite_master WHERE type='index' AND name='idx_events_ts';")
			let present = try probe.step()
			probe.reset()
			guard present else { return false }
			do {
				try db.execute(
					"""
					BEGIN IMMEDIATE;
					DROP INDEX IF EXISTS idx_events_ts;
					COMMIT;
					""")
			} catch {
				try? db.execute("ROLLBACK;")
				throw error
			}
			return true
		}
		guard dropped else { return }
		_ = try? compactIfNeeded(minFreelistPercent: 15)
	}

	// MARK: - Ingest

	/// Current shape: the path rides as an interned `paths.id`, so an event row costs 8 bytes for its
	/// provenance instead of a ~119-character absolute path.
	private static let upsertSQL = """
		INSERT INTO events (provider, msg_id, req_id, model, ts, project, input, output, cache5m, cache1h, cache_read, path_id)
		VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
		ON CONFLICT(provider, msg_id, req_id) DO UPDATE SET
		  model=excluded.model, ts=excluded.ts, project=excluded.project,
		  input=excluded.input, output=excluded.output,
		  cache5m=excluded.cache5m, cache1h=excluded.cache1h, cache_read=excluded.cache_read,
		  path_id=coalesce(excluded.path_id, events.path_id)
		WHERE excluded.output > events.output
		   OR (excluded.output = events.output
		       AND (excluded.input + excluded.output + excluded.cache5m + excluded.cache1h + excluded.cache_read)
		         > (events.input + events.output + events.cache5m + events.cache1h + events.cache_read));
		"""

	/// Pre-interning shape, used ONLY in the window between an upgrade launch and the off-main
	/// `migrateSourcePathIndexIfNeeded()`. It writes BOTH columns: `source_path` so the still-legacy
	/// `deleteEvents` predicate can find these rows, `path_id` so the migration's backfill (which only
	/// fills `path_id IS NULL` rows) is consistent either way.
	private static let upsertLegacySQL = """
		INSERT INTO events (provider, msg_id, req_id, model, ts, project, input, output, cache5m, cache1h, cache_read, path_id, source_path)
		VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
		ON CONFLICT(provider, msg_id, req_id) DO UPDATE SET
		  model=excluded.model, ts=excluded.ts, project=excluded.project,
		  input=excluded.input, output=excluded.output,
		  cache5m=excluded.cache5m, cache1h=excluded.cache1h, cache_read=excluded.cache_read,
		  path_id=coalesce(excluded.path_id, events.path_id),
		  source_path=coalesce(excluded.source_path, events.source_path)
		WHERE excluded.output > events.output
		   OR (excluded.output = events.output
		       AND (excluded.input + excluded.output + excluded.cache5m + excluded.cache1h + excluded.cache_read)
		         > (events.input + events.output + events.cache5m + events.cache1h + events.cache_read));
		"""

	/// Upserts a batch with keep-max-output semantics.
	public func ingest(_ events: [UsageEvent], sourcePath: String? = nil) throws {
		try withConnectionLock {
			guard !events.isEmpty else { return }
			let legacy = legacySourcePathColumn
			let upsert = try db.prepare(legacy ? Self.upsertLegacySQL : Self.upsertSQL)
			try db.transaction {
				// Interned ONCE per batch, inside the same transaction as the rows that reference it, so
				// a rolled-back ingest can never leave a dangling `paths` row behind.
				let pathID = try sourcePath.flatMap { try internedPathID($0) }
				for event in events {
					let usage = event.usage
					upsert.bind(1, event.provider.rawValue)
					upsert.bind(2, event.messageId)
					upsert.bind(3, event.requestId)
					upsert.bind(4, event.model)
					upsert.bind(5, event.timestamp.timeIntervalSince1970)
					upsert.bind(6, event.project)
					upsert.bind(7, usage.input)
					upsert.bind(8, usage.output)
					upsert.bind(9, usage.cacheCreate5m)
					upsert.bind(10, usage.cacheCreate1h)
					upsert.bind(11, usage.cacheRead)
					// `bind(_:String?)` is the only NULL-binding overload; `nil` there is a bound NULL, not
					// an omitted parameter, so a batch with no source path stores `path_id IS NULL`.
					if let pathID { upsert.bind(12, pathID) } else { upsert.bind(12, String?.none) }
					if legacy { upsert.bind(13, sourcePath) }
					_ = try upsert.step()
					upsert.reset()
				}
			}
			bumpGeneration()
		}
	}

	func usageBySourcePath(
		provider: ProviderID, sourcePaths: Set<String>
	) throws -> [String: TokenUsage] {
		try withConnectionLock {
			guard !sourcePaths.isEmpty else { return [:] }
			var result: [String: TokenUsage] = [:]
			let sortedPaths = sourcePaths.sorted()
			var start = 0
			while start < sortedPaths.count {
				let end = min(start + 500, sortedPaths.count)
				let paths = Array(sortedPaths[start..<end])
				let placeholders = Array(repeating: "?", count: paths.count).joined(separator: ",")
				let pathColumn = legacySourcePathColumn ? "source_path" : "paths.path"
				let pathJoin = legacySourcePathColumn ? "" : "JOIN paths ON events.path_id = paths.id"
				let stmt = try db.prepare(
					"""
					SELECT \(pathColumn), SUM(input), SUM(output), SUM(cache5m), SUM(cache1h), SUM(cache_read)
					FROM events \(pathJoin)
					WHERE provider = ? AND \(pathColumn) IN (\(placeholders))
					GROUP BY \(pathColumn)
					""")
				stmt.bind(1, provider.rawValue)
				for (index, path) in paths.enumerated() { stmt.bind(Int32(index + 2), path) }
				while try stmt.step() {
					guard let path = stmt.text(0) else { continue }
					result[path] = TokenUsage(
						input: stmt.int(1), output: stmt.int(2),
						cacheCreate5m: stmt.int(3), cacheCreate1h: stmt.int(4),
						cacheRead: stmt.int(5))
				}
				start = end
			}
			return result
		}
	}

	/// The interned `paths.id` for `path`, inserting it on first sight. Called once per ingested FILE,
	/// never per event, so preparing here is immaterial next to the batch it precedes. Caller must hold
	/// `connectionLock`.
	private func internedPathID(_ path: String) throws -> Int? {
		let insert = try db.prepare("INSERT OR IGNORE INTO paths (path) VALUES (?1);")
		insert.bind(1, path)
		_ = try insert.step()
		let lookup = try db.prepare("SELECT id FROM paths WHERE path = ?1;")
		lookup.bind(1, path)
		guard try lookup.step() else { return nil }
		let id = lookup.int(0)
		// Reset on the way OUT: a statement left parked in `SQLITE_ROW` holds an open read snapshot that
		// blocks VACUUM and WAL checkpointing (see `cursor(for:)`).
		lookup.reset()
		return id
	}

	/// Removes the events indexed from one source file. `timestampAtOrAfter` scopes the delete to a
	/// SUFFIX of that file's timeline — the range a `.watermark` provider is about to re-read — so a
	/// record edited or removed inside that range is genuinely replaced rather than left stale, without
	/// wiping the retained history below the watermark. `nil` deletes the whole file's events.
	///
	/// The `paths` row is deliberately NOT pruned when its last event goes: the set is bounded by
	/// distinct files ever seen (13,746 on the real corpus, ~1.6 MB), while proving a path unreferenced
	/// costs an `events` scan on the very call this index keeps indexed for its 80x speedup. A path
	/// that comes back simply reuses its existing id.
	public func deleteEvents(sourcePath: String, provider: ProviderID? = nil, timestampAtOrAfter: Date? = nil)
		throws
	{
		try withConnectionLock {
			let delete = try db.prepare(
				Self.deleteEventsSQL(
					legacyColumn: legacySourcePathColumn, ranged: timestampAtOrAfter != nil,
					scoped: provider != nil))
			delete.bind(1, sourcePath)
			var param: Int32 = 2
			if let timestampAtOrAfter { delete.bind(param, timestampAtOrAfter.timeIntervalSince1970); param += 1 }
			if let provider { delete.bind(param, provider.rawValue) }
			_ = try delete.step()
			bumpGeneration()
		}
	}

	/// The exact delete SQL, shared by `deleteEvents` AND `deleteEventsQueryPlan` so a plan assertion
	/// can never drift from what actually runs (same contract as `groupedScanSQL`).
	///
	/// Current shape: the scalar subquery resolves the path to its interned id through the `paths`
	/// UNIQUE index, then `idx_events_path_id` narrows `events` — an index SEARCH on both sides. An
	/// unknown path yields NULL, and `path_id = NULL` matches nothing, which is the correct no-op.
	///
	/// Legacy shape (pre-interning window only): the `substr` conjunct is what let SQLite use
	/// `idx_events_source_tail`, while the exact `source_path = ?1` conjunct keeps the row set
	/// UNCONDITIONALLY identical — `source_path = ?1` implies `substr(source_path, -24) = substr(?1, -24)`,
	/// so `A AND B` is logically equivalent to `B` alone.
	static func deleteEventsSQL(legacyColumn: Bool, ranged: Bool, scoped: Bool = false) -> String {
		let scope =
			legacyColumn
			? "substr(source_path, -24) = substr(?1, -24) AND source_path = ?1"
			: "path_id = (SELECT id FROM paths WHERE path = ?1)"
		let providerClause = scoped ? " AND provider = ?\(ranged ? "3" : "2")" : ""
		return "DELETE FROM events WHERE \(scope)\(ranged ? " AND ts >= ?2" : "")\(providerClause);"
	}

	/// `EXPLAIN QUERY PLAN` `detail` rows for the source-path delete — the perf-regression guard.
	/// `deleteEvents` fires from the `.reset` branch several times a minute (`canTailAppend == false`
	/// for Codex, Gemini, OpenCode, Copilot and Muse Spark), and an unindexed full `SCAN events` is
	/// ~80× slower than the indexed delete. Guard: `GroupedScanGuardsTests`.
	func deleteEventsQueryPlan(ranged: Bool) throws -> [String] {
		try withConnectionLock {
			let sql =
				"EXPLAIN QUERY PLAN "
				+ Self.deleteEventsSQL(legacyColumn: legacySourcePathColumn, ranged: ranged)
			guard let stmt = try? db.prepare(sql) else { return [] }
			var rows: [String] = []
			while try stmt.step() { rows.append(stmt.text(3) ?? "") }  // detail = column 3
			return rows
		}
	}

	public func sourcePaths(provider: ProviderID) throws -> Set<String> {
		try withConnectionLock {
			let sql =
				legacySourcePathColumn
				? """
				SELECT DISTINCT source_path
				FROM events
				WHERE provider = ?1 AND source_path IS NOT NULL;
				"""
				: """
				SELECT DISTINCT paths.path
				FROM events JOIN paths ON paths.id = events.path_id
				WHERE events.provider = ?1;
				"""
			let stmt = try db.prepare(sql)
			stmt.bind(1, provider.rawValue)
			var paths = Set<String>()
			while try stmt.step() {
				if let path = stmt.text(0) { paths.insert(path) }
			}
			return paths
		}
	}

	// MARK: - Cursors

	/// Reused across calls instead of re-compiling the same SQL ~10,350 times per reindex pass.
	/// Deliberately NOT a snapshot of the whole table: every lookup still hits live SQLite state, so
	/// there is no staleness surface at all — a cached `[path: FileState]` dictionary would both go
	/// stale against writes made during the same pass and cost ~7 MB of transient allocation, and a
	/// provider-scoped one would silently miss legacy `provider = ''` rows and downgrade their cheap
	/// skip into a `.reset` (deleteEvents + full re-parse). Guarded by `withConnectionLock`, which is
	/// what makes reusing one statement handle across threads safe.
	private var cursorLookup: SQLiteStatement?

	public func cursor(for path: String, provider: ProviderID) -> FileState? {
		withConnectionLock {
			if cursorLookup == nil {
				cursorLookup = try? db.prepare(
					"SELECT size, mtime, offset, fingerprint, ctime, provider, parser_revision, parser_state FROM cursors WHERE path = ?1 AND provider = ?2;")
			}
			guard let stmt = cursorLookup else { return nil }
			// `reset` also clears bindings, so a previous call's path can never leak into this one.
			stmt.reset()
			stmt.bind(1, path)
			stmt.bind(2, provider.rawValue)
			guard (try? stmt.step()) == true else { return nil }
			// `text()` goes through `String(cString:)`, which COPIES, so every field is out of
			// SQLite's memory before the reset below.
			let state = FileState(
				size: stmt.int(0), mtime: stmt.double(1), offset: stmt.int(2),
				fingerprint: stmt.text(3) ?? "", ctime: stmt.double(4), provider: stmt.text(5) ?? "",
				parserRevision: stmt.int(6), parserState: stmt.text(7) ?? "")
			// [CRITICAL] Reset on the way OUT, not only on the way in — see the statement-reset rule in
			// `mac/AGENTS.md`. A statement parked in `SQLITE_ROW` blocks both `VACUUM` and WAL
			// auto-checkpointing, so the `-wal` file grows without bound within a session.
			//
			// It is specifically the cache-HIT path: a statement stepped to `SQLITE_DONE` (a miss)
			// auto-resets and never blocks, which is why this is invisible to any test whose index has
			// no matching cursor row. Resetting only at the top of the NEXT call is not enough —
			// `UsageIndexer.refresh` makes its last call and then stops, leaving it parked between
			// refreshes. Guard: `UsageIndexTests.testCursorLookupDoesNotParkAStatementThatBlocksCheckpointing`.
			stmt.reset()
			return state
		}
	}

	/// Provider-owned parser states from durable cursors. Codex uses these to restore its newest
	/// official rate-limit reading without reopening every historical rollout on each app launch.
	public func parserStates(provider: ProviderID, limit: Int = 128) throws -> [String] {
		try withConnectionLock {
			let stmt = try db.prepare(
				"SELECT parser_state FROM cursors WHERE provider = ?1 AND parser_state != '' ORDER BY path DESC LIMIT ?2;" )
			stmt.bind(1, provider.rawValue)
			stmt.bind(2, max(1, limit))
			var states: [String] = []
			while try stmt.step() {
				if let state = stmt.text(0) { states.append(state) }
			}
			return states
		}
	}

	public func setCursor(
		path: String, size: Int, mtime: Double, offset: Int, fingerprint: String = "", ctime: Double = 0,
		provider: ProviderID? = nil, parserRevision: Int = 1, parserState: String = ""
	)
		throws
	{
		try withConnectionLock {
			// On conflict, only OVERWRITE `provider` when the caller supplied a non-empty one — a legacy
			// caller that omits it (binds '') must never wipe a previously-recorded provider.
			let stmt = try db.prepare(
				"""
				INSERT INTO cursors (path, size, mtime, offset, fingerprint, ctime, provider, parser_revision, parser_state) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
				ON CONFLICT(path, provider) DO UPDATE SET
				  size=excluded.size, mtime=excluded.mtime, offset=excluded.offset,
				  fingerprint=excluded.fingerprint, ctime=excluded.ctime,
				  parser_revision=excluded.parser_revision, parser_state=excluded.parser_state;
				""")
			stmt.bind(1, path)
			stmt.bind(2, size)
			stmt.bind(3, mtime)
			stmt.bind(4, offset)
			stmt.bind(5, fingerprint)
			stmt.bind(6, ctime)
			stmt.bind(7, provider?.rawValue ?? "")
			stmt.bind(8, parserRevision)
			stmt.bind(9, parserState)
			_ = try stmt.step()
		}
	}

	/// Cheap one-time backfill: stamp a provider onto an existing cursor whose column is still '' (a
	/// row written before the `provider` column existed, or by a skip that never rewrote the cursor).
	/// Used by `UsageIndexer.refresh` so the retention sweep can scope to this provider's live files.
	public func setCursorProvider(path: String, provider: ProviderID) throws {
		try withConnectionLock {
			let stmt = try db.prepare(
				"UPDATE cursors SET provider = ?1 WHERE path = ?2 AND provider = '';"
			)
			stmt.bind(1, provider.rawValue)
			stmt.bind(2, path)
			_ = try stmt.step()
		}
	}

	/// Paths of the cursors this provider currently holds — the BOUNDED candidate set for the
	/// durable-retention stale-file sweep (bounded by live file count, unlike the ever-growing set of
	/// `source_path`s that retained events accumulate). See `UsageIndexer.refresh`.
	public func cursorPaths(provider: ProviderID) throws -> Set<String> {
		try withConnectionLock {
			let stmt = try db.prepare("SELECT path FROM cursors WHERE provider = ?1;")
			stmt.bind(1, provider.rawValue)
			var paths = Set<String>()
			while try stmt.step() {
				if let path = stmt.text(0) { paths.insert(path) }
			}
			return paths
		}
	}

	public func deleteCursor(path: String, provider: ProviderID) throws {
		try withConnectionLock {
			let stmt = try db.prepare("DELETE FROM cursors WHERE path = ?1 AND provider = ?2;")
			stmt.bind(1, path)
			stmt.bind(2, provider.rawValue)
			_ = try stmt.step()
		}
	}

	/// Shared row decode for the five scan loops that SELECT the identical 8-column projection
	/// `provider, model, ts, input, output, cache5m, cache1h, cache_read` (`rollup` / `windowSummaries` /
	/// `modelDaySummaries` / `hourWeekdayBins` / `multiWindowSummaries`). `dailyCostSeries` uses a
	/// different model-only projection and is intentionally NOT routed here. Each caller's `body` keeps
	/// its own guard/accumulation — a `return` skips a row (the loop's former `continue`). The `try`
	/// surfaces a mid-scan `SQLiteError.step` to the caller instead of silently truncating (see the
	/// scan-error-surfacing fix), and `stmt.step()`'s ROW/DONE loop behavior is unchanged.
	private func forEachEvent(
		_ stmt: SQLiteStatement,
		_ body: (_ provider: ProviderID?, _ model: String, _ tsEpoch: Double, _ usage: TokenUsage) throws -> Void
	) throws {
		while try stmt.step() {
			let provider = ProviderID(rawValue: stmt.text(0) ?? "")
			let model = stmt.text(1) ?? ""
			let tsEpoch = stmt.double(2)
			let usage = TokenUsage(
				input: stmt.int(3), output: stmt.int(4),
				cacheCreate5m: stmt.int(5), cacheCreate1h: stmt.int(6), cacheRead: stmt.int(7))
			try body(provider, model, tsEpoch, usage)
		}
	}

	// MARK: - Rollup (cold start = SELECT, not a full-corpus walk)

	/// Today / last-7-days / per-model buckets, cost computed PER EVENT (the >200K context tier is a
	/// per-request surcharge, so cost can't be derived from summed tokens). Reads only the last-N-day
	/// window via `idx_events_scan` (`provider` + `ts`). Cross-provider totals use `windowSummaries`.
	public func rollup(
		provider: ProviderID,
		days: Int = 7,
		calculator: CostCalculator = CostCalculator(),
		now: Date = Date(),
		calendar: Calendar = .current
	) throws -> UsageRollup {
		try withConnectionLock {
			let windowDays = max(days, 1)
			let startOfToday = calendar.startOfDay(for: now)
			let windowStart =
				calendar.date(byAdding: .day, value: -(windowDays - 1), to: startOfToday) ?? startOfToday
			let todayEpoch = startOfToday.timeIntervalSince1970
			let windowEpoch = windowStart.timeIntervalSince1970
			let nowEpoch = now.timeIntervalSince1970

			var today = CostBucket()
			var window = CostBucket()
			var byModel: [String: CostBucket] = [:]

			let sql =
				"SELECT provider, model, ts, input, output, cache5m, cache1h, cache_read FROM events WHERE ts >= ?1 AND ts <= ?2 AND provider = ?3;"
			guard let stmt = try? db.prepare(sql) else {
				return UsageRollup(today: today, last7d: window, byModel7d: byModel, windowDays: windowDays)
			}
			stmt.bind(1, windowEpoch)
			stmt.bind(2, nowEpoch)
			stmt.bind(3, provider.rawValue)

			try forEachEvent(stmt) { provider, model, ts, usage in
				// Skip rows whose provider string doesn't decode — matches every sibling scan. Never fall
				// back to `.claude`: that folded an unknown provider's cost into the real-dollar headline.
				// Filtered scans always decode, so nothing is lost.
				guard let eventProvider = provider else { return }
				let event = UsageEvent(
					messageId: "", requestId: "", provider: eventProvider, model: model,
					timestamp: Date(timeIntervalSince1970: ts), usage: usage)
				let cost = calculator.cost(model: model, usage: usage)
				if ts >= todayEpoch { today.add(event, cost: cost) }
				window.add(event, cost: cost)
				byModel[model, default: CostBucket()].add(event, cost: cost)
			}
			return UsageRollup(today: today, last7d: window, byModel7d: byModel, windowDays: windowDays)
		}
	}

	/// Per-day dollar cost for the last `days` LOCAL days (oldest → newest, exactly `days` points),
	/// cost computed PER EVENT (same reason as `rollup()` — the >200K tier is a per-request surcharge)
	/// and bucketed by LOCAL calendar day so the series' rightmost point equals the header's local
	/// `$ today`. Unpriced models are omitted because this is a cost-only series. Cross-provider
	/// totals use `windowSummaries`. Feeds the 7-day popover chart.
	public func dailyCostSeries(
		provider: ProviderID,
		days: Int = 7,
		calculator: CostCalculator = CostCalculator(),
		now: Date = Date(),
		calendar: Calendar = .current
	) throws -> [Double] {
		try withConnectionLock {
			guard days > 0 else { return [] }
			let count = days
			var buckets = [Double](repeating: 0, count: count)
			let startOfToday = calendar.startOfDay(for: now)
			guard let windowStart = calendar.date(byAdding: .day, value: -(count - 1), to: startOfToday)
			else { return buckets }
			let windowEpoch = windowStart.timeIntervalSince1970
			let nowEpoch = now.timeIntervalSince1970

			let sql =
				"SELECT model, ts, input, output, cache5m, cache1h, cache_read FROM events WHERE ts >= ?1 AND ts <= ?2 AND provider = ?3;"
			guard let stmt = try? db.prepare(sql) else { return buckets }
			stmt.bind(1, windowEpoch)
			stmt.bind(2, nowEpoch)
			stmt.bind(3, provider.rawValue)

			while try stmt.step() {
				let model = stmt.text(0) ?? ""
				let usage = TokenUsage(
					input: stmt.int(2), output: stmt.int(3),
					cacheCreate5m: stmt.int(4), cacheCreate1h: stmt.int(5), cacheRead: stmt.int(6))
				guard let cost = calculator.cost(model: model, usage: usage) else { continue }
				let day = calendar.startOfDay(for: Date(timeIntervalSince1970: stmt.double(1)))
				let index = calendar.dateComponents([.day], from: windowStart, to: day).day ?? -1
				if index >= 0 && index < count { buckets[index] += cost }
			}
			return buckets
		}
	}

	/// One indexed event-window scan that returns per-provider and aggregate rollups plus local-day
	/// series. `providers` is the live-provider allowlist for the caller; the aggregate is the sum of
	/// those providers only, so roadmap/local providers cannot leak into the popover aggregate.
	public func windowSummaries(
		providers: [ProviderID],
		days: Int = 7,
		calculator: CostCalculator = CostCalculator(),
		now: Date = Date(),
		calendar: Calendar = .current
	) throws -> UsageWindowSummaries {
		try windowSummariesGrouped(
			providers: providers, days: days, calculator: calculator, now: now, calendar: calendar)
	}

	/// Per-event reference implementation of `windowSummaries`, retained as the parity oracle for
	/// `MultiWindowSummariesParityTests`. Not called in production — `windowSummaries` uses the grouped
	/// scan. Materializes every event row and buckets it with per-row `Calendar` math.
	func windowSummariesPerEvent(
		providers: [ProviderID],
		days: Int = 7,
		calculator: CostCalculator = CostCalculator(),
		now: Date = Date(),
		calendar: Calendar = .current
	) throws -> UsageWindowSummaries {
		try withConnectionLock {
			let count = max(days, 0)
			let startOfToday = calendar.startOfDay(for: now)
			let windowStart =
				count > 0 ? calendar.date(byAdding: .day, value: -(count - 1), to: startOfToday) : nil
			let todayEpoch = startOfToday.timeIntervalSince1970
			// The window bucket, per-model breakdown, and daily series all span the selected timeframe.
			let windowEpoch = (windowStart ?? startOfToday).timeIntervalSince1970
			let lowerEpoch = min(windowEpoch, todayEpoch)
			let nowEpoch = now.timeIntervalSince1970

			let uniqueProviders = Array(Set(providers)).sorted { $0.rawValue < $1.rawValue }
			var aggregate = MutableUsageWindowSummary(days: count)
			var providerSummaries = Dictionary(
				uniqueKeysWithValues: Set(uniqueProviders.map(\.consolidated)).map { ($0, MutableUsageWindowSummary(days: count)) })
			guard !uniqueProviders.isEmpty else {
				return UsageWindowSummaries(aggregate: aggregate.summary(), providers: [:])
			}
			let placeholders = uniqueProviders.indices.map { "?\($0 + 3)" }.joined(separator: ", ")
			let sql = """
				SELECT provider, model, ts, input, output, cache5m, cache1h, cache_read
				FROM events
				WHERE ts >= ?1 AND ts <= ?2 AND provider IN (\(placeholders));
				"""
			guard let stmt = try? db.prepare(sql) else {
				return UsageWindowSummaries(
					aggregate: aggregate.summary(),
					providers: providerSummaries.mapValues { $0.summary() })
			}
			stmt.bind(1, lowerEpoch)
			stmt.bind(2, nowEpoch)
			for (offset, provider) in uniqueProviders.enumerated() {
				stmt.bind(Int32(offset + 3), provider.rawValue)
			}

			try forEachEvent(stmt) { provider, model, ts, usage in
				guard let rawProvider = provider else { return }
				let provider = rawProvider.consolidated
				if providerSummaries[provider] == nil { return }
				let timestamp = Date(timeIntervalSince1970: ts)
				let event = UsageEvent(
					messageId: "", requestId: "", provider: provider, model: model, timestamp: timestamp,
					usage: usage)
				let cost = calculator.cost(model: model, usage: usage)
				// In-place mutation via the Dictionary subscript's `_modify` accessor — no
				// extract-copy-mutate-reinsert (which triggered a per-event COW of the summary's
				// `byModel`/`dailyCostSeries`). No-ops when the key is absent (already guarded above).
				providerSummaries[provider]?.add(
					event, timestamp: timestamp, cost: cost, todayEpoch: todayEpoch,
					windowEpoch: windowEpoch, windowStart: windowStart, calendar: calendar)
				aggregate.add(
					event, timestamp: timestamp, cost: cost, todayEpoch: todayEpoch,
					windowEpoch: windowEpoch, windowStart: windowStart, calendar: calendar)
			}

			return UsageWindowSummaries(
				aggregate: aggregate.summary(),
				providers: providerSummaries.mapValues { $0.summary() })
		}
	}

	/// One row per (provider, model, local calendar day) inside the window, WITHOUT collapsing across
	/// days or models — the source for the Advanced Analytics tray's per-model/per-day breakdown and
	/// CSV export. Mirrors `windowSummaries`' locking/SQL/costing pattern exactly (same `events` table,
	/// same `withConnectionLock`, same per-event `calculator.cost(model:usage:)`), but returns the
	/// un-aggregated rows instead of folding them into `CostBucket`s.
	public func modelDaySummaries(
		providers: [ProviderID],
		days: Int,
		calculator: CostCalculator = CostCalculator(),
		now: Date = Date(),
		calendar: Calendar = .current
	) throws -> [ModelDaySummary] {
		try withConnectionLock {
			let count = max(days, 1)
			let startOfToday = calendar.startOfDay(for: now)
			guard let windowStart = calendar.date(byAdding: .day, value: -(count - 1), to: startOfToday)
			else { return [] }
			let windowEpoch = windowStart.timeIntervalSince1970
			let nowEpoch = now.timeIntervalSince1970

			let uniqueProviders = Array(Set(providers)).sorted { $0.rawValue < $1.rawValue }
			guard !uniqueProviders.isEmpty else { return [] }
			let placeholders = uniqueProviders.indices.map { "?\($0 + 3)" }.joined(separator: ", ")
			let sql = """
				SELECT provider, model, ts, input, output, cache5m, cache1h, cache_read
				FROM events
				WHERE ts >= ?1 AND ts <= ?2 AND provider IN (\(placeholders));
				"""
			guard let stmt = try? db.prepare(sql) else { return [] }
			stmt.bind(1, windowEpoch)
			stmt.bind(2, nowEpoch)
			for (offset, provider) in uniqueProviders.enumerated() {
				stmt.bind(Int32(offset + 3), provider.rawValue)
			}

			// Shares `ModelDayAccumulator` with `ModelDaySummary.bucketed`, so the two paths cannot
			// drift in bucketing, accumulation, or row order.
			var accumulator = ModelDayAccumulator()
			try forEachEvent(stmt) { provider, model, ts, usage in
				guard let rawProvider = provider else { return }
				let provider = rawProvider.consolidated
				accumulator.add(
					provider: provider, model: model,
					day: calendar.startOfDay(for: Date(timeIntervalSince1970: ts)), usage: usage,
					cost: calculator.cost(model: model, usage: usage) ?? 0)
			}
			return accumulator.finish()
		}
	}

	/// Window totals bucketed by PROJECT (the `cwd`/project attribution on each event) — the analytics
	/// warehouse's "by project" slice. Mirrors `modelDaySummaries`' locking / window / per-event costing
	/// pattern, but reads the extra `project` column (so it uses its own `while try stmt.step()` scan
	/// rather than the shared `forEachEvent` helper, which projects only the 8-column token shape) and
	/// folds a nil/empty project into `ProjectCostSummary.unattributed`. Returned most-expensive-first,
	/// ties broken by total tokens then project name so the order is stable for fully-unpriced ($0) rows.
	public func projectCostSummaries(
		providers: [ProviderID],
		days: Int,
		calculator: CostCalculator = CostCalculator(),
		now: Date = Date(),
		calendar: Calendar = .current
	) throws -> [ProjectCostSummary] {
		try withConnectionLock {
			let count = max(days, 1)
			let startOfToday = calendar.startOfDay(for: now)
			guard let windowStart = calendar.date(byAdding: .day, value: -(count - 1), to: startOfToday)
			else { return [] }
			let windowEpoch = windowStart.timeIntervalSince1970
			let nowEpoch = now.timeIntervalSince1970

			let uniqueProviders = Array(Set(providers)).sorted { $0.rawValue < $1.rawValue }
			guard !uniqueProviders.isEmpty else { return [] }
			let placeholders = uniqueProviders.indices.map { "?\($0 + 3)" }.joined(separator: ", ")
			let sql = """
				SELECT project, model, input, output, cache5m, cache1h, cache_read
				FROM events
				WHERE ts >= ?1 AND ts <= ?2 AND provider IN (\(placeholders));
				"""
			guard let stmt = try? db.prepare(sql) else { return [] }
			stmt.bind(1, windowEpoch)
			stmt.bind(2, nowEpoch)
			for (offset, provider) in uniqueProviders.enumerated() {
				stmt.bind(Int32(offset + 3), provider.rawValue)
			}

			var accumulators: [String: ProjectCostSummary] = [:]
			// `while try stmt.step()` (NOT `try?`) so a mid-scan SQLite error surfaces to the caller
			// instead of silently truncating a partial total — the money-path invariant.
			while try stmt.step() {
				let rawProject = stmt.text(0) ?? ""
				let project = rawProject.isEmpty ? ProjectCostSummary.unattributed : rawProject
				let model = stmt.text(1) ?? ""
				let usage = TokenUsage(
					input: stmt.int(2), output: stmt.int(3),
					cacheCreate5m: stmt.int(4), cacheCreate1h: stmt.int(5), cacheRead: stmt.int(6))
				let cost = calculator.cost(model: model, usage: usage) ?? 0
				if var existing = accumulators[project] {
					existing.eventCount += 1
					existing.inputTokens += usage.input
					existing.outputTokens += usage.output
					existing.cache5mTokens += usage.cacheCreate5m
					existing.cache1hTokens += usage.cacheCreate1h
					existing.cacheReadTokens += usage.cacheRead
					existing.cost += cost
					accumulators[project] = existing
				} else {
					accumulators[project] = ProjectCostSummary(
						project: project, eventCount: 1, inputTokens: usage.input, outputTokens: usage.output,
						cache5mTokens: usage.cacheCreate5m, cache1hTokens: usage.cacheCreate1h,
						cacheReadTokens: usage.cacheRead, cost: cost)
				}
			}
			return accumulators.values.sorted { lhs, rhs in
				if lhs.cost != rhs.cost { return lhs.cost > rhs.cost }
				if lhs.totalTokens != rhs.totalTokens { return lhs.totalTokens > rhs.totalTokens }
				return lhs.project < rhs.project
			}
		}
	}

	/// One `HourWeekdayMatrix` PER provider (weekday 1…7 × hour 0…23, LOCAL time) for the Advanced
	/// Analytics window's Rhythm heatmap. Reads raw `ts` (which `modelDaySummaries` collapses to a
	/// `startOfDay`, discarding hour-of-day) and bins each event by `calendar.component(.weekday/.hour)`
	/// — the same local `Calendar` convention as the rest of this file, NOT a UTC `strftime` path.
	///
	/// Returns per-provider matrices (like `windowSummaries`' per-provider dict) rather than one merged
	/// grid so the analytics canvas can scope the Rhythm heatmap to a single provider (focus mode) and
	/// re-fold the checked subset on a checkbox toggle WITHOUT a second scan — exactly how `rows`
	/// (`modelDaySummaries`) already holds every provider and the canvas derives scoped views purely.
	/// Mirrors `modelDaySummaries`' locking / SQL / per-event costing pattern. Copilot bypasses the
	/// index, so its matrix comes from `HourWeekdayMatrix.bucketed(events:)`, not this method.
	public func hourWeekdayBins(
		providers: [ProviderID],
		days: Int,
		calculator: CostCalculator = CostCalculator(),
		now: Date = Date(),
		calendar: Calendar = .current
	) throws -> [ProviderID: HourWeekdayMatrix] {
		try withConnectionLock {
			let count = max(days, 1)
			let startOfToday = calendar.startOfDay(for: now)
			guard let windowStart = calendar.date(byAdding: .day, value: -(count - 1), to: startOfToday)
			else { return [:] }
			let windowEpoch = windowStart.timeIntervalSince1970
			let nowEpoch = now.timeIntervalSince1970

			let uniqueProviders = Array(Set(providers)).sorted { $0.rawValue < $1.rawValue }
			guard !uniqueProviders.isEmpty else { return [:] }
			var result = Dictionary(
				uniqueKeysWithValues: Set(uniqueProviders.map(\.consolidated)).map { ($0, HourWeekdayMatrix.zero) })

			let placeholders = uniqueProviders.indices.map { "?\($0 + 3)" }.joined(separator: ", ")
			let sql = """
				SELECT provider, model, ts, input, output, cache5m, cache1h, cache_read
				FROM events
				WHERE ts >= ?1 AND ts <= ?2 AND provider IN (\(placeholders));
				"""
			guard let stmt = try? db.prepare(sql) else { return result }
			stmt.bind(1, windowEpoch)
			stmt.bind(2, nowEpoch)
			for (offset, provider) in uniqueProviders.enumerated() {
				stmt.bind(Int32(offset + 3), provider.rawValue)
			}

			try forEachEvent(stmt) { provider, model, ts, usage in
				guard let rawProvider = provider else { return }
				let provider = rawProvider.consolidated
				guard result[provider] != nil else { return }
				let date = Date(timeIntervalSince1970: ts)
				let cost = calculator.cost(model: model, usage: usage) ?? 0
				let weekday = calendar.component(.weekday, from: date)
				let hour = calendar.component(.hour, from: date)
				result[provider]?.add(
					weekday: weekday, hour: hour, events: 1, tokens: Double(usage.total), cost: cost)
			}
			return result
		}
	}

	/// Every requested `windows` day-count's summaries from ONE indexed scan bounded by the largest
	/// requested window (not one scan per day-count). SQLite aggregates the window down to one row per
	/// `(provider, model, local-day, >200K-tier)` and Swift prices/buckets those few rows — on a heavy
	/// corpus this is a few hundred rows instead of hundreds of thousands. Delegates to
	/// `multiWindowSummariesGrouped`; `multiWindowSummariesPerEvent` is the retained parity oracle.
	public func multiWindowSummaries(
		providers: [ProviderID],
		windows: [Int] = [7, 14, 30, 90],
		calculator: CostCalculator = CostCalculator(),
		now: Date = Date(),
		calendar: Calendar = .current
	) throws -> UsageMultiWindowSummaries {
		try multiWindowSummariesGrouped(
			providers: providers, windows: windows, calculator: calculator, now: now, calendar: calendar)
	}

	/// Per-event reference implementation of `multiWindowSummaries`, retained as the parity oracle for
	/// `MultiWindowSummariesParityTests`. Not called in production. Each row is parsed/costed once and fed
	/// into every window-size accumulator whose bound it clears, bucketed with per-row `Calendar` math.
	func multiWindowSummariesPerEvent(
		providers: [ProviderID],
		windows: [Int] = [7, 14, 30, 90],
		calculator: CostCalculator = CostCalculator(),
		now: Date = Date(),
		calendar: Calendar = .current
	) throws -> UsageMultiWindowSummaries {
		try withConnectionLock {
			let requestedDays = Array(Set(windows.map { max($0, 0) })).sorted()
			guard !requestedDays.isEmpty else { return UsageMultiWindowSummaries(byDays: [:]) }

			let startOfToday = calendar.startOfDay(for: now)
			let todayEpoch = startOfToday.timeIntervalSince1970
			let nowEpoch = now.timeIntervalSince1970

			// One accumulator set per requested day-count, each with its own window start/epoch — fed
			// from the SAME row stream bounded by the largest window below.
			struct WindowBucket {
				let days: Int
				let windowStart: Date?
				let windowEpoch: Double
				var aggregate: MutableUsageWindowSummary
				var providerSummaries: [ProviderID: MutableUsageWindowSummary]
			}

			let uniqueProviders = Array(Set(providers)).sorted { $0.rawValue < $1.rawValue }
			var buckets: [WindowBucket] = requestedDays.map { days in
				let windowStart = days > 0 ? calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) : nil
				return WindowBucket(
					days: days,
					windowStart: windowStart,
					windowEpoch: (windowStart ?? startOfToday).timeIntervalSince1970,
					aggregate: MutableUsageWindowSummary(days: days),
					providerSummaries: Dictionary(
						uniqueKeysWithValues: Set(uniqueProviders.map(\.consolidated)).map { ($0, MutableUsageWindowSummary(days: days)) }))
			}

			guard !uniqueProviders.isEmpty else {
				return UsageMultiWindowSummaries(
					byDays: Dictionary(
						uniqueKeysWithValues: buckets.map {
							($0.days, UsageWindowSummaries(aggregate: $0.aggregate.summary(), providers: [:]))
						}))
			}

			let lowerEpoch = min(buckets.map(\.windowEpoch).min() ?? todayEpoch, todayEpoch)
			let placeholders = uniqueProviders.indices.map { "?\($0 + 3)" }.joined(separator: ", ")
			let sql = """
				SELECT provider, model, ts, input, output, cache5m, cache1h, cache_read
				FROM events
				WHERE ts >= ?1 AND ts <= ?2 AND provider IN (\(placeholders));
				"""
			guard let stmt = try? db.prepare(sql) else {
				return UsageMultiWindowSummaries(
					byDays: Dictionary(
						uniqueKeysWithValues: buckets.map {
							(
								$0.days,
								UsageWindowSummaries(
									aggregate: $0.aggregate.summary(),
									providers: $0.providerSummaries.mapValues { $0.summary() })
							)
						}))
			}
			stmt.bind(1, lowerEpoch)
			stmt.bind(2, nowEpoch)
			for (offset, provider) in uniqueProviders.enumerated() {
				stmt.bind(Int32(offset + 3), provider.rawValue)
			}

			try forEachEvent(stmt) { provider, model, ts, usage in
				guard let rawProvider = provider else { return }
				let provider = rawProvider.consolidated
				let timestamp = Date(timeIntervalSince1970: ts)
				let event = UsageEvent(
					messageId: "", requestId: "", provider: provider, model: model, timestamp: timestamp,
					usage: usage)
				// Cost computed once per row, reused across every window-size accumulator it feeds.
				let cost = calculator.cost(model: model, usage: usage)
				for index in buckets.indices {
					// Read the per-bucket window bounds into locals FIRST: the in-place `_modify` on
					// `buckets[index].providerSummaries[provider]` takes exclusive access to `buckets`, so the
					// call arguments must not also read `buckets[index]` (overlapping-access violation).
					let bucketWindowEpoch = buckets[index].windowEpoch
					let bucketWindowStart = buckets[index].windowStart
					// In-place `_modify` mutation — avoids the per-event COW of the extracted summary's
					// `byModel`/`dailyCostSeries`. No-ops when the provider isn't in this bucket.
					buckets[index].providerSummaries[provider]?.add(
						event, timestamp: timestamp, cost: cost, todayEpoch: todayEpoch,
						windowEpoch: bucketWindowEpoch, windowStart: bucketWindowStart,
						calendar: calendar)
					buckets[index].aggregate.add(
						event, timestamp: timestamp, cost: cost, todayEpoch: todayEpoch,
						windowEpoch: bucketWindowEpoch, windowStart: bucketWindowStart,
						calendar: calendar)
				}
			}

			return UsageMultiWindowSummaries(
				byDays: Dictionary(
					uniqueKeysWithValues: buckets.map {
						(
							$0.days,
							UsageWindowSummaries(
								aggregate: $0.aggregate.summary(),
								providers: $0.providerSummaries.mapValues { $0.summary() })
						)
					}))
		}
	}

	/// `"yyyy-MM-dd"` in the caller's calendar timezone — byte-identical to SQLite's
	/// `date(ts,'unixepoch','localtime')` when the calendar tz matches the process/OS tz (always true in
	/// production, where `calendar == .current`). Used to map a grouped row's SQL local-day string onto
	/// this window's day slots without re-parsing dates.
	private static func localDayFormatter(_ calendar: Calendar) -> DateFormatter {
		let f = DateFormatter()
		f.calendar = calendar
		f.timeZone = calendar.timeZone
		f.locale = Locale(identifier: "en_US_POSIX")
		f.dateFormat = "yyyy-MM-dd"
		return f
	}

	/// The SQLite `date()` expression that buckets `ts` into `"yyyy-MM-dd"` in the SAME timezone the
	/// caller's `calendar` uses — the only cases SQLite can express exactly. `nil` means the grouped scan
	/// can't reproduce this calendar's day boundaries in SQL (an exotic injected tz), so the caller must
	/// fall back to the per-event path. Production always passes `.current` → `'localtime'`; tests that
	/// pass a UTC calendar → the unmodified UTC `date()`. DST is handled by SQLite for `'localtime'`.
	static func sqlLocalDayExpression(_ calendar: Calendar) -> String? {
		// SQLite's date(ts,'unixepoch',…) emits proleptic-GREGORIAN day strings ("2026-07-14"). A
		// non-Gregorian Calendar.current (Buddhist/Japanese/Islamic/Hebrew — selectable in macOS
		// Language & Region, and a national default in some regions) makes `localDayFormatter` render a
		// different era ("2569-.."/"1448-.."), so the SQL `lday` would never match any day-index key and
		// EVERY row would be dropped ($0 dashboard). SQLite cannot reproduce a non-Gregorian era, so route
		// those to the era-agnostic per-event path. Guard: MultiWindowSummariesParityTests.testNonGregorianCalendarParity.
		guard calendar.identifier == .gregorian else { return nil }
		let tz = calendar.timeZone
		if tz.identifier == TimeZone.current.identifier {
			return "date(ts, 'unixepoch', 'localtime')"
		}
		if tz.secondsFromGMT() == 0 && tz.nextDaylightSavingTimeTransition == nil {
			return "date(ts, 'unixepoch')"  // fixed UTC, no DST
		}
		return nil
	}

	/// Grouped-scan equivalent of `multiWindowSummaries`: instead of materializing every event row into
	/// Swift and bucketing it with per-row `Calendar` math, SQLite aggregates the window down to one row
	/// per `(provider, model, local-day, >200K-tier)` and Swift prices/buckets those few rows. On a heavy
	/// corpus this collapses a ~300K-row / ~600K-`Calendar`-call scan to a few hundred grouped rows.
	///
	/// Correctness rests on two facts proven by `MultiWindowSummariesParityTests`:
	///  1. Local-day bucketing: `date(ts,'unixepoch','localtime')` matches `calendar = .current`, so the
	///     grouped rows' day strings map onto the same slots the per-event path computes.
	///  2. Cost: every `CostBucket` field is additive AND cost is linear once the >200K tier is fixed, so
	///     grouping by the per-event `tiered` flag (`… > 200000`, computed in SQL) and pricing the summed
	///     tokens with `cost(model:usage:forceTier:)` equals the per-event cost sum exactly.
	func multiWindowSummariesGrouped(
		providers: [ProviderID],
		windows: [Int] = [7, 14, 30, 90],
		calculator: CostCalculator = CostCalculator(),
		now: Date = Date(),
		calendar: Calendar = .current
	) throws -> UsageMultiWindowSummaries {
		// An injected timezone SQLite can't reproduce → fall back to the exact per-event path. Keeps the
		// grouped scan a correctness-preserving drop-in for any calendar (production passes `.current`).
		guard let dayExpr = Self.sqlLocalDayExpression(calendar) else {
			return try multiWindowSummariesPerEvent(
				providers: providers, windows: windows, calculator: calculator, now: now, calendar: calendar)
		}
		return try withConnectionLock {
			let requestedDays = Array(Set(windows.map { max($0, 0) })).sorted()
			guard !requestedDays.isEmpty else { return UsageMultiWindowSummaries(byDays: [:]) }

			let startOfToday = calendar.startOfDay(for: now)
			let todayEpoch = startOfToday.timeIntervalSince1970
			let nowEpoch = now.timeIntervalSince1970
			let dayFormatter = Self.localDayFormatter(calendar)
			let todayString = dayFormatter.string(from: startOfToday)

			// One bucket per requested day-count. Each precomputes its window's local-day strings so a
			// grouped row's `lday` maps to a slot by string lookup (no date re-parsing / DST math).
			struct GroupedBucket {
				let days: Int
				let windowEpoch: Double
				let dayIndex: [String: Int]
				var aggregate: MutableUsageWindowSummary
				var providerSummaries: [ProviderID: MutableUsageWindowSummary]
			}

			let uniqueProviders = Array(Set(providers)).sorted { $0.rawValue < $1.rawValue }
			var buckets: [GroupedBucket] = requestedDays.map { days in
				let windowStart = days > 0 ? calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) : nil
				var index: [String: Int] = [:]
				if let windowStart {
					for offset in 0..<days {
						if let d = calendar.date(byAdding: .day, value: offset, to: windowStart) {
							index[dayFormatter.string(from: d)] = offset
						}
					}
				}
				return GroupedBucket(
					days: days,
					windowEpoch: (windowStart ?? startOfToday).timeIntervalSince1970,
					dayIndex: index,
					aggregate: MutableUsageWindowSummary(days: days),
					providerSummaries: Dictionary(
						uniqueKeysWithValues: Set(uniqueProviders.map(\.consolidated)).map { ($0, MutableUsageWindowSummary(days: days)) }))
			}

			func assemble() -> UsageMultiWindowSummaries {
				UsageMultiWindowSummaries(
					byDays: Dictionary(
						uniqueKeysWithValues: buckets.map {
							(
								$0.days,
								UsageWindowSummaries(
									aggregate: $0.aggregate.summary(),
									providers: $0.providerSummaries.mapValues { $0.summary() })
							)
						}))
			}

			guard !uniqueProviders.isEmpty else { return assemble() }

			// tz self-verification (defense-in-depth). `sqlLocalDayExpression` only compares tz identity at
			// call time; SQLite's `localtime` reads the C-library tz, which can lag Foundation's cached
			// `TimeZone.current` if the OS timezone changes mid-session (no `tzset`). Probe that SQLite's day
			// string for `now` matches the Swift-formatted day BEFORE trusting the grouped bucketing — on any
			// mismatch (stale libc tz, tzdata divergence) fall back to the era/tz-agnostic per-event path
			// rather than silently bucket every row by the wrong day.
			let probeExpr = dayExpr.replacingOccurrences(of: "ts", with: "?1")
			if let probe = try? db.prepare("SELECT \(probeExpr);") {
				probe.bind(1, todayEpoch)
				if (try? probe.step()) == true, probe.text(0) != todayString {
					return try multiWindowSummariesPerEvent(
						providers: providers, windows: windows, calculator: calculator, now: now, calendar: calendar)
				}
			}

			let lowerEpoch = min(buckets.map(\.windowEpoch).min() ?? todayEpoch, todayEpoch)
			let placeholders = uniqueProviders.indices.map { "?\($0 + 3)" }.joined(separator: ", ")
			let sql = Self.groupedScanSQL(dayExpr: dayExpr, placeholders: placeholders,
				thresholds: calculator.pricing.contextTierThresholds)
			// Prepare failure on the (more complex) grouped SQL degrades to the exact per-event path, not
			// zeroed buckets — mirroring the tz-unsupported fallback so a prepare fault never silently
			// zeroes real spend. `withConnectionLock` is an NSRecursiveLock, so the nested acquire is safe.
			guard let stmt = try? db.prepare(sql) else {
				return try multiWindowSummariesPerEvent(
					providers: providers, windows: windows, calculator: calculator, now: now, calendar: calendar)
			}
			stmt.bind(1, lowerEpoch)
			stmt.bind(2, nowEpoch)
			for (offset, provider) in uniqueProviders.enumerated() {
				stmt.bind(Int32(offset + 3), provider.rawValue)
			}

			while try stmt.step() {
				guard let rawProvider = ProviderID(rawValue: stmt.text(0) ?? "") else { continue }
				let provider = rawProvider.consolidated
				let model = stmt.text(1) ?? ""
				let lday = stmt.text(2) ?? ""
				let threshold = calculator.pricing.price(for: model)?.lastBaseContextTokenCount ?? CostCalculator.contextTierThreshold
				let tiered = stmt.int(3) > threshold
				let usage = TokenUsage(
					input: stmt.int(4), output: stmt.int(5),
					cacheCreate5m: stmt.int(6), cacheCreate1h: stmt.int(7), cacheRead: stmt.int(8))
				let count = stmt.int(9)
				// Cost priced ONCE per group with the SQL-decided tier — never re-derived from the summed
				// context (which would falsely trip the >200K cliff for a bucket of small events).
				let cost = calculator.cost(model: model, usage: usage, forceTier: tiered)
				let isToday = lday == todayString
				for index in buckets.indices {
					let dayIndex = buckets[index].dayIndex[lday]
					// For a 0-day window (`dayIndex` empty), membership is today-only, matching the
					// per-event path's `windowEpoch == startOfToday`.
					let inWindow = buckets[index].days > 0 ? dayIndex : (isToday ? 0 : nil)
					buckets[index].providerSummaries[provider]?.addGrouped(
						model: model, usage: usage, cost: cost, count: count, isToday: isToday,
						dayIndex: inWindow)
					buckets[index].aggregate.addGrouped(
						model: model, usage: usage, cost: cost, count: count, isToday: isToday,
						dayIndex: inWindow)
				}
			}
			return assemble()
		}
	}

	/// The exact grouped-scan SQL, shared by the production scan AND `groupedScanQueryPlan` so a plan
	/// assertion can never drift from what actually runs. `dayExpr` is a `date(ts,…)` day bucket;
	/// `placeholders` is the `?3, ?4, …` provider IN list.
	static func groupedScanSQL(
		dayExpr: String, placeholders: String, thresholds: [Int] = [200_000]
	) -> String {
		// Split at every configured cliff, independent of model aliases and snapshot suffixes.
		// A bucket's lower bound selects the model's own tier without repricing summed context.
		let cases = thresholds.sorted(by: >).map {
			"WHEN input + cache_read + cache5m + cache1h > \($0) THEN \($0 + 1)"
		}.joined(separator: " ")
		return """
		SELECT provider, model,
		       \(dayExpr) AS lday,
		       CASE \(cases) ELSE 0 END AS tiered,
		       SUM(input), SUM(output), SUM(cache5m), SUM(cache1h), SUM(cache_read), COUNT(*)
		FROM events
		WHERE ts >= ?1 AND ts <= ?2 AND provider IN (\(placeholders))
		GROUP BY provider, model, lday, tiered;
		"""
	}

	/// `EXPLAIN QUERY PLAN` `detail` rows for the grouped scan — the perf-regression guard. A future
	/// edit that drops `idx_events_scan` or adds an `ORDER BY` that forces a full `SCAN events` over the
	/// whole corpus (instead of an index SEARCH on the `ts`/`provider` predicate) would silently regress
	/// the grouped scan back toward per-event cost. Guard: `GroupedScanPlanTests`.
	func groupedScanQueryPlan(providers: [ProviderID], calendar: Calendar = .current, calculator: CostCalculator = CostCalculator()) throws -> [String] {
		try withConnectionLock {
			let unique = Array(Set(providers)).sorted { $0.rawValue < $1.rawValue }
			guard !unique.isEmpty else { return [] }
			let placeholders = unique.indices.map { "?\($0 + 3)" }.joined(separator: ", ")
			let dayExpr = Self.sqlLocalDayExpression(calendar) ?? "date(ts, 'unixepoch', 'localtime')"
			let sql = "EXPLAIN QUERY PLAN " + Self.groupedScanSQL(dayExpr: dayExpr, placeholders: placeholders, thresholds: calculator.pricing.contextTierThresholds)
			guard let stmt = try? db.prepare(sql) else { return [] }
			var rows: [String] = []
			while try stmt.step() { rows.append(stmt.text(3) ?? "") }  // detail = column 3
			return rows
		}
	}

	/// Single-window grouped scan — the first-paint sibling of `windowSummaries`, expressed as a
	/// one-element `multiWindowSummariesGrouped` so both share one aggregation path.
	func windowSummariesGrouped(
		providers: [ProviderID],
		days: Int = 7,
		calculator: CostCalculator = CostCalculator(),
		now: Date = Date(),
		calendar: Calendar = .current
	) throws -> UsageWindowSummaries {
		let key = max(days, 0)
		let multi = try multiWindowSummariesGrouped(
			providers: providers, windows: [key], calculator: calculator, now: now, calendar: calendar)
		return multi.byDays[key] ?? UsageWindowSummaries(
			aggregate: MutableUsageWindowSummary(days: key).summary(), providers: [:])
	}

	/// Row count (for tests / diagnostics).
	public func eventCount(provider: ProviderID? = nil) -> Int {
		withConnectionLock {
			let sql =
				provider == nil
				? "SELECT count(*) FROM events;"
				: "SELECT count(*) FROM events WHERE provider = ?1;"
			guard let stmt = try? db.prepare(sql) else { return 0 }
			if let provider { stmt.bind(1, provider.rawValue) }
			guard (try? stmt.step()) == true else { return 0 }
			return stmt.int(0)
		}
	}
}
