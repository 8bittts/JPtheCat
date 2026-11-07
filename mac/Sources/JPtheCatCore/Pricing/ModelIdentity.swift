import Foundation

/// The one model-id pipeline behind pricing, effort, display, and per-model grouping.
///
/// A locally emitted id can carry extra text that never changes WHICH model ran:
///  - decorators: a `vendor/` prefix, Claude Code's `[1m]` context selector, and a snapshot date
///    (`-YYYYMMDD` or `-YYYY-MM-DD`);
///  - documented aliases (`gpt-5.6` → `gpt-5.6-sol`, `grok-4.6-build` → `grok-4.6`), stored as data in
///    `pricing-default.json` `aliases` so the app, the website, and the coverage audit read one map;
///  - accounting suffixes appended at parse time to select a rate the bare id cannot: OpenCode
///    gateway routes (`-opencode`, `-zen`, `-go`, then an optional `-peak`) from `OpenCodeGateway`,
///    and Claude fast mode (`-fast-mode`, then an optional `-us-inference`) from `ClaudeProvider`.
///
/// Pricing keeps the accounting suffix because it selects the rate. Display, effort, and grouping drop
/// it, so one model never shows as two tiles or two effort tiers. A free-tier suffix (`-free`) survives
/// pricing and grouping: a free turn is unpriced, never billed at the paid row, and never merged into
/// the paid model's dollars. Lookup keys (`pricingID`, `modelKey`) are lowercase because every price
/// row and alias is; display ids keep the emitted case.
public enum ModelIdentity {
	/// Suffixes JP appends to a model id to select a rate. Appended at parse time
	/// (`OpenCodeGateway.normalizedModelID`, `fastModeID`); removed here, so both sides share one
	/// spelling.
	public enum AccountingSuffix {
		public static let openCode = "-opencode"
		public static let zen = "-zen"
		public static let go = "-go"
		public static let peak = "-peak"
		/// Claude fast mode (`usage.speed: "fast"`). Never bare `-fast`: real ids end in it
		/// (`grok-composer-2.5-fast`), and presentation must not merge those into another model.
		public static let fastMode = "-fast-mode"
		/// Claude US-only inference (`usage.inference_geo: "us"`). Priced by a `rate_multipliers`
		/// factor on the id it decorates, not by its own rows.
		public static let usInference = "-us-inference"
		static let routes = [openCode, zen, go]
	}

	static let freeTierSuffix = "-free"
	private static let contextSelector = "[1m]"
	private static let snapshotDatePattern = "-(?:[0-9]{8}|[0-9]{4}-[0-9]{2}-[0-9]{2})$"

	/// True for an OpenCode free-tier id (`…-free`, including `…-contributor-free`), with or without
	/// decorators (`…-free[1m]`, `…-free-20260923`). One rule for pricing and the unpriced disclosure.
	public static func isFreeTier(_ model: String) -> Bool {
		model.hasSuffix(freeTierSuffix) || undecorated(model).hasSuffix(freeTierSuffix)
	}

	/// The text after the last `/`, unless the id ends in `/`. Every parser and lookup strips a vendor
	/// prefix through this one rule.
	public static func withoutVendorPrefix(_ model: String) -> String {
		guard let slash = model.lastIndex(of: "/"), slash < model.index(before: model.endIndex) else {
			return model
		}
		return String(model[model.index(after: slash)...])
	}

	/// The emitted id without its vendor prefix, `[1m]` selector, and snapshot date. Case preserved.
	public static func undecorated(_ model: String) -> String {
		let id = withoutSelector(withoutVendorPrefix(model))
		guard let date = id.range(of: snapshotDatePattern, options: .regularExpression) else { return id }
		return String(id[..<date.lowerBound])
	}

	/// The snapshot date as `YYYYMMDD`, or nil when the id carries none.
	public static func snapshotDate(_ model: String) -> Int? {
		let id = withoutSelector(withoutVendorPrefix(model))
		guard let date = id.range(of: snapshotDatePattern, options: .regularExpression) else { return nil }
		return Int(id[date].filter(\.isNumber))
	}

	/// The id `PricingTable` retries after an exact miss: undecorated, lowercased, then aliased.
	/// Accounting and free-tier suffixes are kept, because they select (or deny) a rate.
	static func pricingID(_ model: String, aliases: [String: String]) -> String {
		let id = undecorated(model).lowercased()
		return aliases[id] ?? id
	}

	/// The accounting id for a Claude fast-mode turn: the undecorated model plus `-fast-mode`, so a
	/// `[1m]` selector or snapshot date can never hide the suffix from pricing.
	public static func fastModeID(_ model: String) -> String {
		undecorated(model) + AccountingSuffix.fastMode
	}

	/// The accounting id for a Claude US-only inference turn: the undecorated id (fast-mode id
	/// included) plus `-us-inference`.
	public static func usInferenceID(_ model: String) -> String {
		undecorated(model) + AccountingSuffix.usInference
	}

	/// Rate-independent identity for grouping and display: undecorated, with any accounting suffix
	/// removed. Keeps the free-tier suffix and the original case.
	public static func presentationID(_ model: String) -> String {
		var id = undecorated(model)
		id = removingSuffix(AccountingSuffix.usInference, from: id)
		id = removingSuffix(AccountingSuffix.fastMode, from: id)
		id = removingSuffix(AccountingSuffix.peak, from: id)
		for route in AccountingSuffix.routes {
			let stripped = removingSuffix(route, from: id)
			if stripped != id { return stripped }
		}
		return id
	}

	/// Model-level key for classification tables (`ModelEffort.levels`): the presentation id,
	/// lowercased, without its free-tier suffix, then aliased to its canonical row.
	public static func modelKey(_ model: String, aliases: [String: String] = bundledAliases) -> String {
		let id = removingSuffix(freeTierSuffix, from: presentationID(model).lowercased())
		return aliases[id] ?? id
	}

	/// The alias map shipped in `pricing-default.json`, read from the one bundled decode. Empty only if
	/// the bundled resource is missing, which `PricingTableTests` treats as a failure.
	public static let bundledAliases: [String: String] = PricingTable.bundledDefault().aliases

	private static func withoutSelector(_ id: String) -> String {
		id.hasSuffix(contextSelector) ? String(id.dropLast(contextSelector.count)) : id
	}

	private static func removingSuffix(_ suffix: String, from id: String) -> String {
		guard id.count > suffix.count, id.hasSuffix(suffix) else { return id }
		return String(id.dropLast(suffix.count))
	}
}
