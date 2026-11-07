// The demo card's audio subsystem, shared by every menubar-demo module (the card, its chrome, and the
// settings face). It lives in its own NON-COMPONENT module for two reasons: the mutable
// `demoUISoundsEnabled` master has to be one instance across all of them, and a `.tsx` file that
// exports components may export nothing else (react-doctor `only-export-components` / Fast Refresh).

const DEMO_MEOW_AUDIO_SRC = "/meow.m4a";

// The interactive UI cues shared 1:1 with the native app (`InteractiveSounds` / `ui-*.m4a`): the
// toggle settle sounds and the light top/bottom button clicks. Cached one HTMLAudioElement per src so
// rapid clicks reuse the decoded buffer. All are gated by the demo's `interactiveSounds` toggle at the
// call site, exactly like `playDemoMeow`.
export const UI_SOUND = {
	toggleOn: "/ui-toggle-on.m4a",
	toggleOff: "/ui-toggle-off.m4a",
	clickTop: "/ui-click-top.m4a",
	clickBottom: "/ui-click-bottom.m4a",
} as const;

let demoMeowAudio: HTMLAudioElement | null = null;
const demoAudioCache = new Map<string, HTMLAudioElement>();

// Mirrors the app's global interactive-sounds master. The settings face keeps this in sync with its
// `interactiveSounds` toggle each render so the shared ChromeButton/CardFooter helpers can self-gate
// without threading the flag through every prop. (The meow stays gated at its call site.)
let demoUISoundsEnabled = true;

/** The one writer of the shared UI-sound master — mirrors the app's global `InteractiveSounds` switch. */
export function setDemoUISoundsEnabled(enabled: boolean) {
	demoUISoundsEnabled = enabled;
}

export function playDemoAudio(src: string, volume = 1) {
	if (typeof window === "undefined") {
		return;
	}
	let audio = src === DEMO_MEOW_AUDIO_SRC ? demoMeowAudio : demoAudioCache.get(src);
	if (!audio) {
		audio = new Audio(src);
		audio.preload = "auto";
		if (src === DEMO_MEOW_AUDIO_SRC) demoMeowAudio = audio;
		else demoAudioCache.set(src, audio);
	}
	// Apply on every call, not just creation — a cached element replayed at a new
	// volume would otherwise silently keep its original level.
	audio.volume = volume;
	try {
		audio.currentTime = 0;
	} catch {
		// Browser may not allow seeking before metadata loads; the click still starts playback.
	}
	void audio.play().catch(() => {});
}

export function playDemoMeow() {
	playDemoAudio(DEMO_MEOW_AUDIO_SRC, 1);
}

export const playToggleSound = (isOn: boolean) => {
	if (!demoUISoundsEnabled) return;
	playDemoAudio(isOn ? UI_SOUND.toggleOn : UI_SOUND.toggleOff, 0.6);
};
export const playTopClick = () => {
	if (!demoUISoundsEnabled) return;
	playDemoAudio(UI_SOUND.clickTop, 0.6);
};
export const playBottomClick = () => {
	if (!demoUISoundsEnabled) return;
	playDemoAudio(UI_SOUND.clickBottom, 0.6);
};
// A selector row (a provider or "All providers") was clicked. Reuses the light top-click cue, matching
// the native app's `InteractiveSounds.selectorClick()` 1:1.
export const playSelectorClick = () => {
	if (!demoUISoundsEnabled) return;
	playDemoAudio(UI_SOUND.clickTop, 0.6);
};
