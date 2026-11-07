import SwiftUI

/// The app's one multi-line text input: a `TextEditor` in a JP-styled well with a placeholder that sits
/// EXACTLY where the user's first character will land.
///
/// SwiftUI has no placeholder for `TextEditor`, so the standard workaround overlays a `Text`. The
/// underlying `NSTextView`'s `NSTextContainer` adds its own `lineFragmentPadding` on top of any
/// overlay padding, so both layers must derive from the same constants below or the placeholder jumps
/// when the user types.
/// `JPTextEditorFieldMetrics` is pinned by `JPTextEditorFieldTests` and proven by a real screenshot of
/// the running app (an `ImageRenderer` pass cannot draw `TextEditor` at all).
enum JPTextEditorFieldMetrics {
	/// The ONE number that describes this control: how far the text sits from the well's border. Both
	/// axes derive from it, so the field reads as an evenly-padded box instead of text jammed against
	/// the top edge.
	static let contentInset: CGFloat = 10

	/// The one asymmetry to correct: `TextEditor`'s `NSTextContainer` ADDS its `lineFragmentPadding` on
	/// top of whatever horizontal padding we apply, so the first glyph lands right of the padding edge.
	/// AppKit has defaulted this to 5 forever. Vertical padding applies 1:1 — verified by measuring the
	/// running app, which is the only way to check this (an `ImageRenderer` pass cannot draw a
	/// `TextEditor` at all).
	static let lineFragmentPadding: CGFloat = 5

	/// Padding for the `TextEditor`: subtract horizontally what the container will add back.
	static var editorInsetX: CGFloat { contentInset - lineFragmentPadding }
	static var editorInsetY: CGFloat { contentInset }

	/// The placeholder is a plain `Text` with no container padding, so it takes the target directly.
	/// Both layers therefore put their first glyph at exactly `contentInset` on both axes — the
	/// placeholder must not move when the user starts typing.
	static var placeholderInsetX: CGFloat { contentInset }
	static var placeholderInsetY: CGFloat { contentInset }
}

struct JPTextEditorField: View {
	let placeholder: String
	@Binding var text: String
	/// Total well height. The usable text area is this minus `2 * editorInsetY`.
	var height: CGFloat = 106
	var disabled = false
	var accessibilityLabel: String

	var body: some View {
		ZStack(alignment: .topLeading) {
			if text.isEmpty {
				Text(placeholder)
					.font(JPAppFont.body)
					.foregroundStyle(JP.inkFaint.opacity(0.74))
					.padding(.horizontal, JPTextEditorFieldMetrics.placeholderInsetX)
					.padding(.vertical, JPTextEditorFieldMetrics.placeholderInsetY)
					.allowsHitTesting(false)
					// The real editor draws its own text; a screen reader announcing the placeholder as
					// content too would double up on the field's label.
					.accessibilityHidden(true)
			}

			TextEditor(text: $text)
				.font(JPAppFont.body)
				.foregroundStyle(JP.ink)
				.lineSpacing(2)
				.padding(.horizontal, JPTextEditorFieldMetrics.editorInsetX)
				.padding(.vertical, JPTextEditorFieldMetrics.editorInsetY)
				.frame(height: height)
				.scrollContentBackground(.hidden)
				.background(Color.clear)
				.disabled(disabled)
				.accessibilityLabel(accessibilityLabel)
		}
		.background(JP.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: JPAppRadius.well, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: JPAppRadius.well, style: .continuous)
				.strokeBorder(JP.line, lineWidth: 1))
	}
}
