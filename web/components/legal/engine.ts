// The reusable WebGL engine for the "tiny skies" dioramas: renderer, a warm
// three-point rig with a rim light, a gradient sky dome + soft horizon fog, a
// delta-timed rAF loop that pauses off-screen/hidden, pointer parallax, resize
// (with adaptive fov so narrow viewports don't crop), and a full teardown.

import * as THREE from "three";
import { PAL } from "./palette";
import { buildSkyDome } from "./world";

type CameraPose = {
	position: THREE.Vector3;
	target: THREE.Vector3;
};

export type FrameFn = (dt: number, elapsed: number, parallax: THREE.Vector2) => void;

// A scene module is a self-contained diorama: a group to add to the shared
// scene, the camera pose that frames it, and a per-frame update.
export type SceneModule = {
	group: THREE.Group;
	pose: CameraPose;
	update: FrameFn;
};

export type Engine = {
	scene: THREE.Scene;
	camera: THREE.PerspectiveCamera;
	maxAnisotropy: number;
	setCameraPose: (pose: CameraPose) => void;
	run: (frame: FrameFn) => void;
	start: () => void;
	stop: () => void;
	dispose: () => void;
};

export function createEngine(canvas: HTMLCanvasElement): Engine {
	const dpr = Math.min(typeof window !== "undefined" ? window.devicePixelRatio : 1, 1.9);
	const renderer = new THREE.WebGLRenderer({
		canvas,
		antialias: dpr < 2,
		powerPreference: "low-power",
	});
	renderer.setPixelRatio(dpr);
	renderer.setClearColor(new THREE.Color(PAL.skyHorizon), 1);
	renderer.shadowMap.enabled = true;
	renderer.shadowMap.type = THREE.PCFShadowMap;
	renderer.toneMapping = THREE.ACESFilmicToneMapping;
	renderer.toneMappingExposure = 1.05;

	const scene = new THREE.Scene();
	// Soft horizon fog so far clouds melt into the sky and the tiny world reads
	// with depth. The sky dome opts out of fog so its gradient stays crisp.
	scene.fog = new THREE.Fog(new THREE.Color(PAL.skyHorizon), 18, 52);
	scene.add(buildSkyDome());

	const camera = new THREE.PerspectiveCamera(30, 1, 0.1, 200);
	const basePosition = new THREE.Vector3(0, 3.2, 12);
	const target = new THREE.Vector3(0, 2.1, 0);
	camera.position.copy(basePosition);
	camera.lookAt(target);

	// --- Warm three-point rig ----------------------------------------------
	const hemi = new THREE.HemisphereLight(
		new THREE.Color(PAL.skyTop),
		new THREE.Color(PAL.grassDark),
		0.95,
	);
	scene.add(hemi);

	const key = new THREE.DirectionalLight(new THREE.Color("#fff2d6"), 2.3);
	key.position.set(-6, 9, 7);
	key.castShadow = true;
	key.shadow.mapSize.set(2048, 2048);
	key.shadow.bias = -0.0012;
	key.shadow.normalBias = 0.03;
	key.shadow.camera.near = 1;
	key.shadow.camera.far = 40;
	const shadowCam = key.shadow.camera;
	shadowCam.left = -10;
	shadowCam.right = 10;
	shadowCam.top = 10;
	shadowCam.bottom = -10;
	shadowCam.updateProjectionMatrix();
	scene.add(key);

	// Warm bounce fill from below-front keeps shadow sides from going grey.
	const fill = new THREE.DirectionalLight(new THREE.Color(PAL.honey), 0.5);
	fill.position.set(5, 1.5, 6);
	scene.add(fill);

	// Rim/back light for the stylised low-poly edge glow (the tinyskies read).
	const rim = new THREE.DirectionalLight(new THREE.Color("#ffe9c4"), 1.1);
	rim.position.set(2, 5, -9);
	scene.add(rim);

	// --- Resize -------------------------------------------------------------
	const resize = () => {
		const width = canvas.clientWidth || 1;
		const height = canvas.clientHeight || 1;
		renderer.setSize(width, height, false);
		const aspect = width / height;
		camera.aspect = aspect;
		// fov is the VERTICAL fov, so narrow (portrait) viewports crop horizontally.
		// Widen the vertical fov as the aspect narrows so the world stays framed.
		camera.fov = aspect < 1.3 ? Math.min(42, 30 + (1.3 - aspect) * 20) : 30;
		camera.updateProjectionMatrix();
	};
	resize();
	const resizeObserver = new ResizeObserver(resize);
	resizeObserver.observe(canvas);

	// --- Pointer parallax (fine pointers only) ------------------------------
	const pointer = new THREE.Vector2(0, 0);
	const smoothed = new THREE.Vector2(0, 0);
	const finePointer = typeof window !== "undefined" && window.matchMedia("(pointer: fine)").matches;
	const onPointerMove = (event: PointerEvent) => {
		const rect = canvas.getBoundingClientRect();
		pointer.set(
			((event.clientX - rect.left) / rect.width) * 2 - 1,
			((event.clientY - rect.top) / rect.height) * 2 - 1,
		);
	};
	if (finePointer) {
		window.addEventListener("pointermove", onPointerMove, { passive: true });
	}

	// --- Loop ---------------------------------------------------------------
	const timer = new THREE.Timer();
	let frameFn: FrameFn | null = null;
	let running = false;

	// Driven by `renderer.setAnimationLoop`, not a hand-rolled rAF: the renderer owns the
	// timing source, so the loop stays correct if this scene is ever presented through WebXR.
	const tick = (timestamp: number) => {
		timer.update(timestamp);
		const dt = Math.min(timer.getDelta(), 0.05);
		const elapsed = timer.getElapsed();
		const pointerSmoothing = 1 - Math.exp(-2.45 * dt);
		smoothed.lerp(pointer, pointerSmoothing);
		const yaw = smoothed.x * 0.22;
		const pitch = -smoothed.y * 0.1;
		camera.position.set(
			basePosition.x + Math.sin(yaw) * 2.2 + Math.sin(elapsed * 0.3) * 0.1,
			basePosition.y + pitch * 1.8 + Math.sin(elapsed * 0.24) * 0.08,
			basePosition.z - Math.abs(Math.sin(yaw)) * 0.5,
		);
		camera.lookAt(target);
		frameFn?.(dt, elapsed, smoothed);
		renderer.render(scene, camera);
	};

	// `desired` = owner intent to run (scene on-screen); the tab-visibility pause
	// applies on top, so returning to a tab does not restart an off-screen scene.
	let desired = false;
	const play = () => {
		if (running || document.hidden || !desired) {
			return;
		}
		running = true;
		timer.reset();
		renderer.setAnimationLoop(tick);
	};
	const pause = () => {
		running = false;
		renderer.setAnimationLoop(null);
	};
	const start = () => {
		desired = true;
		play();
	};
	const stop = () => {
		desired = false;
		pause();
	};

	const onVisibility = () => {
		if (document.hidden) {
			pause();
		} else {
			play();
		}
	};
	document.addEventListener("visibilitychange", onVisibility);

	return {
		scene,
		camera,
		maxAnisotropy: renderer.capabilities.getMaxAnisotropy(),
		setCameraPose: (pose) => {
			basePosition.copy(pose.position);
			target.copy(pose.target);
			camera.position.copy(pose.position);
			camera.lookAt(target);
		},
		run: (frame) => {
			frameFn = frame;
		},
		start,
		stop,
		dispose: () => {
			stop();
			frameFn = null;
			resizeObserver.disconnect();
			document.removeEventListener("visibilitychange", onVisibility);
			if (finePointer) {
				window.removeEventListener("pointermove", onPointerMove);
			}
			scene.clear();
			timer.dispose();
			renderer.dispose();
			renderer.forceContextLoss();
		},
	};
}
