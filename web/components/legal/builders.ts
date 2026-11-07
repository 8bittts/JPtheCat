// Shared GPU resource disposal for the legal scene.

import * as THREE from "three";

function disposeMaterial(material: THREE.Material) {
	const record = material as THREE.Material & Record<string, unknown>;
	for (const key of ["map", "alphaMap", "emissiveMap", "aoMap", "bumpMap"]) {
		const value = record[key];
		if (value instanceof THREE.Texture) {
			value.dispose();
		}
	}
	material.dispose();
}

export function disposeGroup(root: THREE.Object3D) {
	root.traverse((object) => {
		if (
			object instanceof THREE.Mesh ||
			object instanceof THREE.LineSegments ||
			object instanceof THREE.Points
		) {
			object.geometry.dispose();
			const material = object.material;
			if (Array.isArray(material)) {
				for (const entry of material) {
					disposeMaterial(entry);
				}
			} else {
				disposeMaterial(material);
			}
		}
	});
}
