import AppKit
import Foundation
import SwiftUI

// Extracted from DashboardView.swift. The first-run scene shown until the first provider event is
// indexed: JP peeking out from behind a bubble bath, over the "waiting for token pawprints" copy.
// It is entirely self-contained — `FirstRunEmptyState` takes two scalars and reads nothing from the
// dashboard's state — so only it is internal and every helper below stays private to this file.

// MARK: - First-run empty state

struct FirstRunEmptyState: View {
	let isRefreshing: Bool
	let reduceMotion: Bool

	var body: some View {
		VStack(spacing: 12) {
			FirstRunHero(reduceMotion: reduceMotion)
				.frame(height: 142)
				.accessibilityHidden(true)

			VStack(spacing: 5) {
				Text(isRefreshing ? "JP is sniffing for token pawprints..." : "JP is waiting for token pawprints")
					.font(JPAppFont.emptyTitle)
					.foregroundStyle(JP.ink)
					.multilineTextAlignment(.center)
				Text("Run your agents and JP will start counting. 🐾")
					.font(JPAppFont.body)
					.foregroundStyle(JP.inkFaint)
					.multilineTextAlignment(.center)
					.lineSpacing(1.5)
			}
		}
		.frame(maxWidth: .infinity)
		.accessibilityElement(children: .combine)
	}
}

private struct FirstRunHero: View {
	let reduceMotion: Bool

	var body: some View {
		ZStack(alignment: .bottom) {
			backdrop
			ThoughtBubbles(reduceMotion: reduceMotion)
				.offset(x: -2, y: -30)
			JPPeekHead()
				.offset(y: 82)
		}
		.frame(maxWidth: .infinity)
		.overlay(alignment: .bottom) {
			LinearGradient(
				colors: [JP.card.opacity(0), JP.card],
				startPoint: .top,
				endPoint: .bottom)
				.frame(height: 38)
		}
		.clipped()
	}

	private var backdrop: some View {
		ZStack {
			LinearGradient(
				colors: [JP.paper2.opacity(0.62), JP.card.opacity(0.0)],
				startPoint: .top,
				endPoint: .bottom)
			RadialGradient(
				colors: [JP.honey.opacity(0.2), JP.honey.opacity(0.06), JP.card.opacity(0.0)],
				center: .bottom,
				startRadius: 24,
				endRadius: 172)
		}
		.mask {
			LinearGradient(
				stops: [
					.init(color: .clear, location: 0),
					.init(color: .black, location: 0.14),
					.init(color: .black, location: 0.86),
					.init(color: .clear, location: 1),
				],
				startPoint: .leading,
				endPoint: .trailing)
		}
	}
}

private struct JPPeekHead: View {
	var body: some View {
		Group {
			if let image = AppResources.image(forResource: "jp-first-run-peek") {
				Image(nsImage: image)
					.resizable()
					.interpolation(.high)
					.scaledToFit()
			} else {
				Circle().fill(JP.honey.opacity(0.55))
			}
		}
		.frame(width: 172, height: 172)
		.shadow(color: JP.ginger.opacity(0.14), radius: 10, x: 0, y: 4)
	}
}

/// A generous "bubble bath" of many different-sized soap bubbles filling the space around JP on the
/// loading screen — not a few thought bubbles. The field is a deterministic pseudo-random spread (no
/// RNG) so the layout is stable across launches.
private struct ThoughtBubbles: View {
	let reduceMotion: Bool
	@Environment(\.jpMotionPaused) private var motionPaused

	private static let bubbles: [BubbleSpec] = BubbleSpec.field(count: 24, width: 250, height: 128)

	var body: some View {
		// ONE display-link drives all 24 bubbles. Previously each `FloatingBubble` owned its own
		// `TimelineView(.animation)` — 24 independent rAF subscriptions on the first-run screen.
		Group {
			if reduceMotion {
				field(date: nil)
			} else {
				TimelineView(.animation(paused: motionPaused)) { timeline in
					field(date: timeline.date)
				}
			}
		}
		.frame(width: 250, height: 128)
	}

	private func field(date: Date?) -> some View {
		ZStack {
			ForEach(Self.bubbles) { bubble in
				FloatingBubble(spec: bubble, date: date)
			}
		}
	}
}

/// One bubble's placement + timing. `field` lays out a natural-looking spread with the classic
/// `fract(sin·k)` hash so there's variety without `Math.random` (stable, testable positions).
private struct BubbleSpec: Identifiable {
	let id: Int
	let x: CGFloat
	let y: CGFloat
	let size: CGFloat
	let delay: Double
	let rise: CGFloat
	let drift: CGFloat

	static func field(count: Int, width: CGFloat, height: CGFloat) -> [BubbleSpec] {
		(0..<count).map { i in
			let f = Double(i) + 1
			func frac(_ seed: Double) -> Double {
				let v = sin(f * seed) * 43758.5453
				return v - v.rounded(.down)
			}
			let hx = frac(12.9898), hy = frac(78.233), hs = frac(39.425), hd = frac(51.17)
			return BubbleSpec(
				id: i,
				x: CGFloat(hx) * width - width / 2,
				y: CGFloat(hy) * height - height / 2,
				size: 5 + CGFloat(hs) * 16,  // 5…21pt — lots of size variety
				delay: hd * 2.8,
				rise: 16 + CGFloat(hy) * 20,  // 16…36pt upward drift
				drift: (CGFloat(hx) - 0.5) * 10)  // gentle left/right wobble
		}
	}
}

private struct FloatingBubble: View {
	let spec: BubbleSpec
	/// The shared clock from the parent's single `TimelineView`; `nil` parks the bubble (reduced motion).
	let date: Date?

	var body: some View {
		bubble(progress: date.map { progress(at: $0) } ?? 0)
	}

	private func progress(at date: Date) -> Double {
		let duration = 2.6
		let shifted = date.timeIntervalSinceReferenceDate + spec.delay
		let phase = shifted.truncatingRemainder(dividingBy: duration) / duration
		return (1 - cos(.pi * phase)) / 2
	}

	private func bubble(progress: Double) -> some View {
		let p = CGFloat(min(max(progress, 0), 1))
		return Circle()
			.fill(JP.paper2.opacity(0.85))
			.overlay(Circle().strokeBorder(JP.lineStrong, lineWidth: 1.2))
			.overlay(
				// soap-bubble sheen
				Circle().fill(.white.opacity(0.6))
					.frame(width: spec.size * 0.3, height: spec.size * 0.3)
					.offset(x: -spec.size * 0.17, y: -spec.size * 0.17))
			.frame(width: spec.size, height: spec.size)
			.scaleEffect(0.84 + 0.28 * p)
			.opacity(0.92 - 0.6 * p)
			.offset(
				x: spec.x + spec.drift * p,
				y: spec.y - spec.rise * p)
	}
}
