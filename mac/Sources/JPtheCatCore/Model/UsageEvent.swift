import Foundation

/// A supported AI coding tool in the JPtheCat catalog. `ProviderCatalog` is the metadata source;
/// only providers marked `.live` should be treated as launch-ready parsers.
public enum ProviderID: String, Sendable, Codable, CaseIterable {
	case claude
	case codex
	case gemini
	case copilot
	case opencode
	case amp
	case factory
	case codebuff
	case kilo
	case kimi
	case hermes
	case piAgent = "pi"
	case goose
	case openclaw
	case qwen
	case qoder
	case codebuddy
	case cursor
	case openai
	case azureopenai
	case opencodego
	case alibaba
	case alibabatokenplan
	case antigravity
	case devin
	case zai
	case minimax
	case manus
	case kiro
	case vertexai
	case augment
	case jetbrains
	case kimik2
	case moonshot
	case t3chat
	case ollama
	case synthetic
	case openrouter
	case elevenlabs
	case warp
	case windsurf
	case zed
	case perplexity
	case mimo
	case doubao
	case sakana
	case abacus
	case mistral
	case deepseek
	case crof
	case venice
	case commandcode
	case stepfun
	case bedrock
	case grok
	case grokBot = "grok_bot"
	case groq
	case llmproxy
	case litellm
	case deepgram
	case poe
	case chutes
	case aider
	case museSpark = "muse_spark"
	case nemotron
	case bigPickle = "big_pickle"
}

/// Normalized per-turn token counts. Cache creation is split into the 5-minute and 1-hour
/// buckets because they are priced differently (1.25x vs 2x input) — the single most common
/// source of cost error in other tools (ccusage #899).
public struct TokenUsage: Sendable, Equatable {
	public var input: Int
	public var output: Int
	public var cacheCreate5m: Int
	public var cacheCreate1h: Int
	public var cacheRead: Int

	public init(
		input: Int = 0,
		output: Int = 0,
		cacheCreate5m: Int = 0,
		cacheCreate1h: Int = 0,
		cacheRead: Int = 0
	) {
		self.input = input
		self.output = output
		self.cacheCreate5m = cacheCreate5m
		self.cacheCreate1h = cacheCreate1h
		self.cacheRead = cacheRead
	}

	/// Total tokens across every bucket — for token charts, never for billing.
	public var total: Int { input + output + cacheCreate5m + cacheCreate1h + cacheRead }

	public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
		TokenUsage(
			input: lhs.input + rhs.input,
			output: lhs.output + rhs.output,
			cacheCreate5m: lhs.cacheCreate5m + rhs.cacheCreate5m,
			cacheCreate1h: lhs.cacheCreate1h + rhs.cacheCreate1h,
			cacheRead: lhs.cacheRead + rhs.cacheRead
		)
	}

	public static func += (lhs: inout TokenUsage, rhs: TokenUsage) { lhs = lhs + rhs }
}

/// One de-duplicated assistant response with its token usage. `dedupKey` uniquely identifies
/// the underlying request (a resumed/streamed session re-logs the same request many times).
public struct UsageEvent: Sendable, Identifiable {
	public let messageId: String
	public let requestId: String
	public let provider: ProviderID
	public let model: String
	public let timestamp: Date
	public let usage: TokenUsage
	public let project: String?

	public var id: String { "\(messageId):\(requestId)" }

	public init(
		messageId: String,
		requestId: String,
		provider: ProviderID,
		model: String,
		timestamp: Date,
		usage: TokenUsage,
		project: String? = nil
	) {
		self.messageId = messageId
		self.requestId = requestId
		self.provider = provider
		self.model = model
		self.timestamp = timestamp
		self.usage = usage
		self.project = project
	}
}
