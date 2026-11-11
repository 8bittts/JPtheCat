import Foundation

struct OfficialUsageLink: Equatable, Sendable {
	struct Run: Equatable, Sendable {
		var text: String
		var url: URL?
	}

	let runs: [Run]

	static let openCodeConsole = "https://opencode.ai/console"

	var plainText: String { runs.map(\.text).joined() }

	/// One wrapping sentence. Linked words carry an arrow and stay tappable.
	func attributed() -> AttributedString {
		var result = AttributedString()
		for run in runs {
			var part = AttributedString(run.text)
			if let url = run.url {
				part.link = url
				part.underlineStyle = .single
				result += part
				var arrow = AttributedString("\u{00A0}\u{2197}")
				arrow.link = url
				result += arrow
			} else {
				result += part
			}
		}
		return result
	}

	var links: [(text: String, url: URL)] {
		runs.compactMap { run in run.url.map { (run.text, $0) } }
	}

	/// One wrapping sentence. A run with a URL is a link; the words around it stay plain.
	/// Grok names Cursor, Grok, and Grok Bot because those are three different official pages.
	/// OpenCode names Zen and Go the same way, and only when a workspace id was detected locally.
	static func sentence(for providerID: String, openCodeWorkspaceID: String? = nil) -> OfficialUsageLink? {
		switch providerID {
		case "claude":
			return link("View official usage in Claude", "https://claude.ai/settings/usage")
		case "codex":
			return link("View official usage in Codex", "https://chatgpt.com/settings/usage?tab=overview")
		case "grok":
			return grokPlansSentence()
		case "grok_bot":
			return link("View official usage in Grok Bot", "https://grok.com/dashboard")
		case "muse_spark":
			return link("View official usage in Meta", "https://dev.meta.ai/usage/")
		case "copilot":
			return link("View Copilot settings in GitHub", "https://github.com/settings/copilot/features")
		case "cursor":
			return link("View official usage in Cursor", "https://cursor.com/dashboard/spending")
		case "opencode", "opencodego":
			guard let workspaceID = openCodeWorkspaceID else { return nil }
			return linked(
				"View official ",
				("Zen", "\(openCodeConsole)/\(workspaceID)/billing"),
				" or ",
				("Go", "\(openCodeConsole)/\(workspaceID)/go"),
				" usage.")
		default:
			return nil
		}
	}

	/// Cursor, the Grok subscription, and Grok Bot are three plans. The sentence names each page.
	private static func grokPlansSentence() -> OfficialUsageLink? {
		guard
			let cursor = URL(string: "https://cursor.com/dashboard/spending"),
			let grok = URL(string: "https://grok.com/?_s=usage"),
			let bot = URL(string: "https://grok.com/dashboard")
		else { return nil }
		return OfficialUsageLink(runs: [
			Run(text: "View official ", url: nil),
			Run(text: "Cursor", url: cursor),
			Run(text: ", ", url: nil),
			Run(text: "Grok", url: grok),
			Run(text: ", or ", url: nil),
			Run(text: "Grok Bot", url: bot),
			Run(text: " plan usage.", url: nil),
		])
	}

	private static func link(_ title: String, _ url: String) -> OfficialUsageLink? {
		guard let url = URL(string: url) else { return nil }
		return OfficialUsageLink(runs: [Run(text: title, url: url)])
	}

	private static func linked(
		_ lead: String,
		_ first: (String, String),
		_ join: String,
		_ second: (String, String),
		_ tail: String
	) -> OfficialUsageLink? {
		guard let firstURL = URL(string: first.1), let secondURL = URL(string: second.1) else { return nil }
		return OfficialUsageLink(runs: [
			Run(text: lead, url: nil),
			Run(text: first.0, url: firstURL),
			Run(text: join, url: nil),
			Run(text: second.0, url: secondURL),
			Run(text: tail, url: nil),
		])
	}
}
