import AppKit
import Foundation
import SwiftUI

// Extracted from DashboardView.swift, which had grown past 2,600 lines holding 20+ unrelated view
// types. This is the footer's share cluster: the JP-mark button, its popover, and the destination
// table behind it. It shares no state with the dashboard root — the button is the last control in
// `DashboardCardFooter` and everything below is private to this file.
//
// Only `SocialShareButton` is internal (the shared footer builds it); the rest stay private here.
// Every source-text guard over these declarations resolves its anchor through `AppSourceScanner`,
// which walks EVERY app source rather than a file list, so the guards followed this move.

struct SocialShareButton: View {
	@State private var showingShare = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var hovering = false

	var body: some View {
		Button(action: { InteractiveSounds.shared.bottomClick(); showingShare.toggle() }) {
			if let mark = AppResources.image(forResource: "jp-menubar") {
				Image(nsImage: mark).resizable().interpolation(.high)
					.frame(width: JPAppSpacing.footerIconBox, height: JPAppSpacing.footerIconBox)
					.clipShape(RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous))
					.overlay(
						RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
							.strokeBorder(hovering ? JP.ginger.opacity(0.75) : .clear, lineWidth: 1))
					.contentShape(RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous))
			}
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
		.help("Tell others about JP")
		.accessibilityLabel("Tell others about JP")
		.popover(isPresented: $showingShare, arrowEdge: .bottom) {
			SocialSharePopover()
		}
	}
}

private struct SocialSharePopover: View {
	@Environment(\.dismiss) private var dismiss
	@State private var copied = false

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(spacing: 10) {
				if let mark = AppResources.image(forResource: "jp-menubar") {
					Image(nsImage: mark).resizable().interpolation(.high)
						.frame(width: 34, height: 34)
						.clipShape(RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous))
						.accessibilityHidden(true)
				}
				VStack(alignment: .leading, spacing: 2) {
					Text("Tell others about JP")
						.font(JPAppFont.chromeTitle)
						.foregroundStyle(JP.ink)
					Text("Share the cute and useful token cat!")
						.font(JPAppFont.caption)
						.foregroundStyle(JP.inkSoft)
				}
			}
			LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
				ForEach(SocialShareDestination.destinations) { destination in
					Button(action: {
						InteractiveSounds.shared.bottomClick()
						NSWorkspace.shared.open(destination.url)
						dismiss()
					}) {
						SocialShareRow(destination: destination)
					}
					.buttonStyle(.plain)
				}
				Button(action: {
					InteractiveSounds.shared.bottomClick()
					copyShareLink()
				}) {
					HStack(spacing: 10) {
						Image(systemName: copied ? "checkmark.circle.fill" : "link")
							.font(JPAppFont.chromeIcon)
							.foregroundStyle(copied ? JP.sageDeep : JP.gingerDeep)
							.frame(width: 22, height: 22)
						Text(copied ? "Copied link" : "Copy link")
							.font(JPAppFont.bodyStrong)
							.foregroundStyle(JP.ink)
						Spacer(minLength: 0)
					}
					.padding(.horizontal, JPAppSpacing.settingsRowX)
					.padding(.vertical, JPAppSpacing.settingsRowY)
					.background(JP.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous))
					.accessibilityLabel("Put JPtheCat.com on the clipboard")
				}
				.buttonStyle(.plain)
			}
		}
		.padding(JPAppSpacing.panelInset)
		.frame(width: 340, alignment: .topLeading)
		.background(JP.card)
	}

	private func copyShareLink() {
		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		pasteboard.setString(SocialShareDestination.siteURL, forType: .string)
		copied = true
	}
}

private struct SocialShareRow: View {
	let destination: SocialShareDestination
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var hovering = false

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: destination.systemImage)
				.font(JPAppFont.chromeIcon)
				.foregroundStyle(JP.gingerDeep)
				.frame(width: 22, height: 22)
			Text(destination.title)
				.font(JPAppFont.bodyStrong)
				.foregroundStyle(JP.ink)
			Spacer(minLength: 0)
			Image(systemName: "arrow.up.right")
				.font(JPAppFont.micro)
				.foregroundStyle(JP.inkFaint)
		}
		.padding(.horizontal, JPAppSpacing.settingsRowX)
		.padding(.vertical, JPAppSpacing.settingsRowY)
		.background(
			hovering ? JP.honey.opacity(0.18) : JP.paper.opacity(0.72),
			in: RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous)
				.strokeBorder(hovering ? JP.ginger.opacity(0.45) : JP.line.opacity(0.35), lineWidth: 0.6))
		.onHover { hovering = $0 }
		.animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
		.accessibilityLabel("\(destination.title), \(destination.subtitle)")
	}
}

private struct SocialShareDestination: Identifiable {
	let id: String
	let title: String
	let subtitle: String
	let systemImage: String
	let url: URL

	static let siteURL = "https://jpthecat.com"
	private static let shareText = "JP the Cat counts what Claude Code, Codex, Grok, and Muse Spark cost while keeping prompts on your Mac. The cat that counts your agent tokens."
	private static let xShareText = "\(shareText) @8bit"

	static let destinations: [SocialShareDestination] = [
		SocialShareDestination(
			id: "x",
			title: "X / Twitter",
			subtitle: "Posts with @8bit at the end",
			systemImage: "bubble.left.and.bubble.right",
			url: shareURL("https://twitter.com/intent/tweet", query: ["text": xShareText, "url": siteURL])),
		SocialShareDestination(
			id: "facebook",
			title: "Facebook",
			subtitle: "Shares the JP the Cat homepage",
			systemImage: "person.2",
			url: shareURL("https://www.facebook.com/sharer/sharer.php", query: ["u": siteURL])),
		SocialShareDestination(
			id: "linkedin",
			title: "LinkedIn",
			subtitle: "Shares the local-first AI-cost angle",
			systemImage: "briefcase",
			url: shareURL("https://www.linkedin.com/shareArticle", query: ["mini": "true", "url": siteURL, "title": "JP the Cat counts agent tokens", "summary": shareText, "source": "JP the Cat"])),
		SocialShareDestination(
			id: "reddit",
			title: "Reddit",
			subtitle: "Starts a post with crafted title copy",
			systemImage: "text.bubble",
			url: shareURL("https://www.reddit.com/submit", query: ["url": siteURL, "title": shareText])),
		SocialShareDestination(
			id: "email",
			title: "Email",
			subtitle: "Opens a ready-to-send note",
			systemImage: "envelope",
			url: shareURL("mailto:", query: ["subject": "JP the Cat counts agent tokens", "body": "\(shareText)\n\n\(siteURL)"])),
	]

	private static func shareURL(_ base: String, query: [String: String]) -> URL {
		if base == "mailto:" {
			var components = URLComponents()
			components.scheme = "mailto"
			components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
			return components.url ?? URL(string: siteURL)!
		}
		var components = URLComponents(string: base)!
		components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
		return components.url ?? URL(string: siteURL)!
	}
}
