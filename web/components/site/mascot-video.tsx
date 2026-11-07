"use client";

import { useEffect, useRef } from "react";

export function MascotVideo({
	mp4,
	poster,
	size,
	webm,
}: {
	mp4: string;
	poster: string;
	size: number;
	webm: string;
}) {
	const videoRef = useRef<HTMLVideoElement>(null);

	useEffect(() => {
		const video = videoRef.current;
		if (!video) {
			return;
		}

		const shouldReduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

		const selectedSource = () =>
			"GestureEvent" in window && video.canPlayType('video/mp4; codecs="hvc1"') ? mp4 : webm;

		const stopAndUnload = () => {
			video.pause();
			video.preload = "none";
			video.removeAttribute("src");
			video.load();
		};

		// The hero mounts the mascot TWICE — a desktop copy (`hidden md:block`) and a mobile copy
		// (`md:hidden`) — so only ONE is ever laid out. `offsetParent` is null whenever any ancestor
		// is `display:none`, so this cleanly gates load/decode to the breakpoint-visible instance and
		// stops the hidden copy from downloading + decoding the alpha video for nothing.
		const isVisible = () => video.offsetParent !== null;

		const play = () => {
			if (shouldReduceMotion.matches || document.hidden || !isVisible()) {
				return;
			}

			if (!video.getAttribute("src")) {
				video.src = selectedSource();
				video.preload = "auto";
				video.load();
			}

			video.muted = true;
			video.defaultMuted = true;
			video.playsInline = true;
			void video.play().catch(() => {
				// Muted inline autoplay can still be delayed by mobile power/data policies.
			});
		};

		const syncMotionPreference = () => {
			if (shouldReduceMotion.matches || !isVisible()) {
				// Reduced-motion OR this mount is the hidden breakpoint copy → never fetch/decode.
				stopAndUnload();
				return;
			}

			// WebKit decodes the VP9/WebM source without its alpha channel, so the
			// mascot's transparent corners fill with the honey matte and read as an
			// opaque yellow square. Its HEVC-with-alpha path (VideoToolbox) renders them
			// transparent, so Safari gets only the MP4 source. Every other engine keeps
			// the WebM — Chromium on macOS would otherwise decode the HEVC opaque, and
			// only Safari (desktop + iOS) exposes GestureEvent.
			video.src = selectedSource();
			video.preload = "auto";
			video.load();
			play();
		};

		// Re-sync when the `md` breakpoint (Tailwind = 768px) flips this copy between shown/hidden,
		// so the newly-visible mount starts decoding and the newly-hidden one unloads.
		const breakpoint = window.matchMedia("(min-width: 768px)");

		syncMotionPreference();
		shouldReduceMotion.addEventListener("change", syncMotionPreference);
		breakpoint.addEventListener("change", syncMotionPreference);
		video.addEventListener("canplay", play);
		document.addEventListener("visibilitychange", play);

		return () => {
			shouldReduceMotion.removeEventListener("change", syncMotionPreference);
			breakpoint.removeEventListener("change", syncMotionPreference);
			video.removeEventListener("canplay", play);
			document.removeEventListener("visibilitychange", play);
			stopAndUnload();
		};
	}, [mp4, webm]);

	return (
		<video
			ref={videoRef}
			className="h-full w-full object-contain motion-reduce:hidden"
			width={size}
			height={size}
			muted
			loop
			playsInline
			preload="none"
			poster={poster}
			aria-label="JP the cat, gently licking a paw and settling in"
			data-mascot-video
		/>
	);
}
