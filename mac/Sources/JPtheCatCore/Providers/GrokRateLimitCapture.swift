import Foundation

/// Process-wide, thread-safe record of the `(size, mtime)` at which we last scraped a given
/// `unified.jsonl`, so `refreshFromLogs` — called on every dashboard refresh while the opt-in is
/// installed — doesn't re-open + re-read + re-parse a log whose cheap `stat()` hasn't moved since we
/// last processed it (the same regression class `CodexProvider`'s `RateLimitTailCache` fixed). Cleared
/// on process restart; keyed on absolute path so app and `jpthecat-cli` share it within one process.
private final class GrokBillingScrapeCache: @unchecked Sendable {
	private struct Entry { let size: Int; let mtime: Double }
	private let lock = NSLock()
	private var entries: [String: Entry] = [:]

	/// True when we already scraped this exact `(path, size, mtime)` triple — nothing new to read.
	func isProcessed(path: String, size: Int, mtime: Double) -> Bool {
		lock.lock()
		defer { lock.unlock() }
		guard let entry = entries[path] else { return false }
		return entry.size == size && entry.mtime == mtime
	}

	func markProcessed(path: String, size: Int, mtime: Double) {
		lock.lock()
		defer { lock.unlock() }
		entries[path] = Entry(size: size, mtime: mtime)
	}
}

private let grokBillingScrapeCache = GrokBillingScrapeCache()

/// Installs (opt-in) a Grok Build hook that captures SuperGrok / weekly credit usage into a file JP
/// can read. Grok does not persist an official rate-limit % the way Codex does; it only fetches
/// billing live and logs `billing: fetched credits config` into `~/.grok/logs/unified.jsonl`.
///
/// This never runs on install or silently — the app calls `install()` only after an explicit,
/// acknowledged tap in Settings, and `uninstall()` fully reverts by deleting the marked hook +
/// capture script. It only writes under:
///  - `~/.grok/hooks/jpthecat-rate-limit-capture.json` (Grok's designed global hooks dir)
///  - `~/Library/Application Support/JPtheCat/grok-rate-limit-capture.sh` (the script the hook runs)
///  - `~/Library/Application Support/JPtheCat/grok-rate-limits.json` (the reading JP consumes)
///
/// Never edits `~/.grok/config.toml`, never reads `auth.json`, never calls xAI over the network —
/// the capture scrapes numbers Grok already wrote to its local debug log (same honesty class as
/// Claude's statusline scrape).
public enum GrokRateLimitCapture {
	public static let beginMarker = "# BEGIN JPTHECAT-GROK-RATE-LIMIT-CAPTURE"
	public static let endMarker = "# END JPTHECAT-GROK-RATE-LIMIT-CAPTURE"
	public static let hookFileName = "jpthecat-rate-limit-capture.json"
	public static let scriptFileName = "grok-rate-limit-capture.sh"
	/// Log line Grok emits after a successful billing fetch (verified against Grok Build 0.2.99).
	public static let billingLogMessage = "billing: fetched credits config"

	public enum State: Equatable {
		case active  // the marked hook + script are installed
		case installable  // Grok Build is present and we can write hooks
		case unavailable  // Grok Build not detected
	}

	// MARK: - Paths

	public static func grokHome(
		home: URL? = nil
	) -> URL {
		if let home { return home }
		if let env = ProcessInfo.processInfo.environment["GROK_HOME"], !env.isEmpty {
			return URL(fileURLWithPath: env, isDirectory: true)
		}
		return FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".grok", isDirectory: true)
	}

	public static func hooksDirectory(grokHome: URL? = nil) -> URL {
		self.grokHome(home: grokHome).appendingPathComponent("hooks", isDirectory: true)
	}

	public static func hookURL(grokHome: URL? = nil) -> URL {
		hooksDirectory(grokHome: grokHome).appendingPathComponent(hookFileName)
	}

	public static func defaultLogURL(grokHome: URL? = nil) -> URL {
		self.grokHome(home: grokHome)
			.appendingPathComponent("logs", isDirectory: true)
			.appendingPathComponent("unified.jsonl")
	}

	public static func appSupportDirectory() -> URL? {
		try? FileManager.default.url(
			for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
			.appendingPathComponent("JPtheCat", isDirectory: true)
	}

	public static func scriptURL() -> URL? {
		appSupportDirectory()?.appendingPathComponent(scriptFileName)
	}

	// MARK: - State / install

	/// Current install state. Detection requires Grok Build to be present; the toggle stays hidden
	/// until then (same rule as the Live-data Grok row).
	public static func state(
		grokHome: URL? = nil,
		detected: Bool? = nil
	) -> State {
		let isDetected = detected ?? GrokProvider.isGrokBuildDetected(home: grokHome)
		guard isDetected else { return .unavailable }
		if isInstalled(grokHome: grokHome) { return .active }
		return .installable
	}

	/// The Settings toggle's on/off state derives from EXACTLY ONE ground-truth signal — whether the
	/// marked hook + script are installed (`state == .active`) — never OR'd with the captured-file
	/// freshness. An orphaned leftover `grok-rate-limits.json` (e.g. deleted hook via a path outside
	/// this app) must NOT keep the switch on; that `signalA || signalB` bug was the Claude "fixed
	/// twice" regression. Kept here (pure, no I/O) so the invariant is unit-testable, not just inlined
	/// in the SwiftUI view. See AGENTS.md "A toggle's on/off state must derive from ONE ground-truth
	/// signal".
	public static func toggleIsOn(state: State) -> Bool { state == .active }

	public static func isInstalled(grokHome: URL? = nil) -> Bool {
		let hook = hookURL(grokHome: grokHome)
		guard
			let hookBody = try? String(contentsOf: hook, encoding: .utf8),
			hookBody.contains("jpthecat-rate-limit-capture") || hookBody.contains(scriptFileName)
		else { return false }
		guard let script = scriptURL(),
			let scriptBody = try? String(contentsOf: script, encoding: .utf8),
			isInstalled(inScript: scriptBody)
		else { return false }
		return true
	}

	public static func isInstalled(inScript script: String) -> Bool {
		script.contains(beginMarker)
	}

	/// Writes the capture script + Grok hook (idempotent). Also runs one immediate log scrape so a
	/// machine that already has a fresh billing log line gets a gauge without waiting for the next
	/// Grok session.
	public static func install(grokHome: URL? = nil) throws {
		guard state(grokHome: grokHome) != .unavailable else {
			throw CaptureError.grokNotDetected
		}
		guard let support = appSupportDirectory() else { throw CaptureError.noAppSupport }
		try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

		guard let script = scriptURL() else { throw CaptureError.noAppSupport }
		let scriptBody = captureScript()
		try scriptBody.write(to: script, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755], ofItemAtPath: script.path)

		let hooksDir = hooksDirectory(grokHome: grokHome)
		try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
		let hookBody = hookJSON(scriptPath: script.path)
		try hookBody.write(to: hookURL(grokHome: grokHome), atomically: true, encoding: .utf8)

		// Best-effort immediate scrape — failure here is not an install failure (no log yet is fine).
		_ = refreshFromLogs(grokHome: grokHome)
	}

	/// Removes the marked hook + capture script and leaves Grok otherwise untouched.
	public static func uninstall(grokHome: URL? = nil) throws {
		let fm = FileManager.default
		let hook = hookURL(grokHome: grokHome)
		if fm.fileExists(atPath: hook.path) {
			try? fm.removeItem(at: hook)
		}
		if let script = scriptURL(), fm.fileExists(atPath: script.path) {
			try? fm.removeItem(at: script)
		}
	}

	public enum CaptureError: Error, Equatable {
		case grokNotDetected
		case noAppSupport
	}

	// MARK: - Log scrape (pure + side-effecting)

	/// Scrape `unified.jsonl` for the latest billing config and write `grok-rate-limits.json`.
	/// Returns true when a fresh capture was written. Safe to call from dashboard refresh while the
	/// opt-in is installed — never invents a percentage when the log has no billing line.
	@discardableResult
	public static func refreshFromLogs(
		grokHome: URL? = nil,
		logURL: URL? = nil,
		outputURL: URL? = nil,
		now: Date = Date()
	) -> Bool {
		let log = logURL ?? defaultLogURL(grokHome: grokHome)
		guard let out = outputURL ?? GrokRateLimitStore.defaultURL() else { return false }
		// Skip the whole tail read + parse + write when the log's cheap stat() hasn't moved since we last
		// processed it — the last-good capture is already on disk. (The hook's own python still does its
		// authoritative full-scan capture when Grok runs; this in-process re-scrape is only supplementary.)
		let attrs = try? FileManager.default.attributesOfItem(atPath: log.path)
		let size = (attrs?[.size] as? NSNumber)?.intValue
		let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970
		if let size, let mtime, grokBillingScrapeCache.isProcessed(path: log.path, size: size, mtime: mtime) {
			return false
		}
		defer {
			if let size, let mtime {
				grokBillingScrapeCache.markProcessed(path: log.path, size: size, mtime: mtime)
			}
		}
		guard let payload = scrapeLatestBilling(fromLog: log, now: now) else { return false }
		return writeCapture(payload, to: out)
	}

	/// Pure: scan a unified.jsonl file (newest line wins) and return the capture payload, or nil.
	/// Reads only the last `maxBytes` (billing lines are appended, so the newest is at the end) rather
	/// than the whole file, mirroring `CodexProvider.latestRateLimitsFromTail` — the log can grow into
	/// the MBs during a long session and this runs on every refresh while the opt-in is installed.
	public static func scrapeLatestBilling(
		fromLog logURL: URL, now: Date = Date(), maxBytes: UInt64 = 1_048_576
	) -> [String: Any]? {
		JSONLStreamReader.firstMatchingTail(fileURL: logURL, maxBytes: maxBytes) { line in
			parseBillingLogLine(String(decoding: line, as: UTF8.self), now: now)
		}
	}

	/// Pure: decode one `unified.jsonl` line that may carry `billing: fetched credits config`.
	/// Returns the on-disk capture dictionary, or nil when the line is not a usable billing reading.
	public static func parseBillingLogLine(_ line: String, now: Date = Date()) -> [String: Any]? {
		guard line.contains(billingLogMessage),
			let data = line.data(using: .utf8),
			let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return nil }

		// Prefer the structured ctx.config Grok logs; ignore unrelated billing noise.
		let msg = root["msg"] as? String
		guard msg == billingLogMessage else { return nil }

		let ctx = root["ctx"] as? [String: Any]
		let config = ctx?["config"] as? [String: Any]
		guard let config else { return nil }

		// creditUsagePercent is sometimes omitted while usage is still effectively 0.
		let used: Double
		if let n = config["creditUsagePercent"] as? NSNumber {
			used = n.doubleValue
		} else if let d = config["creditUsagePercent"] as? Double {
			used = d
		} else if let s = config["creditUsagePercent"] as? String, let d = Double(s) {
			// Accept a numeric string too, matching the hook python's `float(used)` — otherwise the two
			// "keep in sync" scrapers would classify a string-typed percentage differently.
			used = d
		} else {
			// No percentage on this line — not a usable official reading (do not invent 0).
			return nil
		}

		let period = config["currentPeriod"] as? [String: Any]
		let endISO = period?["end"] as? String
		let resetsAt = endISO.flatMap(parseISO8601)

		// Capture timestamp: prefer the log line's `ts`, else now.
		let capturedAt: Date
		if let ts = root["ts"] as? String, let parsed = parseISO8601(ts) {
			capturedAt = parsed
		} else {
			capturedAt = now
		}

		let plan =
			(ctx?["subscriptionTier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
			?? (config["subscriptionTier"] as? String).flatMap { $0.isEmpty ? nil : $0 }

		var weekly: [String: Any] = [
			"used_percentage": min(100, max(0, used))
		]
		if let resetsAt {
			weekly["resets_at"] = resetsAt.timeIntervalSince1970
		}

		var out: [String: Any] = [
			"capturedAt": capturedAt.timeIntervalSince1970,
			"weekly": weekly,
			"source": "unified.jsonl",
		]
		if let plan { out["plan_type"] = plan }
		if let periodType = period?["type"] as? String {
			out["period_type"] = periodType
		}
		return out
	}

	// MARK: - Install payloads (unit-testable strings)

	public static func captureScript() -> String {
		// The shell script re-invokes the same scrape via a tiny embedded python so hooks work even
		// when JP the Cat is not running. Logic mirrors `parseBillingLogLine` (keep in sync).
		"""
		\(beginMarker) (added by JPtheCat — safe to delete this file + ~/.grok/hooks/\(hookFileName) to remove)
		# Scrapes Grok Build's local billing log line into grok-rate-limits.json for JP the Cat.
		# No network, no auth.json, no prompts — only numbers Grok already wrote to unified.jsonl.
		set -euo pipefail
		LOG="${GROK_HOME:-$HOME/.grok}/logs/unified.jsonl"
		OUTDIR="$HOME/Library/Application Support/JPtheCat"
		OUT="$OUTDIR/grok-rate-limits.json"
		mkdir -p "$OUTDIR" 2>/dev/null || exit 0
		[ -f "$LOG" ] || exit 0
		/usr/bin/python3 - "$LOG" "$OUT" <<'PY'
		import json, sys, os, tempfile
		from datetime import datetime, timezone

		log_path, out_path = sys.argv[1], sys.argv[2]
		msg_want = "billing: fetched credits config"

		def parse_iso(s):
		    if not s:
		        return None
		    s = s.replace("Z", "+00:00")
		    try:
		        return datetime.fromisoformat(s)
		    except Exception:
		        return None

		payload = None
		try:
		    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
		        lines = f.readlines()
		except OSError:
		    sys.exit(0)

		for line in reversed(lines):
		    line = line.strip()
		    if msg_want not in line:
		        continue
		    try:
		        root = json.loads(line)
		    except Exception:
		        continue
		    if root.get("msg") != msg_want:
		        continue
		    ctx = root.get("ctx") or {}
		    config = ctx.get("config") or {}
		    used = config.get("creditUsagePercent")
		    if used is None:
		        continue
		    try:
		        used = float(used)
		    except (TypeError, ValueError):
		        continue
		    period = config.get("currentPeriod") or {}
		    end = parse_iso(period.get("end"))
		    ts = parse_iso(root.get("ts")) or datetime.now(timezone.utc)
		    weekly = {"used_percentage": max(0.0, min(100.0, used))}
		    if end is not None:
		        weekly["resets_at"] = end.timestamp()
		    plan = ctx.get("subscriptionTier") or config.get("subscriptionTier")
		    out = {
		        "capturedAt": ts.timestamp(),
		        "weekly": weekly,
		        "source": "unified.jsonl",
		    }
		    if plan:
		        out["plan_type"] = plan
		    if period.get("type"):
		        out["period_type"] = period["type"]
		    payload = out
		    break

		if not payload:
		    sys.exit(0)

		dir_name = os.path.dirname(out_path)
		fd, tmp = tempfile.mkstemp(prefix="grok-rate-", dir=dir_name)
		try:
		    with os.fdopen(fd, "w", encoding="utf-8") as w:
		        json.dump(payload, w, separators=(",", ":"))
		    os.replace(tmp, out_path)
		except Exception:
		    try:
		        os.unlink(tmp)
		    except OSError:
		        pass
		    sys.exit(0)
		PY
		\(endMarker)
		"""
	}

	public static func hookJSON(scriptPath: String) -> String {
		// SessionStart + UserPromptSubmit + Stop: keep the reading fresh while the user works.
		// Fail-open (Grok hooks never block the session if this fails).
		// Use bash + single-quoted path so spaces are safe; escape only for the JSON string value.
		let command = "bash " + shellQuote(scriptPath)
		let jsonCommand = jsonStringEscape(command)
		return """
			{
			  "hooks": {
			    "SessionStart": [
			      {
			        "hooks": [
			          { "type": "command", "command": "\(jsonCommand)", "timeout": 15 }
			        ]
			      }
			    ],
			    "UserPromptSubmit": [
			      {
			        "hooks": [
			          { "type": "command", "command": "\(jsonCommand)", "timeout": 15 }
			        ]
			      }
			    ],
			    "Stop": [
			      {
			        "hooks": [
			          { "type": "command", "command": "\(jsonCommand)", "timeout": 15 }
			        ]
			      }
			    ]
			  }
			}
			"""
	}

	/// Single-quote a path for `bash '…'`.
	private static func shellQuote(_ path: String) -> String {
		"'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}

	/// Escape a string for embedding inside a JSON double-quoted value.
	private static func jsonStringEscape(_ value: String) -> String {
		value
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
			.replacingOccurrences(of: "\n", with: "\\n")
			.replacingOccurrences(of: "\r", with: "\\r")
			.replacingOccurrences(of: "\t", with: "\\t")
	}

	// MARK: - Private

	private static func writeCapture(_ payload: [String: Any], to url: URL) -> Bool {
		guard JSONSerialization.isValidJSONObject(payload),
			let data = try? JSONSerialization.data(withJSONObject: payload, options: [])
		else { return false }
		let dir = url.deletingLastPathComponent()
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		// One atomic step (temp-write + rename), matching the hook python's `os.replace` and Claude's
		// `mv -f`. The old remove-then-move dance was non-atomic: a concurrent reader (the hook script,
		// or a dashboard read on another thread) could see no file in the gap, and if the hook recreated
		// the file first the `moveItem` threw NSFileWriteFileExistsError and silently lost this write.
		do {
			try data.write(to: url, options: .atomic)
			return true
		} catch {
			return false
		}
	}

	private static func parseISO8601(_ raw: String) -> Date? {
		ISOTimestamp.fractional.date(from: raw) ?? ISOTimestamp.plain.date(from: raw)
	}
}
