import Observation

@MainActor
@Observable
final class DashboardChromeState {
	/// Starts on so a click on another app leaves the dashboard above every screen.
	/// The Settings pin can turn that off for the rest of this launch. It is not persisted:
	/// the next launch begins on top again. The menu-bar item remains the hide control.
	var isPinned = true
	/// True while the dashboard window is fully hidden (covered or miniaturized) and its
	/// `TimelineView(.animation)` surfaces should stop evaluating. Written ONLY by
	/// `StatusBarController`'s occlusion observer, from a notification that actually arrived — see
	/// `DashboardMotionGate` for why that ordering is load-bearing. Defaults to false so motion runs
	/// normally anywhere the observer never installs.
	var motionPaused = false
}
