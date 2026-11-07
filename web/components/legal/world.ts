// The shared world: a warm gradient sky dome, a flat grassy ground strip across
// the bottom, drifting clouds, warm fireflies, a glass globe, and a soft ground
// shadow. Assembled by the scene; JP floats inside the globe.

import * as THREE from "three";
import { cloudPuff, makeRng } from "./lowpoly";
import { PAL } from "./palette";

// A big inverted sphere with a vertical warm gradient baked into its vertices.
export function buildSkyDome(): THREE.Mesh {
	const geo = new THREE.SphereGeometry(60, 24, 16);
	const top = new THREE.Color(PAL.skyTop);
	const mid = new THREE.Color(PAL.skyMid);
	const horizon = new THREE.Color(PAL.skyHorizon);
	const position = geo.attributes.position;
	const colors = new Float32Array(position.count * 3);
	const color = new THREE.Color();
	for (let i = 0; i < position.count; i += 1) {
		const t = THREE.MathUtils.clamp((position.getY(i) / 60) * 0.5 + 0.5, 0, 1);
		if (t < 0.5) {
			color.copy(horizon).lerp(mid, t / 0.5);
		} else {
			color.copy(mid).lerp(top, (t - 0.5) / 0.5);
		}
		colors[i * 3] = color.r;
		colors[i * 3 + 1] = color.g;
		colors[i * 3 + 2] = color.b;
	}
	geo.setAttribute("color", new THREE.BufferAttribute(colors, 3));
	const material = new THREE.MeshBasicMaterial({
		vertexColors: true,
		side: THREE.BackSide,
		fog: false,
		depthWrite: false,
	});
	const mesh = new THREE.Mesh(geo, material);
	mesh.renderOrder = -10;
	return mesh;
}

// The glass globe (snow-globe) JP floats inside.
export function glassGlobe(radius: number): THREE.Mesh {
	const tint = new THREE.Color("#dbe9f4");
	const material = new THREE.MeshPhysicalMaterial({
		color: tint,
		transparent: true,
		opacity: 0.13,
		roughness: 0.06,
		metalness: 0,
		emissive: tint,
		emissiveIntensity: 0.1,
		side: THREE.DoubleSide,
		depthWrite: false,
	});
	return new THREE.Mesh(new THREE.SphereGeometry(radius, 40, 28), material);
}

export function buildGlassRim(radius: number): THREE.Mesh {
	const material = new THREE.MeshBasicMaterial({
		color: "#f3fbff",
		transparent: true,
		opacity: 0.42,
		depthWrite: false,
	});
	const rim = new THREE.Mesh(new THREE.TorusGeometry(radius, 0.018, 8, 96), material);
	rim.renderOrder = 7;
	return rim;
}

export function buildGlassHighlights(centerY: number, radius: number): THREE.Group {
	const group = new THREE.Group();
	const glint = new THREE.Mesh(
		new THREE.PlaneGeometry(radius * 0.66, radius * 1.02),
		new THREE.MeshBasicMaterial({
			map: glintSprite(),
			transparent: true,
			blending: THREE.AdditiveBlending,
			depthWrite: false,
			opacity: 0.5,
		}),
	);
	glint.position.set(radius * 0.62, centerY + radius * 0.68, radius * 0.86);
	glint.rotation.z = -0.5;
	glint.renderOrder = 8;
	group.add(glint);
	return group;
}

function glintSprite(): THREE.CanvasTexture {
	const canvas = document.createElement("canvas");
	canvas.width = 64;
	canvas.height = 128;
	const ctx = canvas.getContext("2d");
	if (ctx) {
		const grad = ctx.createRadialGradient(32, 64, 0, 32, 64, 30);
		grad.addColorStop(0, "rgba(255,255,255,0.95)");
		grad.addColorStop(0.55, "rgba(255,255,255,0.3)");
		grad.addColorStop(1, "rgba(255,255,255,0)");
		ctx.fillStyle = grad;
		ctx.fillRect(0, 0, 64, 128);
	}
	const t = new THREE.CanvasTexture(canvas);
	t.colorSpace = THREE.SRGBColorSpace;
	return t;
}

// A dark dusk sky rendered on the far interior wall of the globe, so the white
// snow and the warm house windows pop (a real night-scene snow globe).
export function buildGlobeBackdrop(radius: number): THREE.Mesh {
	const geo = new THREE.SphereGeometry(radius, 32, 22);
	const top = new THREE.Color(PAL.globeTop);
	const bottom = new THREE.Color(PAL.globeBottom);
	const position = geo.attributes.position;
	const colors = new Float32Array(position.count * 3);
	const color = new THREE.Color();
	for (let i = 0; i < position.count; i += 1) {
		const t = THREE.MathUtils.clamp(position.getY(i) / radius, -1, 1) * 0.5 + 0.5;
		color.copy(bottom).lerp(top, t);
		colors[i * 3] = color.r;
		colors[i * 3 + 1] = color.g;
		colors[i * 3 + 2] = color.b;
	}
	geo.setAttribute("color", new THREE.BufferAttribute(colors, 3));
	const material = new THREE.MeshBasicMaterial({
		vertexColors: true,
		side: THREE.BackSide,
		fog: false,
	});
	const mesh = new THREE.Mesh(geo, material);
	mesh.renderOrder = -5;
	return mesh;
}

// A turned-wood pedestal the glass sphere nestles into (collar hides the seam).
export function globeBase(collarR: number): THREE.Group {
	const g = new THREE.Group();
	const wood = new THREE.MeshStandardMaterial({
		color: new THREE.Color("#70492a"),
		roughness: 0.55,
		metalness: 0,
	});
	const woodDark = new THREE.MeshStandardMaterial({
		color: new THREE.Color("#472f1c"),
		roughness: 0.55,
		metalness: 0,
	});
	const gold = new THREE.MeshStandardMaterial({
		color: new THREE.Color("#d8a63a"),
		roughness: 0.35,
		metalness: 0.5,
	});

	const foot = new THREE.Mesh(
		new THREE.CylinderGeometry(collarR * 1.02, collarR * 1.5, 0.42, 44),
		wood,
	);
	foot.position.y = 0.21;
	foot.castShadow = true;
	foot.receiveShadow = true;
	g.add(foot);
	const band = new THREE.Mesh(
		new THREE.CylinderGeometry(collarR * 0.96, collarR * 1.03, 0.09, 44),
		gold,
	);
	band.position.y = 0.47;
	g.add(band);
	const neck = new THREE.Mesh(
		new THREE.CylinderGeometry(collarR * 0.9, collarR * 0.96, 0.34, 44),
		woodDark,
	);
	neck.position.y = 0.68;
	neck.castShadow = true;
	g.add(neck);
	const collar = new THREE.Mesh(new THREE.TorusGeometry(collarR * 0.92, 0.09, 16, 44), wood);
	collar.rotation.x = Math.PI / 2;
	collar.position.y = 0.9;
	g.add(collar);
	return g;
}

export type Clouds = {
	group: THREE.Group;
	update: (elapsed: number) => void;
};

export function buildClouds(count: number, seed: number): Clouds {
	const rng = makeRng(seed);
	const group = new THREE.Group();
	const drift: { g: THREE.Group; speed: number; x0: number; range: number }[] = [];
	for (let i = 0; i < count; i += 1) {
		const scale = 0.7 + rng() * 0.7;
		const puff = cloudPuff(scale, rng);
		const x0 = (rng() - 0.5) * 28;
		const y = 5 + rng() * 6;
		const z = -13 - rng() * 16;
		puff.position.set(x0, y, z);
		group.add(puff);
		drift.push({ g: puff, speed: 0.15 + rng() * 0.25, x0, range: 18 });
	}
	const update = (elapsed: number) => {
		for (const d of drift) {
			d.g.position.x = d.x0 + ((elapsed * d.speed) % d.range);
		}
	};
	return { group, update };
}
