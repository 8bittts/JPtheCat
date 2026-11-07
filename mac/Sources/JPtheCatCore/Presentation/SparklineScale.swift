import Foundation

/// Vertical normalization for the dashboard hero sparkline, shared as the ONE source of truth so every
/// provider's chart reads honestly on its own terms — the model for every future provider we add.
///
/// The regression this prevents: a low/steady provider (e.g. Codex) plotted against a shared
/// cross-provider maximum anchored at zero collapses into a near-flat line under a bigger provider's
/// peak, hiding its real day-to-day variation. The fix is **per-provider auto-range with a
/// min-anchored baseline** — each series is scaled to its OWN min→max, so the full vertical band is
/// used regardless of absolute spend level.
///
/// Two guardrails are load-bearing and are exactly what this pure function (and its test) lock in:
///  1. The baseline is the series **minimum**, never zero, so amplitude is independent of magnitude.
///  2. A `peak * headroomFraction` **floor** in the denominator keeps a genuinely near-flat series
///     from amplifying trivial noise into a full-height jagged line — honest amplitude, not invented
///     variation. A single dominant spike day legitimately compresses the rest (the tail *is* flat
///     relative to that spike).
///
/// Pure (values in, 0…1 fractions out; 0 = series minimum at the baseline, 1 = series peak at the top)
/// so it lives in Core with no SwiftUI/AppKit dependency. `SparkChart.points(in:)` maps these
/// fractions to y-coordinates; never reintroduce a shared `chartScaleMax` or a `value / globalMax`
/// zero-anchored mapping at the call site.
public enum SparklineScale {
	/// Minimum visible variation as a fraction of the series peak. Below this, a series is treated as
	/// effectively flat so noise is not blown up to full height.
	public static let headroomFraction = 0.15

	/// Normalized 0…1 heights for a series, min-anchored and per-series auto-ranged.
	/// - Returns one fraction per input value (`(v - min) / denom`). An empty input returns `[]`; a
	///   perfectly flat series returns all-zero (parked on the baseline, never divide-by-zero).
	public static func fractions(_ values: [Double]) -> [Double] {
		guard let hi = values.max(), let lo = values.min() else { return [] }
		let denom = Swift.max(hi - lo, hi * headroomFraction, 0.000001)
		return values.map { ($0 - lo) / denom }
	}

	/// Vertical inset for sparkline drawing — safe at compact selector heights (5pt quota bars use
	/// a separate meter; sparklines use ≥16pt).
	public static func verticalPadding(forHeight height: CGFloat) -> CGFloat {
		min(4, height * 0.22)
	}

	/// Maps a series to chart points in a rect using min-anchored `fractions`. Higher values sit nearer
	/// the top (smaller y). Guard: `SparklineScaleTests.testChartPointsPeakAboveTrough`.
	public static func chartPoints(values: [Double], in size: CGSize) -> [CGPoint] {
		guard !values.isEmpty else { return [] }
		let pad = verticalPadding(forHeight: size.height)
		let usableH = max(1, size.height - pad * 2)
		let fractions = fractions(values)
		let stepX = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0
		return fractions.enumerated().map { index, fraction in
			CGPoint(x: CGFloat(index) * stepX, y: pad + usableH * (1 - CGFloat(fraction)))
		}
	}
}
