import Foundation

/// Installs (opt-in) the `COPILOT_OTEL_FILE_EXPORTER_PATH` export into the user's shell rc file, the
/// only way to make GitHub Copilot CLI write its local OpenTelemetry export to a file JP can read —
/// it is off by default. This never runs on install or silently — the app calls `install()` only
/// after an explicit, acknowledged tap in Settings, and `uninstall()` fully reverts by deleting the
/// clearly-marked block. Copilot CLI has no `settings.json`-style config JP can point at (unlike
/// Claude's statusline), so this targets the user's shell profile directly, matching
/// `StatuslineCapture`'s shape but a different target file.
///
/// [Durable lesson — `COPILOT_OTEL_ENABLED=true` alone is NOT enough] Verified against the CLI's own
/// bundled help text (`copilot help monitoring`, `@github/copilot-darwin-arm64/app.js`) and a real
/// session log (`~/.copilot/logs/process-*.log` printed `OpenTelemetry enabled: exporter=otlp-http`):
/// setting only `COPILOT_OTEL_ENABLED=true` enables OTel instrumentation but defaults the exporter
/// BACKEND to `otlp-http` (a network OTLP endpoint) — it writes NO local file at all, so
/// `CopilotProvider`'s `~/.copilot/otel/*.jsonl` glob silently finds nothing forever, with no error
/// anywhere to signal why. The CLI's docs are explicit: "Auto-selects 'file' when
/// COPILOT_OTEL_FILE_EXPORTER_PATH is set" — and setting that path ALSO auto-enables OTel, so it is
/// the one env var this needs, not two. This shipped as a real bug (a user's real Copilot sessions
/// enabled the env var, used the CLI, and still saw zero local data) before being caught by directly
/// reading the CLI's own session log rather than assuming `COPILOT_OTEL_ENABLED=true` was sufficient
/// from name alone. Do not revert to `COPILOT_OTEL_ENABLED=true`-only.
public enum CopilotOtelSetup {
	public static let beginMarker = "# BEGIN JPTHECAT-COPILOT-OTEL"
	public static let endMarker = "# END JPTHECAT-COPILOT-OTEL"

	public enum State: Equatable {
		case active  // the export line is present in the resolved shell rc file
		case installable(URL)  // a shell rc file exists and we can safely append the block
		case unavailable  // no detectable shell rc file (unrecognized $SHELL, or none found)
	}

	/// Resolves the shell rc file to target from `$SHELL`, preferring the file if it already exists
	/// and falling back to the conventional default for that shell otherwise (so a fresh user without
	/// a `.zshrc` yet still gets an `.installable` state, not `.unavailable`).
	static func shellRCURL(shellEnv: String? = ProcessInfo.processInfo.environment["SHELL"]) -> URL? {
		let home = FileManager.default.homeDirectoryForCurrentUser
		guard let shellEnv else { return nil }
		if shellEnv.hasSuffix("/zsh") {
			return home.appendingPathComponent(".zshrc")
		}
		if shellEnv.hasSuffix("/bash") {
			let bashProfile = home.appendingPathComponent(".bash_profile")
			if FileManager.default.fileExists(atPath: bashProfile.path) { return bashProfile }
			return home.appendingPathComponent(".bashrc")
		}
		return nil
	}

	/// Current install state, resolved from the detected shell rc file.
	public static func state() -> State {
		guard let url = shellRCURL() else { return .unavailable }
		guard let script = try? String(contentsOf: url, encoding: .utf8) else {
			return .installable(url)
		}
		return isInstalled(inScript: script) ? .active : .installable(url)
	}

	/// Whether an installed block is running the CURRENT (file-exporter) enablement line, vs. a stale
	/// block from before the `COPILOT_OTEL_ENABLED=true`-only bug fix. `install()` uses this to
	/// silently upgrade an existing user's block instead of leaving them permanently on the broken
	/// network-exporter default.
	static func isCurrent(inScript script: String) -> Bool {
		script.contains(otelFileExporterPath().path)
	}

	/// Whether GitHub Copilot CLI is actually installed on this machine right now — checked so the
	/// Settings row never appears for a user who doesn't have the tool.
	///
	/// [Correctness note] `~/.copilot` existing is NOT sufficient on its own: it's created on the
	/// very first launch attempt and survives even after the CLI itself is uninstalled, so checking
	/// it alone produces false positives for anyone who ever tried Copilot CLI once (verified on a
	/// real dev machine: a `~/.copilot/config.json` + `logs/` dated weeks ago, with no `copilot`
	/// binary anywhere and no npm package installed). The authoritative signal is the executable
	/// itself. A GUI-launched app does NOT inherit the user's shell `$PATH` (`launchctl getenv PATH`
	/// is typically empty/minimal — verified empirically), so this checks a fixed list of the
	/// directories CLI tools are actually installed into on macOS (Homebrew, `/usr/local/bin`, common
	/// npm global bin locations) rather than trusting `ProcessInfo.environment["PATH"]` alone.
	public static func isCopilotCLIDetected(
		searchDirectories: [URL] = defaultCopilotSearchDirectories()
	) -> Bool {
		ProviderExecutableDetection.containsExecutable(
			named: ["copilot"], searchDirectories: searchDirectories)
	}

	public static func defaultCopilotSearchDirectories() -> [URL] {
		ProviderExecutableDetection.defaultSearchDirectories()
	}

	/// Appends the enablement block to the shell rc file (idempotent). If a stale pre-fix block is
	/// already present (the `COPILOT_OTEL_ENABLED=true`-only form), it is replaced in place so
	/// existing installs silently pick up the working file-exporter form on the next Settings visit.
	/// Throws when no shell rc file could be resolved — callers should fall back to showing manual
	/// instructions. Also ensures the export directory exists, since Copilot CLI's file exporter does
	/// not create missing parent directories on its own.
	public static func install() throws {
		guard let url = shellRCURL() else { throw SetupError.noShellRC }
		var script = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
		if isInstalled(inScript: script) {
			guard !isCurrent(inScript: script) else { return }
			script = removingBlock(from: script)
		}
		if !script.isEmpty, !script.hasSuffix("\n") { script += "\n" }
		script += (script.isEmpty ? "" : "\n") + enablementBlock() + "\n"
		try script.write(to: url, atomically: true, encoding: .utf8)
		try FileManager.default.createDirectory(
			at: otelFileExporterPath().deletingLastPathComponent(),
			withIntermediateDirectories: true)
	}

	/// Removes the marked block, fully reverting the install.
	public static func uninstall() throws {
		guard let url = shellRCURL(), let script = try? String(contentsOf: url, encoding: .utf8)
		else { return }
		let stripped = removingBlock(from: script)
		guard stripped != script else { return }
		try stripped.write(to: url, atomically: true, encoding: .utf8)
	}

	public enum SetupError: Error, Equatable { case noShellRC }

	// MARK: - Pure helpers (unit-tested)

	public static func isInstalled(inScript script: String) -> Bool { script.contains(beginMarker) }

	/// The fixed file Copilot CLI's OTel file exporter writes to. A single stable path (not
	/// timestamped) so `CopilotProvider`'s incremental tailing/re-read logic has one file to track.
	public static func otelFileExporterPath(
		home: URL = FileManager.default.homeDirectoryForCurrentUser
	) -> URL {
		home.appendingPathComponent(".copilot/otel/otel.jsonl", isDirectory: false)
	}

	public static func enablementBlock() -> String {
		"""
		\(beginMarker) (added by JPtheCat — safe to delete this block to remove)
		# Enables GitHub Copilot CLI's local OpenTelemetry export so JPtheCat can audit token usage.
		# Only affects NEW shell sessions/Copilot CLI runs — never touches Copilot's own config.
		# Setting the file path (not just COPILOT_OTEL_ENABLED) is required: it both auto-enables OTel
		# AND selects the local file exporter backend instead of the default network otlp-http one.
		export COPILOT_OTEL_FILE_EXPORTER_PATH="\(otelFileExporterPath().path)"
		\(endMarker)
		"""
	}

	static func removingBlock(from script: String) -> String {
		guard
			let begin = script.range(of: beginMarker),
			let end = script.range(of: endMarker)
		else { return script }
		// Extend the cut to swallow the trailing newline after END and any blank line we added.
		var lower = begin.lowerBound
		var upper = end.upperBound
		if upper < script.endIndex, script[upper] == "\n" { upper = script.index(after: upper) }
		while lower > script.startIndex {
			let prev = script.index(before: lower)
			if script[prev] == "\n" { lower = prev } else { break }
		}
		var out = script
		out.removeSubrange(lower..<upper)
		return out
	}
}
