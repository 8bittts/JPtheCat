import Foundation

public enum ProviderSupport: String, Sendable, Codable {
	case live
	case localRoadmap
	case connectRoadmap
	case apiRoadmap
	case candidateRoadmap
}

public enum ProviderCatalogSource: String, Sendable, Codable {
	case codexBar
	case ccusage
	case codingAgentUsageTracker
	case openIsland
	case jpRoadmap
}

public struct ProviderDescriptor: Sendable, Equatable {
	public let id: ProviderID
	public let name: String
	/// Compact label for tight surfaces (the rotating menu-bar limit pill). Defaults to `name`; set it
	/// only where the full marketing name is too long — e.g. "Claude Code" → "Claude". The menu bar must
	/// read "Claude"/"Codex", never "Claude Code"/"Cx".
	public let shortName: String
	public let glyph: String
	public let support: ProviderSupport
	public let sources: [ProviderCatalogSource]
	public let iconSlug: String?

	public init(
		id: ProviderID,
		name: String,
		shortName: String? = nil,
		glyph: String,
		support: ProviderSupport,
		sources: [ProviderCatalogSource],
		iconSlug: String? = nil
	) {
		self.id = id
		self.name = name
		self.shortName = shortName ?? name
		self.glyph = glyph
		self.support = support
		self.sources = sources
		self.iconSlug = iconSlug
	}

	/// The compact menu-bar label for a provider identified by its full `name`, falling back to the
	/// name itself for anything not in the catalog. One lookup so the rotating pill and its tooltip
	/// agree on "Claude"/"Codex".
	public static func shortName(forName name: String) -> String {
		ProviderCatalog.all.first { $0.name == name }?.shortName ?? name
	}
}

/// Canonical provider inventory for Core and public docs. It combines CodexBar's 54-provider
/// descriptor baseline, ccusage's local-source list, Open Island's agent-control inventory, and
/// Aider as an existing JP roadmap item.
public enum ProviderCatalog {
	public static let all: [ProviderDescriptor] = [
		ProviderDescriptor(
			id: .claude, name: "Claude Code", shortName: "Claude", glyph: "Cl", support: .live,
			sources: [.codexBar, .ccusage, .codingAgentUsageTracker, .openIsland], iconSlug: "claude"),
		ProviderDescriptor(
			id: .codex, name: "Codex", glyph: "Cx", support: .live,
			sources: [.codexBar, .ccusage, .codingAgentUsageTracker, .openIsland], iconSlug: "codex"),
		// Grok Build CLI — local `~/.grok/sessions/**/updates.jsonl` via `GrokProvider`, plus
		// mid-turn `inference_done` rounds from `~/.grok/logs/unified.jsonl`. SuperGrok /
		// X Premium+ dollars are notional list price (same honesty as Codex). Official weekly
		// SuperGrok % is opt-in capture only (`GrokRateLimitCapture`); never a token-derived %.
		ProviderDescriptor(
			id: .grok, name: "Grok", glyph: "Gk", support: .live,
			sources: [.codexBar, .jpRoadmap], iconSlug: "grok"),

		ProviderDescriptor(
			// Google is sunsetting Gemini CLI for free/Pro/Ultra individuals in favor of Antigravity
			// CLI; parser stays ready for enterprise/API/OSS users.
			id: .gemini, name: "Gemini", glyph: "G", support: .localRoadmap,
			sources: [.codexBar, .ccusage, .codingAgentUsageTracker, .openIsland], iconSlug: "gemini"),
		// Held at roadmap: the only real local usage source (Copilot CLI's OpenTelemetry export) is
		// opt-in and needs manual setup, and the zero-config alternative has a confirmed unfixed
		// data-loss bug (github/copilot-cli#3994).
		ProviderDescriptor(
			id: .copilot, name: "GitHub Copilot", shortName: "Copilot", glyph: "Co", support: .localRoadmap,
			sources: [.codexBar, .ccusage, .codingAgentUsageTracker], iconSlug: "copilot"),
		// OpenCode Zen — the pay-as-you-go AI gateway at `opencode.ai/zen`. Its durable local signal is
		// `opencode.db` message/session rows whose own `providerID` is `opencode`; the model brands
		// (Muse Spark/Nemotron/MiMo/Big Pickle/DeepSeek) peel their models from a NON-gateway route, so
		// a Zen-routed row belongs to Zen and never double-counts against a model-brand row.
		ProviderDescriptor(
			id: .opencode, name: "OpenCode Zen", shortName: "Zen", glyph: "Oc", support: .live,
			sources: [.codexBar, .ccusage, .codingAgentUsageTracker, .openIsland], iconSlug: "opencode"),
		ProviderDescriptor(
			id: .amp, name: "Amp", glyph: "Am", support: .localRoadmap,
			sources: [.codexBar, .ccusage, .codingAgentUsageTracker], iconSlug: "amp"),
		ProviderDescriptor(
			id: .factory, name: "Droid (Factory)", glyph: "Dr", support: .localRoadmap,
			sources: [.codexBar, .ccusage, .codingAgentUsageTracker, .openIsland], iconSlug: "factory"),
		ProviderDescriptor(
			id: .codebuff, name: "Codebuff", glyph: "Cb", support: .localRoadmap,
			sources: [.codexBar, .ccusage], iconSlug: "codebuff"),
		ProviderDescriptor(
			id: .kilo, name: "Kilo", glyph: "Ki", support: .localRoadmap,
			sources: [.codexBar, .ccusage], iconSlug: "kilo"),
		ProviderDescriptor(
			id: .kimi, name: "Kimi", glyph: "Km", support: .localRoadmap,
			sources: [.codexBar, .ccusage, .codingAgentUsageTracker, .openIsland], iconSlug: "kimi"),
		ProviderDescriptor(
			id: .hermes, name: "Hermes Agent", glyph: "He", support: .localRoadmap,
			sources: [.ccusage]),
		ProviderDescriptor(
			id: .piAgent, name: "pi-agent", glyph: "Pi", support: .localRoadmap,
			sources: [.ccusage]),
		ProviderDescriptor(
			id: .goose, name: "Goose", glyph: "Go", support: .localRoadmap,
			sources: [.ccusage]),
		ProviderDescriptor(
			id: .openclaw, name: "OpenClaw", glyph: "Oc", support: .localRoadmap,
			sources: [.ccusage]),
		ProviderDescriptor(
			id: .qwen, name: "Qwen", glyph: "Qw", support: .localRoadmap,
			sources: [.ccusage, .openIsland]),
		ProviderDescriptor(
			id: .qoder, name: "Qoder", glyph: "Qd", support: .candidateRoadmap,
			sources: [.openIsland]),
		ProviderDescriptor(
			id: .codebuddy, name: "CodeBuddy", glyph: "CB", support: .candidateRoadmap,
			sources: [.openIsland]),

		ProviderDescriptor(
			id: .openai, name: "OpenAI", glyph: "OA", support: .apiRoadmap,
			sources: [.codexBar]),
		ProviderDescriptor(
			id: .azureopenai, name: "Azure OpenAI", glyph: "Az", support: .apiRoadmap,
			sources: [.codexBar]),
		// OpenCode Go — the $10/month OpenCode Zen subscription (5h $12 / weekly $30 / monthly $60 of
		// usage). Same `opencode.db` source as Zen, but rows whose own `providerID` is `opencode-go`.
		// The windows are official documented caps against locally recorded cost; OpenCode publishes no
		// local reset boundary, so JP shows measured usage-vs-cap and never a fabricated reset countdown.
		ProviderDescriptor(
			id: .opencodego, name: "OpenCode Go", shortName: "Go", glyph: "Og", support: .live,
			sources: [.codexBar, .jpRoadmap], iconSlug: "opencodego"),
		ProviderDescriptor(
			id: .alibaba, name: "Alibaba", glyph: "Al", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "alibaba"),
		ProviderDescriptor(
			id: .alibabatokenplan, name: "Alibaba Token Plan", glyph: "At", support: .apiRoadmap,
			sources: [.codexBar]),
		ProviderDescriptor(
			// Antigravity CLI (`agy`) is Google's successor to Gemini CLI (the migration Google is
			// pushing everyone to). It writes local data under ~/.gemini/antigravity-cli/, but its
			// transcripts record only the model + activity — NO token/usage counts — so we can't price
			// it yet. `localRoadmap` = a local tool we target next, once it exposes usage.
			id: .antigravity, name: "Antigravity", glyph: "Ag", support: .localRoadmap,
			sources: [.codexBar, .codingAgentUsageTracker], iconSlug: "antigravity"),
		ProviderDescriptor(
			id: .devin, name: "Devin", glyph: "Dv", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "devin"),
		ProviderDescriptor(
			id: .zai, name: "z.ai", glyph: "Za", support: .apiRoadmap,
			sources: [.codexBar, .codingAgentUsageTracker], iconSlug: "zai"),
		ProviderDescriptor(
			id: .minimax, name: "MiniMax", glyph: "Mm", support: .apiRoadmap,
			sources: [.codexBar, .codingAgentUsageTracker], iconSlug: "minimax"),
		ProviderDescriptor(
			id: .manus, name: "Manus", glyph: "Ma", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "manus"),
		ProviderDescriptor(
			id: .kiro, name: "Kiro", glyph: "Kr", support: .apiRoadmap,
			sources: [.codexBar, .codingAgentUsageTracker], iconSlug: "kiro"),
		ProviderDescriptor(
			id: .vertexai, name: "Vertex AI", glyph: "Vx", support: .apiRoadmap,
			sources: [.codexBar, .codingAgentUsageTracker], iconSlug: "vertexai"),
		ProviderDescriptor(
			id: .augment, name: "Augment", glyph: "Au", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "augment"),
		ProviderDescriptor(
			id: .jetbrains, name: "JetBrains AI", glyph: "Jb", support: .apiRoadmap,
			sources: [.codexBar, .codingAgentUsageTracker], iconSlug: "jetbrains"),
		ProviderDescriptor(
			id: .kimik2, name: "Kimi K2 (unofficial)", glyph: "K2", support: .apiRoadmap,
			sources: [.codexBar, .codingAgentUsageTracker]),
		ProviderDescriptor(
			id: .moonshot, name: "Moonshot / Kimi API", glyph: "Mo", support: .apiRoadmap,
			sources: [.codexBar]),
		ProviderDescriptor(
			id: .t3chat, name: "T3 Chat", glyph: "T3", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "t3chat"),
		ProviderDescriptor(
			id: .ollama, name: "Ollama", glyph: "Ol", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "ollama"),
		ProviderDescriptor(
			id: .synthetic, name: "Synthetic", glyph: "Sy", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "synthetic"),
		ProviderDescriptor(
			id: .openrouter, name: "OpenRouter", glyph: "Or", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "openrouter"),
		ProviderDescriptor(
			id: .elevenlabs, name: "ElevenLabs", glyph: "El", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "elevenlabs"),
		ProviderDescriptor(
			id: .warp, name: "Warp", glyph: "Wp", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "warp"),
		ProviderDescriptor(
			id: .windsurf, name: "Windsurf", glyph: "Ws", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "windsurf"),
		ProviderDescriptor(
			id: .zed, name: "Zed", glyph: "Zd", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "zed"),
		ProviderDescriptor(
			id: .perplexity, name: "Perplexity", glyph: "Px", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "perplexity"),
		ProviderDescriptor(
			id: .mimo, name: "Xiaomi MiMo", shortName: "MiMo", glyph: "Mi",
			support: .localRoadmap, sources: [.jpRoadmap], iconSlug: "mimo"),
		ProviderDescriptor(
			id: .doubao, name: "Doubao", glyph: "Db", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "doubao"),
		ProviderDescriptor(
			id: .sakana, name: "Sakana AI", glyph: "Sk", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "sakana"),
		ProviderDescriptor(
			id: .abacus, name: "Abacus AI", glyph: "Ab", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "abacus"),
		ProviderDescriptor(
			id: .mistral, name: "Mistral", glyph: "Ms", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "mistral"),
		ProviderDescriptor(
			id: .deepseek, name: "DeepSeek", glyph: "Ds", support: .localRoadmap,
			sources: [.jpRoadmap], iconSlug: "deepseek"),
		ProviderDescriptor(
			id: .crof, name: "Crof", glyph: "Cr", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "crof"),
		ProviderDescriptor(
			id: .venice, name: "Venice", glyph: "Ve", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "venice"),
		ProviderDescriptor(
			id: .commandcode, name: "Command Code", glyph: "Cc", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "commandcode"),
		ProviderDescriptor(
			id: .stepfun, name: "StepFun", glyph: "Sf", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "stepfun"),
		ProviderDescriptor(
			id: .bedrock, name: "AWS Bedrock", glyph: "Br", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "bedrock"),
		ProviderDescriptor(
			id: .groq, name: "Groq", glyph: "Gq", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "groq"),
		ProviderDescriptor(
			id: .llmproxy, name: "LLM Proxy", glyph: "Lp", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "llmproxy"),
		ProviderDescriptor(
			id: .litellm, name: "LiteLLM", glyph: "Ll", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "litellm"),
		ProviderDescriptor(
			id: .deepgram, name: "Deepgram", glyph: "Dg", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "deepgram"),
		ProviderDescriptor(
			id: .poe, name: "Poe", glyph: "Po", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "poe"),
		ProviderDescriptor(
			id: .chutes, name: "Chutes", glyph: "Ch", support: .apiRoadmap,
			sources: [.codexBar], iconSlug: "chutes"),
		ProviderDescriptor(
			id: .museSpark, name: "Muse Spark", glyph: "Sp", support: .live,
			sources: [.jpRoadmap], iconSlug: "muse-spark"),
		ProviderDescriptor(
			id: .aider, name: "Aider", glyph: "Ai", support: .candidateRoadmap,
			sources: [.jpRoadmap]),
		ProviderDescriptor(
			id: .nemotron, name: "Nemotron 3", shortName: "Nemotron", glyph: "Nt",
			support: .localRoadmap, sources: [.jpRoadmap], iconSlug: "nemotron"),
		ProviderDescriptor(
			id: .bigPickle, name: "Big Pickle", glyph: "BP",
			support: .localRoadmap, sources: [.jpRoadmap], iconSlug: "big-pickle"),
	]

	public static var live: [ProviderDescriptor] {
		all.filter { $0.support == .live }
	}

	/// Providers JP accounts for LOCALLY — a dashboard row that is summed into the dollar aggregate
	/// (`ProviderBasis.notional`) and fanned out by `jpthecat-cli --provider all` — without a `.live`
	/// marketing claim. Today that is exactly the OpenCode model-brand rows; the set is derived from
	/// `OpenCodeBrand` so the CLI, the dashboard, and this catalog cannot list different brands.
	/// A brand leaves this set only by a deliberate `.live` promotion (`_docs/11-adding-a-provider.md`).
	public static var localAccountingIDs: Set<ProviderID> {
		Set(OpenCodeBrand.allCases.map(\.id))
	}

	/// Every provider whose figures may enter a dollar total: the aggregable live set (a live
	/// `ProviderBasis.gateway` row is displayed, never summed) plus local accounting.
	public static var aggregateIDs: Set<ProviderID> {
		Set(live.map(\.id).filter { ProviderBasis.of($0).isAggregable }).union(localAccountingIDs)
	}

	public static func descriptor(for id: ProviderID) -> ProviderDescriptor? {
		all.first { $0.id == id.consolidated }
	}

	public static func withSource(_ source: ProviderCatalogSource) -> [ProviderDescriptor] {
		all.filter { $0.sources.contains(source) }
	}
}
