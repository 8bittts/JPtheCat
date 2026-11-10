import Foundation
import JPtheCatCore

// jpthecat-cli — prints today / last-7d cost as JSON. Default provider is Claude Code (the Phase 1
// verification target: this number must match a hand-checked `ccusage calculate` run). Pass
// `--codex` to read OpenAI Codex rollout usage instead. Pass `--indexed` to ingest through the
// persistent `usage.sqlite` index (incremental: unchanged files are skipped) and roll up via SELECT
// instead of a full-corpus walk on warm runs. Reuse --db to measure warm-start skips; first ingest
// still pays the provider parse cost.

let args = CommandLine.arguments

func arg(_ name: String) -> String? {
	guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
	return args[idx + 1]
}

if args.contains("--help") || args.contains("-h") {
	print(
		"""
		usage: jpthecat-cli snapshot --json [--provider all|claude|codex|grok|muse-spark|gemini|opencode|opencode-go|copilot|nemotron|mimo|big-pickle|deepseek] [--days 7|14|30|90] [--indexed] [--output <path>]
		       jpthecat-cli report --format markdown [--provider all|claude|codex|grok|muse-spark|gemini|opencode|opencode-go|copilot|nemotron|mimo|big-pickle|deepseek] [--days 7|14|30|90] [--indexed] [--output <path>]
		       jpthecat-cli [--claude | --codex | --grok | --muse-spark | --gemini | --opencode | --opencode-go | --copilot | --nemotron | --mimo | --big-pickle | --deepseek] [--indexed [--db <path>]] [--root <file>] [--json]
		  Reads AI coding usage and prints today/7d cost as JSON.
		  snapshot      print the stable local automation JSON contract
		  report        print a local Markdown report
		  --provider    provider for snapshot/report (default: all — every dashboard-summed provider plus the OpenCode gateways; gemini audit-only, copilot non-aggregable)
		  --days        selected window for snapshot/report (default: 14; supported: 7, 14, 30, 90)
		  --output      write output atomically to a path instead of stdout
		  --claude       read Claude Code (~/.claude/projects) — the default
		  --codex        read Codex (~/.codex/sessions) instead of Claude Code (~/.claude/projects)
		  --grok         read Grok Build (~/.grok/sessions) instead of Claude Code
		  --grok-bot     legacy alias for the unified Grok view
		  --muse-spark   read Muse Spark (OpenCode opencode.db Muse Spark and Muse Wonder rows) instead of Claude Code
		  --nemotron     read Nemotron 3 (OpenCode opencode.db nemotron sessions) instead of Claude Code
		  --mimo         read Xiaomi MiMo (OpenCode opencode.db mimo sessions) instead of Claude Code
		  --big-pickle   read Big Pickle (OpenCode opencode.db big-pickle sessions) instead of Claude Code
		  --deepseek     read DeepSeek (OpenCode opencode.db deepseek sessions) instead of Claude Code
		  --gemini       audit Gemini (~/.gemini/tmp) instead of Claude Code (~/.claude/projects)
		  --opencode     read OpenCode Zen (~/.local/share/opencode opencode.db rows routed through the Zen gateway) instead of Claude Code
		  --opencode-go  read OpenCode Go (~/.local/share/opencode opencode.db rows routed through the Go gateway) instead of Claude Code
		  --copilot      audit GitHub Copilot CLI (~/.copilot/otel, requires opt-in COPILOT_OTEL_FILE_EXPORTER_PATH=<path>) instead of Claude Code
		  --cursor       legacy alias for the unified Grok view
		  --indexed      ingest into usage.sqlite (incremental) and roll up via SELECT; prints index_stats
		  --db <path>    index path (default: a temp file); reuse the same path to see warm-start skips
		  --root <dir>   read from <dir> instead of the provider default (for testing on a snapshot)
		""")
	exit(0)
}

if args.dropFirst().first == "snapshot" || args.dropFirst().first == "report" {
	do {
		let output = try runAutomationCommand(args: args)
		if let outputPath = arg("--output") {
			try writeAtomically(output, to: URL(fileURLWithPath: outputPath))
		} else {
			print(output, terminator: output.hasSuffix("\n") ? "" : "\n")
		}
		exit(0)
	} catch {
		FileHandle.standardError.write(Data("jpthecat: \(error)\n".utf8))
		exit(1)
	}
}

var rootOverride: URL?
if let root = arg("--root") { rootOverride = URL(fileURLWithPath: root, isDirectory: true) }

/// One row per provider the CLI exposes.
///
/// [Why this exists] Adding a provider means ONE edit here, not several coordinated call sites that
/// can silently drift.
/// Guard: `CLIProviderTableTests`.
struct CLIProvider: Sendable {
	/// Legacy single-provider flag (`jpthecat-cli --codex`).
	let flag: String
	/// Tokens `snapshot`/`report` accept for `--provider`; the first is canonical.
	let selectionTokens: [String]
	/// Value of the legacy JSON `provider` field.
	let name: String
	let id: ProviderID
	/// Where the legacy path tells the user to look when the local source is missing.
	let sourceDescription: String
	/// True for the providers `--provider all` fans out to: every row the dashboard sums into its
	/// dollar total (`ProviderCatalog.aggregateIDs` = the live set plus the OpenCode model-brand rows
	/// JP accounts for locally) plus the two OpenCode gateways, which are listed but excluded from the
	/// total. Audit-only (Gemini) and token-estimate (Copilot, Cursor) providers stay out of `all`.
	/// Guard: `CLIProviderTableTests` pins this against Core, so the CLI total equals the app's.
	let includedInAll: Bool
	/// Every row is an `IndexableProvider`, which is what lets `--indexed` refresh through ONE generic
	/// call instead of a downcast switch whose `guard … else { return }` arms no-oped in silence.
	let make: @Sendable (URL?) -> any IndexableProvider
}

/// [CRITICAL] The table lives on a type, not in a top-level `let`. Top-level globals in `main.swift`
/// initialize in STATEMENT ORDER at runtime, and the `snapshot`/`report` dispatch above returns long
/// before this point in the file — a top-level `let cliProviders` read from `runAutomationCommand`
/// therefore reads uninitialized memory and segfaults. A `static let` is lazily initialized on first
/// use (`swift_once`), so both entry points get the same fully-built table.
enum CLIProviderTable {
	/// Claude Code is the default target: the row selected when no legacy flag is passed at all.
	static let claude = CLIProvider(
		flag: "--claude", selectionTokens: ["claude"], name: "claude",
		id: .claude, sourceDescription: "~/.claude/projects", includedInAll: true,
		make: { ClaudeProvider(root: $0) })

	static let all: [CLIProvider] = [
		claude,
		CLIProvider(
			flag: "--codex", selectionTokens: ["codex"], name: "codex",
			id: .codex, sourceDescription: "~/.codex/sessions", includedInAll: true,
			make: { CodexProvider(root: $0) }),
		CLIProvider(
			flag: "--grok", selectionTokens: ["grok", "cursor", "grok-bot", "grok_bot", "grokbot"], name: "grok",
			id: .grok, sourceDescription: "~/.grok/sessions", includedInAll: true,
			make: { GrokProvider(root: $0) }),

		CLIProvider(
			flag: "--muse-spark", selectionTokens: ["muse-spark", "muse_spark", "musespark"],
			name: "muse_spark", id: .museSpark,
			sourceDescription: "~/.local/share/opencode (Muse Spark and Muse Wonder turns in opencode.db)",
			includedInAll: true, make: { MuseSparkProvider(root: $0) }),
		CLIProvider(
			flag: "--gemini", selectionTokens: ["gemini"], name: "gemini",
			id: .gemini, sourceDescription: "~/.gemini/tmp", includedInAll: false,
			make: { GeminiProvider(root: $0) }),
		CLIProvider(
			flag: "--opencode", selectionTokens: ["opencode", "opencode-zen", "opencode_zen", "zen"],
			name: "opencode", id: .opencode,
			sourceDescription: "~/.local/share/opencode (Opencode Zen rows in opencode.db)",
			includedInAll: true, make: { OpenCodeProvider(root: $0) }),
		CLIProvider(
			flag: "--opencode-go", selectionTokens: ["opencode-go", "opencode_go", "opencodego"],
			name: "opencode_go", id: .opencodego,
			sourceDescription: "~/.local/share/opencode (OpenCode Go rows in opencode.db)",
			includedInAll: true, make: { OpenCodeGoProvider(root: $0) }),
		CLIProvider(
			flag: "--copilot", selectionTokens: ["copilot"], name: "copilot",
			id: .copilot, sourceDescription: "~/.copilot/otel",
			includedInAll: false, make: { CopilotProvider(root: $0) }),

		CLIProvider(
			flag: "--nemotron", selectionTokens: ["nemotron"], name: "nemotron",
			id: .nemotron,
			sourceDescription: "~/.local/share/opencode (nemotron sessions in opencode.db)",
			includedInAll: true, make: { OpenCodeBrandProvider(brand: .nemotron, root: $0) }),
		CLIProvider(
			flag: "--mimo", selectionTokens: ["mimo"], name: "mimo",
			id: .mimo,
			sourceDescription: "~/.local/share/opencode (mimo sessions in opencode.db)",
			includedInAll: true, make: { OpenCodeBrandProvider(brand: .mimo, root: $0) }),
		CLIProvider(
			flag: "--big-pickle", selectionTokens: ["big-pickle", "big_pickle", "bigpickle"],
			name: "big_pickle", id: .bigPickle,
			sourceDescription: "~/.local/share/opencode (big-pickle sessions in opencode.db)",
			includedInAll: true, make: { OpenCodeBrandProvider(brand: .bigPickle, root: $0) }),
		CLIProvider(
			flag: "--deepseek", selectionTokens: ["deepseek"], name: "deepseek",
			id: .deepseek,
			sourceDescription: "~/.local/share/opencode (deepseek sessions in opencode.db)",
			includedInAll: true, make: { OpenCodeBrandProvider(brand: .deepseek, root: $0) }),
	]

	/// The row a legacy invocation selects. The flags are mutually exclusive in practice; when more
	/// than one is passed the LAST matching row wins, which reproduces the old `if/else` ladder's
	/// precedence exactly (it tested Cursor first and fell through to Claude Code last).
	static func selected(arguments: [String]) -> CLIProvider {
		all.last { row in arguments.contains(row.flag) || (row.id == .grok && arguments.contains { ["--cursor", "--grok-bot", "--grok_bot"].contains($0) }) } ?? claude
	}
}

let selectedCLIProvider = CLIProviderTable.selected(arguments: args)

let useCodex = selectedCLIProvider.id == .codex
let useGrok = selectedCLIProvider.id == .grok
let useGemini = selectedCLIProvider.id == .gemini
let useCopilot = selectedCLIProvider.id == .copilot
let useIndex = args.contains("--indexed")
// Copilot stays a token estimate; unified Grok prices known local models at notional list rates.
let selectedCalculator =
	useCopilot
		? CostCalculator(pricing: PricingTable(models: [:]))
		: CostCalculator()
let providerName = selectedCLIProvider.name
let providerID: ProviderID = selectedCLIProvider.id

func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

func encode(_ bucket: CostBucket) -> [String: Any] {
	var out: [String: Any] = [
		"cost_usd": round2(bucket.cost),
		"events": bucket.eventCount,
		"input_tokens": bucket.usage.input,
		"output_tokens": bucket.usage.output,
		"cache_write_5m_tokens": bucket.usage.cacheCreate5m,
		"cache_write_1h_tokens": bucket.usage.cacheCreate1h,
		"cache_read_tokens": bucket.usage.cacheRead,
	]
	if !bucket.unpricedModels.isEmpty { out["unpriced_models"] = bucket.unpricedModels.sorted() }
	return out
}

// Build ONLY the selected provider, typed as `IndexableProvider` so the indexer can consume it
// without a downcast.
let baseProvider: any IndexableProvider = selectedCLIProvider.make(rootOverride)

let cursorSource = CursorProvider(root: args.contains("--cursor") ? rootOverride : nil)
let includeCursorSource = useGrok && (CursorHookSetup.state() == .active || (args.contains("--cursor") && rootOverride != nil)) && cursorSource.isAvailable()
let grokPlan = useGrok ? GrokPlanUsageStore.load() : nil
guard baseProvider.isAvailable() || includeCursorSource || grokPlan != nil else {
	FileHandle.standardError.write(
		Data("jpthecat: no \(selectedCLIProvider.sourceDescription) found\n".utf8))
	exit(1)
}

let start = Date()
var rollup: UsageRollup
var totalEvents: Int
var indexStats: [String: Any]?
// The analytics warehouse's "by project" slice for the last 7 days (same window as `by_model_7d`).
var byProject: [ProjectCostSummary] = []

if useIndex {
	let dbPath = arg("--db") ?? (NSTemporaryDirectory() + "jpthecat-index-\(providerName).sqlite")
	do {
		let index = try UsageIndex(path: dbPath)
		let indexer = UsageIndexer(index: index)
		let stats = try indexer.refresh(baseProvider)
		if includeCursorSource { _ = try indexer.refresh(cursorSource) }
		let sourceIDs = [providerID] + (includeCursorSource ? [.cursor] : [])
		rollup = try index.windowSummaries(providers: sourceIDs, calculator: selectedCalculator).aggregate.rollup
		totalEvents = sourceIDs.reduce(0) { $0 + index.eventCount(provider: $1) }
		byProject = (try? index.projectCostSummaries(providers: [providerID] + (includeCursorSource ? [.cursor] : []), days: 7, now: start)) ?? []
		indexStats = [
			"db": dbPath, "files_read": stats.filesRead, "files_skipped": stats.filesSkipped,
			"events_ingested": stats.eventsIngested,
		]
	} catch {
		FileHandle.standardError.write(Data("jpthecat: index error: \(error)\n".utf8))
		exit(1)
	}
} else {
	let events = baseProvider.loadEvents() + (includeCursorSource ? cursorSource.loadEvents() : [])
	rollup = UsageStore(calculator: selectedCalculator).rollup(events)
	totalEvents = events.count
	// Match the index path's 7-day local-calendar window, then bucket by project in-memory.
	let cal = Calendar.current
	if let windowStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: start)) {
		byProject = ProjectCostSummary.bucketed(
			events: events.filter { $0.timestamp >= windowStart }, calculator: selectedCalculator)
	}
}

var output: [String: Any] = [
	"provider": providerName,
	"today": encode(rollup.today),
	"last_7d": encode(rollup.last7d),
	"by_model_7d": rollup.byModel7d.mapValues { bucket -> [String: Any] in
		var row: [String: Any] = ["cost_usd": round2(bucket.cost), "events": bucket.eventCount]
		if !bucket.unpricedModels.isEmpty { row["unpriced"] = true }
		return row
	},
	"by_project_7d": byProject.map { p -> [String: Any] in
		["project": p.project, "cost_usd": round2(p.cost), "events": p.eventCount, "tokens": p.totalTokens]
	},
	"total_events": totalEvents,
	"elapsed_ms": Int(Date().timeIntervalSince(start) * 1000),
	"generated_at": ISO8601DateFormatter().string(from: Date()),
]
if let indexStats { output["index_stats"] = indexStats }
if useGrok, let plan = grokPlan {
	let encoder = JSONEncoder()
	encoder.dateEncodingStrategy = .secondsSince1970
	if let data = try? encoder.encode(plan), let object = try? JSONSerialization.jsonObject(with: data) {
		output["official_plan_usage"] = object
	}
	if rollup.last7d.eventCount == 0, let primary = GrokPlanUsageStore.primaryMeter(plan: plan, fallback: baseProvider.latestRateLimits()) {
		output["display_metric"] = "percent"
		output["display_value"] = primary.usedPercent
	}
}
// Codex on a ChatGPT subscription, Gemini on OAuth/Code Assist, the OpenCode gateways and model
// brands, and Copilot's mixed-provider OTel export are not JP-owned direct billing surfaces here.
// The label is derived from Core's one `ProviderBasis` table (the snapshot command uses the same
// mapping), so a provider can never be reported as real spend by omission; Gemini is audit-only with
// no basis row of its own and is a subscription's notional figure.
let legacyBasis: LocalAutomationCostBasis =
	useGemini ? .notionalListPrice : LocalAutomationCostBasis(ProviderBasis.of(selectedCLIProvider.id))
if legacyBasis != .realSpend {
	output["cost_basis"] = legacyBasis.rawValue
}

// Resolve through the selected provider's own signal. Every legacy --json response carries the tri-state
// block: Claude/Codex can be official when their feed is current; every no-signal provider is explicitly
// unknown. Keeping this outside the Codex-only rate_limits block is load-bearing — omission is ambiguous.
let selectedLimits = useGrok ? GrokPlanUsageStore.rateLimits(fallback: baseProvider.latestRateLimits()) : baseProvider.latestRateLimits()

// Codex is a subscription: the honest headline is rate-limit usage, not dollars.
if useCodex, let limits = selectedLimits {
	func window(_ w: RateLimitWindow?) -> [String: Any]? {
		guard let w else { return nil }
		var row: [String: Any] = ["used_percent": w.usedPercent, "window_minutes": w.windowMinutes]
		if let resets = w.resetsAt { row["resets_at"] = ISO8601DateFormatter().string(from: resets) }
		return row
	}
	var rl: [String: Any] = [:]
	if let plan = limits.planType { rl["plan_type"] = plan }
	if let primary = window(limits.primary) { rl["primary_5h"] = primary }
	if let secondary = window(limits.secondary) { rl["secondary_weekly"] = secondary }
	output["rate_limits"] = rl
}

// Unified honest headroom: numeric fields exist ONLY for an official state, never for unknown.
let headroom = ProviderHeadroom.resolve(from: selectedLimits)
var hr: [String: Any] = ["state": headroom.stateToken]
if case let .official(remaining, minutes, resets) = headroom {
	hr["remaining_percent"] = remaining
	hr["window_minutes"] = minutes
	if let resets { hr["resets_at"] = ISO8601DateFormatter().string(from: resets) }
}
output["headroom"] = hr

let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))

enum CLIError: Error, CustomStringConvertible {
	case unsupportedCommand(String)
	case unsupportedFormat(String)
	case unknownProvider(String)
	case providerUnavailable(String)

	var description: String {
		switch self {
		case let .unsupportedCommand(command):
			"unsupported command: \(command)"
		case let .unsupportedFormat(format):
			"unsupported format: \(format)"
		case let .unknownProvider(provider):
			"unknown provider: \(provider)"
		case let .providerUnavailable(provider):
			"no local \(provider) source found"
		}
	}
}

func runAutomationCommand(args: [String]) throws -> String {
	guard let command = args.dropFirst().first else { throw CLIError.unsupportedCommand("") }
	let providerSelection = arg("--provider") ?? "all"
	let days = LocalAutomationSnapshotBuilder.normalizedDays(Int(arg("--days") ?? "14") ?? 14)
	let root = arg("--root").map { URL(fileURLWithPath: $0, isDirectory: true) }
	let useIndex = args.contains("--indexed")
	let explicitDB = arg("--db")
	let dbPath = explicitDB ?? (NSTemporaryDirectory() + "jpthecat-automation-\(UUID().uuidString).sqlite")
	// A caller-supplied `--db` is theirs to keep; an auto-generated temp index (plus its WAL/shm
	// siblings) is disposable and must not accumulate one full-corpus DB per automation invocation.
	defer {
		if explicitDB == nil {
			for suffix in ["", "-wal", "-shm"] {
				try? FileManager.default.removeItem(atPath: dbPath + suffix)
			}
		}
	}

	let providers = try selectedAutomationProviders(selection: providerSelection, root: root)
	guard !providers.isEmpty || providerSelection == "all" else {
		throw CLIError.providerUnavailable(providerSelection)
	}

	let index = try UsageIndex(path: dbPath)
	if useIndex {
		let indexer = UsageIndexer(index: index)
		// `providers` is `[any IndexableProvider]`, so this is ONE generic call for every provider.
		// It replaced a downcast switch whose `guard let … as? XProvider else { return }` arms turned
		// a type mismatch into a silent no-op — a provider would simply contribute nothing.
		for provider in providers {
			_ = try indexer.refresh(provider)
		}
	} else {
		for provider in providers {
			try index.ingest(provider.loadEvents())
		}
	}

	let providerIDs = providers.map(\.id)
	let tokenOnlySelection = providerIDs.allSatisfy { $0 == .copilot }
	let calculator = tokenOnlySelection
		? CostCalculator(pricing: PricingTable(models: [:]))
		: CostCalculator()
	let summaries = try index.windowSummaries(
		providers: providerIDs, days: days, calculator: calculator)
	var rateLimits = Dictionary(uniqueKeysWithValues: providers.compactMap { provider -> (ProviderID, RateLimitSnapshot)? in
		guard let limits = provider.latestRateLimits() else { return nil }
		return (provider.id, limits)
	})
	if providerIDs.contains(.grok), let limits = GrokPlanUsageStore.rateLimits() { rateLimits[.grok] = limits }
	let snapshot = LocalAutomationSnapshotBuilder.build(
		summaries: summaries,
		providerIDs: providerIDs,
		rateLimits: rateLimits,
		source: "jpthecat-cli",
		grokPlan: providerIDs.contains(.grok) ? GrokPlanUsageStore.load() : nil,
		generatedAt: Date())

	switch command {
	case "snapshot":
		guard args.contains("--json") else { throw CLIError.unsupportedFormat("snapshot requires --json") }
		return String(decoding: try LocalAutomationSnapshotEncoder.encode(snapshot), as: UTF8.self)
	case "report":
		let format = arg("--format") ?? "markdown"
		guard format == "markdown" else { throw CLIError.unsupportedFormat(format) }
		return snapshot.markdownReport()
	default:
		throw CLIError.unsupportedCommand(command)
	}
}

/// Resolves `--provider` against the one `CLIProviderTable`. `all` is every dashboard-summed row plus
/// the gateways (see `CLIProvider.includedInAll`) — audit-only and token-estimate providers must be
/// asked for by name, exactly as before.
func selectedAutomationProviders(selection: String, root: URL?) throws -> [any IndexableProvider] {
	let candidates: [CLIProvider]
	if selection == "all" {
		candidates = CLIProviderTable.all.filter(\.includedInAll)
	} else if let selected = CLIProviderTable.all.first(where: { $0.selectionTokens.contains(selection) }) {
		candidates = [selected]
	} else { throw CLIError.unknownProvider(selection) }
	var result: [any IndexableProvider] = candidates.compactMap { candidate in
		let provider = candidate.make(root)
		return provider.isAvailable() || (candidate.id == .grok && GrokPlanUsageStore.load() != nil) ? provider : nil
	}
	if candidates.contains(where: { $0.id == .grok }), CursorHookSetup.state() == .active || (selection == "cursor" && root != nil) {
		let cursor = CursorProvider(root: selection == "cursor" ? root : nil)
		if cursor.isAvailable() { result.append(cursor) }
	}
	return result
}

func writeAtomically(_ output: String, to url: URL) throws {
	try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
	try output.data(using: .utf8)?.write(to: url, options: [.atomic])
}
