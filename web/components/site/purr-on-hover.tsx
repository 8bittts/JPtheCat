"use client";

import { type ReactNode, useEffect, useRef, useState } from "react";

const MEOW_AUDIO_SRC = "/meow.m4a";
const DUPLICATE_EVENT_WINDOW_MS = 250;

let sharedAudio: HTMLAudioElement | null = null;
let primingInstalled = false;
let audioUnlocked = false;

function getSharedAudio() {
	if (typeof window === "undefined") {
		return null;
	}

	if (!sharedAudio) {
		sharedAudio = new Audio(MEOW_AUDIO_SRC);
		sharedAudio.preload = "auto";
		// Play the mascot meow at full element volume, matching the app's
		// `UsageAlertCenter` meow (player.volume = 1.0). The asset itself is
		// loudness-normalized (~-23 LUFS) so it sits coherently under the UI cues.
		sharedAudio.volume = 1;
	}

	return sharedAudio;
}

function resetAudio(audio: HTMLAudioElement) {
	try {
		audio.currentTime = 0;
	} catch {
		// Some browsers reject seeking until metadata is available. Playback still works.
	}
}

function installAudioPrimer() {
	if (primingInstalled || typeof window === "undefined") {
		return;
	}

	const prime = async () => {
		const audio = getSharedAudio();
		if (!audio) {
			return;
		}

		const wasMuted = audio.muted;
		audio.muted = true;
		try {
			await audio.play();
			audio.pause();
			resetAudio(audio);
			audioUnlocked = true;
		} catch {
			audioUnlocked = false;
		} finally {
			audio.muted = wasMuted;
		}
	};

	window.addEventListener("pointerdown", prime, { once: true, capture: true });
	window.addEventListener("keydown", prime, { once: true, capture: true });
	primingInstalled = true;
}

function stopMeow() {
	const audio = getSharedAudio();
	if (!audio) {
		return;
	}

	audio.pause();
	resetAudio(audio);
}

async function startMeow() {
	const audio = getSharedAudio();
	if (!audio) {
		return false;
	}

	stopMeow();

	try {
		await audio.play();
	} catch {
		return false;
	}

	audioUnlocked = true;
	return true;
}

export function PurrOnHover({
	children,
	className = "",
	trigger,
}: {
	children: ReactNode;
	className?: string;
	trigger: string;
}) {
	const triggerRef = useRef<HTMLSpanElement>(null);
	const playVersion = useRef(0);
	const lastPlayAt = useRef(Number.NEGATIVE_INFINITY);
	const [playing, setPlaying] = useState(false);

	useEffect(() => {
		installAudioPrimer();
		const trigger = triggerRef.current;
		if (!trigger) {
			return;
		}

		const play = async (event?: PointerEvent | MouseEvent) => {
			const force = event?.type === "pointerdown";
			if (!force && event instanceof PointerEvent && event.pointerType === "touch") {
				return;
			}
			const now = performance.now();
			if (!force && now - lastPlayAt.current < DUPLICATE_EVENT_WINDOW_MS) {
				return;
			}
			lastPlayAt.current = now;

			const version = playVersion.current + 1;
			playVersion.current = version;
			const didStart = await startMeow();
			if (version === playVersion.current) {
				setPlaying(didStart);
			} else {
				stopMeow();
			}
		};
		const stop = () => {
			playVersion.current += 1;
			stopMeow();
			setPlaying(false);
		};
		const playFromFocus = () => play();
		const markEnded = () => {
			setPlaying(false);
		};
		const audio = getSharedAudio();

		trigger.addEventListener("pointerenter", play);
		trigger.addEventListener("mouseenter", play);
		trigger.addEventListener("pointerdown", play);
		trigger.addEventListener("pointerleave", stop);
		trigger.addEventListener("mouseleave", stop);
		trigger.addEventListener("focusin", playFromFocus);
		trigger.addEventListener("focusout", stop);
		audio?.addEventListener("ended", markEnded);

		return () => {
			trigger.removeEventListener("pointerenter", play);
			trigger.removeEventListener("mouseenter", play);
			trigger.removeEventListener("pointerdown", play);
			trigger.removeEventListener("pointerleave", stop);
			trigger.removeEventListener("mouseleave", stop);
			trigger.removeEventListener("focusin", playFromFocus);
			trigger.removeEventListener("focusout", stop);
			audio?.removeEventListener("ended", markEnded);
			stop();
		};
	}, []);

	return (
		<span
			ref={triggerRef}
			className={`inline-flex ${className}`}
			data-purr-trigger={trigger}
			data-purr-state={playing ? "playing" : "idle"}
			data-purr-unlocked={audioUnlocked ? "true" : "false"}
		>
			{children}
		</span>
	);
}
