"use client";

import { useEffect, useRef } from "react";
import type { Engine } from "./engine";
import { PAL } from "./palette";
import { ScenePoster } from "./scene-poster";

// Matches the 3D sky dome gradient (palette skyTop → skyMid → skyHorizon) so the
// load state and the WebGL scene share one continuous sky — no jarring swap. Built
// from PAL so it can never drift from the dome.
const SKY_GRADIENT = `linear-gradient(180deg, ${PAL.skyTop} 0%, ${PAL.skyMid} 55%, ${PAL.skyHorizon} 100%)`;

/**
 * Full-width host for a legal diorama. Loading UX: the container paints a clean
 * sky gradient immediately; the WebGL scene fades in over it. The detailed SVG
 * poster is shown ONLY to reduced-motion / no-WebGL / boot-failure visitors (via
 * a CSS `motion-reduce` default plus a ref fallback) — motion+WebGL users never
 * see the flat illustration, so there's no cartoon-to-3D flash. All three.js is
 * dynamically imported so it stays off the critical path.
 */
export function SceneStage({ variant }: { variant: "privacy" | "terms" }) {
	const containerRef = useRef<HTMLDivElement | null>(null);
	const canvasRef = useRef<HTMLCanvasElement | null>(null);
	const posterRef = useRef<HTMLDivElement | null>(null);

	useEffect(() => {
		const canvas = canvasRef.current;
		const container = containerRef.current;
		if (!canvas || !container) {
			return;
		}
		if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
			return; // CSS already reveals the poster; never start a loop
		}
		if (!hasWebGL()) {
			if (posterRef.current) {
				posterRef.current.style.opacity = "1"; // no 3D → show the illustration
			}
			return;
		}

		let disposed = false;
		let booting = false;
		// [CRITICAL] `boot()` is async, so the observer can report "off-screen" while `engine` is still
		// null and `engine?.stop()` is a no-op. This flag records visibility regardless, so boot never
		// starts a rAF loop for a scene the visitor has already scrolled past — otherwise the engine
		// renders a 2048x2048 shadow map every frame forever on a visible tab.
		let visible = false;
		let engine: Engine | null = null;
		let teardownScene: (() => void) | null = null;

		const showPoster = () => {
			if (posterRef.current) {
				posterRef.current.style.opacity = "1";
			}
		};
		const teardown = () => {
			teardownScene?.();
			teardownScene = null;
			engine?.dispose();
			engine = null;
		};

		const loadSceneModules = async () => {
			const [{ createEngine }, { disposeGroup }] = await Promise.all([
				import("./engine"),
				import("./builders"),
			]);
			await (document.fonts?.ready ?? Promise.resolve());
			const build =
				variant === "privacy"
					? (await import("./scene-privacy")).buildPrivacyScene
					: (await import("./scene-terms")).buildTermsScene;
			return { createEngine, disposeGroup, build };
		};

		const wireScene = ({
			createEngine,
			disposeGroup,
			build,
		}: Awaited<ReturnType<typeof loadSceneModules>>) => {
			const created = createEngine(canvas);
			const scene = build();
			created.scene.add(scene.group);
			created.setCameraPose(scene.pose);
			created.run(scene.update);
			if (visible && !disposed) {
				created.start();
			}
			engine = created;
			const onContextLost = (event: Event) => {
				event.preventDefault();
				created.stop();
				canvas.style.opacity = "0";
				showPoster();
			};
			canvas.addEventListener("webglcontextlost", onContextLost, false);
			teardownScene = () => {
				canvas.removeEventListener("webglcontextlost", onContextLost);
				disposeGroup(scene.group);
			};
			canvas.style.opacity = "1";
			if (disposed) {
				teardown();
			}
		};

		const boot = async () => {
			booting = true;
			try {
				const modules = await loadSceneModules();
				if (disposed) {
					return;
				}
				wireScene(modules);
			} catch {
				showPoster(); // boot failed → fall back to the static illustration
			} finally {
				booting = false;
			}
		};

		const onVisibilityChange = (isIntersecting: boolean) => {
			if (!isIntersecting) {
				engine?.stop();
				return;
			}
			if (engine) {
				engine.start();
			} else if (!booting) {
				void boot();
			}
		};

		const observer = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					visible = entry.isIntersecting;
					onVisibilityChange(entry.isIntersecting);
				}
			},
			{ rootMargin: "200px 0px" },
		);
		observer.observe(container);

		return () => {
			disposed = true;
			observer.disconnect();
			teardown();
		};
	}, [variant]);

	return (
		<div
			ref={containerRef}
			className="scene-stage relative w-full overflow-hidden"
			style={{ background: SKY_GRADIENT }}
		>
			{/* Detailed illustration: hidden for motion+WebGL, shown for reduced-motion
			    (pure CSS) or no-WebGL/boot-failure (ref). Carries the sr-only text alt. */}
			<div
				ref={posterRef}
				className="absolute inset-0 opacity-0 transition-opacity duration-500 motion-reduce:opacity-100"
			>
				<ScenePoster variant={variant} />
			</div>
			{/* Decorative WebGL layer, fading in over the sky gradient. */}
			<canvas
				ref={canvasRef}
				className="pointer-events-none absolute inset-0 h-full w-full"
				style={{ opacity: 0, transition: "opacity 700ms ease" }}
			/>
			{/* melt the bottom of the scene into the page content below */}
			<div
				className="pointer-events-none absolute inset-x-0 bottom-0 h-16"
				style={{ background: "linear-gradient(to bottom, transparent, var(--color-paper))" }}
			/>
		</div>
	);
}

function hasWebGL(): boolean {
	try {
		const canvas = document.createElement("canvas");
		return Boolean(canvas.getContext("webgl2") || canvas.getContext("webgl"));
	} catch {
		return false;
	}
}
