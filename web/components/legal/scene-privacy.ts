// The shared legal diorama (both /privacy and /terms): a realistic Christmas
// SNOW GLOBE. A glass sphere on a turned-wood pedestal, its bottom filled with a
// seamless snow cap that hugs the glass. Inside: a cozy Santa house, snow-capped
// pines, elves walking back and forth, heavy falling snow, a dark dusk sky, and
// JP presiding near the top. Fresnel rim + specular highlights sell the glass.

import * as THREE from "three";
import type { FrameFn, SceneModule } from "./engine";
import { buildSun } from "./mascot";
import { buildElf, buildPineTree, buildSantaHouse, buildSnow, buildSnowCap, XMAS } from "./village";
import {
	buildClouds,
	buildGlassHighlights,
	buildGlassRim,
	buildGlobeBackdrop,
	glassGlobe,
	globeBase,
} from "./world";

export function buildPrivacyScene(): SceneModule {
	const group = new THREE.Group();

	const globeR = 2.35;
	const baseHeight = 0.5;
	const centerY = 2.85; // globe centre; the sphere spans y 0.5 .. 5.2
	const baseTopY = 1.05; // the sphere emerges from the pedestal collar here
	const snowLineY = 1.7; // where the snow surface sits inside the globe

	// pedestal that cups the sphere (collar radius = sphere cross-section at its top)
	const collarR = Math.sqrt(globeR * globeR - (centerY - baseTopY) ** 2);
	const base = globeBase(collarR);
	base.position.y = baseTopY - baseHeight / 2;
	group.add(base);

	// seamless snow cap filling the bottom of the globe, meeting the glass all round
	const cap = buildSnowCap(globeR * 0.995, centerY, snowLineY);
	group.add(cap.group);

	// --- The Christmas village on the snow ---------------------------------
	const village = new THREE.Group();
	village.position.set(0, snowLineY, 0);
	village.scale.setScalar(1.25);
	group.add(village);

	const house = buildSantaHouse();
	house.position.set(0.05, 0, -0.35);
	house.rotation.y = 0.12;
	village.add(house);
	const tree1 = buildPineTree(1.0, 5);
	tree1.position.set(-1.05, 0, 0.05);
	village.add(tree1);
	const tree2 = buildPineTree(0.75, 9);
	tree2.position.set(0.95, 0, -0.55);
	village.add(tree2);

	const elves = [
		buildElf(
			new THREE.Vector3(-0.7, 0, 0.6),
			new THREE.Vector3(0.55, 0, 0.55),
			0.8,
			XMAS.red,
			XMAS.green,
			1,
		),
		buildElf(
			new THREE.Vector3(0.8, 0, 0.1),
			new THREE.Vector3(-0.1, 0, 0.75),
			0.62,
			XMAS.green,
			XMAS.red,
			2,
		),
		buildElf(
			new THREE.Vector3(-0.85, 0, -0.1),
			new THREE.Vector3(-0.3, 0, 0.55),
			0.95,
			XMAS.red,
			XMAS.green,
			3,
		),
	];
	for (const elf of elves) {
		village.add(elf.group);
	}

	// --- Dusk backdrop (inside), glass, rim, highlights, snow --------------
	const backdrop = buildGlobeBackdrop(globeR * 0.985);
	backdrop.position.y = centerY;
	group.add(backdrop);

	const globe = glassGlobe(globeR);
	globe.position.y = centerY;
	group.add(globe);
	const globeMat = globe.material as THREE.MeshPhysicalMaterial;

	const rim = buildGlassRim(globeR * 1.003);
	rim.position.y = centerY;
	group.add(rim);
	group.add(buildGlassHighlights(centerY, globeR));

	const snow = buildSnow(700, new THREE.Vector3(0, centerY, 0), globeR * 0.9, snowLineY);
	group.add(snow.points);

	// JP presides over the village as a little sun, upper-right, with spinning
	// rays and pulsing flares.
	const sun = buildSun(0.92);
	sun.group.position.set(0.72, centerY + 1.0, 0.25);
	group.add(sun.group);

	const clouds = buildClouds(5, 88);
	group.add(clouds.group);

	const update: FrameFn = (dt, t, parallax) => {
		for (const elf of elves) {
			elf.update(t);
		}
		snow.update(dt);
		sun.update(dt, t);
		clouds.update(t);
		village.rotation.y = Math.sin(t * 0.16) * 0.04 + parallax.x * 0.04;
		globeMat.opacity = 0.1 + Math.sin(t * 0.6) * 0.02;
	};

	return {
		group,
		update,
		pose: {
			position: new THREE.Vector3(0, 2.9, 10.4),
			target: new THREE.Vector3(0, 2.45, 0),
		},
	};
}
