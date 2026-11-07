// Low-poly toolkit: flat-shaded faceted materials, subtle vertex jitter, and a
// soft cloud puff. Everything procedural so the scene stays strictly CSP-clean.

import * as THREE from "three";
import { PAL } from "./palette";

export function makeRng(seed: number): () => number {
	let s = seed >>> 0;
	return () => {
		s |= 0;
		s = (s + 0x6d2b79f5) | 0;
		let t = Math.imul(s ^ (s >>> 15), 1 | s);
		t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

export type LowPolyOptions = {
	roughness?: number;
	emissive?: string;
	emissiveIntensity?: number;
	flatShading?: boolean;
	transparent?: boolean;
	opacity?: number;
};

export function lowPolyMaterial(
	color: string,
	options: LowPolyOptions = {},
): THREE.MeshStandardMaterial {
	return new THREE.MeshStandardMaterial({
		color: new THREE.Color(color),
		roughness: options.roughness ?? 0.85,
		metalness: 0,
		flatShading: options.flatShading ?? true,
		emissive: new THREE.Color(options.emissive ?? "#000000"),
		emissiveIntensity: options.emissiveIntensity ?? 0,
		transparent: options.transparent ?? false,
		opacity: options.opacity ?? 1,
	});
}

export function cloudPuff(scale: number, rng: () => number): THREE.Group {
	const group = new THREE.Group();
	const lobes = 3 + Math.floor(rng() * 3);
	const material = lowPolyMaterial(PAL.cloud, { roughness: 1, flatShading: true });
	for (let i = 0; i < lobes; i += 1) {
		const r = scale * (0.5 + rng() * 0.5);
		const sphere = new THREE.Mesh(new THREE.IcosahedronGeometry(r, 1), material);
		sphere.position.set(
			(rng() - 0.5) * scale * 1.8,
			(rng() - 0.5) * scale * 0.4,
			(rng() - 0.5) * scale * 0.9,
		);
		sphere.scale.y = 0.7;
		group.add(sphere);
	}
	return group;
}
