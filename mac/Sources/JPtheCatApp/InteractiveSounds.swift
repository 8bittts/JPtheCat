import AVFoundation
import Foundation

/// Plays JP the Cat's short interactive UI cues — the settle sounds for toggles and the light clicks
/// for the top chrome and bottom footer buttons. Every cue is gated on the SAME global master as the
/// meow (`SettingsStore.interactiveSoundsEnabled`), so turning "Interactive sounds" off in Settings
/// silences the whole set. Players are preloaded and cached (one per cue) so a rapid click never pays
/// for a fresh decode. The homepage `menubar-demo.tsx` mirrors these cues with the matching
/// `web/public/ui-*.m4a` files.
@MainActor
final class InteractiveSounds {
	static let shared = InteractiveSounds()

	/// The four packaged cues (`ui-<name>.m4a` in the app Resources, mirrored in `web/public`).
	enum Cue: String, CaseIterable {
		case toggleOn = "ui-toggle-on"
		case toggleOff = "ui-toggle-off"
		case clickTop = "ui-click-top"
		case clickBottom = "ui-click-bottom"
	}

	private var players: [Cue: AVAudioPlayer] = [:]

	private init() {}

	/// The global interactive-sounds master (defaults on). Shared with `UsageAlertCenter`'s meow so a
	/// single toggle governs every non-alert sound in the app.
	private var enabled: Bool { SettingsStore.interactiveSoundsEnabled() }

	nonisolated static func url(for cue: Cue) -> URL? {
		AppResources.url(forResource: cue.rawValue, withExtension: "m4a")
	}

	private func player(for cue: Cue) -> AVAudioPlayer? {
		if let existing = players[cue] { return existing }
		guard let url = Self.url(for: cue) else { return nil }
		guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
		player.volume = 0.6
		player.prepareToPlay()
		players[cue] = player
		return player
	}

	/// Play a cue, unless the global master is off. Restarts an already-playing instance so rapid taps
	/// each get a fresh hit rather than being swallowed.
	@discardableResult
	func play(_ cue: Cue) -> Bool {
		guard enabled, let player = player(for: cue) else { return false }
		if player.isPlaying { player.stop() }
		player.currentTime = 0
		// `stop()` (and a finished play) undoes the buffer prep, so re-prime before
		// replaying — keeps retriggers low-latency and matches the meow path in
		// `UsageAlertCenter.playMeow()`.
		player.prepareToPlay()
		return player.play()
	}

	/// Toggle settle cue — the rising note when a switch turns ON, the falling note when it turns OFF.
	func toggle(_ isOn: Bool) { play(isOn ? .toggleOn : .toggleOff) }

	/// A top chrome-cluster button (gear, pin, back, theme, widget, update dot) was clicked.
	func topClick() { play(.clickTop) }

	/// A bottom footer button (refresh, quit, help, share) was clicked.
	func bottomClick() { play(.clickBottom) }

	/// A dashboard selector row — a provider or the "All providers" aggregate — was clicked. Reuses the
	/// light top-click cue (selector rows are the card's primary navigation), named so the intent is
	/// explicit and easy to re-point if a dedicated selector cue ever ships. Mirrored in the homepage
	/// `menubar-demo.tsx` `playSelectorClick`.
	func selectorClick() { play(.clickTop) }
}
