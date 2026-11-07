import Foundation
import SwiftUI
import JPtheCatCore

// Extracted from DashboardView.swift: the provider-focus detail bay — the single most-edited surface
// for provider work, ~20 private helpers deep, and the reason that file had grown past 2,600 lines.
// It renders one `DashboardViewModel.ProviderRow` and owns no dashboard state, so the split is a pure
// move: rate-limit gauges, local-activity metrics, context-token composition, the per-model list, and
// the window trend strip, plus the gauge meter they draw with.

// MARK: - Provider detail (official usage gauges when the provider exposes them)

struct ProviderDetail: View {
	let row: DashboardViewModel.ProviderRow
	let days: Int
	/// A Zen or Go section inside the one OpenCode row. The parent owns the scope note and the links.
	var embedded: Bool = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.dashboardLayout) private var layout
	// OpenCode's console link is per-workspace; the ID comes from OpenCode's own log (cached by file
	// state in Core), refreshed on appear so a new login is picked up without an app restart.
	@State private var openCodeWorkspaceID: String? = OpenCodeWorkspace.currentID()

	var body: some View {
		detailContent
			.padding(.horizontal, embedded ? 0 : JPAppSpacing.contentX)
			.padding(.vertical, embedded ? 0 : JPAppSpacing.sectionY)
			.frame(maxWidth: .infinity, alignment: .leading)
			.onAppear {
				guard !embedded else { return }
				openCodeWorkspaceID = OpenCodeWorkspace.currentID()
			}
	}

	@ViewBuilder private var detailContent: some View {
		if !embedded, !row.sourceSections.isEmpty {
			VStack(alignment: .leading, spacing: 11) {
				if let note = row.sourceScopeNote { scopeNoteView(note) }
				usageLink
				ForEach(row.sourceSections) { section in
					ProviderDetail(row: section, days: days, embedded: true)
				}
			}
		} else {
			VStack(alignment: .leading, spacing: 11) {
				if embedded {
					Text(row.name)
						.font(JPAppFont.labelMedium)
						.foregroundStyle(JP.inkSoft)
				}
				defaultProviderDetail
			}
		}
	}

	@ViewBuilder private var defaultProviderDetail: some View {
		if let insight = signatureInsight { calloutView(insight) }
		if !embedded, let note = row.sourceScopeNote { scopeNoteView(note) }
		if let plan = row.cursorPlan, !row.isOfficialPlanOnly || !row.detailPlanMeters().isEmpty {
			cursorPlanMeters(plan)
		}
		// Lead with reported or measured windows; retain each source's honest badge and reset.
		if (row.detailShowsPrimaryWindow && row.usedPct != nil) || (row.detailShowsWeeklyWindow && row.weeklyUsedPct != nil) || row.monthlyUsedPct != nil || !row.modelWindows.isEmpty { usageWindows }
		if row.awaitingResetRefresh { resetHintView }
		if let credits = row.codexCredits { creditBalance(credits) }
		// Official plan meters above already answer "what does my plan say"; the local token section
		// below keeps its own "locally observed" wording.
		if row.isFullyUnpriced && row.cursorPlan == nil { localOnlyNotice }
		if !embedded { usageLink }
		if hasLocalActivity {
			localUsageSummary
			compositionBar
		}
		if !row.byModel7d.isEmpty { modelList }
		if let aiu = row.aiuWindow { aiuLine(aiu) }
		if hasLocalActivity { trendStrip }
		// A fully-unpriced row already shows its real token count instead of a dollar figure above —
		// nothing is silently hidden, so this note would be redundant. Only show it for a row with a
		// MIX of priced and unpriced models, where the dollar total is real but an undercount.
		if !row.unpricedModels.isEmpty, !row.isFullyUnpriced, let disclosure = pricingDisclosure(for: row.unpricedModels) {
				Text(disclosure)
					.font(JPAppFont.caption).foregroundStyle(JP.gingerDeep)
				.fixedSize(horizontal: false, vertical: true)
		}
	}

	/// Grok can exist from opt-in plan meters alone (no local logs or hook data). Then the local
	/// token cards would read as a wall of zeros, so they hide instead.
	private var hasLocalActivity: Bool {
		return !row.isOfficialPlanOnly && (row.weekEvents > 0 || row.todayEvents > 0)
	}

	private func creditBalance(_ credits: CodexCreditBalance) -> some View {
		VStack(alignment: .leading, spacing: JPAppSpacing.rowY) {
			HStack(alignment: .firstTextBaseline) {
				Text("Credits remaining").font(JPAppFont.labelMedium).foregroundStyle(JP.inkSoft)
				Spacer(minLength: JPAppSpacing.rowY)
				Text(credits.displayValue).font(JPAppFont.metricSmall).foregroundStyle(JP.ink)
					.monospacedDigit().fixedSize(horizontal: false, vertical: true)
			}
			Text("Separate from the included allowance and notional dollars.")
				.font(JPAppFont.caption).foregroundStyle(JP.inkFaint)
				.fixedSize(horizontal: false, vertical: true)
			if let capturedAt = row.creditsCapturedAt {
				Text("Reported \(capturedAt.formatted(date: .abbreviated, time: .shortened))")
					.font(JPAppFont.caption).foregroundStyle(JP.inkFaint)
			}
		}
		.accessibilityElement(children: .combine)
	}

	/// Cursor's official plan meters, exactly as Cursor's own dashboard reports them: Cursor Models,
	/// Other Models, and Grok Bot weekly, each with its own reset countdown. Badged `official`.
	private func cursorPlanMeters(_ plan: CursorPlanUsage) -> some View {
		let meters = row.detailPlanMeters()
		return VStack(alignment: .leading, spacing: 8) {
			Text(plan.detailHeader(providerName: row.name))
				.font(JPAppFont.labelMedium)
				.foregroundStyle(JP.inkSoft)
			if !meters.isEmpty {
				DashboardDetailGrid(columnCount: meters.count == 1 ? 1 : 2) {
					ForEach(meters) { meter in
						VStack(alignment: .leading, spacing: 8) {
							gauge(meter.label, pct: meter.usedPercent, official: true)
							resetLine(meter.resetsAt)
						}
					}
				}
			}
		}
	}

	private var localOnlyNotice: some View {
		HStack(alignment: .top, spacing: 7) {
			Image(systemName: "externaldrive.fill")
				.font(JPAppFont.caption)
				.foregroundStyle(JP.providerTint(row.tintHex))
				.frame(width: 14)
			Text("Local activity only · Not \(row.name) plan or billing usage")
				.font(JPAppFont.labelStrong)
				.foregroundStyle(JP.ink)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(.horizontal, JPAppSpacing.noticeX).padding(.vertical, JPAppSpacing.noticeY)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(JP.paper, in: RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous)
			.strokeBorder(JP.lineStrong, lineWidth: 1))
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Local activity only. Not \(row.name) plan or billing usage.")
	}

	@ViewBuilder private var usageLink: some View {
		if let sentence = OfficialUsageLink.sentence(
			for: row.id, openCodeWorkspaceID: openCodeWorkspaceID)
		{
			Text(sentence.attributed())
				.font(JPAppFont.labelStrong)
				.foregroundStyle(JP.gingerDeep)
				.tint(JP.gingerDeep)
				.fixedSize(horizontal: false, vertical: true)
				.help("Opens the provider's official usage page")
		}
	}

	// MARK: Signature insight (JP's opinion — one combined, surprising number)

	/// Codex → 5-hour burn pace (official windows). Claude → the model that eats a disproportionate
	/// share of the bill. Returns nil (and the callout collapses) when neither is honestly computable.
	private var signatureInsight: (text: String, estimate: Bool)? {
		// Decision logic (thresholds, verdicts, the 0.10 cutoff) lives in Core `SignatureInsight` and is
		// unit-tested there; the View only turns the structured result into wording.
		guard let insight = SignatureInsight.compute(
			limitLikelyHit: row.limitLikelyHit,
			usedPct: row.usedPct,
			resetsAt5h: row.resetsAt5h,
			windowMinutes5h: row.windowMinutes5h,
			week: row.week,
			weekEvents: row.weekEvents,
			models: row.byModel7d.map { .init(model: $0.model, cost: $0.cost, eventCount: $0.eventCount) },
			now: Date())
		else { return nil }
		let text: String
		switch insight {
		case let .limitFrozen(used):
			text = "Estimated at 100% — Claude's last official reading froze at \(pct0(used)) because Claude only refreshes it when it answers."
		case let .burnPace(used, elapsed, verdict):
			let verdictText = switch verdict {
			case .runningHot: "running hot"
			case .wellUnderPace: "well under pace"
			case .onPace: "on pace"
			}
			text = "\(pct0(used)) used, \(pct0(elapsed * 100)) of the 5-hour window gone — \(verdictText)."
		case let .costConcentration(model, turnShare, billShare):
			let basis = row.notional ? "notional cost" : "bill"
			text = "\(shortModel(model)) ran \(pct0(turnShare * 100)) of your turns but \(pct0(billShare * 100)) of the \(basis)."
		}
		return (text, insight.isEstimate)
	}

	private func calloutView(_ insight: (text: String, estimate: Bool)) -> some View {
		HStack(alignment: .top, spacing: 7) {
			Circle().fill(JP.sage).frame(width: 6, height: 6).padding(.top, 4)
				Text(insight.text)
					.font(JPAppFont.labelStrong).foregroundStyle(JP.ink)
				.fixedSize(horizontal: false, vertical: true)
			Spacer(minLength: 0)
			if insight.estimate { estBadge }
		}
		.padding(.horizontal, JPAppSpacing.noticeX).padding(.vertical, JPAppSpacing.noticeY)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(JP.sage.opacity(0.12), in: RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous).strokeBorder(JP.sage.opacity(0.55), lineWidth: 1))
	}

	/// AIU consumption over the window — Copilot's real billing unit (`github.copilot.nano_aiu`).
	/// A raw consumption count, deliberately NOT dollars and NOT a quota %: Copilot exposes neither a
	/// priced model id (`model = "auto"`) nor a local quota ceiling, so AIU is the honest local signal.
	/// Styled in the row's own viz tint (Copilot purple), matching the `estimate` badge — a different
	/// KIND of number than the shared dollar/notional surfaces.
	private func aiuLine(_ aiu: Double) -> some View {
		let tint = JP.providerTint(row.tintHex)
		let value = formatAIU(aiu)
		return HStack(alignment: .firstTextBaseline, spacing: 7) {
			Circle().fill(tint).frame(width: 6, height: 6)
			Text("AIU used · \(days) days")
				.font(JPAppFont.labelStrong).foregroundStyle(JP.ink)
			Spacer(minLength: 6)
			Text(value)
				.font(JPAppFont.metricSmall).foregroundStyle(tint)
				.monospacedDigit()
		}
		.padding(.horizontal, JPAppSpacing.noticeX).padding(.vertical, JPAppSpacing.noticeY)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("AIU used over \(days) days: \(value). A consumption count, not a dollar amount or a quota percentage.")
	}

	private func formatAIU(_ value: Double) -> String {
		let rounded = (value * 100).rounded() / 100
		let number = rounded.rounded() == rounded ? String(Int(rounded)) : String(rounded)
		return "\(number) AIU"
	}

	private func scopeNoteView(_ text: String) -> some View {
		HStack(alignment: .top, spacing: 7) {
			Circle().fill(JP.gingerDeep).frame(width: 6, height: 6).padding(.top, 4)
			Text(text)
				.font(JPAppFont.labelStrong).foregroundStyle(JP.ink)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(.horizontal, JPAppSpacing.noticeX).padding(.vertical, JPAppSpacing.noticeY)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(JP.gingerDeep.opacity(0.08), in: RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous).strokeBorder(JP.gingerDeep.opacity(0.35), lineWidth: 1))
		.accessibilityLabel("Data scope: \(text)")
	}

	/// Shown when the provider's official window just rolled past its reset boundary and no fresher
	/// reading has arrived yet. The gauge is blank because the window RESET — not because there's no data
	/// — so instead of the % silently vanishing (which read as "the bars randomly reset"), we say so
	/// plainly. Never fabricates a replacement number: JP genuinely doesn't know the new % until the
	/// provider next emits one (Codex on its next turn, Claude/Grok on the next capture).
	private var resetHintView: some View {
		HStack(alignment: .top, spacing: 7) {
			Circle().fill(JP.sage).frame(width: 6, height: 6).padding(.top, 4)
			Text("Limit window just reset — waiting for \(row.name) to report the new percentage.")
				.font(JPAppFont.labelStrong).foregroundStyle(JP.ink)
				.fixedSize(horizontal: false, vertical: true)
			Spacer(minLength: 0)
		}
		.padding(.horizontal, JPAppSpacing.noticeX).padding(.vertical, JPAppSpacing.noticeY)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(JP.sage.opacity(0.10), in: RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous).strokeBorder(JP.sage.opacity(0.45), lineWidth: 1))
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Limit window just reset. Waiting for \(row.name) to report the new percentage. No number is shown because it is not yet known.")
	}

	// MARK: Reported and measured windows with their own reset countdowns

	private var usageWindows: some View {
		VStack(alignment: .leading, spacing: 11) {
			// Two columns place the full-width monthly bar above the shorter pair; one column keeps
			// the natural short-to-long order.
			if layout == .twoColumns { monthlyGauge }
			if (row.detailShowsPrimaryWindow && row.usedPct != nil) || (row.detailShowsWeeklyWindow && row.weeklyUsedPct != nil) {
				DashboardDetailGrid(columnCount: row.detailShowsPrimaryWindow && row.usedPct != nil && row.detailShowsWeeklyWindow && row.weeklyUsedPct != nil ? 2 : 1) {
					if row.detailShowsPrimaryWindow, let pct = row.usedPct {
						VStack(alignment: .leading, spacing: 8) {
							gauge(windowLabel(row.windowMinutes5h, fallback: "5-hour"),
								pct: row.limitLikelyHit ? 100 : pct,
								official: row.usageOfficial && !row.limitLikelyHit,
								badgeWord: isGatewayRow ? "measured" : nil)
							resetLine(row.resetsAt5h)
						}
					}
					if row.detailShowsWeeklyWindow, let weekly = row.weeklyUsedPct {
						VStack(alignment: .leading, spacing: 8) {
							gauge(windowLabel(row.windowMinutesWeekly, fallback: "7-day"), pct: weekly,
								official: row.usageOfficial, badgeWord: isGatewayRow ? "measured" : nil)
							resetLine(row.resetsAtWeekly)
						}
					}
				}
			}
			if layout == .oneColumn { monthlyGauge }
			// Reported model limits belong below plan windows, most-used first.
			// An empty feed renders nothing, never a fabricated zero-percent gauge.
			if !row.modelWindows.isEmpty {
				DashboardDetailGrid(columnCount: row.modelWindows.count == 1 ? 1 : 2) {
					ForEach(ProviderDetailLayout.windowsByUsage(row.modelWindows)) { scoped in
						VStack(alignment: .leading, spacing: 8) {
							gauge("\(scoped.label) · 7-day window used",
								pct: scoped.window.usedPercent, official: true)
							resetLine(scoped.window.resetsAt)
						}
					}
				}
			}
		}
	}

	/// Monthly remains measured and has no invented reset boundary.
	@ViewBuilder private var monthlyGauge: some View {
		if let monthly = row.monthlyUsedPct {
			gauge(windowLabel(row.monthlyWindowMinutes, fallback: "30-day"), pct: monthly,
				official: row.usageOfficial && !row.quotaIsMeasured,
				badgeWord: isGatewayRow ? "measured" : nil)
		}
	}

	@ViewBuilder private func resetLine(_ date: Date?) -> some View {
		if let phrase = ProviderRelativeReset.resetsInPhrase(until: date) {
			Text(phrase).font(JPAppFont.micro).foregroundStyle(JP.inkFaint)
		}
	}

	private func windowLabel(_ minutes: Int?, fallback: String) -> String {
		row.detailWindowLabel(minutes, fallback: fallback)
	}

	private var localActivityTitle: String {
		let kind = row.usesTokenDisplay ? "local token activity" : "local activity"
		if embedded { return kind.prefix(1).uppercased() + kind.dropFirst() }
		return "\(row.name) \(kind)"
	}

	private var localUsageSummary: some View {
		VStack(alignment: .leading, spacing: 7) {
				Text(localActivityTitle)
					.font(JPAppFont.labelMedium)
				.foregroundStyle(JP.inkSoft)
			HStack(spacing: 8) {
				metric(
					row.usesTokenDisplay ? "Tokens · today" : "Today", value: row.usesTokenDisplay ? TokenFormatter.compact(row.todayUsage.total) : dollars(row.today),
					caption: row.usesTokenDisplay ? "\(row.todayEvents) turns" : "\(compact(row.todayUsage.total)) tok · \(row.todayEvents) turns")
				metric(
					row.usesTokenDisplay ? "Tokens · \(days) days" : "\(days) days", value: row.usesTokenDisplay ? TokenFormatter.compact(row.weekUsage.total) : dollars(row.week),
					caption: row.usesTokenDisplay ? "\(row.weekEvents) turns" : "\(compact(row.weekUsage.total)) tok · \(row.weekEvents) turns")
			}
			HStack(spacing: 8) {
				metric(row.usesTokenDisplay ? "Cached context" : "Cache hit", value: cacheHitPct.map(pct0) ?? "—", caption: "of context from cache")
				secondaryCard
			}
			statsLine
			runRateStrip
				Text(
					row.usesTokenDisplay
						? "JP counts locally observed tokens. The provider calculates plan usage separately."
						: (row.notional ? "Notional list-price dollars from local usage logs." : "Real-dollar spend from local usage logs."))
					.font(JPAppFont.caption)
				.foregroundStyle(JP.inkFaint)
				.lineLimit(2)
		}
	}

	/// Prefers the delightful "cache saved you $X" when there were priced cache reads; otherwise falls
	/// back to cost-per-turn so the card never goes empty. A fully-unpriced row has no dollar figure at
	/// all, so it shows tokens-per-turn instead of a dead "—".
	@ViewBuilder private var secondaryCard: some View {
		if let saved = row.cacheSavings7d {
			metric("Saved by cache", value: MoneyFormatter.dollars(saved, code: row.currencyCode), caption: row.notional ? "est. · notional" : "est. vs no cache")
		} else if row.usesTokenDisplay, let tpt = tokensPerTurn {
			metric("Context / turn", value: compact(tpt), caption: "\(days)-day average")
		} else if let cpt = costPerTurn {
			metric("Cost / turn", value: MoneyFormatter.dollars(cpt, decimals: 3, code: row.currencyCode), caption: "\(days)-day average")
		} else {
			metric("Cost / turn", value: "—", caption: "\(days)-day average")
		}
	}

	private var statsLine: some View {
		let parts: [String] = [
			blendedPer1M.map { "\(MoneyFormatter.dollars($0, code: row.currencyCode))/1M tok" },
			tokensPerTurn.map { "\(compact($0)) tok/turn" },
			outputSharePct.map { "\(pct0($0)) generated output" },
		].compactMap { $0 }
			return Text(parts.joined(separator: " · "))
				.font(JPAppFont.caption).foregroundStyle(JP.inkFaint)
			.lineLimit(1).minimumScaleFactor(0.8)
	}

	@ViewBuilder private var runRateStrip: some View {
		if let rr = runRate30 {
				HStack(spacing: 6) {
					Text("At this pace").font(JPAppFont.caption).foregroundStyle(JP.inkFaint)
					Spacer(minLength: 4)
					Text("~\(MoneyFormatter.dollars(rr, decimals: rr < 1 ? 2 : 0, code: row.currencyCode)) / 30 days")
						.font(JPAppFont.metricSmall).foregroundStyle(JP.ink)
				estBadge
			}
		}
	}

	// MARK: Input-side token composition (finally exposes the 5m vs 1h cache-write split)

	private var compositionBar: some View {
		let read = row.weekUsage.cacheRead
		let w5 = row.weekUsage.cacheCreate5m
		let w1 = row.weekUsage.cacheCreate1h
		let fresh = row.weekUsage.input
		let denom = read + w5 + w1 + fresh
		return VStack(alignment: .leading, spacing: 5) {
				HStack {
					Text("Context tokens · \(days) days").font(JPAppFont.caption).foregroundStyle(JP.inkSoft)
					Spacer()
					Text(cacheHitPct.map { "\(pct0($0)) cached" } ?? "")
						.font(JPAppFont.captionMono).foregroundStyle(JP.inkFaint)
			}
			GeometryReader { geo in
				HStack(spacing: 0) {
					if denom > 0 {
						barSeg(read, denom, JP.sage.opacity(0.9), geo.size.width)
						barSeg(w5, denom, JP.honey, geo.size.width)
						barSeg(w1, denom, JP.gingerDeep.opacity(0.85), geo.size.width)
						barSeg(fresh, denom, JP.ginger.opacity(0.85), geo.size.width)
					} else {
						Rectangle().fill(JP.trackFill)
					}
				}
			}
			.frame(height: 8).clipShape(Capsule())
				Text("read \(compact(read)) · write 5m \(compact(w5)) · write 1h \(compact(w1)) · fresh \(compact(fresh))")
					.font(JPAppFont.micro).foregroundStyle(JP.inkFaint).lineLimit(2)
		}
	}

	private func barSeg(_ value: Int, _ denom: Int, _ color: Color, _ width: CGFloat) -> some View {
		Rectangle().fill(color).frame(width: denom > 0 ? width * CGFloat(value) / CGFloat(denom) : 0)
	}

	// MARK: Per-model mini-list (the single biggest "data left behind" win)

	private var modelList: some View {
		VStack(alignment: .leading, spacing: 5) {
				HStack {
					Text("By model · \(days) days").font(JPAppFont.caption).foregroundStyle(JP.inkSoft)
					Spacer()
			}
			// Same order and figures in both layouts; only the row shape changes.
			if layout == .oneColumn {
				ForEach(ProviderDetailLayout.modelsByUsage(row.byModel7d)) { line in compactModelRow(line) }
			} else {
				DashboardDetailGrid {
					ForEach(ProviderDetailLayout.modelsByUsage(row.byModel7d)) { line in modelTile(line) }
				}
			}
		}
	}

	/// Two-column tile: the name wraps above its meter.
	private func modelTile(_ line: DashboardViewModel.ModelLine) -> some View {
		VStack(alignment: .leading, spacing: 5) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				modelName(line)
					.frame(maxWidth: .infinity, alignment: .leading)
					.fixedSize(horizontal: false, vertical: true)
				modelAmount(line)
			}
			HStack(spacing: 8) {
				modelMeter(line)
				effortSlot(line)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.accessibilityElement(children: .combine)
	}

	/// One-column row: name, meter, amount, and effort share one line, as in the compact card.
	/// The name keeps one third of the card and wraps rather than truncating.
	private func compactModelRow(_ line: DashboardViewModel.ModelLine) -> some View {
		HStack(spacing: 8) {
			modelName(line)
				.frame(width: DashboardLayout.oneColumn.width / 3, alignment: .leading)
				.fixedSize(horizontal: false, vertical: true)
			modelMeter(line)
			modelAmount(line)
				.frame(minWidth: 78, alignment: .trailing)
			effortSlot(line)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.accessibilityElement(children: .combine)
	}

	private func modelName(_ line: DashboardViewModel.ModelLine) -> some View {
		Text(shortModel(line.model))
			.font(JPAppFont.label).foregroundStyle(JP.inkSoft)
			.help(line.model)
	}

	@ViewBuilder private func modelAmount(_ line: DashboardViewModel.ModelLine) -> some View {
		if let cost = line.cost {
			Text(MoneyFormatter.dollars(cost, code: row.currencyCode))
				.font(JPAppFont.metricSmall).foregroundStyle(JP.ink)
				.fixedSize()
		} else {
			Text("\(compact(line.usage.total)) tok")
				.font(JPAppFont.micro).foregroundStyle(JP.gingerDeep)
				.fixedSize()
		}
	}

	private func modelMeter(_ line: DashboardViewModel.ModelLine) -> some View {
		Capsule().fill(JP.trackFill).frame(height: 5)
			.overlay(Capsule().strokeBorder(JP.inkFaint.opacity(0.5), lineWidth: 1))
			.overlay(alignment: .leading) {
				GeometryReader { geo in
					Capsule().fill(JP.providerTint(row.tintHex).opacity(JP.barFillOpacity))
						.frame(width: max(2, geo.size.width * modelShare(line)))
				}
			}
			.frame(minWidth: 20)
			.help("\(compact(line.usage.total)) tokens · relative to the most-used model")
	}

	@ViewBuilder private func effortSlot(_ line: DashboardViewModel.ModelLine) -> some View {
		if let level = effortLevel(line.model) {
			effortChip(level: level)
		} else {
			// An unclassified model shows no tier. The empty slot keeps every meter length and row
			// height equal to a row that carries a chip.
			Color.clear.frame(width: 42, height: LabelBadgeMetrics.height).accessibilityHidden(true)
		}
	}

	private func effortChip(level: ModelEffortLevel) -> some View {
		Text(level.label)
			.font(JPAppFont.micro)
			.lineLimit(1)
			.foregroundStyle(level.foregroundColor)
			.labelBadgeLayout()
			.frame(minWidth: 42, alignment: .center)
			.background(level.backgroundColor, in: RoundedRectangle(cornerRadius: JPAppRadius.chip))
			.overlay(
				RoundedRectangle(cornerRadius: JPAppRadius.chip)
					.strokeBorder(level.borderColor, lineWidth: 0.7)
			)
	}

	private enum ModelEffortLevel: Sendable {
		case low, medium, high

		var label: String {
			switch self {
			case .low: "Low"
			case .medium: "Medium"
			case .high: "High"
			}
		}

		var backgroundColor: Color {
			switch self {
			case .low: JP.paper2.opacity(0.8)
			case .medium: JP.paper.opacity(0.95)
			case .high: JP.honey.opacity(0.18)
			}
		}

		var borderColor: Color {
			switch self {
			case .low: JP.line
			case .medium: JP.line
			case .high: JP.honey.opacity(0.75)
			}
		}

		var foregroundColor: Color {
			switch self {
			case .low: JP.inkSoft
			case .medium: JP.inkSoft
			case .high: JP.gingerDeep
			}
		}
	}

	/// Classification lives in Core (`ModelEffort`, guarded against web drift by `ModelEffortTests`);
	/// the SwiftUI chip colors below stay App-side. Map the Core tier to the App enum that carries them,
	/// or nil for a model Core does not classify.
	private func effortLevel(_ model: String) -> ModelEffortLevel? {
		switch ModelEffort.level(for: model) {
		case .low: .low
		case .medium: .medium
		case .high: .high
		case nil: nil
		}
	}

	private func modelMetric(_ line: DashboardViewModel.ModelLine) -> Double {
		Double(line.usage.total)
	}

	private var maxModelMetric: Double {
		row.byModel7d.map(modelMetric).max() ?? 0
	}

	/// Token usage is scaled against the most-used model, matching the tile order. A dominant model
	/// no longer crushes smaller-but-real usage into an invisible sliver; a small headroom
	/// floor keeps any nonzero model visibly present, mirroring `SparklineScale`'s approach.
	private func modelShare(_ line: DashboardViewModel.ModelLine) -> Double {
		let value = modelMetric(line)
		let maxValue = maxModelMetric
		guard value > 0, maxValue > 0 else { return 0 }
		let headroom = 0.06
		return min(1, max(0, headroom + (1 - headroom) * (value / maxValue)))
	}

	// MARK: window trend (annotates the sparkline with real extrema + an honest delta)

	/// A fully-unpriced row (Copilot) charts/annotates tokens instead of dollars — its cost series is
	/// a dead all-zero line, so both the trend strip and the peak-day callout would otherwise read
	/// "wk $0.00" / no peak at all despite real activity.
	private var trendSeries: [Double] { row.usesTokenDisplay ? row.tokenSeries : row.series }
	private var trendTotal: Double { row.usesTokenDisplay ? Double(row.weekUsage.total) : row.week }
	private var trendToday: Double { row.usesTokenDisplay ? Double(row.todayUsage.total) : (row.today ?? row.series.last ?? 0) }
	private func trendAmount(_ value: Double) -> String {
		row.usesTokenDisplay ? TokenFormatter.compact(Int(value)) : money(value)
	}

	private var trendStrip: some View {
		let avg = trendTotal / Double(max(days, 1))
		return HStack(spacing: 8) {
			Text("wk \(trendAmount(trendTotal))").font(JPAppFont.micro).foregroundStyle(JP.inkFaint)
			Spacer(minLength: 0)
			Text(row.usesTokenDisplay ? "\(signedTokens(trendToday - avg)) vs daily avg" : "\(signed(trendToday - avg)) vs avg")
				.font(JPAppFont.microMedium).foregroundStyle(JP.inkSoft)
			Spacer(minLength: 0)
			if let peak = peakDay {
				Text("peak \(trendAmount(peak.value)) \(peak.weekday)").font(JPAppFont.micro).foregroundStyle(JP.inkFaint)
			}
		}
	}

	/// Same "±N" shape as `signed(_:)` (dollars) but for a whole-number token delta.
	private func signedTokens(_ value: Double) -> String {
		let magnitude = TokenFormatter.compact(Int(abs(value).rounded()))
		if abs(value) < 1 { return "±\(magnitude)" }
		return value > 0 ? "+\(magnitude)" : "-\(magnitude)"
	}

	/// Cached exactly like the Advanced Analytics window's `shortWeekdayFormatter`/`drillDayFormatter`:
	/// `peakDay` is read from `trendStrip`, i.e. from the render path, and constructing a
	/// `DateFormatter` spins up a fresh ICU formatter every `body` pass. Never move this back inside.
	private static let peakWeekdayFormatter: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "EEE"
		return f
	}()

	private var peakDay: (value: Double, weekday: String)? {
		guard let maxV = trendSeries.max(), maxV > 0, let idx = trendSeries.firstIndex(of: maxV) else { return nil }
		let offset = (trendSeries.count - 1) - idx  // rightmost point == today
		let today = Calendar.current.startOfDay(for: Date())
		guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { return nil }
		return (maxV, Self.peakWeekdayFormatter.string(from: date))
	}

	// MARK: Derived metrics (all computable from real ProviderRow fields)

	/// Input-side context total (matches CostCalculator's context definition; output excluded).
	private var contextTokens: Int {
		row.weekUsage.input + row.weekUsage.cacheRead + row.weekUsage.cacheCreate5m + row.weekUsage.cacheCreate1h
	}
	private var cacheHitPct: Double? {
		contextTokens > 0 ? 100 * Double(row.weekUsage.cacheRead) / Double(contextTokens) : nil
	}
	private var costPerTurn: Double? { row.weekEvents > 0 && row.week > 0 ? row.week / Double(row.weekEvents) : nil }
	private var blendedPer1M: Double? {
		row.weekUsage.total > 0 && row.week > 0 ? row.week / (Double(row.weekUsage.total) / 1_000_000) : nil
	}
	private var tokensPerTurn: Int? { row.weekEvents > 0 ? row.weekUsage.total / row.weekEvents : nil }
	private var outputSharePct: Double? {
		let io = row.weekUsage.input + row.weekUsage.output
		return io > 0 ? 100 * Double(row.weekUsage.output) / Double(io) : nil
	}
	private var runRate30: Double? { row.week > 0 ? row.week / Double(max(days, 1)) * 30 : nil }

	private var estBadge: some View {
			Text("est.").font(JPAppFont.microMedium)
			.labelBadgeLayout()
			.background(JP.honey.opacity(0.2), in: RoundedRectangle(cornerRadius: JPAppRadius.chip))
			.foregroundStyle(JP.gingerDeep)
	}

	private func pct0(_ value: Double) -> String { String(format: "%.0f%%", value) }
	private func money(_ value: Double) -> String { MoneyFormatter.dollars(value, code: row.currencyCode) }

	private func signed(_ value: Double) -> String {
		let magnitude = MoneyFormatter.dollars(abs(value), code: row.currencyCode)
		if abs(value) < 0.005 { return "±\(magnitude)" }
		return (value > 0 ? "+" : "-") + magnitude
	}

	/// Drops a trailing `-YYYYMMDD` snapshot date and a known vendor prefix so "claude-opus-4-5-20251101"
	/// reads as "opus-4-5" in the tight name column. Recipe lives in Core `ModelName.short`.
	private func shortModel(_ model: String) -> String { ModelName.short(model) }

	private func metric(_ label: String, value: String, caption: String) -> some View {
		VStack(alignment: .leading, spacing: 2) {
				Text(label)
					.font(JPAppFont.eyebrow)
				.foregroundStyle(JP.gingerDeep)
				Text(value)
					.font(JPAppFont.metricValue)
				.foregroundStyle(JP.ink)
				Text(caption)
					.font(JPAppFont.micro)
				.foregroundStyle(JP.inkFaint)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, JPAppSpacing.metricCardX)
		.padding(.vertical, JPAppSpacing.metricCardY)
		.background(JP.paper.opacity(0.82), in: RoundedRectangle(cornerRadius: JPAppRadius.metricCard, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: JPAppRadius.metricCard, style: .continuous)
				.strokeBorder(JP.line.opacity(0.85), lineWidth: 0.5))
	}

	// Token-count "53.6K"/"1.2M" formatting reuses Core's `TokenFormatter.compact(_:)` —
	// this used to be a byte-identical private copy.
	private func compact(_ value: Int) -> String { TokenFormatter.compact(value) }

	private func dollars(_ value: Double?) -> String {
		guard let value else { return "unpriced" }
		return MoneyFormatter.dollars(value, code: row.currencyCode)
	}

	private func gauge(_ label: String, pct: Double, official: Bool, badgeWord: String? = nil) -> some View {
		// A GATEWAY (OpenCode Go) window is measured local cost against a published cap, NOT a
		// provider-reported percentage — so it reads "measured", never "official".
		let word = badgeWord ?? (official ? "official" : "est.")
		let officialTone = official && badgeWord == nil
		return VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text(label).font(JPAppFont.label).foregroundStyle(JP.inkSoft)
				Spacer()
					Text(String(format: "%.0f%%", pct))
						.font(JPAppFont.metricSmall).foregroundStyle(JP.ink)
					Text(word).font(JPAppFont.microMedium)
					.labelBadgeLayout()
					.background((officialTone ? JP.sage : JP.honey).opacity(0.2), in: RoundedRectangle(cornerRadius: JPAppRadius.chip))
					.foregroundStyle(officialTone ? JP.sageDeep : JP.gingerDeep)
			}
			GaugeBar(fraction: max(0, min(1, pct / 100)), tint: JP.providerTint(row.tintHex), reduceMotion: reduceMotion)
				.frame(height: 8)
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(label)
		.accessibilityValue("\(Int(pct.rounded()))% used, \(word), \(gaugeThreshold(pct))")
	}

	/// OpenCode Zen / Go are `ProviderBasis.gateway` rollups.
	private var isGatewayRow: Bool { ProviderBasis.of(rawID: row.id) == .gateway }

	/// Threshold word matching the calm/watch/alert gauge semantics so VoiceOver conveys the
	/// state, not just the length/color of the bar.
	private func gaugeThreshold(_ pct: Double) -> String {
		pct >= 90 ? "near or over limit" : pct >= 70 ? "approaching limit" : "healthy headroom"
	}
}

/// A fixed-height meter whose fill animates left-to-right by WIDTH only. The height never
/// animates, so the bar can't appear to "drop in from above" during window resizes/crossfades —
/// the only motion is the fill sweeping right.
private struct GaugeBar: View {
	let fraction: Double
	let tint: Color
	let reduceMotion: Bool
	@State private var animated: Double = 0

	var body: some View {
		GeometryReader { geo in
			ZStack(alignment: .leading) {
				Capsule().fill(JP.trackFill)
					.overlay(Capsule().strokeBorder(JP.inkFaint.opacity(0.5), lineWidth: 1))
				Capsule().fill(tint.opacity(0.85))
					.frame(width: max(0, geo.size.width * animated))
			}
			.frame(height: geo.size.height, alignment: .center)
		}
		.onAppear {
			if reduceMotion { animated = fraction }
			else { withAnimation(.easeOut(duration: 0.5)) { animated = fraction } }
		}
		.onChange(of: fraction) { _, next in
			if reduceMotion { animated = next }
			else { withAnimation(.easeOut(duration: 0.35)) { animated = next } }
		}
	}
}
