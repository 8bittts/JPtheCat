import Foundation

/// Opt-in Cursor CLI usage capture.
///
/// Installs one fail-open `stop` command into Cursor's designed user hook file and one recorder script
/// under JP's Application Support directory. Unrelated hook entries are decoded and written back
/// unchanged semantically; uninstall removes only the exact JP command. The recorder never persists
/// raw hook input and uses only macOS-provided `/usr/bin/plutil` to extract the allowlisted fields.
public enum CursorHookSetup {
	public static let scriptFileName = "cursor-usage-capture.sh"
	public static let captureFileName = "cursor-usage.jsonl"
	public static let scriptMarker = "# JPTHECAT-CURSOR-USAGE-CAPTURE"
	/// Bumped whenever the emitted recorder changes in a way an ALREADY-INSTALLED script must pick up.
	/// `install()` is only ever called on an explicit opt-in, so without this an existing install would
	/// keep running the revision it was first written with forever — which is exactly the population
	/// the capture-file cap below has to reach. `repairOutdatedRecorderOncePerProcess(appSupport:)`
	/// rewrites JP's own script (and nothing else) when `state()` finds an active install carrying an
	/// older revision.
	public static let scriptRevisionMarker = "# JPTHECAT-CURSOR-CAPTURE-REV 2"

	/// Size at which the recorder trims its own capture file, and how many of the NEWEST records it
	/// keeps when it does.
	///
	/// [Why this exists] The capture file is JP's own append-only ledger (`>> $output`) and nothing in
	/// the app ever rotated, truncated, or deleted it — so it grew without bound for as long as the
	/// hook stayed installed, and `CursorProvider` re-parsed every line of it on every refresh. That
	/// unbounded growth is JP's defect, not Cursor's, so the cap belongs at the WRITE side where the
	/// growth happens. Trimming is line-granular (`tail -n`) so a trimmed file never starts mid-record,
	/// and events already indexed survive the trim — `CursorProvider`'s `ResetPolicy` is
	/// `.rereadWholeRetainingIndexedEvents` precisely so the warehouse keeps them.
	public static let captureMaxBytes = 2 * 1024 * 1024
	public static let captureKeepLines = 5_000

	public enum State: Equatable {
		case active
		case installable
		case unavailable
	}

	public enum SetupError: Error, Equatable {
		case cursorNotDetected
		case malformedHooks
		case noAppSupport
	}

	public static func cursorHome(
		home: URL = FileManager.default.homeDirectoryForCurrentUser
	) -> URL {
		home.appendingPathComponent(".cursor", isDirectory: true)
	}

	public static func hooksURL(cursorHome: URL? = nil) -> URL {
		(cursorHome ?? self.cursorHome()).appendingPathComponent("hooks.json", isDirectory: false)
	}

	public static func appSupportDirectory(
		home: URL = FileManager.default.homeDirectoryForCurrentUser
	) -> URL {
		home.appendingPathComponent("Library/Application Support/JPtheCat", isDirectory: true)
	}

	public static func scriptURL(appSupport: URL? = nil) -> URL {
		(appSupport ?? appSupportDirectory()).appendingPathComponent(scriptFileName)
	}

	public static func captureURL(appSupport: URL? = nil) -> URL {
		(appSupport ?? appSupportDirectory()).appendingPathComponent(captureFileName)
	}

	public static func isCursorCLIDetected(
		searchDirectories: [URL] = ProviderExecutableDetection.defaultSearchDirectories()
	) -> Bool {
		ProviderExecutableDetection.containsExecutable(
			named: ["cursor-agent", "cursor"], searchDirectories: searchDirectories)
	}

	public static func hookCommand(appSupport: URL? = nil) -> String {
		"/bin/sh \(shellQuote(scriptURL(appSupport: appSupport).path))"
	}

	/// The installed state of the capture hook.
	///
	/// Read-only on every path but one: an ACTIVE install whose recorder predates
	/// `scriptRevisionMarker` is repaired in place by
	/// `repairOutdatedRecorderOncePerProcess(appSupport:)`. The steady state — an install already on
	/// the current revision — performs NO disk write at all, which matters because `DashboardViewModel`
	/// calls this twice on every refresh.
	/// Guard: `CursorProviderTests.testSteadyStateQueryPerformsNoDiskWrite`.
	public static func state(
		cursorHome: URL? = nil,
		appSupport: URL? = nil,
		detected: Bool? = nil
	) -> State {
		guard detected ?? isCursorCLIDetected() else { return .unavailable }
		let command = hookCommand(appSupport: appSupport)
		guard
			let root = try? readHooks(at: hooksURL(cursorHome: cursorHome), allowMissing: true),
			hasCommand(command, in: root),
			let script = try? String(contentsOf: scriptURL(appSupport: appSupport), encoding: .utf8),
			script.contains(scriptMarker)
		else { return .installable }
		if !script.contains(scriptRevisionMarker) {
			repairOutdatedRecorderOncePerProcess(appSupport: appSupport ?? appSupportDirectory())
		}
		// An outdated recorder is still an ACTIVE install, so the reported state never flickers to "off".
		return .active
	}

	/// Paths whose recorder this process has already attempted to repair.
	///
	/// [Why this is bounded] The repair is a one-time MIGRATION of an install written before a recorder
	/// change, not a recurring duty — `install()` runs on explicit consent only, so `state()` is the
	/// only path that ever reaches that population. But `state()` is called twice per dashboard refresh
	/// and again on every Settings appearance, so an unbounded repair would retry a disk write forever
	/// whenever the write cannot land (read-only volume, revoked permission, a script some other tool
	/// keeps rewriting). One attempt per (process, appSupport path) caps it. The attempt is recorded
	/// BEFORE the write, not after, precisely so a failing write cannot become that unbounded retry.
	private static let repairLock = NSLock()
	nonisolated(unsafe) private static var repairAttemptedPaths: Set<String> = []

	/// Rewrites JP's OWN recorder script — and nothing else — for an active install still running a
	/// pre-`scriptRevisionMarker` revision.
	///
	/// [HARD REQUIREMENT] This must never touch `hooks.json` or any other Cursor/harness config; the
	/// only file it may write is the marked script under JP's Application Support directory.
	/// Guard: `CursorProviderTests.testStateUpgradesAnActiveInstallRunningAnOlderRecorder`.
	private static func repairOutdatedRecorderOncePerProcess(appSupport: URL) {
		let key = appSupport.standardizedFileURL.path
		repairLock.lock()
		let firstAttempt = repairAttemptedPaths.insert(key).inserted
		repairLock.unlock()
		guard firstAttempt else { return }
		try? writeCaptureScript(appSupport: appSupport)
	}

	/// Writes (or overwrites) the recorder script at `0700`. Idempotent by construction.
	private static func writeCaptureScript(appSupport: URL) throws {
		try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
		let script = scriptURL(appSupport: appSupport)
		try captureScript(outputURL: captureURL(appSupport: appSupport))
			.write(to: script, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
	}

	public static func install(
		cursorHome: URL? = nil,
		appSupport: URL? = nil,
		detected: Bool? = nil
	) throws {
		guard detected ?? isCursorCLIDetected() else { throw SetupError.cursorNotDetected }
		let support = appSupport ?? appSupportDirectory()
		let url = hooksURL(cursorHome: cursorHome)
		var root = try readHooks(at: url, allowMissing: true)
		try writeCaptureScript(appSupport: support)

		let command = hookCommand(appSupport: support)
		if !hasCommand(command, in: root) {
			var hooks = root["hooks"] as? [String: Any] ?? [:]
			var stop = hooks["stop"] as? [Any] ?? []
			stop.append(["command": command, "timeout": 2, "failClosed": false])
			hooks["stop"] = stop
			root["hooks"] = hooks
			if root["version"] == nil { root["version"] = 1 }
			try writeHooks(root, to: url)
		}
	}

	public static func uninstall(
		cursorHome: URL? = nil,
		appSupport: URL? = nil
	) throws {
		let support = appSupport ?? appSupportDirectory()
		let url = hooksURL(cursorHome: cursorHome)
		if var root = try? readHooks(at: url, allowMissing: false) {
			var hooks = root["hooks"] as? [String: Any] ?? [:]
			let command = hookCommand(appSupport: support)
			if let existing = hooks["stop"] as? [Any] {
				let retained = existing.filter {
					guard let entry = $0 as? [String: Any] else { return true }
					return (entry["command"] as? String) != command
				}
				if retained.isEmpty {
					hooks.removeValue(forKey: "stop")
				} else {
					hooks["stop"] = retained
				}
			}
			root["hooks"] = hooks
			try writeHooks(root, to: url)
		}
		let script = scriptURL(appSupport: support)
		if FileManager.default.fileExists(atPath: script.path) {
			try FileManager.default.removeItem(at: script)
		}
		// Remove JP's own capture file too — leaving it behind was the only thing on disk that kept
		// growing after the feature was turned off, and nothing else ever deleted it. Usage already
		// ingested into the index is untouched: `UsageIndexer`'s stale sweep forgets the FILE and keeps
		// its events, so uninstalling stops capture without erasing history.
		let capture = captureURL(appSupport: support)
		if FileManager.default.fileExists(atPath: capture.path) {
			try FileManager.default.removeItem(at: capture)
		}
	}

	static func captureScript(outputURL: URL) -> String {
		let output = shellQuote(outputURL.path)
		return """
		#!/bin/sh
		\(scriptMarker)
		\(scriptRevisionMarker)
		# Fail open: usage capture must never affect Cursor's agent loop.
		payload=$(/bin/cat) || exit 0
		raw_field() {
		  printf '%s' "$payload" | /usr/bin/plutil -extract "$1" raw -n -o - - 2>/dev/null
		}
		encoded_field() {
		  raw_field "$1" | /usr/bin/base64 | /usr/bin/tr -d '\\n'
		}
		generation_id=$(encoded_field generation_id)
		[ -n "$generation_id" ] || exit 0
		conversation_id=$(encoded_field conversation_id)
		model=$(encoded_field model)
		input_tokens=$(raw_field input_tokens); input_tokens=${input_tokens:-0}
		output_tokens=$(raw_field output_tokens); output_tokens=${output_tokens:-0}
		cache_read_tokens=$(raw_field cache_read_tokens); cache_read_tokens=${cache_read_tokens:-0}
		cache_write_tokens=$(raw_field cache_write_tokens); cache_write_tokens=${cache_write_tokens:-0}
		for count in "$input_tokens" "$output_tokens" "$cache_read_tokens" "$cache_write_tokens"; do
		  case "$count" in ''|*[!0-9]*) exit 0 ;; esac
		done
		[ $((input_tokens + output_tokens + cache_read_tokens + cache_write_tokens)) -gt 0 ] || exit 0
		captured_at=$(/bin/date +%s) || exit 0
		/bin/mkdir -p \(shellQuote(outputURL.deletingLastPathComponent().path)) 2>/dev/null || exit 0
		/bin/chmod 700 \(shellQuote(outputURL.deletingLastPathComponent().path)) 2>/dev/null || true
		/usr/bin/printf '{"captured_at":%s,"conversation_id_b64":"%s","generation_id_b64":"%s","model_b64":"%s","input_tokens":%s,"output_tokens":%s,"cache_read_tokens":%s,"cache_write_tokens":%s}\\n' \
		  "$captured_at" "$conversation_id" "$generation_id" "$model" "$input_tokens" "$output_tokens" "$cache_read_tokens" "$cache_write_tokens" \
		  >> \(output) 2>/dev/null || true
		# Cap JP's own capture file. Nothing else ever trims it, so without this it grows for as long as
		# the hook stays installed. Line-granular (`tail -n`) so the trimmed file never starts mid-record,
		# and idempotent: below the cap this is one `wc -c` and nothing else. Only ever touches JP's own
		# marked output file — never Cursor's config, never any other path.
		size=$(/usr/bin/wc -c < \(output) 2>/dev/null | /usr/bin/tr -d '[:space:]')
		case "$size" in ''|*[!0-9]*) exit 0 ;; esac
		[ "$size" -gt \(captureMaxBytes) ] || exit 0
		trimmed=\(output).trim.$$
		if /usr/bin/tail -n \(captureKeepLines) \(output) > "$trimmed" 2>/dev/null; then
		  /bin/mv -f "$trimmed" \(output) 2>/dev/null || /bin/rm -f "$trimmed" 2>/dev/null
		else
		  /bin/rm -f "$trimmed" 2>/dev/null
		fi
		exit 0
		"""
	}

	private static func readHooks(at url: URL, allowMissing: Bool) throws -> [String: Any] {
		guard FileManager.default.fileExists(atPath: url.path) else {
			if allowMissing { return ["version": 1, "hooks": [String: Any]()] }
			throw SetupError.malformedHooks
		}
		guard
			let data = try? Data(contentsOf: url),
			let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			root["hooks"] == nil || root["hooks"] is [String: Any]
		else { throw SetupError.malformedHooks }
		return root
	}

	private static func writeHooks(_ root: [String: Any], to url: URL) throws {
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
		try data.write(to: url, options: [.atomic])
	}

	private static func hasCommand(_ command: String, in root: [String: Any]) -> Bool {
		guard let hooks = root["hooks"] as? [String: Any],
			let stop = hooks["stop"] as? [Any]
		else { return false }
		return stop.contains {
			guard let entry = $0 as? [String: Any] else { return false }
			return (entry["command"] as? String) == command
		}
	}

	private static func shellQuote(_ value: String) -> String {
		"'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
	}
}
