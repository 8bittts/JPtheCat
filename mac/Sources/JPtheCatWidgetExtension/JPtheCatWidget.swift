import AppIntents
import AppKit
import JPtheCatCore
import SwiftUI
import WidgetKit

struct JPtheCatWidgetEntryView: View {
	let entry: JPtheCatWidgetEntry

	@Environment(\.widgetFamily) private var widgetFamily

	var body: some View {
		Group {
			switch widgetFamily {
			case .systemSmall:
				SmallSpendWidget(entry: entry)
			case .systemMedium:
				MediumSpendWidget(entry: entry)
			case .systemLarge:
				LargeSpendWidget(entry: entry)
			default:
				MediumSpendWidget(entry: entry)
			}
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel(accessibilitySummary)
	}

	private var accessibilitySummary: String {
		let snapshot = entry.snapshot
    let amount = WidgetValueFormatter.string(
      snapshot.totalToday, metric: snapshot.metric, code: snapshot.currencyCode)
		// Rule (b): the accessibility value must state the notional basis whenever the total includes
		// Codex list-price. `basis.shortLabel` reads "incl notional" / "notional" / "real spend" — always
		// honest, so we speak it unconditionally rather than deferring disclosure to a per-provider row.
    var parts = [
      snapshot.heroAccessibilitySummary(amount: amount)
    ]
		// Medium + Large voice EVERY contributing provider (same set the visual face shows).
		// Small has no provider rows by design — hero aggregate only.
		if widgetFamily != .systemSmall {
			for provider in WidgetAllProvidersPresentation.providersToDisplay(snapshot.providers) {
				var row: String
				if (provider.metric == .percent || provider.id == "grok_bot") {
					let pct = Int((provider.metric == .percent ? provider.today : (provider.weeklyUsedPercent ?? 0)).rounded())
					row = "\(provider.name), official plan usage, \(pct)% used"
				} else {
					row =
						"\(provider.name) \(WidgetValueFormatter.string(provider.today, metric: provider.metric, code: provider.currencyCode))"
					if provider.usageOfficial,
						let used = provider.usedPercent ?? provider.weeklyUsedPercent
					{
						row += ", \(Int(used.rounded()))% used"
					}
				}
				if provider.metric == .tokens {
					row += ", \(provider.tokenBasisLabel)"
				} else if provider.metric == .dollars, provider.basis != .realSpend {
					row += ", \(provider.basis.shortLabel)"
				}
				parts.append(row)
			}
		}
    if snapshot.isStale() {
      parts.append("data may be stale, open JP the Cat to refresh")
    }
		// Speak the same availability/error disclosure the visual faces show (WidgetFooter/StatusCaption)
		// so VoiceOver never announces "today $0.00" as real spend when every source is unavailable.
		if let notice = snapshot.disclosureNotice { parts.append(notice) }
		return parts.joined(separator: ", ")
	}
}

struct JPtheCatWidget: Widget {
	let kind: String = JPWidgetContract.kind

	var body: some WidgetConfiguration {
		AppIntentConfiguration(
			kind: kind,
			intent: JPtheCatWidgetConfigurationIntent.self,
			provider: JPtheCatWidgetTimelineProvider()
		) { entry in
			JPtheCatWidgetEntryView(entry: entry)
				.containerBackground(for: .widget) {
					JPWidgetBackground()
				}
		}
		.configurationDisplayName("JP the Cat")
		.description("Track AI coding spend and provider limits at a glance.")
		.supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
		// Own ALL padding via each face's explicit `.padding()`. Without this, WidgetKit's default content
		// margins stack ON TOP of our padding — inflating the inset and making top vs left read unequal.
		.contentMarginsDisabled()
	}
}

@main
struct JPtheCatWidgetBundle: WidgetBundle {
	var body: some Widget {
		JPtheCatWidget()
	}
}

// MARK: - Faces

struct SmallSpendWidget: View {
	let entry: JPtheCatWidgetEntry
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			WidgetHeader(title: entry.snapshot.title, compact: true)
			// Amount seats directly under the header (app-hero parity); the single flexible spacer below
			// pins the sparkline to the bottom instead of floating the amount into a dead mid-card gap.
      Text(
        WidgetValueFormatter.string(
          entry.snapshot.totalToday, metric: entry.snapshot.metric,
          code: entry.snapshot.currencyCode)
      )
				.font(.system(size: 24, weight: .semibold, design: .monospaced))
				.foregroundStyle(WidgetPalette.ink(scheme))
				.minimumScaleFactor(0.72)
				.lineLimit(1)
			// Notional disclosure as the SAME pill badge the provider rows use (just "notional", no "incl");
			// the accessibility value still speaks the full "incl notional" basis for the mixed total.
			if entry.snapshot.metric == .percent {
				OfficialBasisBadge()
			} else if entry.snapshot.disclosesNotionalBasis {
				ProviderBasisBadge(text: "notional")
			} else {
				Text(entry.snapshot.primaryValueCaption)
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(WidgetPalette.inkSoft(scheme))
			}
			Spacer(minLength: 6)
			if entry.snapshot.metric != .percent {
				MiniSparkline(values: entry.snapshot.series, tintHex: entry.snapshot.tintHex)
					.frame(height: 24)
			} else if entry.configuration.showLimits,
				let provider = entry.snapshot.providers.first,
				let used = provider.usedPercent ?? provider.weeklyUsedPercent {
				LimitCapsule(percent: used, tint: WidgetPalette.viz(provider.tintHex, scheme))
			}
			WidgetStatusCaption(snapshot: entry.snapshot, isPreview: entry.isPreview)
		}
		// 16pt inset on all sides, matching Large, so the mark/header has the same breathing room above
		// and to the left across every family (Small/Medium were 14 and read too tight).
		.padding(16)
	}
}

struct MediumSpendWidget: View {
	let entry: JPtheCatWidgetEntry
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		// Medium is only 170pt tall — no sparkline (kept on Small + Large). Provider density adapts:
		// ≤2 full gauge rows, ≥3 a 2-column grid so every contributing provider stays visible at
		// the locked 364×170 size (verified via exact-size ImageRenderer harness).
		let providerCount = entry.snapshot.providers.count
		let dense = WidgetAllProvidersPresentation.layout(
			family: .medium, providerCount: providerCount) == .twoColumnGrid
		// Tighter block spacing (7/9 vs 8/10) closes the loose gap below the header/mark and keeps the
		// hero→row rhythm even at the locked 364×170 size.
		VStack(alignment: .leading, spacing: dense ? 7 : 9) {
			if providerCount > 6 {
				HStack(spacing: 8) {
					WidgetHeader(title: entry.snapshot.title, compact: false)
					hero(dense: true)
				}
			} else {
				WidgetHeader(title: entry.snapshot.title, compact: false)
				hero(dense: dense)
			}
			// Provider list sits under the hero (not mid-card). Remaining height falls below the list
			// so a 4-provider grid does not float in a large empty band above the status caption.
      ProviderGaugeList(
        providers: entry.snapshot.providers,
        showLimits: entry.configuration.showLimits,
        family: .medium)
			Spacer(minLength: dense ? 4 : 8)
			WidgetStatusCaption(snapshot: entry.snapshot, isPreview: entry.isPreview)
		}
		// 16pt top + leading to match Large (the mark read too tight at 14); bottom stays 12 so the
		// vertical budget is unchanged from the fits-at-364×170 layout and nothing re-clips.
		.padding(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
	}
	private func hero(dense: Bool) -> some View {
		Text(WidgetValueFormatter.string(entry.snapshot.totalToday,
			metric: entry.snapshot.metric, code: entry.snapshot.currencyCode))
			.font(.system(size: dense ? 26 : 30, weight: .semibold, design: .monospaced))
			.foregroundStyle(WidgetPalette.ink(scheme))
			.minimumScaleFactor(0.7)
			.lineLimit(1)
	}

}

struct LargeSpendWidget: View {
	let entry: JPtheCatWidgetEntry
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		// The REAL placed Large face has less usable height than the exact-size render implies (see
		// mac/AGENTS.md), so budget conservatively: 8pt block spacing + a 66pt sparkline + a 14pt bottom
		// inset keep the footer clear of the bottom edge, and the flexible spacers absorb any slack.
		// Treat a layout change here as unverified until confirmed on a real placed widget.
		VStack(alignment: .leading, spacing: 8) {
			WidgetHeader(title: entry.snapshot.title, compact: false)
			HStack(alignment: .top, spacing: 12) {
				VStack(alignment: .leading, spacing: 3) {
          Text(
            WidgetValueFormatter.string(
              entry.snapshot.totalToday,
              metric: entry.snapshot.metric,
              code: entry.snapshot.currencyCode)
          )
          .font(
            .system(
              size: 34, weight: .semibold,
              design: .monospaced)
          )
						.foregroundStyle(WidgetPalette.ink(scheme))
						.minimumScaleFactor(0.72)
						.lineLimit(1)
					Text(entry.snapshot.primaryValueCaption)
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(WidgetPalette.inkSoft(scheme))
				}
				Spacer(minLength: 6)
				if entry.snapshot.metric != .percent {
				VStack(alignment: .trailing, spacing: 3) {
          Text(
            WidgetValueFormatter.string(
              entry.snapshot.totalWindow,
              metric: entry.snapshot.metric,
              code: entry.snapshot.currencyCode)
          )
          .font(
            .system(
              size: 17, weight: .semibold,
              design: .monospaced)
          )
						.foregroundStyle(WidgetPalette.ink(scheme))
						.minimumScaleFactor(0.72)
						.lineLimit(1)
					Text("last \(entry.snapshot.windowDays) days")
						.font(.system(size: 11, weight: .medium))
						.foregroundStyle(WidgetPalette.inkSoft(scheme))
				}
				}
			}
			if entry.snapshot.metric != .percent {
				MiniSparkline(values: entry.snapshot.series, tintHex: entry.snapshot.tintHex)
					.frame(height: 66)
			}
			Spacer(minLength: 6)
      ProviderGaugeList(
        providers: entry.snapshot.providers,
        showLimits: entry.configuration.showLimits,
        family: .large)
			Spacer(minLength: 6)
			WidgetFooter(snapshot: entry.snapshot, isPreview: entry.isPreview)
		}
		.padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
	}
}
