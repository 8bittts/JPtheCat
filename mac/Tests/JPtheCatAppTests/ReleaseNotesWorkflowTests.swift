import XCTest

final class ReleaseNotesWorkflowTests: XCTestCase {
	/// Runs the REAL embedded awk categorizer from `generate-appcast.sh` over sample commit subjects.
	/// A source-grep test would only prove a line exists; this proves the filter actually behaves.
	private func categorize(_ subjects: [String]) throws -> [String] {
		let script = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/scripts/generate-appcast.sh"),
			encoding: .utf8)
		guard let start = script.range(of: "function trim(value)"),
			let end = script.range(of: "> \"$NOTES_ROWS\"", range: start.upperBound..<script.endIndex),
			let closingQuote = script[start.lowerBound..<end.lowerBound].lastIndex(of: "'")
		else { throw XCTSkip("could not locate the embedded awk program") }
		let program = String(script[start.lowerBound..<closingQuote])

		let dir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-notes-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		let awkFile = dir.appendingPathComponent("notes.awk")
		try program.write(to: awkFile, atomically: true, encoding: .utf8)
		let inputFile = dir.appendingPathComponent("subjects.txt")
		try (subjects.joined(separator: "\n") + "\n").write(to: inputFile, atomically: true, encoding: .utf8)

		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/awk")
		process.arguments = ["-f", awkFile.path, inputFile.path]
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = FileHandle.nullDevice
		try process.run()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return String(decoding: data, as: UTF8.self)
			.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
	}

	/// [Contract] A perf-only release yields empty notes and aborts; `[notes]` is the per-commit opt-in.
	/// Rationale: generate-appcast.sh `category()`.
	func testNotesTagPromotesAnOtherwiseInternalPerfCommit() throws {
		let rows = try categorize([
			"perf: stop the refresh storm and the Copilot triple-parse",
			"perf: cut sustained CPU by 90% during active sessions [notes]",
		])
		XCTAssertEqual(rows.count, 1, "only the tagged perf commit may reach users — got: \(rows)")
		let row = try XCTUnwrap(rows.first)
		XCTAssertTrue(row.hasPrefix("app\t"), "a tagged perf commit is customer-facing — got: \(row)")
		XCTAssertTrue(
			row.contains("Cut sustained CPU by 90% during active sessions"),
			"the bullet must read as plain English — got: \(row)")
		XCTAssertFalse(row.contains("[notes]"), "the opt-in tag must never reach users — got: \(row)")
		XCTAssertFalse(row.contains("perf:"), "the type prefix must be stripped — got: \(row)")
	}

	/// [Regression, v1.096] A comment-and-doc grooming pass written as a declarative sentence with no
	/// conventional prefix — "Every document and code comment states its constraint once, and nothing
	/// else" — matched no doc rule and shipped as a customer-facing bullet in the v1.096 Sparkle notes.
	/// `docs?` is word-bounded so it never matched "document", and the sibling rule tests only the
	/// literal "documentation". Code comments and documents are never a user-visible surface.
	func testPlainEnglishCommentAndDocGroomingNeverReachesUsers() throws {
		let rows = try categorize([
			"Every document and code comment states its constraint once, and nothing else",
			"Tidy up the code comments across the provider layer",
			"Rewrite documents so each states its constraint once",
		])
		XCTAssertTrue(
			rows.filter { $0.hasPrefix("app\t") }.isEmpty,
			"comment/doc grooming must never render as a customer note — got: \(rows)")
	}

	/// The one that actually shipped, pinned verbatim so the exact leaked subject can never regress.
	func testTheExactSubjectThatLeakedIntoV1096IsInternal() throws {
		let rows = try categorize([
			"Every document and code comment states its constraint once, and nothing else"
		])
		XCTAssertFalse(
			rows.contains { $0.hasPrefix("app\t") },
			"the v1.096 leak must stay internal — got: \(rows)")
	}

	/// The fix must not swing the other way: a genuine user-facing feature still reaches users.
	func testDocRuleDoesNotSwallowRealFeatureNotes() throws {
		let rows = try categorize([
			"feat: per-model weekly limit gauges for Claude",
			"fix: menu bar no longer freezes at the last reading",
		])
		XCTAssertEqual(
			rows.filter { $0.hasPrefix("app\t") }.count, 2,
			"real features must still render as customer notes — got: \(rows)")
	}

	/// The tag may promote an INTERNAL commit, never a docs/release-machinery one. Documentation and
	/// release plumbing are customer-invisible by category, and that boundary sits ABOVE the opt-in.
	func testNotesTagCannotPromoteADocsOrReleaseCommit() throws {
		let rows = try categorize([
			"docs: update the engineering log [notes]",
			"release: bump the appcast [notes]",
			"chore: bump a dependency [notes]",
		])
		XCTAssertEqual(
			rows.filter { $0.hasPrefix("app\t") }.count, 1,
			"only the chore may be promoted; docs and release machinery stay internal — got: \(rows)")
		XCTAssertFalse(
			rows.contains { $0.contains("engineering log") },
			"a docs commit must never reach users even when tagged — got: \(rows)")
	}

	/// Untagged ordinary work is unaffected — the default stays exactly as conservative as before.
	func testOrdinaryFeatAndFixCommitsStillReachUsersUntagged() throws {
		let rows = try categorize([
			"feat: add an opt-in Cursor CLI row",
			"fix: price Grok 4.5 cached input correctly",
			"refactor: extract a helper",
		])
		XCTAssertEqual(rows.filter { $0.hasPrefix("app\t") }.count, 2, "got: \(rows)")
		XCTAssertFalse(rows.contains { $0.contains("extract a helper") })
	}

	/// The `[notes]` hatch is evaluated BEFORE the CamelCase-symbol filter, and that is the only reason
	/// a provider name spelled like a code symbol can carry its own bullet. Pins the claim root
	/// `AGENTS.md` makes about the hatch, so a future reorder fails here instead of silently dropping
	/// a real provider from a release.
	func testNotesTagCarriesACamelCaseProviderNameThatIsOtherwiseDropped() throws {
		let rows = try categorize([
			"[notes] Add MiMo and OpenCode support",
			"Add MiMo and OpenCode support",
		])
		XCTAssertEqual(
			rows.filter { $0.hasPrefix("app\t") }.count, 1,
			"the tagged subject must reach users and the untagged CamelCase one must not — got: \(rows)")
		let row = try XCTUnwrap(rows.first { $0.hasPrefix("app\t") })
		XCTAssertTrue(
			row.contains("Add MiMo and OpenCode support"),
			"the tagged subject survives verbatim, minus the tag — got: \(row)")
	}

	/// The CamelCase filter matches `Upper lower Upper lower`, so a name with a SINGLE leading capital
	/// ("Nemotron", "Grok") is never treated as a code symbol and needs no `[notes]` hatch. Recorded so
	/// the wording in `AGENTS.md` lists only names that are actually CamelCase-shaped.
	func testSingleCapitalVendorNamesNeedNoNotesHatch() throws {
		let rows = try categorize([
			"Add Nemotron support",
			"Add Grok Build support",
		])
		XCTAssertEqual(
			rows.filter { $0.hasPrefix("app\t") }.count, 2,
			"single-capital vendor names are not code symbols — got: \(rows)")
	}

	func testAppcastNotesAreComprehensiveAndPersonaLed() throws {
		let source = try String(
			contentsOf: repoRoot()
				.appendingPathComponent("mac/scripts/generate-appcast.sh"),
			encoding: .utf8)

		// The heading no longer repeats the version (Sparkle already shows it in its own chrome at
		// the top of the update dialog); the persona line is promoted to the main heading instead.
		XCTAssertTrue(source.contains("<h2>Small paws, strict standards. Here are the improvements:</h2>"))
		XCTAssertFalse(source.contains("JP inspected"))
		// App notes still render as plain user-facing bullets; the old "<h3> App changes JP approves"
		// section heading was intentionally dropped, so guard the render call itself, not the heading.
		XCTAssertTrue(source.contains("render_notes_section \"app\""))
		XCTAssertTrue(source.contains("release notes are empty"))
		XCTAssertTrue(source.contains("Built with ❤️ from San Francisco and Honolulu."))
		XCTAssertFalse(source.contains("If this ever looks empty"))
		XCTAssertFalse(source.contains("Improvements and fixes."))
		XCTAssertFalse(source.contains("count >= 6"))

		// Release notes are customer-facing ONLY: doc/operator, release-machinery, and internal-grooming
		// commits must never render into the appcast the user reads.
		XCTAssertFalse(source.contains("Docs and operator notes JP insists you read"))
		XCTAssertFalse(source.contains("Release machinery JP swatted into shape"))
		XCTAssertFalse(source.contains("Quiet internal grooming"))
		XCTAssertTrue(source.contains("customer-facing"))

		// Internal/mechanical work written as a plain subject (no conventional prefix) must not leak
		// code into user notes: a code selector like foo(bar:) or mechanical keywords are classified
		// internal and dropped. Guards the "move to Core … limit(for:providerLimits:) with tests" leak.
		XCTAssertTrue(source.contains(#"[a-z_][a-z0-9_.]*\([a-z0-9_: ]*\)/"#))
		XCTAssertTrue(source.contains("move to core|with tests?"))

		// Paren heuristics judge the BODY, not the type(scope) prefix.
		// Full version at generate-appcast.sh:194-198.
		XCTAssertTrue(source.contains("rest = lower"))
		XCTAssertTrue(source.contains(#"if (rest ~ /[a-z_][a-z0-9_.]*\([a-z0-9_: ]*\)/) return "internal""#))
		XCTAssertTrue(source.contains(#"if (rest ~ /[a-z][a-z0-9_.-]* +\([a-z0-9_: -]+\)/) return "internal""#))
		// perf/style join refactor/chore as always-internal build types, since the paren check that
		// used to catch a `perf(core):` prefix now only sees the (mechanical) body.
		XCTAssertTrue(source.contains("^(refactor|chore|perf|style)(\\([^)]*\\))?:"))

		// Corrective re-release escape hatch: the notes base tag can be widened one version back when a
		// prior release shipped defective notes, so the next version re-surfaces the fixed bullet.
		XCTAssertTrue(source.contains("JPTHECAT_NOTES_SINCE_TAG"))
		XCTAssertTrue(source.contains("NOTES_BASE_TAG"))
		// Latest-release notes only: the base tag is PREVIOUS_TAG, so Sparkle notes cover just
		// PREVIOUS_TAG..HEAD (this release), never a same-day roll-up. No same-day consolidation walk.
		XCTAssertTrue(source.contains("NOTES_BASE_TAG=\"$PREVIOUS_TAG\""))
		XCTAssertFalse(source.contains("same_day_notes_base_tag"))
		// Corrective re-sign of the CURRENT published version: override HTML + re-run generate-appcast
		// against the existing notarized DMG (never hand-edit the signed appcast).
		XCTAssertTrue(source.contains("JPTHECAT_NOTES_HTML"))
		XCTAssertTrue(source.contains("Using override release notes from"))

		// Dev-tooling / agent-harness commits (skills, slash commands) are not app features and must
		// never render as a customer note.
		XCTAssertTrue(source.contains("agent skills?|slash command"))

		// Internal roadmap "Phase N:" prefixes are stripped, and de-prefixed bullets are recapitalized,
		// so a note reads as user language ("Add Free Mode …", not "Phase 3: add Free Mode …").
		XCTAssertTrue(source.contains("[Pp]hase[[:space:]]*[0-9]+"))
		XCTAssertTrue(source.contains("toupper(substr(subject, 1, 1))"))

		// Doc-editing language is always internal regardless of phrasing (generate-appcast.sh:170-175).
		XCTAssertTrue(source.contains(#"\.md([^a-z]|$)"#))
		XCTAssertTrue(source.contains("claude\\.md|agents\\.md|readme|changelog|engineering"))
		XCTAssertTrue(source.contains("narrative|narratives|restructure|stale"))

		// Developer-facing vocabulary never renders as a customer note (generate-appcast.sh:216-228).
		XCTAssertTrue(source.contains("parser|cli wiring|audit.only|otel|review findings?"))
		XCTAssertTrue(source.contains("shared[[:space:]]+(design[[:space:]]+)?token"))
		XCTAssertTrue(source.contains("[A-Z][a-z]+[A-Z][a-z]+"))
		XCTAssertTrue(source.contains("hack|chrome"))

		// CamelCase check exempts the brand name (generate-appcast.sh:240-243).
		XCTAssertTrue(source.contains("gsub(/JPtheCat/, \"\", camel_subject)"))

		// Path gate on TOP of category(); both must be present (generate-appcast.sh:150-157).
		XCTAssertTrue(source.contains("APP_NOTE_PATHS="))
		XCTAssertTrue(source.contains(#"log --no-merges --format='%s' "$LOG_RANGE" -- $APP_NOTE_PATHS"#))
		// The scoped set mirrors release-jpthecat.sh's BUILD_DIRTY inputs — the things that actually
		// determine the notarized binary.
		XCTAssertTrue(source.contains("mac/Sources"))
		XCTAssertTrue(source.contains("mac/tools"))
	}

	func testReleaseManifestDescribesGitHistoryNotesContract() throws {
		let source = try String(
			contentsOf: repoRoot()
				.appendingPathComponent("mac/scripts/release-jpthecat.sh"),
			encoding: .utf8)

		XCTAssertTrue(source.contains("Sparkle release notes are generated from git history"))
		XCTAssertTrue(source.contains("strict-but-cute voice"))
	}

	/// Regression guard for the shared-tree-reset hardening: the release commit+tag+push MUST run from
	/// an isolated worktree (never the shared checkout) and the push MUST fetch+rebase+retry. A future
	/// edit that reverts to an inline `git commit`/`git push origin main` on the shared checkout would
	/// re-open the window where a concurrent hard-reset discards an in-flight release.
	func testReleaseIsolatesCommitInAWorktreeWithRebaseRetry() throws {
		let source = try String(
			contentsOf: repoRoot()
				.appendingPathComponent("mac/scripts/release-jpthecat.sh"),
			encoding: .utf8)

		// Commit lands in a dedicated worktree checked out at the current local HEAD after proving
		// that HEAD includes origin/main, so unpublished WIP commits are included but stale checkouts
		// fail closed.
		XCTAssertTrue(source.contains("worktree add"))
		XCTAssertTrue(source.contains("REL_WORKTREE"))
		XCTAssertTrue(source.contains("merge-base --is-ancestor origin/main HEAD"))
		XCTAssertTrue(source.contains("worktree add -q --detach \"$REL_WORKTREE\" HEAD"))
		XCTAssertFalse(source.contains("worktree add -q --detach \"$REL_WORKTREE\" origin/main"))
		XCTAssertTrue(source.contains("git -C \"$REL_WORKTREE\" commit"))
		XCTAssertTrue(source.contains("git -C \"$REL_WORKTREE\" push origin HEAD:main"))
		// Push retries by rebasing onto origin/main rather than aborting on a parallel commit.
		XCTAssertTrue(source.contains("rebase origin/main"))
		// The worktree is always torn down on exit.
		XCTAssertTrue(source.contains("worktree remove --force"))
	}

	func testPublishedStableAppcastUsesFriendlyFooter() throws {
		let generator = try String(
			contentsOf: repoRoot()
				.appendingPathComponent("mac/scripts/generate-appcast.sh"),
			encoding: .utf8)

		XCTAssertTrue(generator.contains("Built with ❤️ from San Francisco and Honolulu."))
		XCTAssertFalse(generator.contains("If this ever looks empty"))
	}

	private func repoRoot() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
	}
}
