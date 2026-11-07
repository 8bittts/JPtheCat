import AppIntents
import AppKit
import JPtheCatCore
import SwiftUI
import WidgetKit

// MARK: - Header + mark

// `internal` so the render test can exercise the header at an explicit `compact` (the real Small path,
// since `\.widgetFamily` is read-only and can't be forced through `.environment` in a render harness).
struct WidgetHeader: View {
	let title: String
	let compact: Bool
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		HStack(spacing: 8) {
			JPWidgetMark(size: compact ? 22 : 26)
			VStack(alignment: .leading, spacing: 0) {
				// The Small (170pt) face shows the compact "JP" wordmark (the mark IS the cat) so every Small
				// face matches; the widget's display name and the Medium/Large headers keep the full
				// "JP the Cat" (compact-surface carve-out, like the pill). The driver is Small-face
				// consistency, not truncation.
				Text(compact ? "JP" : "JP the Cat")
					.font(.system(size: compact ? 12 : 13, weight: .semibold))
					.foregroundStyle(WidgetPalette.ink(scheme))
					.lineLimit(1)
				if !compact {
					Text(title)
						.font(.system(size: 11, weight: .medium))
						.foregroundStyle(WidgetPalette.inkSoft(scheme))
						.lineLimit(1)
				}
			}
			Spacer(minLength: 0)
		}
	}
}

struct JPWidgetMark: View {
	let size: CGFloat
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		Group {
			// Load via NSImage (the app's path). SwiftUI's `Image(name:bundle:)` does NOT resolve a loose
			// (non-asset-catalog) PNG on macOS, which is why the mark previously rendered blank; the
			// fallback also now keys on a nil IMAGE, not a nil bundle, so a resolve failure shows "JP".
			if let mark = WidgetAssets.image(named: "jp-menubar") {
				Image(nsImage: mark)
					.resizable()
					.interpolation(.high)
					.scaledToFill()
			} else {
				Text("JP")
          .font(
            .system(
              size: size * 0.38, weight: .bold,
              design: .rounded)
          )
					.foregroundStyle(.black)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.background(WidgetPalette.mascotBadge)
			}
		}
		.frame(width: size, height: size)
		.clipShape(Circle())
		.overlay(Circle().stroke(WidgetPalette.markRim(scheme), lineWidth: 0.6))
		.shadow(color: .black.opacity(0.12), radius: 2, y: 1)
	}
}

// MARK: - Provider rows

/// All-providers list for Medium/Large — always renders every snapshot provider (no silent `prefix`).
/// Density is chosen by `WidgetAllProvidersPresentation.layout` so locked face sizes still fit.
struct ProviderGaugeList: View {
	let providers: [WidgetProviderSnapshot]
	let showLimits: Bool
	let family: WidgetAllProvidersPresentation.Family

	var body: some View {
		// Contract: display set == input set. Never `prefix` / drop a contributing provider.
		let rows = WidgetAllProvidersPresentation.providersToDisplay(providers)
		let layout = WidgetAllProvidersPresentation.layout(
			family: family, providerCount: rows.count)
		switch layout {
		case .fullRows:
			fullWidthStack(rows: rows, showLimits: showLimits, compact: false)
		case .compactRows:
			// Limits drop first when vertical budget is tight — name + basis + amount stay.
			fullWidthStack(rows: rows, showLimits: false, compact: true)
		case .twoColumnGrid:
			twoColumnGrid(rows: rows)
		}
	}

	@ViewBuilder
	private func fullWidthStack(
		rows: [WidgetProviderSnapshot], showLimits: Bool, compact: Bool
	) -> some View {
		VStack(spacing: compact ? 4 : 7) {
			ForEach(rows) { provider in
				ProviderGaugeRow(
					provider: provider, showLimits: showLimits, compact: compact)
			}
		}
	}

	@ViewBuilder
	private func twoColumnGrid(rows: [WidgetProviderSnapshot]) -> some View {
		// Medium's remaining vertical budget after header + hero is ~two compact rows.
		// A 2-column grid keeps every provider visible at 364×170 without clipping.
		let columns = [
			GridItem(.flexible(minimum: 0), spacing: 10),
			GridItem(.flexible(minimum: 0), spacing: 10),
		]
		LazyVGrid(columns: columns, alignment: .leading, spacing: family == .medium && rows.count > 6 ? 0 : 6) {
			ForEach(rows) { provider in
				ProviderGridCell(provider: provider)
			}
		}
	}
}

struct ProviderGaugeRow: View {
	let provider: WidgetProviderSnapshot
	let showLimits: Bool
	var compact: Bool = false
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		HStack(spacing: compact ? 6 : 8) {
			ProviderMarkChip(providerID: provider.id, tintHex: provider.tintHex)
			Text(provider.name)
				.font(.system(size: compact ? 11 : 12, weight: .medium))
				.foregroundStyle(WidgetPalette.ink(scheme))
				.lineLimit(1)
				.minimumScaleFactor(0.85)
			if (provider.metric == .percent || provider.id == "grok_bot"), provider.usageOfficial {
				OfficialBasisBadge()
			} else if provider.metric == .tokens {
				ProviderBasisBadge(text: provider.tokenBasisLabel)
			} else if ProviderBasis.of(rawID: provider.id) == .gateway {
				ProviderBasisBadge(text: ProviderBasis.gateway.badge)
			} else if provider.basis != .realSpend {
				ProviderBasisBadge(text: provider.basis.shortLabel)
			}
			Spacer(minLength: compact ? 4 : 6)
			// Only render an OFFICIAL limit gauge — rule (d) forbids ever surfacing a Claude estimate, so a
			// non-official percentage is treated as absent rather than badged "est". The fill uses the
			// legibility-lifted tint so Codex's charcoal doesn't vanish on the dark card.
			if showLimits, provider.usageOfficial,
				let used = provider.usedPercent ?? provider.weeklyUsedPercent
			{
				LimitCapsule(
					percent: used,
					tint: WidgetPalette.viz(provider.tintHex, scheme)
				)
				.frame(width: compact ? 56 : 76)
			}
			Text(providerDisplayAmount(provider))
			.font(.system(size: compact ? 11 : 12, weight: .semibold, design: .monospaced))
			.foregroundStyle(WidgetPalette.ink(scheme))
			.lineLimit(1)
			.minimumScaleFactor(0.85)
		}
	}
}

/// Compact Medium cell for the 2-column All-providers grid: mark + short name + amount.
/// Basis is carried by the amount metric (`estimate` tokens vs dollars) and the a11y summary.
struct ProviderGridCell: View {
	let provider: WidgetProviderSnapshot
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		HStack(spacing: 6) {
			ProviderMarkChip(providerID: provider.id, tintHex: provider.tintHex)
			Text(WidgetAllProvidersPresentation.shortName(for: provider))
				.font(.system(size: 11, weight: .medium))
				.foregroundStyle(WidgetPalette.ink(scheme))
				.lineLimit(1)
				.minimumScaleFactor(0.8)
			Spacer(minLength: 2)
			Text(
				WidgetValueFormatter.string(
					provider.today, metric: provider.metric,
					code: provider.currencyCode)
			)
			.font(.system(size: 11, weight: .semibold, design: .monospaced))
			.foregroundStyle(WidgetPalette.ink(scheme))
			.lineLimit(1)
			.minimumScaleFactor(0.8)
		}
	}
}

/// The provider brand mark — mirrors the app's `SelectorRow.iconSlot`: a white template glyph on a RAW
/// brand-tint chip (the chip keeps the brand color; a white glyph carries contrast even on a dark
/// card). Falls back to a legibility-lifted dot if the SVG isn't bundled so a provider never renders
/// empty. The SVGs load via NSImage (the app's path), not `Image(name:bundle:)`.
struct ProviderMarkChip: View {
	let providerID: String
	let tintHex: String
	@Environment(\.colorScheme) private var scheme

	private let container: CGFloat = 15
	private let glyph: CGFloat = 10

	var body: some View {
		Group {
			if let mark = WidgetAssets.svg(named: "provider-\(providerID)") {
				ZStack {
          RoundedRectangle(cornerRadius: 5, style: .continuous).fill(
            Color(hex: tintHex))
					RoundedRectangle(cornerRadius: 5, style: .continuous)
						.strokeBorder(.white.opacity(0.22), lineWidth: 1)
					Image(nsImage: mark)
						.resizable()
						.renderingMode(.template)
						.interpolation(.high)
						.scaledToFit()
						.foregroundStyle(.white)
						.frame(width: glyph, height: glyph)
				}
			} else {
				Circle()
					.fill(WidgetPalette.viz(tintHex, scheme))
					.frame(width: 8, height: 8)
			}
		}
		.frame(width: container, height: container)
	}
}

func providerDisplayAmount(_ provider: WidgetProviderSnapshot) -> String {
	if provider.id == "grok_bot", provider.metric != .percent, provider.usageOfficial, let weekly = provider.weeklyUsedPercent {
		return "\(Int(weekly.rounded()))%"
	}
	return WidgetValueFormatter.string(
		provider.today, metric: provider.metric, code: provider.currencyCode)
}

struct OfficialBasisBadge: View {
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		Text(ProviderBasis.officialPlan.badge)
			.font(.system(size: 10, weight: .semibold, design: .monospaced))
			.foregroundStyle(WidgetPalette.sageDeep(scheme))
			.lineLimit(1)
			.fixedSize()
			.padding(.horizontal, LabelBadgeMetrics.horizontalInset)
			.frame(height: LabelBadgeMetrics.height)
			.background(WidgetPalette.sageWash(scheme), in: Capsule())
	}
}

struct ProviderBasisBadge: View {
	let text: String
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		// `.fixedSize()` so the badge always shows the whole word — under a large dollar value it used to
		// lose width to the fixed-width gauge + money and truncate to "notion…".
		Text(text)
			.font(.system(size: 10, weight: .semibold, design: .monospaced))
			.foregroundStyle(WidgetPalette.gingerDeep(scheme))
			.lineLimit(1)
			.fixedSize()
			.padding(.horizontal, LabelBadgeMetrics.horizontalInset)
			.frame(height: LabelBadgeMetrics.height)
			.background(WidgetPalette.honeyWash(scheme), in: Capsule())
	}
}

struct LimitCapsule: View {
	let percent: Double
	let tint: Color
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		// A bare gauge bar — the sub-bar "31% · 83% wk" caption was unreadable at widget scale (9pt), so
		// the bar shows the primary official fill (short window, otherwise weekly). Exact pool labels
		// live in the app dashboard; the accessibility value voices the reported used percent.
		// Opaque `track` role (not a translucent gray) so the empty groove reads on the dark card.
		GeometryReader { proxy in
			ZStack(alignment: .leading) {
				Capsule().fill(WidgetPalette.track(scheme))
				Capsule()
					.fill(tint)
					.frame(width: proxy.size.width * fraction(percent))
			}
		}
		.frame(height: 6)
	}

	private func fraction(_ value: Double) -> Double { max(0, min(1, value / 100)) }
}

// MARK: - Sparkline

struct MiniSparkline: View {
	let values: [Double]
	let tintHex: String
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		let tint = WidgetPalette.viz(tintHex, scheme)
		GeometryReader { proxy in
			let points = normalizedPoints(in: proxy.size)
			ZStack {
				LinearGradient(
					colors: [tint.opacity(0.16), tint.opacity(0.02)],
					startPoint: .top,
          endPoint: .bottom
        )
				.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
				Path { path in
					guard let first = points.first else { return }
					path.move(to: first)
					for point in points.dropFirst() {
						path.addLine(to: point)
					}
				}
        .stroke(
          tint,
          style: StrokeStyle(
            lineWidth: 2.6, lineCap: .round, lineJoin: .round))
				if points.count >= 2, let last = points.last {
					// Halo keyed to the widget card color (not `.background`, which resolves to the system
					// container background and decouples the halo from JP's paper/charcoal card).
					Circle()
						.fill(WidgetPalette.card(scheme))
						.frame(width: 9, height: 9)
						.position(last)
					Circle()
						.fill(tint)
						.frame(width: 5, height: 5)
						.position(last)
				}
			}
		}
	}

	private func normalizedPoints(in size: CGSize) -> [CGPoint] {
		let points = SparklineScale.chartPoints(values: values, in: size)
		guard points.count >= 2 else {
			let pad = SparklineScale.verticalPadding(forHeight: size.height)
			return [CGPoint(x: 0, y: size.height - pad), CGPoint(x: size.width, y: size.height - pad)]
		}
		return points
	}

}

// MARK: - Footer + status

struct WidgetFooter: View {
	let snapshot: WidgetSnapshot
	let isPreview: Bool
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		HStack(spacing: 6) {
			freshness
				.font(.system(size: 11, weight: .medium))
			if let notice = snapshot.disclosureNotice {
				Text(notice)
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(WidgetPalette.gingerDeep(scheme))
					.lineLimit(1)
			}
			Spacer(minLength: 0)
			// Notional is disclosed by the per-provider `notional` badge in the rows (and the a11y value);
			// the redundant aggregate "incl notional" footer label is dropped.
		}
	}

	// A stale snapshot must announce itself instead of presenting hours-old (or prior-day) numbers as
	// live; when fresh, `Text(_, style: .relative)` self-updates between WidgetKit reloads so the age
	// doesn't freeze at "just now".
	@ViewBuilder private var freshness: some View {
		if isPreview {
			Text("Preview data").foregroundStyle(WidgetPalette.inkSoft(scheme))
		} else if snapshot.isStale() {
      Text("Stale — open JP the Cat").foregroundStyle(
        WidgetPalette.gingerDeep(scheme))
		} else {
			HStack(spacing: 3) {
				Text("Updated")
				Text(snapshot.generatedAt, style: .relative)
			}
			.foregroundStyle(WidgetPalette.inkSoft(scheme))
		}
	}
}

/// Compact status line for the Small/Medium faces (which have no footer): surfaces a refresh error,
/// preview-data disclosure, or a stale marker, and renders nothing in the normal fresh state.
struct WidgetStatusCaption: View {
	let snapshot: WidgetSnapshot
	let isPreview: Bool
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		if let caption {
			Text(caption)
				.font(.system(size: 10, weight: .medium))
				.foregroundStyle(
					snapshot.disclosureNotice != nil
            ? WidgetPalette.gingerDeep(scheme)
            : WidgetPalette.inkSoft(scheme)
        )
				.lineLimit(1)
				.minimumScaleFactor(0.85)
		}
	}

	private var caption: String? {
		if let notice = snapshot.disclosureNotice { return notice }
		if isPreview { return "Preview data" }
		if snapshot.isStale() { return "Stale — open JP the Cat" }
		return nil
	}
}

struct JPWidgetBackground: View {
	// macOS widgets honor the system appearance; the card must follow it. All widget text/roles resolve
	// through `WidgetPalette` per `ColorScheme`, so a light-only cream card would have put dark ink text
	// on... nothing legible in Dark Mode. The gradient flips to a warm charcoal in dark so contrast
	// holds in both appearances without abandoning JP's paper look (and matches the app's Midnight card).
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
		WidgetPalette.background(colorScheme)
	}
}
