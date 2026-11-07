import Foundation
import SwiftUI
import JPtheCatCore

// Extracted from DashboardView.swift. The header readout: the basis-label ticker band and the
// split-flap money hero beneath it. Both are pure presentation driven by their inputs, and the
// Advanced Analytics window already reuses the basis chip, so this is shared chrome rather than
// dashboard-root internals.
//
// The flap timing model itself is the pure, unit-tested `SplitFlapTransition` (its own file); what
// lives here is only the AppKit-side visuals it drives.

// MARK: - Header readout

struct BasisLabelChip: View {
	let text: String
	let reduceMotion: Bool

	var body: some View {
		TickerTapeText(text: text, reduceMotion: reduceMotion)
			.frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
	}
}

struct TickerTapeMotion: Equatable {
	let distance: CGFloat
	let duration: Double

	static let shared = TickerTapeMotion(distance: 132, duration: 12)

	static func motion(for _: String) -> TickerTapeMotion { shared }
}

private struct TickerTapeText: View {
	let text: String
	let reduceMotion: Bool
	@Environment(\.jpMotionPaused) private var motionPaused

	var body: some View {
		GeometryReader { proxy in
			ZStack(alignment: .leading) {
				JP.paper2
				if reduceMotion {
					label(text)
						.padding(.leading, 6)
				} else {
					TimelineView(.animation(paused: motionPaused)) { timeline in
						tape
							.offset(x: tickerOffset(at: timeline.date) + 6)
					}
				}
			}
			.frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
			.clipped()
			.background(JP.paper2)
			.clipShape(RoundedRectangle(cornerRadius: JPAppRadius.chip, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: JPAppRadius.chip, style: .continuous)
					.strokeBorder(JP.line.opacity(0.8), lineWidth: 0.5))
			.mask { edgeFade }
		}
		// The marquee draws the basis string up to 3× under normal motion; collapse to one spoken
		// element so VoiceOver reads the basis once, not repeated per tape copy.
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(text)
	}

	private var tapeDivider: some View {
		Circle().fill(JP.inkFaint.opacity(0.65)).frame(width: 3, height: 3)
	}

	private var tape: some View {
		HStack(spacing: 14) {
			label(text)
			tapeDivider
			label(text)
			tapeDivider
			label(text)
		}
	}

	private func label(_ value: String) -> some View {
		Text(value)
			.font(JPAppFont.eyebrowStrong)
			.foregroundStyle(JP.inkFaint)
			.lineLimit(1)
			.fixedSize(horizontal: true, vertical: false)
	}

	private var edgeFade: some View {
		LinearGradient(
			stops: [
				.init(color: .clear, location: 0),
				.init(color: .black.opacity(0.55), location: 0.09),
				.init(color: .black, location: 0.16),
				.init(color: .black, location: 0.84),
				.init(color: .black.opacity(0.55), location: 0.91),
				.init(color: .clear, location: 1),
			],
			startPoint: .leading,
			endPoint: .trailing)
	}

	private func tickerOffset(at date: Date) -> CGFloat {
		let motion = TickerTapeMotion.motion(for: text)
		guard motion.duration > 0 else { return 0 }
		let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: motion.duration) / motion.duration
		return -motion.distance * CGFloat(phase)
	}
}

struct SplitFlapMoney: View {
	let value: Double
	var currencyCode: String = MoneyFormatter.baseCurrencyCode
	var notional: Bool = false
	let reduceMotion: Bool
	/// When set, renders this text verbatim instead of formatting `value` as money — used for a
	/// fully-unpriced provider (Copilot) whose dollar figure would be a dead `$0.00`, showing a token
	/// count ("53.6K tok") instead. `value` is ignored in that case (kept required so every OTHER call
	/// site stays money-based without an extra parameter).
	var textOverride: String? = nil
	/// When `textOverride` is set, spoken accessibility can differ from the token-estimate default.
	var textOverrideAccessibilityLabel: String? = nil
	@State private var displayed = ""
	@State private var flipping: Set<Int> = []
	@State private var animationGeneration = 0

	private var target: String { textOverride ?? MoneyFormatter.dollars(value, code: currencyCode) }
	private var characters: [Character] { Array(displayed.isEmpty ? target : displayed) }

	var body: some View {
		HStack(spacing: 3) {
			ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
				SplitFlapCharacter(character: character, isFlipping: flipping.contains(index), reduceMotion: reduceMotion)
			}
		}
		// Collapse the per-character flap tiles into ONE value — without this each tile is its own
		// leaf and VoiceOver reads "$", "1", ",", "2", … instead of the whole amount + notional basis.
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(
			textOverrideAccessibilityLabel
				?? (textOverride != nil
					? "\(target), an estimate — not as precise as Claude/Codex/Grok"
					: (notional ? "\(target), includes notional list price" : target))
		)
		.onAppear { displayed = target }
		.onChange(of: target) { _, newValue in update(to: newValue) }
	}

	private func update(to newValue: String) {
		guard displayed != newValue else { return }
		animationGeneration += 1
		let generation = animationGeneration
		flipping = []
		guard !reduceMotion else {
			displayed = newValue
			return
		}
		// Timing + finish-state come from the pure, unit-tested `SplitFlapTransition` (it guards on
		// equal-length / non-empty / has-changes and returns nil to snap). The `asyncAfter` +
		// implicit-`withAnimation` visuals below are the shipped flap look, driven verbatim by the
		// model's per-index schedule — so a test can assert the terminal state without exercising AppKit.
		guard let transition = SplitFlapTransition(old: Array(displayed), new: Array(newValue)) else {
			displayed = newValue
			return
		}

		for step in transition.steps {
			DispatchQueue.main.asyncAfter(deadline: .now() + step.flipAt) {
				guard animationGeneration == generation else { return }
				withAnimation(.easeInOut(duration: 0.12)) {
					_ = flipping.insert(step.index)
				}
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + step.swapAt) {
				guard animationGeneration == generation else { return }
				var currentCharacters = Array(displayed)
				guard step.index < currentCharacters.count else { return }
				currentCharacters[step.index] = transition.new[step.index]
				displayed = String(currentCharacters)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + step.releaseAt) {
				guard animationGeneration == generation else { return }
				withAnimation(.easeOut(duration: 0.16)) {
					_ = flipping.remove(step.index)
				}
			}
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + transition.finishAt) {
			guard animationGeneration == generation else { return }
			displayed = newValue
			flipping = []
		}
	}
}

private struct SplitFlapCharacter: View {
	let character: Character
	let isFlipping: Bool
	let reduceMotion: Bool

	private var tileWidth: CGFloat {
		switch character {
		case "$": 25
		case ".", ",": 15
		default: 24
		}
	}

		var body: some View {
			RoundedRectangle(cornerRadius: JPAppRadius.tile, style: .continuous)
				.fill(JP.paper)
				.shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
				.frame(width: tileWidth, height: 48)
			.overlay(
				// The glyph renders at its natural (monospaced) width, centered over the tile — so a narrow
				// "." / "," flap can't clip the character the way a hard `.frame(width:)` on the Text did.
				Text(String(character))
					.font(JPAppFont.metricHero)
					.foregroundStyle(JP.ink)
					.fixedSize())
			.overlay(Rectangle().fill(JP.lineStrong.opacity(0.75)).frame(height: 1), alignment: .center)
			.overlay(Rectangle().fill(.white.opacity(0.35)).frame(height: 1), alignment: .top)
			.rotation3DEffect(
				.degrees(isFlipping && !reduceMotion ? -82 : 0),
				axis: (x: 1, y: 0, z: 0),
				anchor: .center,
				perspective: 0.72)
			.animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isFlipping)
	}
}
