import SwiftUI

struct OnboardingView: View {
	let windowChrome: Bool
	let onContinue: () -> Void
	let onOpenSettings: () -> Void
	let onRefresh: () -> Void
	let onQuit: () -> Void
	let onOpenWebsite: () -> Void

	// periphery:ignore - intentional theme dependency so this root re-renders on any theme switch;
	// @ObservedObject subscribes at the object level even though `.theme` isn't read directly below.
	@ObservedObject private var themeManager = ThemeManager.shared
	@Environment(\.dashboardLayout) private var layout

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			topBar
			rule
			content
			rule
			DashboardCardFooter(
				leadingText: "First run",
				onRefresh: onRefresh,
				onQuit: onQuit,
				onOpenWebsite: onOpenWebsite)
		}
		.frame(width: layout.width, alignment: .top)
		.background(JP.card)
		// No `.preferredColorScheme` — see the matching note on `DashboardView.body`; `ThemeManager
		// .apply()` already drives the app-wide `NSApp.appearance`, and `JP.*` reads `JPTheme.current`
		// directly, so this duplicate SwiftUI-level invalidation isn't needed and was contributing to
		// the theme-switch freeze.
		.accessibilityElement(children: .contain)
	}

	private var topBar: some View {
		ChromeTitleRow(windowChrome: windowChrome) {
			Text("FIRST RUN")
				.font(JPAppFont.chip)
				.foregroundStyle(JP.gingerDeep)
				.labelBadgeLayout()
				.background(JP.honey.opacity(0.16), in: Capsule())
		}
	}

	private var content: some View {
		VStack(alignment: .leading, spacing: 16) {
			hero
			VStack(alignment: .leading, spacing: 8) {
				Text("The cat that counts your agent tokens.")
					.font(JPAppFont.emptyTitle)
					.foregroundStyle(JP.ink)
					.fixedSize(horizontal: false, vertical: true)
				Text("JP watches Claude Code, Codex, Grok, and Muse Spark usage from your Mac, then keeps the menu-bar total honest without sending prompts anywhere.")
					.font(JPAppFont.body)
					.foregroundStyle(JP.inkSoft)
					.lineSpacing(1.5)
					.fixedSize(horizontal: false, vertical: true)
			}
			featureList
			actions
		}
		.padding(.horizontal, JPAppSpacing.contentX)
		.padding(.vertical, 18)
	}

	private var hero: some View {
		HStack(alignment: .center, spacing: 14) {
			Group {
				if let image = AppResources.image(forResource: "jp-first-run-peek") {
					Image(nsImage: image)
						.resizable()
						.interpolation(.high)
						.scaledToFit()
				} else {
					Circle().fill(JP.honey.opacity(0.5))
				}
			}
			.frame(width: 92, height: 92)
			.shadow(color: JP.ginger.opacity(0.14), radius: 9, x: 0, y: 4)
			.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 7) {
				Text("Local-first meter")
					.font(JPAppFont.eyebrowStrong)
					.foregroundStyle(JP.gingerDeep)
				Text("Prompts, code, and transcripts stay on this Mac.")
					.font(JPAppFont.bodyStrong)
					.foregroundStyle(JP.ink)
					.fixedSize(horizontal: false, vertical: true)
				Text("Website analytics stay on the website. The app reads only local usage sources.")
					.font(JPAppFont.caption)
					.foregroundStyle(JP.inkFaint)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.padding(12)
		.background(
			LinearGradient(
				colors: [JP.honey.opacity(0.16), JP.paper2.opacity(0.52)],
				startPoint: .topLeading,
				endPoint: .bottomTrailing),
			in: RoundedRectangle(cornerRadius: JPAppRadius.panel, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: JPAppRadius.panel, style: .continuous)
				.strokeBorder(JP.honey.opacity(0.42), lineWidth: 1))
	}

	private var featureList: some View {
		VStack(spacing: 8) {
			OnboardingFeatureRow(
				icon: "creditcard",
				title: "Claude dollars",
				subtitle: "Real local Claude Code cost, including cache pricing.")
			OnboardingFeatureRow(
				icon: "gauge.medium",
				title: "Codex limits",
				subtitle: "Official 5-hour and weekly used percentages stay labelled as used.")
			OnboardingFeatureRow(
				icon: "lock.shield",
				title: "Free and local",
				subtitle: "No account, no key. Everything stays on this Mac.")
		}
	}

	private var actions: some View {
		HStack(spacing: 8) {
			Button(action: { InteractiveSounds.shared.bottomClick(); onContinue() }) {
				Text("Start tracking")
					.font(JPAppFont.chromeAction)
					.foregroundStyle(JP.ctaText)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 8)
					.background(
						JP.ctaGradient,
						in: RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous))
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Start tracking")

			Button(action: { InteractiveSounds.shared.bottomClick(); onOpenSettings() }) {
				Text("Open Settings")
					.font(JPAppFont.chromeAction)
					.foregroundStyle(JP.gingerDeep)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 8)
					.background(
						JP.paper.opacity(0.72),
						in: RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous))
					.overlay(
						RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
							.strokeBorder(JP.line, lineWidth: 1))
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Open Settings")
		}
	}

	private var rule: some View { Rectangle().fill(JP.line).frame(height: 1) }
}

private struct OnboardingFeatureRow: View {
	let icon: String
	let title: String
	let subtitle: String

	var body: some View {
		HStack(alignment: .top, spacing: 9) {
			Image(systemName: icon)
				.font(JPAppFont.settingsIcon)
				.foregroundStyle(JP.gingerDeep)
				.frame(width: 18, height: 18)
				.padding(.top, 1)
				// Decorative accent — the title/subtitle carry the meaning, so don't make VoiceOver read
				// the SF Symbol name ("credit card", "gauge", "lock shield") before each feature.
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(JPAppFont.bodyStrong)
					.foregroundStyle(JP.ink)
				Text(subtitle)
					.font(JPAppFont.caption)
					.foregroundStyle(JP.inkFaint)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, JPAppSpacing.noticeX)
		.padding(.vertical, 8)
		.background(JP.paper2.opacity(0.42), in: RoundedRectangle(cornerRadius: JPAppRadius.well, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: JPAppRadius.well, style: .continuous)
				.strokeBorder(JP.line.opacity(0.55), lineWidth: 1))
	}
}
