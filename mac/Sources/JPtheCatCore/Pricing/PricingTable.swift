import Foundation

/// Per-token USD prices for one model. Field names mirror LiteLLM's
/// `model_prices_and_context_window.json` so that file can be ingested directly later.
/// The legacy `*Above200k` field names carry each model's configured whole-request premium.
public struct ModelPrice: Sendable, Decodable {
	public let inputCostPerToken: Double
	public let outputCostPerToken: Double
	public let cacheCreationInputTokenCost: Double? // 5-minute cache write (1.25x input)
	public let cacheCreationInputTokenCostAbove1hr: Double? // 1-hour cache write (2x input)
	public let cacheReadInputTokenCost: Double? // cache read/hit (0.1x input)

	/// Legacy tier field names use 200K; this optional threshold overrides that default.
	public var contextTierThreshold: Int? = nil
	public var contextTierInclusive: Bool? = nil

	var lastBaseContextTokenCount: Int {
		(contextTierThreshold ?? 200_000) - (contextTierInclusive == true ? 1 : 0)
	}

	// >200K-context tier (whole-request surcharge). nil = model has no surcharge (flat to 1M).
	public let inputCostPerTokenAbove200k: Double?
	public let outputCostPerTokenAbove200k: Double?
	public let cacheCreationInputTokenCostAbove200k: Double?
	public let cacheCreationInputTokenCostAbove1hrAbove200k: Double?
	public let cacheReadInputTokenCostAbove200k: Double?

	enum CodingKeys: String, CodingKey {
		case contextTierThreshold = "context_tier_threshold"
		case contextTierInclusive = "context_tier_inclusive"
		case inputCostPerToken = "input_cost_per_token"
		case outputCostPerToken = "output_cost_per_token"
		case cacheCreationInputTokenCost = "cache_creation_input_token_cost"
		case cacheCreationInputTokenCostAbove1hr = "cache_creation_input_token_cost_above_1hr"
		case cacheReadInputTokenCost = "cache_read_input_token_cost"
		case inputCostPerTokenAbove200k = "input_cost_per_token_above_200k_tokens"
		case outputCostPerTokenAbove200k = "output_cost_per_token_above_200k_tokens"
		case cacheCreationInputTokenCostAbove200k = "cache_creation_input_token_cost_above_200k_tokens"
		case cacheCreationInputTokenCostAbove1hrAbove200k =
			"cache_creation_input_token_cost_above_1hr_above_200k_tokens"
		case cacheReadInputTokenCostAbove200k = "cache_read_input_token_cost_above_200k_tokens"
	}

	/// Every rate times `factor`, with the context threshold kept. A field the row leaves nil stays nil,
	/// so `CostCalculator`'s fallbacks derive it from the scaled input rate.
	func scaled(by factor: Double) -> ModelPrice {
		ModelPrice(
			inputCostPerToken: inputCostPerToken * factor,
			outputCostPerToken: outputCostPerToken * factor,
			cacheCreationInputTokenCost: cacheCreationInputTokenCost.map { $0 * factor },
			cacheCreationInputTokenCostAbove1hr: cacheCreationInputTokenCostAbove1hr.map { $0 * factor },
			cacheReadInputTokenCost: cacheReadInputTokenCost.map { $0 * factor },
			contextTierThreshold: contextTierThreshold,
			contextTierInclusive: contextTierInclusive,
			inputCostPerTokenAbove200k: inputCostPerTokenAbove200k.map { $0 * factor },
			outputCostPerTokenAbove200k: outputCostPerTokenAbove200k.map { $0 * factor },
			cacheCreationInputTokenCostAbove200k: cacheCreationInputTokenCostAbove200k.map { $0 * factor },
			cacheCreationInputTokenCostAbove1hrAbove200k: cacheCreationInputTokenCostAbove1hrAbove200k.map { $0 * factor },
			cacheReadInputTokenCostAbove200k: cacheReadInputTokenCostAbove200k.map { $0 * factor })
	}
}

/// Model-id -> price. Three-layer resolution: bundled defaults (this type, via `bundledDefault()`) →
/// remote ETag override (`RemotePricingStore.resolvedTable()` merges a fetched table on top) →
/// unpriced (`price(for:)` returns nil so the caller badges it rather than billing $0). An exact id
/// wins; then a rate-multiplier suffix scales the price of the id it decorates; otherwise
/// `ModelIdentity.pricingID` removes decorators (vendor prefix, `[1m]`, snapshot date), lowercases,
/// and applies the documented `aliases` map from the same JSON.
public struct PricingTable: Sendable {
	private let models: [String: ModelPrice]
	/// Emitted id → canonical row id (`pricing-default.json` `aliases`).
	let aliases: [String: String]
	/// Accounting suffix → factor on every rate of the id it decorates (`pricing-default.json`
	/// `rate_multipliers`): a premium that applies to whole model families needs no row per model.
	let rateMultipliers: [String: Double]

	/// `aliases` and `rateMultipliers` default to the bundled maps so a table built in code prices the
	/// same emitted ids as the shipped one.
	public init(
		models: [String: ModelPrice], aliases: [String: String] = ModelIdentity.bundledAliases,
		rateMultipliers: [String: Double] = PricingTable.bundledRateMultipliers
	) {
		self.models = models
		self.aliases = aliases
		self.rateMultipliers = rateMultipliers
	}

	/// The models this table can price (for coverage tests).
	public var knownModels: Set<String> { Set(models.keys) }

	var contextTierThresholds: [Int] {
		Array(Set([200_000] + models.values.map(\.lastBaseContextTokenCount))).sorted()
	}

	/// Overlay a remote override on this (bundled) table: `other`'s per-model prices and aliases win,
	/// entries present only here are preserved. This is the "bundled → remote override" middle layer of
	/// the three-layer resolution, so a partial remote never drops a bundled model to unpriced
	/// (`RemotePricingStore`).
	public func merging(_ other: PricingTable) -> PricingTable {
		PricingTable(
			models: models.merging(other.models) { _, remote in remote },
			aliases: aliases.merging(other.aliases) { _, remote in remote },
			rateMultipliers: rateMultipliers.merging(other.rateMultipliers) { _, remote in remote })
	}

	/// The shipped table, decoded once per process. `ModelIdentity.bundledAliases` reads the same value.
	public static func bundledDefault() -> PricingTable { bundled }

	/// The `rate_multipliers` map shipped in `pricing-default.json`.
	public static var bundledRateMultipliers: [String: Double] { bundled.rateMultipliers }

	private static let bundled: PricingTable = {
		struct File: Decodable {
			let models: [String: ModelPrice]
			let aliases: [String: String]?
			let rate_multipliers: [String: Double]?
		}
		guard let url = JPResourceBundle.url(
			forResource: "pricing-default",
			withExtension: "json",
			in: "JPtheCatCore"),
			let data = try? Data(contentsOf: url),
			let file = try? JSONDecoder().decode(File.self, from: data)
		else { return PricingTable(models: [:], aliases: [:], rateMultipliers: [:]) }
		return PricingTable(
			models: file.models, aliases: file.aliases ?? [:], rateMultipliers: file.rate_multipliers ?? [:])
	}()

	/// True when every factor is a finite premium or discount a real price list could publish. A remote
	/// body with any other factor is rejected whole, like a broken alias.
	static func rateMultipliersAreSound(_ multipliers: [String: Double]) -> Bool {
		multipliers.allSatisfy { suffix, factor in
			suffix.hasPrefix("-") && suffix.count > 1 && factor.isFinite && factor > 0 && factor < 10
		}
	}

	/// Every reason an alias entry is broken on its own, as `alias → target: reason`; empty means sound.
	/// `pricingID` looks a key up only after removing decorators and lowercasing, so a decorated or
	/// upper-case key is silently dead, and a free-tier key would bill a free turn.
	/// `RemotePricingStore` rejects a remote body with any defect. A key that shadows a row is checked
	/// only for the bundled map (`ModelIdentityTests`): a later feed may retire a row this build still
	/// bundles, and rejecting that whole feed would freeze every other price update.
	static func aliasDefects(_ aliases: [String: String], rows: Set<String>) -> [String] {
		aliases.sorted { $0.key < $1.key }.compactMap { alias, target in
			let reason: String? =
				if !rows.contains(target) { "target has no row" }
				else if ModelIdentity.isFreeTier(alias) { "key is a free-tier id" }
				else if alias != ModelIdentity.undecorated(alias).lowercased() { "key is not a lookup id" }
				else { nil }
			return reason.map { "\(alias) → \(target): \($0)" }
		}
	}

	/// Exact match first, then the decorator-free, lowercased, aliased id.
	///
	/// A FREE-TIER id (`…-free`, `…-contributor-free`) is deliberately unpriced, never mapped down to
	/// its paid base row: OpenCode Zen/Go charge nothing for those models, so showing the base model's
	/// list rate would print a notional dollar figure for usage that cost $0. Unpriced is the honest
	/// answer here — the row then falls back to token display (`ProviderRow.isFullyUnpriced`) instead
	/// of a misleading cost. This is ONE rule for every row: the model-brand providers (MiMo, Nemotron,
	/// DeepSeek, Big Pickle, Muse Spark) keep the suffix at parse time too, so the same free turn can
	/// never read as $0 under the gateway and as list-price dollars under its brand.
	/// `ModelIdentity.isFreeTier` also sees through decorators, so `…-free[1m]` or a dated free id stays
	/// unpriced.
	///
	/// A rate-multiplier suffix (`…-us-inference`) prices the id it decorates, then scales every rate.
	/// When that id is unpriced, the turn stays unpriced.
	public func price(for model: String) -> ModelPrice? {
		if ModelIdentity.isFreeTier(model) { return nil }
		if let p = models[model] { return p }
		for (suffix, factor) in rateMultipliers where model.count > suffix.count && model.hasSuffix(suffix) {
			return price(for: String(model.dropLast(suffix.count)))?.scaled(by: factor)
		}
		let id = ModelIdentity.pricingID(model, aliases: aliases)
		return id == model ? nil : models[id]
	}
}
