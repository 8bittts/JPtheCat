import Foundation
import AppKit
import SwiftUI
import JPtheCatCore

// Compact "53.6K" / "1.2M" token formatting lives in Core as `TokenFormatter.compact(_:suffix:)`
// — the dashboard, the menu-bar tooltip, and the widget faces all route through that one ladder.
// No unit suffix here: a dollar figure never appends "usd" either, and the surrounding label already
// makes the unit clear (these only ever appear where dollars normally would).

func displayUnpricedModel(_ model: String) -> String {
	model.isEmpty ? "unknown Codex model" : model
}

func pricingDisclosure(for models: [String]) -> String? {
	guard !models.isEmpty else { return nil }
	let unknown = models.filter { !ModelIdentity.isFreeTier($0) }
	guard !unknown.isEmpty else { return nil }
	return "Unpriced models omitted from cost: \(unknown.map(displayUnpricedModel).joined(separator: ", "))"
}

/// The one eligibility mapping shared by both top-bar controls and the Settings row.
/// Official windows join as percentages. A provider without an official quota joins only when it
/// has an actual token count today; self-relative activity percentages never enter the menu bar.
func availableMenuBarLimitProviders(
	from rows: [DashboardViewModel.ProviderRow]
) -> [MenuBarLimitProvider] {
	rows.compactMap { row -> MenuBarLimitProvider? in
		guard row.usedPct != nil || row.weeklyUsedPct != nil || row.todayUsage.total > 0 else {
			return nil
		}
		var windows: [MenuBarDisplayWindow] = []
		if row.usedPct != nil { windows.append(MenuBarDisplayWindow(windowMinutes: row.windowMinutes5h)) }
		if row.weeklyUsedPct != nil { windows.append(MenuBarDisplayWindow(windowMinutes: row.windowMinutesWeekly)) }
		if windows.isEmpty, row.todayUsage.total > 0 { windows.append(.estimate) }
		return MenuBarLimitProvider(
			id: row.id,
			shortName: ProviderDescriptor.shortName(forName: row.name),
			windows: windows)
	}
}

enum DashboardSurfaceMetrics {
	// `DashboardLayout.width` owns the card width; both layouts share the gap and row rhythm.
	static let selectorColumnGap: CGFloat = 12
	static let selectorRowGap: CGFloat = 2
	/// Initial content size before SwiftUI reports its preferred intrinsic height.
	static func initialWindowSize(for layout: DashboardLayout) -> CGSize {
		CGSize(width: layout.width, height: 700)
	}
}

/// Provider rows retain intrinsic sizing and source-order keyboard/VoiceOver traversal.
struct DashboardSelectorLayout<Aggregate: View, Providers: View>: View {
	var columnCount = 2
	@ViewBuilder var aggregate: () -> Aggregate
	@ViewBuilder var providers: () -> Providers

	var body: some View {
		VStack(spacing: DashboardSurfaceMetrics.selectorRowGap) {
			aggregate()
			LazyVGrid(
				columns: Array(repeating: GridItem(.flexible(), spacing: DashboardSurfaceMetrics.selectorColumnGap), count: columnCount),
				spacing: DashboardSurfaceMetrics.selectorRowGap
			) { providers() }
		}
	}
}

/// The compact dashboard — the native counterpart to the marketing site's `menubar-demo.tsx`.
/// "Sunlit Ledger" light theme. Interactive: the selector rows drive a view-state machine (All
/// providers vs a selected provider) that swaps the header, the trend chart, and the detail section.
struct DashboardView: View {
	var model: DashboardViewModel
	var windowChrome: Bool = false  // true in the draggable app window: inset the top bar past the traffic lights
	var chrome: DashboardChromeState?
	var menuBarDisplayPresentation: MenuBarDisplayPresentationState? = nil
	var onToggleWindowPin: (() -> Void)?
	var onSurfaceSizeChange: (() -> Void)?
	var onOpenAdvancedAnalytics: (() -> Void)?
	var onOpenLiveData: (() -> Void)?
	var onOpenThemes: (() -> Void)?
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	// The whole card re-colors on a theme change: subscribing here makes SwiftUI re-render this root
	// (and its children) on any `ThemeManager.shared` publish, so every `JP.*` token re-reads the
	// active theme — no `.preferredColorScheme` needed (see the note on `body` below).
	// periphery:ignore - intentional theme dependency; @ObservedObject subscribes at the object
	// level regardless of whether `.theme` is read directly in this body.
	@ObservedObject private var themeManager = ThemeManager.shared
	@State private var showingOnboarding = !SettingsStore.onboardingCompleted()
	@State private var showingSettings = false
	@ObservedObject private var settings = SettingsStore.shared
	// Post-update feedback: resolved once per dashboard appearance by `PostUpdateFeedbackGate`.
	@State private var feedbackPrompt: PostUpdateFeedbackPresentation?

	var body: some View {
		ZStack(alignment: .top) {
			if showingOnboarding {
				OnboardingView(
					windowChrome: windowChrome,
					onContinue: { completeOnboarding() },
					onOpenSettings: {
						completeOnboarding()
						setShowingSettings(true)
					},
					onRefresh: { model.refresh() },
					onQuit: { NSApp.terminate(nil) },
					onOpenWebsite: { SettingsBackView.open("https://jpthecat.com") })
					.frame(width: layout.width, alignment: .top)
					.clipped()
					.transition(.opacity)
			} else if showingSettings {
				SettingsBackView(
					model: model,
					windowChrome: windowChrome,
					chrome: chrome,
					menuBarDisplayPresentation: menuBarDisplayPresentation,
					onToggleWindowPin: onToggleWindowPin,
					onOpenAdvancedAnalytics: { onOpenAdvancedAnalytics?() },
					onOpenLiveData: { onOpenLiveData?() },
					onOpenThemes: { onOpenThemes?() },
					onClose: { setShowingSettings(false) })
					.frame(width: layout.width, alignment: .top)
					.clipped()
					.transition(.opacity)
			} else {
				frontFace
					.frame(width: layout.width, alignment: .top)
					.clipped()
					.transition(.opacity)
			}
		}
		.frame(width: layout.width, alignment: .top)
		.background(JP.card)
		// No `.preferredColorScheme` here: `ThemeManager.apply()` already drives `NSApp.appearance`
		// for the whole app, and `JP.*` colors read `JPTheme.current` directly (not the SwiftUI
		// `colorScheme` environment) — a second, SwiftUI-level color-scheme change here duplicated
		// that AppKit-level invalidation and forced a full `NSHostingView` relayout on top of it,
		// contributing to a freeze on theme switch (see the regression note on `ThemeManager.apply()`).
		.onAppear {
			onSurfaceSizeChange?()
			resolvePostUpdateFeedbackPrompt()
		}
		.sheet(
			isPresented: Binding(
				get: { feedbackPrompt != nil },
				set: { if !$0 { feedbackPrompt = nil } })
		) {
			if let feedbackPrompt {
				PostUpdateFeedbackSheet(
					version: feedbackPrompt.version,
					report: feedbackPrompt.report
				) { optOut in
					if optOut { SettingsStore.setFeedbackOptedOut(true) }
					self.feedbackPrompt = nil
				}
			}
		}
		.onChange(of: surfaceSizingKey) { _, _ in onSurfaceSizeChange?() }
		.onReceive(NotificationCenter.default.publisher(for: .jpShowSettings)) { _ in
			completeOnboarding()
			setShowingSettings(true)
		}
		// One injection point for every animated leaf below (RotationIndicatorLight, FloatingBubble,
		// TickerTapeText, PulseDot, SparkChart's ping) so none of them needs the flag prop-drilled.
		// `chrome` is nil outside the owned window, which leaves the environment default (false) and
		// therefore animates exactly as before. See `DashboardMotionGate`.
		.environment(\.jpMotionPaused, chrome?.motionPaused ?? false)
		// The one place the persisted layout enters the view tree; every face and detail reads it here.
		.environment(\.dashboardLayout, layout)
	}

	private var layout: DashboardLayout { settings.dashboardLayout }

	private var frontFace: some View {
		VStack(alignment: .leading, spacing: 0) {
			topBar
			rule
			header
			rule
			if model.hasData {
				chartSection
				rule
				selector
				detailBay
			} else {
				emptyState
			}
			footer
		}
	}

	private var surfaceSizingKey: String {
		// The data half lives on DashboardState (behaviorally tested + shared); the face toggles are
		// view-local @State that never flow through a refresh, so they are folded in here. The layout
		// changes the card width itself.
		"\(showingOnboarding)-\(showingSettings)-\(layout.rawValue)-\(model.state.surfaceSizingSignature)"
	}

	/// Crossfade between the dashboard and settings face without a 3D card flip.
	private func setShowingSettings(_ value: Bool) {
		if reduceMotion {
			showingSettings = value
		} else {
			withAnimation(.easeInOut(duration: 0.12)) { showingSettings = value }
		}
	}

	/// Dismiss first-run onboarding exactly once, persisted under `SettingsStore` so reopening the app
	/// goes straight to the live dashboard unless the user resets their defaults.
	private func completeOnboarding() {
		guard showingOnboarding || !SettingsStore.onboardingCompleted() else { return }
		SettingsStore.shared.onboardingCompleted = true
		if reduceMotion {
			showingOnboarding = false
		} else {
			withAnimation(.easeInOut(duration: 0.12)) { showingOnboarding = false }
		}
	}

	/// Resolve (and immediately record) the post-update feedback prompt on dashboard open.
	///
	/// The version is recorded for BOTH outcomes that consume it — prompt and record-only — before the
	/// sheet renders, so a crash, a force-quit, or a dismissal can never re-ask for the same version.
	/// The gate itself is pure and lives in `PostUpdateFeedbackGate`; only the sourcing is here.
	private func resolvePostUpdateFeedbackPrompt() {
		guard feedbackPrompt == nil else { return }
		let info = Bundle.main.infoDictionary
		let version = info?["CFBundleShortVersionString"] as? String ?? ""
		let previousVersion = SettingsStore.feedbackPromptedVersion()
		let decision = PostUpdateFeedbackGate.decide(
			PostUpdateFeedbackGate.Inputs(
				lastPromptedVersion: previousVersion,
				currentVersion: version,
				optedOut: SettingsStore.feedbackOptedOut(),
				onboardingCompleted: SettingsStore.onboardingCompleted()))
		guard decision != .skip else { return }
		SettingsStore.setFeedbackPromptedVersion(version)
		guard decision == .prompt else { return }
		feedbackPrompt = PostUpdateFeedbackPresentation(
			version: version,
			report: PostUpdateFeedbackReport.make(
				appVersion: version,
				buildNumber: info?["CFBundleVersion"] as? String ?? "unknown",
				previousVersion: previousVersion,
				macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString))
	}

	private var rule: some View { Rectangle().fill(JP.line).frame(height: 1) }

	// MARK: - Top bar

	private var topBar: some View {
			ChromeTitleRow(windowChrome: windowChrome) { headerControls }
		}

	private var headerControls: some View {
		HStack(spacing: JPAppSpacing.chromeControlGap) {
			RotationIndicatorLight(isRotating: settings.menuBarDisplayFormat.isRotating)
			MenuBarDisplayCycleButton(
				format: settings.menuBarDisplayFormat,
				renderedTitle: menuBarDisplayPresentation?.title,
				isEnabled: true
			) {
				settings.menuBarDisplayFormat =
					settings.menuBarDisplayFormat.next(providers: menuBarLimitProviders)
			}
			DashboardLayoutButton(layout: layout) { settings.dashboardLayout = layout.next }
			SettingsLink { setShowingSettings(true) }
		}
	}

	private var menuBarLimitProviders: [MenuBarLimitProvider] {
		availableMenuBarLimitProviders(from: model.state.rows)
	}

	// MARK: - Header (selected view's today)

	private var header: some View {
			VStack(alignment: .leading, spacing: 8) {
				// Basis label leads as one full-width ticker design across All Providers and provider focus.
				BasisLabelChip(text: model.selectedBasisLabel, reduceMotion: reduceMotion)
					.frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
					.id(model.selectedBasisLabel)
				// Vertically CENTER both sides in the hero row: the split-flap total (its 48pt tiles
				// already sit centered in this 52pt frame) and the shorter right column each get equal
				// space above and below. `.center` is what makes the eyebrow/total/caption group read as
				// centered against the big ticker instead of top-heavy.
				HStack(alignment: .center) {
					// LEFT: the big split-flap ticker (today's spend) stands alone as the hero figure. A
					// fully-unpriced row (Copilot) shows its real token count instead of a dead $0.00.
					SplitFlapMoney(
						value: model.selectedToday, currencyCode: selectedCurrencyCode,
						notional: model.selectedNotional, reduceMotion: reduceMotion,
						textOverride: heroTodayTextOverride,
						textOverrideAccessibilityLabel: heroTodayAccessibilityLabel)
						.frame(height: 52, alignment: .leading)
					Spacer(minLength: 8)
					// RIGHT: the provider eyebrow sits ABOVE the window total + timeframe caption.
					VStack(alignment: .trailing, spacing: 3) {
						Text(model.selectedName.uppercased())
							.font(JPAppFont.eyebrow)
							.foregroundStyle(JP.gingerDeep)
							.lineLimit(1)
					Text(heroWeekTokenText ?? heroWindowSecondaryText)
						.font(JPAppFont.metric)
						.foregroundStyle(JP.ink)
						.lineLimit(1).fixedSize()
						if model.selectedRow?.heroShowsOfficialPlanUsage() != true {
							Text("last \(model.selectedDays) days")
								.font(JPAppFont.caption).foregroundStyle(JP.inkFaint)
						}
					}
				}
			}
			.padding(.horizontal, JPAppSpacing.contentX)
			.padding(.top, JPAppSpacing.headerTop)
			.padding(.bottom, JPAppSpacing.headerBottom)
		}

	/// Plan-only usage shows an official primary %; fully-unpriced rows show today's token count.
	private var heroTodayTextOverride: String? {
		guard let row = model.selectedRow else { return nil }
		if let plan = row.heroPrimaryTextOverride() { return plan }
		guard row.usesTokenDisplay else { return nil }
		return TokenFormatter.compact(row.todayUsage.total)
	}

	private var heroTodayAccessibilityLabel: String? {
		guard let row = model.selectedRow, row.heroShowsOfficialPlanUsage(),
			let pct = row.heroPrimaryTextOverride()
		else { return nil }
		return "\(pct) of \(row.primaryPlanWindowLabel.lowercased()) included usage, official \(row.name) plan usage"
	}

	private var heroWeekTokenText: String? {
		guard let row = model.selectedRow, row.usesTokenDisplay else { return nil }
		return TokenFormatter.compact(row.weekUsage.total)
	}

	/// When a provider has no official quota % but does carry a self-relative activity estimate (Muse
	/// Spark), the hero's right column shows ~NN% activity instead of a misleading sub-dollar week total
	/// beside a big today-$ figure.
	private var heroWindowSecondaryText: String {
		guard let row = model.selectedRow else { return money(model.selectedWeek) }
		if let planCaption = row.heroSecondaryCaption() { return planCaption }
		if row.usedPct != nil || row.weeklyUsedPct != nil { return money(row.week) }
		if let pct = row.estimatedSharePct {
			return "~\(Int(pct.rounded()))% activity"
		}
		return money(row.week)
	}

	// MARK: - Chart

	private var chartSection: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 4) {
				Text("\(model.selectedName) ·")
					.font(JPAppFont.caption).foregroundStyle(JP.inkFaint)
					.accessibilityHidden(true)
				if model.selectedRow?.heroShowsOfficialPlanUsage() == true {
					Text(model.selectedRow?.primaryPlanWindowLabel ?? "Official plan usage")
						.font(JPAppFont.caption).foregroundStyle(JP.inkFaint)
					Spacer(minLength: 6)
					Text("official")
						.font(JPAppFont.microMedium).lineLimit(1).fixedSize()
						.labelBadgeLayout()
						.background(JP.sage.opacity(0.2), in: Capsule())
						.foregroundStyle(JP.sageDeep)
				} else {
					TimeframePicker(
						days: model.selectedDays, options: DashboardViewModel.timeframeOptions,
						onSelect: { model.setTimeframe($0) })
					Spacer()
				}
			}
			// Collapse ONLY the chart drawing + availability notice into one spoken label — the
			// interactive TimeframePicker above must stay its own focusable element (children: .ignore on
			// the whole section dropped it from the accessibility tree, so VoiceOver couldn't change days).
			VStack(alignment: .leading, spacing: 6) {
				if let quotaFraction = model.selectedRow?.heroChartQuotaFraction() {
					HeroOfficialQuotaMeter(
						fraction: quotaFraction, tint: JP.providerTint(model.selectedTintHex),
						footerCaption: model.selectedRow?.heroFooterCaption())
						.frame(height: 52)
				} else {
					SparkChart(
						values: chartValues, tint: JP.providerTint(model.selectedTintHex),
						reduceMotion: reduceMotion)
						.frame(height: 52)
						.id(model.selectedId ?? "all")  // reset the beacon animation when the view swaps
				}
				if model.isAllSelected, let notice = model.providerAvailabilityNotice {
					Text(notice)
						.font(JPAppFont.caption)
						.foregroundStyle(JP.gingerDeep)
						.lineLimit(2)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			.accessibilityElement(children: .ignore)
			.accessibilityLabel(chartAccessibilityLabel)
		}
		.padding(.horizontal, JPAppSpacing.contentX).padding(.vertical, JPAppSpacing.sectionY)
	}

	/// Cost series for every view except a fully-unpriced selected provider, which charts its real
	/// token series instead (its cost series is a dead all-zero line).
	private var chartValues: [Double] {
		if let row = model.selectedRow, row.usesTokenDisplay { return row.tokenSeries }
		return model.selectedSeries
	}

	private var chartAccessibilityLabel: String {
		let base: String
		if let row = model.selectedRow, row.heroShowsOfficialPlanUsage(),
			let pct = row.heroPrimaryTextOverride()
		{
			base = "\(model.selectedName) official \(row.primaryPlanWindowLabel.lowercased()) included usage, \(pct) used"
		} else if heroWeekTokenText != nil {
			base =
				"\(model.selectedName) token usage, last \(model.selectedDays) days, \(heroWeekTokenText ?? "")"
		} else {
			base = "\(model.selectedName) spend, last \(model.selectedDays) days, \(money(model.selectedWeek))"
		}
		return DashboardState.chartAccessibilityLabel(
			base: base, notice: model.providerAvailabilityNotice, isAllSelected: model.isAllSelected)
	}

	// MARK: - Selector (drives the view-state machine)

	private var selector: some View {
		DashboardSelectorLayout(columnCount: layout.columnCount) {
			SelectorRow(
				name: "All providers", tint: JP.ginger, vizTint: JP.providerTint(JPAppColor.aggregateTintHex),
				amount: money(model.aggregateToday),
				share: 1, selected: model.isAllSelected,
				// No `notional` badge on the aggregate row: the full-width basis-label ticker band above the
				// selector is the aggregate's notional/list-price disclosure surface, so a per-row badge here
				// is redundant clutter. Do NOT reintroduce it. (Provider rows still badge their own basis.)
				badge: nil,
				meterDescription: "Activity pulse",
				iconName: "jp-menubar", whiteGlyph: false, iconMetrics: .allProviders, pulsing: true) {
					model.select(nil)
				}
		} providers: {
			ForEach(model.rows) { row in
				SelectorRow(
					name: row.name, tint: JP.hex(row.tintHex), vizTint: JP.providerTint(row.tintHex),
					// A stale row keeps its last-good amount; excluded rows show "—". A fully-unpriced row
					// (Copilot) shows its token count instead of a dead $0.00.
					amount: row.isContributing
						? (row.selectorTrailingAmount()
							?? (row.usesTokenDisplay
								? TokenFormatter.compact(row.todayUsage.total, suffix: " tok")
								: (row.today.map(money) ?? "—")))
						: "—",
					share: model.selectorMeterFraction(row), selected: row.isSelectable && model.selectedId == row.id,
					badge: selectorBadge(for: row),
					meterDescription: model.selectorMeterDescription(row),
					trendSeries: row.selectorTrendSeries(),
					iconName: "provider-\(row.id)", whiteGlyph: true) {
						guard row.isSelectable else {
							model.select(nil)
							return
						}
						// Toggle: clicking the already-open provider closes it back to the All-providers view.
						model.select(model.selectedId == row.id ? nil : row.id)
					}
			}
		}
			.padding(.horizontal, JPAppSpacing.selectorFooterX).padding(.vertical, JPAppSpacing.footerY)
	}

	/// Selector-row badge: `real` for a real-dollar provider (Claude), `notional` for list-price providers
	/// (Codex/Grok/Muse Spark), `local` for a non-aggregable token row (Copilot/Cursor), `stale` when
	/// the last refresh threw (last-good data kept), `unavailable` when the source's log folder vanished.
	/// The basis words are Core's `ProviderBasis.badge` vocabulary — the SAME strings the Advanced
	/// Analytics window renders. Leaving a real-dollar row unbadged made the basis readable only by the
	/// ABSENCE of a pill, so every available row carries one.
	///
	/// [NOTE] The `.available` arm derives its word from Core's one `ProviderBasis` table rather than a
	/// per-call-site `row.notional` ternary — the badge vocabulary has exactly one home. The inner
	/// switch is exhaustive on purpose: a NEW `ProviderBasis` case must make an explicit decision here
	/// instead of inheriting some other basis's word.
	/// Parity anchors: `scripts/verify-app-demo-parity.sh` pins the `.real`/`.notional` badge lines
	/// against the web demo's own badge vocabulary, and
	/// `TokenFormatterParityTests.testSelectorBadgeWordsMatchProviderBasis` fails if the two diverge.
	private func selectorBadge(for row: DashboardViewModel.ProviderRow) -> String? {
		switch row.availability {
		case .stale: return "stale"
		case .unavailable: return "unavailable"
		case .disabled: return "disabled"
		case .available:
			if let planBadge = row.selectorOfficialPlanBadge() { return planBadge }
			if ProviderBasis.of(rawID: row.id) == .gateway {
				return row.usesTokenDisplay ? "local" : ProviderBasis.gateway.badge
			}
			guard row.isAggregable else { return "local" }
			switch ProviderBasis.of(rawID: row.id) {
			case .real: return ProviderBasis.real.badge
			case .notional: return ProviderBasis.notional.badge
			case .estimate: return ProviderBasis.estimate.badge
			case .gateway: return ProviderBasis.gateway.badge
			case .officialPlan: return ProviderBasis.officialPlan.badge
			}
		}
	}

	// MARK: - Detail (composition for All; a gauge/note for a provider)

	@ViewBuilder private var detail: some View {
		if let row = model.selectedRow {
			ProviderDetail(row: row, days: model.selectedDays)
		} else {
			Composition(
				rows: model.rows, aggregateWeek: model.aggregateWeek, days: model.selectedDays,
				share: model.weeklyShare)
		}
	}

	private var detailBay: some View {
		detail
			.frame(maxWidth: .infinity, alignment: .topLeading)
		.background(JP.paper2.opacity(0.5))
		.overlay(Rectangle().fill(JP.line).frame(height: 1), alignment: .top)
	}

	// MARK: - Empty + footer

	private var emptyState: some View {
			FirstRunEmptyState(isRefreshing: model.isRefreshing, reduceMotion: reduceMotion)
				.padding(.horizontal, JPAppSpacing.contentX)
				.padding(.vertical, JPAppSpacing.emptyStateY)
	}

	private var footer: some View {
		TimelineView(.periodic(from: .now, by: 1)) { context in
			DashboardCardFooter(
				leadingText: DashboardFreshness.evaluate(
					refreshStatus: model.state.refreshStatus,
					now: context.date
				).footerText,
				onRefresh: { model.refresh() },
				onOpenAdvancedAnalytics: { onOpenAdvancedAnalytics?() },
				onQuit: { NSApp.terminate(nil) },
				onOpenWebsite: { SettingsBackView.open("https://jpthecat.com") },
				// Mirrors the Settings face's own accessory exactly — the update notification was
				// previously only visible after opening Settings.
				accessory: { UpdateStatusDot(currentVersion: appVersion) })
		}
	}

	/// Currency for the currently selected view (a provider row, or the aggregate). All providers are
	/// USD today; this keeps the header/hero honest if a future provider reports a native currency.
	private var selectedCurrencyCode: String {
		model.selectedRow?.currencyCode ?? model.aggregateCurrencyCode
	}

	private func money(_ value: Double) -> String {
		MoneyFormatter.dollars(value, code: selectedCurrencyCode)
	}

	/// Same recipe as `SettingsBackView.appVersion` — reads `CFBundleShortVersionString` directly since
	/// `UpdateStatusDot` needs it on both faces now.
	private var appVersion: String {
		let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
		return "v\(short)"
	}

}

/// The shared card footer used by BOTH the dashboard face and the settings face, so the
/// bottom strip is always styled identically: a leading caption, footer actions, and the
/// circularly-rounded JP mark, over the same paper wash + top hairline.
struct DashboardCardFooter<Accessory: View>: View {
	let leadingText: String
	var onRefresh: (() -> Void)? = nil
	var onOpenAdvancedAnalytics: (() -> Void)? = nil
	let onQuit: () -> Void
	let onOpenWebsite: () -> Void
	@ViewBuilder var accessory: () -> Accessory
	// On the settings face `leadingText` is constant, so without a theme dependency SwiftUI would skip
	// re-rendering this on a theme flip and freeze the caption/wash at the previous palette.
	// periphery:ignore
	@ObservedObject private var themeManager = ThemeManager.shared

	var body: some View {
		HStack(spacing: 6) {
			Text(leadingText)
				.font(JPAppFont.caption)
				.foregroundStyle(JP.inkSoft)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
			Spacer()
			if let onRefresh {
				DashboardFooterActionButton(
					systemImage: "arrow.clockwise",
					helpText: "Refresh now",
					accessibilityLabel: "Refresh now",
					action: onRefresh)
			}
			if let onOpenAdvancedAnalytics {
				AdvancedAnalyticsFooterButton(onOpenTray: onOpenAdvancedAnalytics)
			}
			DashboardFooterActionButton(
				systemImage: "questionmark.circle",
				helpText: "Open JP the Cat website",
				accessibilityLabel: "Open JP the Cat website",
				action: onOpenWebsite)
			accessory()
			// Quit sits immediately before the JP mark (bottom-right-most), not between Refresh/Help.
			DashboardFooterActionButton(
				systemImage: "power",
				helpText: "Quit JP the Cat",
				accessibilityLabel: "Quit JP the Cat",
				destructive: true,
				action: onQuit)
			SocialShareButton()
		}
		.padding(.horizontal, JPAppSpacing.contentX).padding(.vertical, JPAppSpacing.footerY)
		.frame(maxWidth: .infinity)
		.background(JP.paper2.opacity(0.5))
		.overlay(Rectangle().fill(JP.line).frame(height: 1), alignment: .top)
	}
}

extension DashboardCardFooter where Accessory == EmptyView {
	init(
		leadingText: String,
		onRefresh: (() -> Void)? = nil,
		onOpenAdvancedAnalytics: (() -> Void)? = nil,
		onQuit: @escaping () -> Void,
		onOpenWebsite: @escaping () -> Void
	) {
		self.leadingText = leadingText
		self.onRefresh = onRefresh
		self.onOpenAdvancedAnalytics = onOpenAdvancedAnalytics
		self.onQuit = onQuit
		self.onOpenWebsite = onOpenWebsite
		self.accessory = { EmptyView() }
	}
}

/// Explains why a non-aggregable provider's "local" badge means its tokens stay OUT of
/// combined dollar totals and alerts; a token-estimate widget remains separate — spacing mirrors
/// `SocialSharePopover` (the app's other
/// popover) so both read consistently: a 12pt-spaced VStack, a 2pt-spaced icon+title/subtitle header,
/// then body copy, all inside one shared `JPAppSpacing.panelInset` padding.
private struct GatewayExplainerPopover: View {
	let providerName: String
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(spacing: 10) {
				Image(systemName: "info.circle.fill")
					.font(JPAppFont.chromeIcon)
					.foregroundStyle(JP.gingerDeep)
					.frame(width: 22, height: 22)
				VStack(alignment: .leading, spacing: 2) {
					Text("Why isn't \(providerName) in my total?")
						.font(JPAppFont.chromeTitle)
						.foregroundStyle(JP.ink)
					Text("Gateway dollars — shown, not summed")
						.font(JPAppFont.caption)
						.foregroundStyle(JP.inkSoft)
				}
			}
			VStack(alignment: .leading, spacing: 8) {
				Text(
					"\(providerName) shows local gateway usage in dollars here, but the same usage is "
						+ "already counted under its model-brand rows. Combined totals include those brands "
						+ "only — never the gateway rollup twice.")
					.font(JPAppFont.body)
					.foregroundStyle(JP.inkSoft)
					.fixedSize(horizontal: false, vertical: true)
			}
			HStack {
				Spacer()
				Button("Got it") { dismiss() }
					.buttonStyle(.borderedProminent)
					.tint(JP.gingerDeep)
			}
		}
		.padding(JPAppSpacing.panelInset)
		.frame(width: 320)
	}
}

private struct EstimateExplainerPopover: View {
	let providerName: String

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(spacing: 10) {
				Image(systemName: "info.circle.fill")
					.font(JPAppFont.chromeIcon)
					.foregroundStyle(JP.gingerDeep)
					.frame(width: 22, height: 22)
				VStack(alignment: .leading, spacing: 2) {
					Text("Why isn't \(providerName) in my total?")
						.font(JPAppFont.chromeTitle)
						.foregroundStyle(JP.ink)
					Text("Local activity — separate from provider usage")
						.font(JPAppFont.caption)
						.foregroundStyle(JP.inkSoft)
				}
			}
			VStack(alignment: .leading, spacing: 8) {
				Text(
					"\(providerName) has its own row here with real activity — its own totals and trend "
						+ "line — but it never counts toward your combined total, the menu-bar widget, or "
						+ "usage alerts.")
					.font(JPAppFont.body)
					.foregroundStyle(JP.ink)
					.fixedSize(horizontal: false, vertical: true)
				Text(
					"\(providerName)'s numbers come from an opt-in local export. They show tokens processed "
						+ "on this Mac, not your provider plan allowance or billing balance. Mixing them into "
						+ "your official usage would make both measurements less trustworthy.")
					.font(JPAppFont.body)
					.foregroundStyle(JP.ink)
					.fixedSize(horizontal: false, vertical: true)
				Text("You can turn this off anytime in Settings → Live data.")
					.font(JPAppFont.caption)
					.foregroundStyle(JP.inkFaint)
					.fixedSize(horizontal: false, vertical: true)
					// Extra breathing room above this trailing footer note; the shared 8pt inter-paragraph
					// spacing reads too tight between the body copy and this caption.
					.padding(.top, 4)
			}
		}
		.padding(JPAppSpacing.panelInset)
		.frame(width: 300, alignment: .topLeading)
		.background(JP.card)
	}
}

private struct DashboardFooterActionButton: View {
	let systemImage: String
	let helpText: String
	let accessibilityLabel: String
	var destructive: Bool = false
	let action: () -> Void
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var hovering = false

	var body: some View {
		Button(action: { InteractiveSounds.shared.bottomClick(); action() }) {
			Image(systemName: systemImage)
				.font(JPAppFont.chromeIcon)
				.foregroundStyle(destructive ? JP.gingerDeep : (hovering ? JP.gingerDeep : JP.inkSoft))
				.frame(width: JPAppSpacing.footerIconBox, height: JPAppSpacing.footerIconBox)
				.contentShape(RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous))
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
		.help(helpText)
		.accessibilityLabel(accessibilityLabel)
	}
}

struct PinButton: View {
	let isPinned: Bool
	let action: () -> Void
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var hovering = false

	var body: some View {
		Button(action: { InteractiveSounds.shared.topClick(); action() }) {
			Image(systemName: isPinned ? "pin.fill" : "pin")
				.font(JPAppFont.chromeIcon)
				.foregroundStyle(foreground)
				.frame(width: JPAppSpacing.chromeGlyphW, height: JPAppSpacing.chromeGlyphH)
				.frame(width: JPAppSpacing.chromeControlSize, height: JPAppSpacing.chromeControlSize)
				.background(
					RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
						.fill(background))
				.overlay(
					RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
						.strokeBorder(border, lineWidth: 1))
			}
			.buttonStyle(.plain)
			.onHover { hovering = $0 }
			.animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
			.animation(reduceMotion ? nil : JPAppMotion.hover, value: isPinned)
			.jpTooltip(JPTooltip.pinDashboard(isPinned: isPinned))
			.accessibilityLabel(isPinned ? "Unpin dashboard" : "Pin dashboard")
			.accessibilityValue(isPinned ? "Pinned" : "Unpinned")
	}

	private var foreground: Color {
		if isPinned { return JP.sage }
		return hovering ? JP.gingerDeep : JP.inkSoft
	}

	private var background: Color {
		if isPinned { return JP.sage.opacity(0.16) }
		return hovering ? JP.paper2.opacity(0.72) : .clear
	}

	private var border: Color {
		if isPinned { return JP.sage.opacity(0.34) }
		return hovering ? JP.lineStrong.opacity(0.95) : .clear
	}
}

/// One-click access to the same complete display-format cycle exposed by Settings.
/// Kept as a shared top-chrome control so the dashboard and Settings faces cannot drift.
struct MenuBarDisplayCycleButton: View {
	let format: MenuBarDisplayFormat
	var renderedTitle: String? = nil
	let isEnabled: Bool
	let action: () -> Void
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var hovering = false

	var body: some View {
		Button(action: { InteractiveSounds.shared.topClick(); action() }) {
			Image(systemName: "menubar.rectangle")
				.font(JPAppFont.chromeIcon)
				.foregroundStyle(hovering && isEnabled ? JP.gingerDeep : JP.inkSoft)
				.frame(width: JPAppSpacing.chromeGlyphW, height: JPAppSpacing.chromeGlyphH)
				.frame(width: JPAppSpacing.chromeControlSize, height: JPAppSpacing.chromeControlSize)
				.background(
					RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
						.fill(hovering && isEnabled ? JP.paper2.opacity(0.72) : .clear))
				.overlay(
					RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
						.strokeBorder(hovering && isEnabled ? JP.lineStrong.opacity(0.95) : .clear, lineWidth: 1))
		}
		.buttonStyle(.plain)
		.disabled(!isEnabled)
		.opacity(isEnabled ? 1 : 0.48)
		.onHover { hovering = $0 }
		.animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
		.help(helpText)
		.accessibilityLabel("Cycle menu bar display")
		.accessibilityValue(isEnabled ? currentTitle : "Menu bar display unavailable")
	}

	private var helpText: String {
		isEnabled
			? "Cycle menu bar display — current: \(currentTitle)"
			: "Menu bar display cycle unavailable"
	}

	private var currentTitle: String { renderedTitle ?? format.settingsTitle }
}

/// Cycles the card between one and two columns. Shared by the dashboard and Settings chrome, so both
/// faces offer the same control. The glyph shows the CURRENT layout; the tooltip names the next one.
struct DashboardLayoutButton: View {
	let layout: DashboardLayout
	let action: () -> Void
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var hovering = false

	var body: some View {
		Button(action: { InteractiveSounds.shared.topClick(); action() }) {
			Image(systemName: layout.systemImage)
				.font(JPAppFont.chromeIcon)
				.foregroundStyle(hovering ? JP.gingerDeep : JP.inkSoft)
				.frame(width: JPAppSpacing.chromeGlyphW, height: JPAppSpacing.chromeGlyphH)
				.frame(width: JPAppSpacing.chromeControlSize, height: JPAppSpacing.chromeControlSize)
				.background(
					RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
						.fill(hovering ? JP.paper2.opacity(0.72) : .clear))
				.overlay(
					RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
						.strokeBorder(hovering ? JP.lineStrong.opacity(0.95) : .clear, lineWidth: 1))
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
		.jpTooltip(JPTooltip.dashboardLayout(current: layout))
		.accessibilityLabel("Dashboard layout")
		.accessibilityValue(layout.title)
		.accessibilityHint("Switches to \(layout.next.title.lowercased())")
	}
}

/// The header's "Settings" link crossfades to the settings face.
private struct SettingsLink: View {
	let action: () -> Void
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var hovering = false

	var body: some View {
		Button(action: { InteractiveSounds.shared.topClick(); action() }) {
			Image(systemName: "gearshape")
				.font(JPAppFont.chromeIcon)
				.foregroundStyle(hovering ? JP.gingerDeep : JP.inkSoft)
				.frame(width: JPAppSpacing.chromeGlyphW, height: JPAppSpacing.chromeGlyphH)
				.frame(width: JPAppSpacing.chromeControlSize, height: JPAppSpacing.chromeControlSize)
				.background(
					RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
						.fill(hovering ? JP.paper2.opacity(0.72) : .clear))
				.overlay(
					RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
						.strokeBorder(hovering ? JP.lineStrong.opacity(0.95) : .clear, lineWidth: 1))
			}
			.buttonStyle(.plain)
			.onHover { hovering = $0 }
			.animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
			.help("Settings")
			.accessibilityLabel("Settings")
		}
	}

// MARK: - Timeframe dropdown (widens the chart + every window-derived figure)

struct TimeframePicker: View {
	let days: Int
	let options: [Int]
	let onSelect: (Int) -> Void
	@State private var hovering = false

	var body: some View {
		Menu {
			ForEach(options, id: \.self) { option in
				Button {
					onSelect(option)
				} label: {
					if option == days {
						Label("Last \(option) days", systemImage: "checkmark")
					} else {
						Text("Last \(option) days")
					}
				}
			}
		} label: {
			HStack(spacing: 3) {
				Text("last \(days) days")
					.font(JPAppFont.captionStrong)
				Image(systemName: "chevron.down")
					.font(JPAppFont.menuChevron)
			}
			.foregroundStyle(JP.inkSoft)
			.padding(.horizontal, JPAppSpacing.chromeControlX)
			.padding(.vertical, JPAppSpacing.chromeControlY)
			.background(
				RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
					.fill(hovering ? JP.paper2.opacity(0.72) : JP.paper))
			.overlay(
				RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
					.strokeBorder(hovering ? JP.lineStrong.opacity(0.95) : JP.line, lineWidth: 1))
		}
		.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
		.onHover { hovering = $0 }
		.help("Timeframe for the chart and every figure")
		.accessibilityLabel("Timeframe")
		.accessibilityValue("Last \(days) days")
	}
}

// MARK: - Selector row (button)

struct SelectorRowIconMetrics {
	let containerSize: CGFloat
	let imageSize: CGFloat
	let drawsBackground: Bool
	let drawsOutline: Bool

	static let normalizedContainerSize: CGFloat = 18
	static let normalizedImageSize: CGFloat = 16

	static let allProviders = SelectorRowIconMetrics(
		containerSize: normalizedContainerSize,
		imageSize: normalizedImageSize,
		drawsBackground: false,
		drawsOutline: false)
	static let provider = SelectorRowIconMetrics(
		containerSize: normalizedContainerSize,
		imageSize: normalizedImageSize,
		drawsBackground: true,
		drawsOutline: true)
}

struct SelectorRowMeterMetrics {
	static let progressHeight: CGFloat = 5
	// Matches the 18pt selector icon box, so the aggregate row is no taller than the provider rows while
	// giving the sparkline real vertical room: usable height = 18 − ballDiameter(7) = 11pt of amplitude, so
	// the ball visibly RIDES the peaks/valleys instead of sliding flat left↔right. Do not shrink this back
	// toward the ball diameter — that collapses the amplitude and the ball just travels horizontally.
	static let pulseFrameHeight: CGFloat = 18
	/// Aggregate "polling" heartbeat: a ball that rides up/down along a small sparkline line. The line
	/// spans the FULL meter-column width (no fixed cap) so it scales all the way to the right.
	static let dotDiameter: CGFloat = 7
	static let dotTrackHeight: CGFloat = 2.5
}

// `internal` (not `private`) so `AppResourcesIconCacheTests` can prove `SelectorRow.icon(_:)` still
// routes through the memoized `AppResources.icon(named:)` — same reason `SparkChart` below is internal.
// Still only constructed within this file.
struct SelectorRow: View {
	let name: String
	let tint: Color  // brand tint — the icon chip (white glyph sits on it, so it must stay dark)
	var vizTint: Color  // legible-on-theme tint for the share bar / hover / glow (Codex charcoal
	// vanishes on the dark card, so data-viz uses providerTint while the icon keeps the brand color)
	let amount: String
	let share: Double
	let selected: Bool
	let badge: String?
	let meterDescription: String
	var trendSeries: [Double]? = nil
	var iconName: String? = nil
	var whiteGlyph: Bool = true
	var iconMetrics: SelectorRowIconMetrics = .provider
	/// The aggregate ("All providers") row has no meaningful per-provider share, so instead of a
	/// static full bar it shows a compact sparkline pulse — a constant "polling" heartbeat.
	var pulsing: Bool = false
	let action: () -> Void
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var hovering = false
	@State private var showingEstimateInfo = false
	@State private var showingGatewayInfo = false

	/// `local` gets a visually DISTINCT color from `notional`/`stale`/`unavailable`/`disabled` — all
	/// of those share the honey/ginger-deep pill since they're all "basis/availability" notes about
	/// REAL dollar figures, but `local` means something categorically different (a whole ROW that's
	/// excluded from every total), so it borrows the row's own `vizTint` (Copilot's purple) at a light
	/// wash instead, so it reads as "this row is a different kind of thing," not just another dollar
	/// caveat next to figures that already look identical to Codex's `notional` pill.
	/// `real` uses the sage pill — the SAME basis vocabulary as the Advanced Analytics window, where sage
	/// means "real dollars" and honey means "notional list price". Keeping the two surfaces on one color
	/// language is why this isn't just another honey pill.
	private func badgeLabel(_ text: String) -> some View {
		let isTintWash = text == "local" || text == "gateway"
		let isSage = text == "real" || text == "official"
		let fill: Color = isTintWash ? vizTint : (isSage ? JP.sage : JP.honey)
		let ink: Color = isTintWash ? vizTint : (isSage ? JP.sageDeep : JP.gingerDeep)
		return Text(text).font(JPAppFont.microMedium).lineLimit(1).fixedSize()
			.labelBadgeLayout()
			.background(
				fill.opacity(isTintWash ? 0.18 : (isSage ? 0.2 : 0.25)),
				in: RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous))
			.foregroundStyle(ink)
	}

	var body: some View {
		// Selector rows (each provider + "All providers") play the light click cue like every other
		// dashboard button, gated by the shared interactive-sounds master. Mirrored on the homepage demo.
		//
		// [Layout note] The "local" badge (Copilot/Cursor) needs to be independently tappable (opens an
		// explainer popover) while the REST of the row still selects the provider on any other click,
		// AND it needs to sit to the LEFT of the amount — matching where the plain `notional`/`stale`
		// badges sit — not after it. A `Button` nested inside another `Button`'s label does NOT work
		// reliably on macOS — AppKit's hit-testing collapses to the OUTER button, silently swallowing
		// the inner one's taps (verified live: clicking directly on the badge selected the row instead
		// of opening the popover). The fix is to make the badge a true SIBLING button, not a nested
		// one, positioned BETWEEN two select-buttons that share the identical `action` — [icon+name+
		// meter] then the badge then [amount] — so the badge sits visually where it belongs while
		// still being an independent tap target, and clicking either select-button (or anywhere that
		// isn't the badge) selects the row exactly as before. Do not go back to nesting a Button inside
		// the row's Button, and do not move the badge after the amount again.
		HStack(spacing: 0) {
			Button(action: { InteractiveSounds.shared.selectorClick(); action() }) {
				HStack(spacing: 8) {
					iconSlot
					// Selected rows sit on the `trackFill` groove, where inkSoft is only ~4.4:1 — use full ink.
					// The column is a fixed width so every meter starts at the same x; it is wide enough for
					// the longest catalog name ("OpenCode Zen") so no row has to shrink or truncate.
					Text(name).font(JPAppFont.rowLabel).foregroundStyle(selected ? JP.ink : JP.inkSoft)
						.lineLimit(1).frame(width: 104, alignment: .leading)
					// Meter column — provider usage-window when available, otherwise aggregate dollar share.
					selectorMeter
					// A non-"local" badge (notional/stale/unavailable/disabled) stays inside this
					// select button as plain, non-interactive text, directly left of the amount — the
					// "local" badge renders separately below, as its own sibling button, but in the
					// SAME visual position (left of the amount).
					if let badge, badge != "local", badge != "gateway" { badgeLabel(badge).layoutPriority(1) }
				}
					.padding(.leading, JPAppSpacing.rowX).padding(.vertical, JPAppSpacing.rowY)
					.padding(.trailing, badge == nil ? JPAppSpacing.rowX : 0)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel("\(name), \(amount) today, \(meterDescription)\(badge.map { ", \($0)" } ?? "")\(selected ? ", selected" : "")")
			.help(meterDescription)
			if badge == "local" {
				Button(action: {
					InteractiveSounds.shared.selectorClick()
					showingEstimateInfo = true
				}) {
					badgeLabel("local")
				}
				.buttonStyle(.plain)
				.padding(.leading, 6)
				.help("Why isn't this in my total?")
				.popover(isPresented: $showingEstimateInfo, arrowEdge: .bottom) {
					EstimateExplainerPopover(providerName: name)
				}
			}
			if badge == "gateway" {
				Button(action: {
					InteractiveSounds.shared.selectorClick()
					showingGatewayInfo = true
				}) {
					badgeLabel("gateway")
				}
				.buttonStyle(.plain)
				.padding(.leading, 6)
				.help("Why isn't this gateway in my total?")
				.popover(isPresented: $showingGatewayInfo, arrowEdge: .bottom) {
					GatewayExplainerPopover(providerName: name)
				}
			}
			Button(action: { InteractiveSounds.shared.selectorClick(); action() }) {
				HStack(spacing: 0) {
					Text(amount).font(JPAppFont.metric)
						.foregroundStyle(JP.ink).lineLimit(1).fixedSize()
				}
					.padding(.leading, badge == nil ? 0 : 6).padding(.trailing, JPAppSpacing.rowX)
					.padding(.vertical, JPAppSpacing.rowY)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityHidden(true)  // the leading select-button already speaks the full row label
			.layoutPriority(1)
		}
			.background(
				RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous)
					.fill(selected ? JP.trackFill : (hovering ? vizTint.opacity(0.08) : .clear))
					.overlay(RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous)
						.strokeBorder(selected ? JP.lineStrong : (hovering ? vizTint.opacity(0.42) : .clear), lineWidth: 1)))
			.overlay(
				RoundedRectangle(cornerRadius: JPAppRadius.cardGlow, style: .continuous)
					.stroke(vizTint.opacity(hovering ? 0.18 : 0), lineWidth: 6)
					.blur(radius: hovering ? 5 : 0)
					.padding(-2))
			.scaleEffect(hovering && !selected && !reduceMotion ? 1.012 : 1)
			.shadow(color: hovering ? vizTint.opacity(0.18) : .clear, radius: hovering ? 9 : 0, x: 0, y: 2)
		.onHover { hovering = $0 }
		.animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
	}

	@ViewBuilder private var selectorMeter: some View {
		GeometryReader { geo in
			if let trendSeries {
				SparkChart(values: trendSeries, tint: vizTint, reduceMotion: reduceMotion)
			} else if pulsing {
				// The aggregate pulse spans the FULL meter column (like the provider share bars) so the
				// sparkline scales all the way to the right — never a fixed 76pt stub left-aligned in dead
				// space. PulseDot is itself a GeometryReader, so it fills whatever width it's given.
				PulseDot(animated: !reduceMotion, tint: vizTint)
			} else {
				ZStack(alignment: .leading) {
					// Groove: the full-width track. Its `trackFill` is barely distinct from the card in light
					// mode AND is the exact color of a SELECTED row's background — so on its own the unused
					// portion reads as empty space and the gauge looks like a stub (the "bar isn't all the way
					// to the right" report). A hairline `inkFaint` border delineates the FULL extent in every
					// state (light/dark × selected/unselected), so a partial usage gauge always reads as
					// "X% of a visible full track".
					Capsule().fill(JP.trackFill)
						.overlay(Capsule().strokeBorder(JP.inkFaint.opacity(0.5), lineWidth: 1))
					Capsule().fill(vizTint.opacity(JP.barFillOpacity))
						.frame(width: max(2, geo.size.width * share))
					// Rows are rebuilt and re-applied after every provider refresh.
					// An implicit animation here can therefore replay the fill from its minimum width even
					// when the provider's percentage did not change, making every provider appear to fall
					// to 0% and recover on the polling cadence.
					// Render the current value directly; the aggregate heartbeat is the selector's only
					// continuous motion, while genuine provider percentage changes remain immediately exact.
				}
			}
		}
		.frame(
			height: (trendSeries != nil || pulsing)
				? SelectorRowMeterMetrics.pulseFrameHeight
				: SelectorRowMeterMetrics.progressHeight)
		// [Regression guard] Explicit `maxWidth: .infinity` — the meter used to rely on being the ONLY
		// flexible view inside the row's single Button label to implicitly claim all leftover width.
		// Once the row split into sibling select-buttons (badge tap-target fix), that implicit
		// propagation became unreliable and the meter could size to its `minWidth` floor instead,
		// leaving dead space between the name and the bar. Never remove this — always request the
		// space explicitly rather than relying on Button/HStack flexible-sizing inference.
		.frame(minWidth: 20, maxWidth: .infinity)
	}

	private var iconSlot: some View {
		ZStack {
			RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
				.fill(iconMetrics.drawsBackground ? tint : .clear)
			if iconMetrics.drawsOutline {
				RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
					.strokeBorder(.white.opacity(0.22), lineWidth: 1)
			}
			if let iconName, let img = SelectorRow.icon(iconName) {
				iconImage(img)
			}
		}
		.frame(width: iconMetrics.containerSize, height: iconMetrics.containerSize)
	}

	@ViewBuilder private func iconImage(_ img: NSImage) -> some View {
		if whiteGlyph {
			Image(nsImage: img)
				.resizable()
				.interpolation(.high)
				.renderingMode(.template)
				.scaledToFit()
				.foregroundStyle(.white)
				.frame(width: iconMetrics.imageSize, height: iconMetrics.imageSize)
		} else {
			Image(nsImage: img)
				.resizable()
				.interpolation(.high)
				.renderingMode(.original)
				.scaledToFit()
				.frame(width: iconMetrics.imageSize, height: iconMetrics.imageSize)
		}
	}

	/// Provider marks are white SVG glyphs (`provider-*.svg`); NSImage renders SVG with correct
	/// transparency on macOS 14. Falls back to a bundled raster (e.g. the JP mark PNG).
	///
	/// [Regression guard] This is a THIN wrapper over the memoized `AppResources.icon(named:)` and must
	/// stay one. It used to call `NSImage(contentsOf:)` itself, and `iconSlot` calls it from inside a
	/// SwiftUI `body` that re-runs on every hover in/out and every refresh — so each evaluation re-read
	/// and re-decoded the provider SVG off disk. Never inline a raw `NSImage(contentsOf:)` here again.
	/// Guard: `AppResourcesIconCacheTests` (asserts on `AppResources.iconDiskLoadCount`, since image
	/// identity cannot tell a working cache from a removed one).
	static func icon(_ name: String) -> NSImage? {
		AppResources.icon(named: name)
	}
}

/// The aggregate ("All providers") row's constant "polling" heartbeat: a small sparkline "bar" with a
/// floating ball that rides along the line — travelling left↔right while riding the peaks and valleys.
/// The ball uses the legible-on-theme data-viz `tint` (WCAG-lifted for the dark card); the line is the
/// same tint dimmed so both read in light and dark mode. The ball emits the SAME radar-ping ring as the
/// larger `SparkChart` end dot (expanding scale + fading opacity on a 1.4s repeat) so the two heartbeats
/// read as one system, and wears the same `JP.card` ring border.
///
/// **Animation is driven by `TimelineView(.animation)`** — a per-frame display-link loop (the same
/// mechanism the freshness footer uses) — NOT `withAnimation`. A `withAnimation(...).repeatForever`
/// kicked off in `.onAppear` silently failed to run here (the phase was consumed only in manual
/// `.position` arithmetic inside a nested `GeometryReader`, which never interpolated), so the ball sat
/// dead-static. A timeline re-evaluates the body every frame with a fresh clock, so the ball is GUARANTEED
/// to move. `reduceMotion` skips the timeline entirely (static frame, no rAF) per the motion contract.
private struct PulseDot: View {
	let animated: Bool
	let tint: Color
	@Environment(\.jpMotionPaused) private var motionPaused

	var body: some View {
		if animated {
			TimelineView(.animation(paused: motionPaused)) { timeline in
				let s = timeline.date.timeIntervalSinceReferenceDate
				// Position: a slow, CALM drift — 0→1→0 over 28s (14s each way). `(1-cos(2π·s/period))/2` is a
				// smooth ease-in-out sweep with no end discontinuity. DELIBERATELY slower than any prior
				// release (the long-shipped speed was a 14s round trip and read as too busy for an idle
				// "polling" heartbeat). A BIGGER period is SLOWER — do not shrink it back. See AGENTS.md.
				let travel = (1 - cos(2 * .pi * s / 28)) / 2
				// Radar ping — the SAME effect as the larger `SparkChart` end dot: a ring that expands and
				// fades on a 1.4s repeat. Both derive it from the shared `RadarPing` so they can't drift.
				let ping = RadarPing.phase(at: s)
				dot(travel: travel, ping: ping)
			}
		} else {
			dot(travel: 0.12, ping: nil)  // parked, no ping, no rAF
		}
	}

	private func dot(travel: Double, ping: Double?) -> some View {
		GeometryReader { geo in
			let d = SelectorRowMeterMetrics.dotDiameter
			let r = d / 2
			// The line spans the FULL frame width, but is inset VERTICALLY by the ball radius so the fat
			// ball never clips a peak against the frame edge (that clip read as "the ball isn't on the
			// line"). The ball samples its y from the SAME inset rect, so its center lands exactly on the
			// stroked line at every point of the sweep.
			let fullRect = CGRect(x: 0, y: 0, width: geo.size.width, height: geo.size.height)
			let t = CGFloat(min(max(travel, 0), 1))
			let ballX = r + max(0, geo.size.width - d) * t
			let ballY = PulseSparklineShape.y(
				atXFraction: geo.size.width > 0 ? ballX / geo.size.width : 0,
				in: fullRect, verticalInset: r)
			ZStack(alignment: .topLeading) {
				PulseSparklineShape(verticalInset: r)
					.stroke(
						tint,
						style: StrokeStyle(
							lineWidth: SelectorRowMeterMetrics.dotTrackHeight,
							lineCap: .round,
							lineJoin: .round))
					.opacity(0.5)
				// Expanding/fading ping ring, mirroring SparkChart's end dot: scale 1→2.4, opacity 0.4→0.
				if let ping {
					Circle()
						.fill(tint)
						.frame(width: d, height: d)
						.scaleEffect(RadarPing.scale(ping))
						.opacity(RadarPing.opacity(ping))
						.position(x: ballX, y: ballY)
				}
				// The solid ball rides on top, with the same card-colored ring the chart dot uses.
				Circle()
					.fill(tint)
					.frame(width: d, height: d)
					.overlay(Circle().strokeBorder(JP.card, lineWidth: 1.5))
					.position(x: ballX, y: ballY)
			}
		}
	}
}

/// The sparkline "bar" the aggregate ball rides along — a fixed jagged polyline. `y(atXFraction:in:)`
/// returns the line's y for a given horizontal fraction so the ball can sit exactly on the line and
/// float up/down as it travels.
private struct PulseSparklineShape: Shape {
	/// Vertical inset (typically the ball radius) so the fat ball riding the line never clips a peak.
	var verticalInset: CGFloat = 0

	/// (x-fraction, y-offset-fraction of the usable height from the vertical center; + is down).
	static let points: [(x: CGFloat, y: CGFloat)] = [
		(0.00, 0.10), (0.18, -0.18), (0.36, 0.16), (0.58, -0.26), (0.78, 0.08), (1.00, -0.12),
	]

	func path(in rect: CGRect) -> Path {
		var path = Path()
		let usable = rect.insetBy(dx: 0, dy: verticalInset)
		let pts = Self.points.map {
			CGPoint(x: usable.minX + usable.width * $0.x, y: usable.midY + usable.height * $0.y)
		}
		guard let first = pts.first else { return path }
		path.move(to: first)
		for point in pts.dropFirst() { path.addLine(to: point) }
		return path
	}

	static func y(atXFraction fraction: CGFloat, in rect: CGRect, verticalInset: CGFloat = 0) -> CGFloat {
		let usable = rect.insetBy(dx: 0, dy: verticalInset)
		let t = min(max(fraction, 0), 1)
		for i in 1..<points.count {
			let a = points[i - 1], b = points[i]
			guard t <= b.x else { continue }
			let span = b.x - a.x
			let local = span > 0 ? (t - a.x) / span : 0
			return usable.midY + usable.height * (a.y + (b.y - a.y) * local)
		}
		return usable.midY + usable.height * (points.last?.y ?? 0)
	}
}

// MARK: - Composition (aggregate detail)

private struct Composition: View {
	let rows: [DashboardViewModel.ProviderRow]
	let aggregateWeek: Double
	let days: Int
	let share: (DashboardViewModel.ProviderRow) -> Double

	var body: some View {
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text("Spend by provider · last \(days) days").font(JPAppFont.label).foregroundStyle(JP.inkSoft)
					Spacer()
					Text(MoneyFormatter.dollars(aggregateWeek))
						.font(JPAppFont.metricSmall).foregroundStyle(JP.ink)
			}
			GeometryReader { geo in
				HStack(spacing: 0) {
					ForEach(rows) { row in
						Rectangle().fill(JP.providerTint(row.tintHex).opacity(0.85))
							.frame(width: max(0, geo.size.width * share(row)))
					}
				}
			}
			.frame(height: 10).clipShape(Capsule())
			// No per-provider legend here: the selector list above already shows every provider's
			// tint dot, name, and amount, so a second copy under the bar was pure duplication.
			// A fully-unpriced row (Copilot) already shows its real token count instead of a dollar
			// figure — nothing is silently hidden there, so it doesn't need this note. Only a row with a
			// MIX of priced and unpriced models still legitimately needs it (its dollar total is real,
			// just an undercount).
			let unpriced = Array(Set(rows.filter { !$0.isFullyUnpriced }.flatMap(\.unpricedModels))).sorted()
			if let disclosure = pricingDisclosure(for: unpriced) {
					Text(disclosure)
						.font(JPAppFont.caption).foregroundStyle(JP.gingerDeep)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
			.padding(.horizontal, JPAppSpacing.contentX).padding(.vertical, JPAppSpacing.sectionY)
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}

// MARK: - Mini trend chart (points span the selected timeframe)

/// Hero chart for plan-only usage: one official primary gauge, never a flat $0 sparkline.
struct HeroOfficialQuotaMeter: View {
	let fraction: Double
	let tint: Color
	var showHeader: Bool = true
	var footerCaption: String? = nil

	private var usedPercent: Int { Int((min(1, max(0, fraction)) * 100).rounded()) }
	private var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }

	var body: some View {
		VStack(spacing: showHeader ? 6 : 2) {
			if showHeader {
				HStack(alignment: .firstTextBaseline) {
					Text("Weekly included usage")
						.font(JPAppFont.caption)
						.foregroundStyle(JP.inkSoft)
					Spacer(minLength: 8)
					Text("\(remainingPercent)% remaining")
						.font(JPAppFont.caption)
						.foregroundStyle(JP.inkFaint)
						.lineLimit(1)
				}
			}
			GeometryReader { geo in
				ZStack(alignment: .leading) {
					Capsule().fill(JP.trackFill)
						.overlay(Capsule().strokeBorder(JP.inkFaint.opacity(0.5), lineWidth: 1))
					Capsule().fill(tint.opacity(JP.barFillOpacity))
						.frame(width: max(2, geo.size.width * min(1, max(0, fraction))))
				}
			}
			.frame(height: 10)
			if let footerCaption {
				HStack {
					Spacer(minLength: 0)
					Text(footerCaption)
						.font(JPAppFont.micro)
						.foregroundStyle(JP.inkFaint)
						.lineLimit(1)
				}
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		.accessibilityElement()
		.accessibilityLabel("Official weekly included usage")
		.accessibilityValue("\(usedPercent) percent used, \(remainingPercent) percent remaining")
	}
}

// `internal` (not `private`) so `SparkChartRenderTests` can render the real hero chart — its geometry is
// hoisted out of the animation loop, so a faithful render proof matters. Still only used within this file.
struct SparkChart: View {
	let values: [Double]
	let tint: Color
	let reduceMotion: Bool
	@Environment(\.jpMotionPaused) private var motionPaused

	var body: some View {
		// Geometry (auto-range + both Bézier paths) builds ONCE per layout; only the ping ring animates,
		// so it lives in a nested TimelineView instead of re-running points()/paths every display-link tick.
		GeometryReader { geo in
			let pts = points(in: geo.size)
			ZStack(alignment: .topLeading) {
				if pts.count >= 2 {
					fillPath(pts, height: geo.size.height).fill(
						LinearGradient(
							colors: [tint.opacity(0.22), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
					linePath(pts).stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
				}
				if let last = pts.last {
					if !reduceMotion {
						TimelineView(.animation(paused: motionPaused)) { timeline in
							let ping = RadarPing.phase(at: timeline.date.timeIntervalSinceReferenceDate)
							Circle().fill(tint).frame(width: 8, height: 8)
								.scaleEffect(RadarPing.scale(ping))
								.opacity(RadarPing.opacity(ping))
								.position(last)
						}
					}
					Circle().fill(tint).frame(width: 7, height: 7)
						.overlay(Circle().strokeBorder(JP.card, lineWidth: 2)).position(last)
				}
			}
		}
	}

	private func points(in size: CGSize) -> [CGPoint] {
		SparklineScale.chartPoints(values: values, in: size)
	}

	private func linePath(_ pts: [CGPoint]) -> Path {
		var path = Path()
		path.addLines(pts)
		return path
	}

	private func fillPath(_ pts: [CGPoint], height: CGFloat) -> Path {
		var path = Path()
		guard let first = pts.first, let last = pts.last else { return path }
		path.move(to: CGPoint(x: first.x, y: height))
		pts.forEach { path.addLine(to: $0) }
		path.addLine(to: CGPoint(x: last.x, y: height))
		path.closeSubpath()
		return path
	}
}

// MARK: - Palette
// The JP / JPAppColor palette and the `Color(hex:)` helper now live in
// JPAppDesignTokens.swift — the single token home alongside JPAppFont / JPAppSpacing /
// JPAppRadius. `typealias JP = JPAppColor` keeps every `JP.*` call site here working.

#if DEBUG
extension DashboardView {
	/// Deterministic ImageRenderer fixture: no first-run overlay or changes to real user preferences.
	init(fixtureModel model: DashboardViewModel) {
		self.init(model: model)
		self._showingOnboarding = State(initialValue: false)
	}
}
#endif
