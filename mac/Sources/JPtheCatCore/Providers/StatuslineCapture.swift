import Foundation

/// Installs (opt-in) the Claude rate-limit capture into the user's Claude Code statusline. Claude
/// only exposes its official 5h/weekly limits through the statusline stdin feed, so the ONLY way to
/// surface them is to hook that script. This never runs on install or silently — the app calls
/// `install()` only after an explicit, acknowledged tap in Settings, and `uninstall()` fully reverts
/// by deleting the clearly-marked block. It appends to the user's existing statusline **script**
/// (never rewrites `settings.json`), and only when it can find where that script buffers stdin.
public enum StatuslineCapture {
	public static let beginMarker = "# BEGIN JPTHECAT-RATE-LIMIT-CAPTURE"
	public static let endMarker = "# END JPTHECAT-RATE-LIMIT-CAPTURE"

	public enum State: Equatable {
		case active  // the capture block is present in the resolved statusline script
		case installable(URL)  // a statusline script exists and we can safely append the block
		case unavailable  // no statusline script, or it doesn't buffer stdin we can hook
	}

	static var settingsURL: URL {
		FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
	}

	/// Current install state, resolved from `~/.claude/settings.json` → statusline script.
	public static func state() -> State {
		guard
			let settings = try? Data(contentsOf: settingsURL),
			let scriptPath = statuslineScriptPath(fromSettingsJSON: settings),
			let script = try? String(contentsOfFile: scriptPath, encoding: .utf8)
		else { return .unavailable }
		if isInstalled(inScript: script) { return .active }
		guard stdinVarName(inScript: script) != nil else { return .unavailable }
		return .installable(URL(fileURLWithPath: scriptPath))
	}

	/// Appends the capture block to the statusline script (idempotent). Throws when there is no
	/// hookable script — callers should fall back to showing manual instructions.
	public static func install() throws {
		guard
			let settings = try? Data(contentsOf: settingsURL),
			let scriptPath = statuslineScriptPath(fromSettingsJSON: settings)
		else { throw CaptureError.noStatusline }
		var script = try String(contentsOfFile: scriptPath, encoding: .utf8)
		// An up-to-date block is a no-op; a stale one is REPLACED rather than skipped, so an existing
		// installer picks up capture improvements instead of forwarding the old field set forever.
		if isInstalled(inScript: script) {
			guard needsMigration(inScript: script) else { return }
			script = removingBlock(from: script)
		}
		guard let varName = stdinVarName(inScript: script) else { throw CaptureError.noStdinCapture }
		if !script.hasSuffix("\n") { script += "\n" }
		script += "\n" + captureBlock(varName: varName) + "\n"
		try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
	}

	/// Refreshes an ALREADY-INSTALLED block that predates the current `blockRevision`, in place. Does
	/// nothing when the capture was never installed — this only ever rewrites a block the user already
	/// opted into, inside the same markers, and never installs one on its own.
	public static func migrateIfNeeded() {
		guard
			let settings = try? Data(contentsOf: settingsURL),
			let scriptPath = statuslineScriptPath(fromSettingsJSON: settings),
			let script = try? String(contentsOfFile: scriptPath, encoding: .utf8),
			needsMigration(inScript: script)
		else { return }
		try? install()
	}

	/// Removes the marked block, fully reverting the install.
	public static func uninstall() throws {
		guard
			let settings = try? Data(contentsOf: settingsURL),
			let scriptPath = statuslineScriptPath(fromSettingsJSON: settings)
		else { return }
		let script = try String(contentsOfFile: scriptPath, encoding: .utf8)
		let stripped = removingBlock(from: script)
		guard stripped != script else { return }
		try stripped.write(toFile: scriptPath, atomically: true, encoding: .utf8)
	}

	public enum CaptureError: Error, Equatable { case noStatusline, noStdinCapture }

	// MARK: - Pure helpers (unit-tested)

	/// Extracts the statusline script path from `settings.json`. `statusLine.command` may be a bare
	/// path or a launcher like `bash ~/x.sh`; we take the last whitespace-token ending in `.sh` (or
	/// the last token) and expand `~`/`$HOME`.
	public static func statuslineScriptPath(fromSettingsJSON data: Data) -> String? {
		guard
			let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let statusLine = root["statusLine"] as? [String: Any],
			let command = statusLine["command"] as? String
		else { return nil }
		let tokens = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
		guard !tokens.isEmpty else { return nil }
		let token = tokens.last(where: { $0.hasSuffix(".sh") }) ?? tokens[tokens.count - 1]
		return expandHome(token)
	}

	/// Finds the variable a script buffers stdin into (`VAR=$(cat)`), so the appended block can reuse
	/// it instead of consuming stdin a second time (which would starve the original statusline).
	public static func stdinVarName(inScript script: String) -> String? {
		for line in script.split(separator: "\n") {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard let eq = trimmed.firstIndex(of: "=") else { continue }
			let name = String(trimmed[trimmed.startIndex..<eq])
			let rhs = String(trimmed[trimmed.index(after: eq)...])
			if rhs.hasPrefix("$(cat)"), !name.isEmpty,
				name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
				return name
			}
		}
		return nil
	}

	public static func isInstalled(inScript script: String) -> Bool { script.contains(beginMarker) }

	/// Bumped whenever `captureBlock` changes what it writes. An already-installed block is otherwise
	/// invisible to `install()` (marker-only detection), so a capture improvement would only ever reach
	/// NEW users while every existing installer kept forwarding the old field set forever.
	///
	/// Revision 3: the write gate accepts ANY official window. Claude Code documents `five_hour` as
	/// optional, and 2.1.318 sends a weekly-only payload; revision 2 wrote only when `five_hour` was
	/// present, so the file froze at its last 5-hour-era reading while the real weekly percentage moved
	/// on (8% shown against a live 75%).
	public static let blockRevision = 3

	private static let revisionMarker = "# jpthecat-capture-revision:"

	/// True when the script carries our block at an OLDER revision (or none), so `install()` should
	/// rewrite it in place. A NEWER revision is left alone: an older JP build must never downgrade a
	/// block a newer build wrote, or it would reinstate the bug the newer revision fixed.
	public static func needsMigration(inScript script: String) -> Bool {
		guard isInstalled(inScript: script) else { return false }
		guard let installed = installedRevision(inScript: script) else { return true }
		return installed < blockRevision
	}

	/// The `# jpthecat-capture-revision: N` stamp inside the block, or nil for a pre-revision block.
	static func installedRevision(inScript script: String) -> Int? {
		for line in script.split(separator: "\n") {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard trimmed.hasPrefix(revisionMarker) else { continue }
			return Int(trimmed.dropFirst(revisionMarker.count).trimmingCharacters(in: .whitespaces))
		}
		return nil
	}

	/// jq test: true when the payload carries at least one `five_hour` or `seven_day*` window with a
	/// numeric `used_percentage`. A null `rate_limits` (before the first response) or a gateway-only
	/// `spend_limit` writes nothing, so the last real reading is never overwritten by an empty one.
	static let gateProgram =
		#"[.rate_limits | objects | to_entries[] | select(.key == "five_hour" or (.key | startswith("seven_day"))) | .value.used_percentage | numbers] | length > 0"#

	/// jq writer: the capture time plus every present `five_hour` / `seven_day*` window, verbatim.
	static let writeProgram =
		#"{capturedAt:(now|floor)} + (.rate_limits | with_entries(select(.key == "five_hour" or (.key | startswith("seven_day")))))"#

	public static func captureBlock(varName: String) -> String {
		"""
		\(beginMarker) (added by JPtheCat — safe to delete this block to remove)
		\(revisionMarker) \(blockRevision)
		# Writes Claude's OFFICIAL rate_limits (5h + weekly, plus any per-model weekly windows) to a file
		# the JPtheCat app reads. Either window may be absent, so it writes whenever ANY window is present.
		# `with_entries` forwards every `seven_day*` window Claude reports, so a per-model bar (e.g. Fable)
		# appears automatically if and when Claude Code adds one to this feed.
		if echo "$\(varName)" | jq -e '\(gateProgram)' >/dev/null 2>&1; then
		  __jpc_dir="$HOME/Library/Application Support/JPtheCat"
		  mkdir -p "$__jpc_dir" 2>/dev/null
		  echo "$\(varName)" | jq -c '\(writeProgram)' \
		    > "$__jpc_dir/claude-rate-limits.json.tmp" 2>/dev/null \
		    && mv -f "$__jpc_dir/claude-rate-limits.json.tmp" "$__jpc_dir/claude-rate-limits.json" 2>/dev/null
		fi
		\(endMarker)
		"""
	}

	static func removingBlock(from script: String) -> String {
		MarkedScriptBlock.removing(from: script, beginMarker: beginMarker, endMarker: endMarker)
	}

	private static func expandHome(_ path: String) -> String {
		let home = FileManager.default.homeDirectoryForCurrentUser.path
		if path == "~" { return home }
		if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
		if path.hasPrefix("$HOME/") { return home + String(path.dropFirst("$HOME".count)) }
		return path
	}
}
