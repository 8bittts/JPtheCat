// A tiny Christmas village that lives inside the snow globe: a cozy Santa house,
// snow-capped pine trees, little elves walking back and forth carrying gifts,
// a snowy ground, and heavy falling snow. All procedural (CSP-clean).

import * as THREE from "three";
import { lowPolyMaterial, makeRng } from "./lowpoly";

const RED = "#c9392b";
const REDDARK = "#9e2b20";
const GREEN = "#2f6b40";
const GREENDARK = "#255233";
const SNOW = "#f6fbff";
const CREAM = "#f2e7d2";
const BROWN = "#7a5230";
const GLOW = "#ffdf8a";
const SKIN = "#f0c9a0";

export const XMAS = { red: RED, green: GREEN, snow: SNOW } as const;

// A seamless snow CAP that fills the bottom of the globe and hugs the glass:
// a spherical segment below the snow line + a flat top disc the village sits on.
// Returns the disc radius so the caller knows how much room the village has.
export function buildSnowCap(
	capR: number,
	centerY: number,
	snowLineY: number,
): { group: THREE.Group; discRadius: number } {
	const g = new THREE.Group();
	const snowMat = () => lowPolyMaterial(SNOW, { roughness: 1, flatShading: false });

	const cosT = THREE.MathUtils.clamp((snowLineY - centerY) / capR, -1, 1);
	const thetaStart = Math.acos(cosT);
	const bottom = new THREE.Mesh(
		new THREE.SphereGeometry(capR, 48, 24, 0, Math.PI * 2, thetaStart, Math.PI - thetaStart),
		snowMat(),
	);
	bottom.position.y = centerY;
	bottom.receiveShadow = true;
	g.add(bottom);

	const discRadius = Math.sqrt(Math.max(0, capR * capR - (snowLineY - centerY) ** 2));
	const disc = new THREE.Mesh(new THREE.CircleGeometry(discRadius, 48), snowMat());
	disc.rotation.x = -Math.PI / 2;
	disc.position.y = snowLineY;
	disc.receiveShadow = true;
	g.add(disc);

	// gentle drifts on top for a little relief
	const rng = makeRng(3);
	for (let i = 0; i < 5; i += 1) {
		const drift = new THREE.Mesh(
			new THREE.SphereGeometry(discRadius * (0.12 + rng() * 0.1), 12, 8),
			snowMat(),
		);
		drift.scale.y = 0.3;
		const a = rng() * Math.PI * 2;
		const rr = discRadius * (0.35 + rng() * 0.5);
		drift.position.set(Math.cos(a) * rr, snowLineY + 0.01, Math.sin(a) * rr);
		g.add(drift);
	}
	return { group: g, discRadius };
}

// A cozy, clearly-Christmas Santa house.
export function buildSantaHouse(): THREE.Group {
	const g = new THREE.Group();
	const wallW = 0.62;
	const wallH = 0.42;
	const wallD = 0.5;

	const walls = new THREE.Mesh(new THREE.BoxGeometry(wallW, wallH, wallD), lowPolyMaterial(CREAM));
	walls.position.y = wallH / 2;
	walls.castShadow = true;
	g.add(walls);

	const roofW = wallW + 0.14;
	const roofH = 0.34;
	const roofD = wallD + 0.14;
	const shape = new THREE.Shape();
	shape.moveTo(-roofW / 2, 0);
	shape.lineTo(roofW / 2, 0);
	shape.lineTo(0, roofH);
	shape.closePath();
	const roofGeo = new THREE.ExtrudeGeometry(shape, { depth: roofD, bevelEnabled: false });
	roofGeo.translate(0, 0, -roofD / 2);
	const roof = new THREE.Mesh(roofGeo, lowPolyMaterial(RED));
	roof.position.y = wallH;
	roof.castShadow = true;
	g.add(roof);

	const capShape = new THREE.Shape();
	capShape.moveTo(-roofW / 2 - 0.02, 0);
	capShape.lineTo(roofW / 2 + 0.02, 0);
	capShape.lineTo(0, roofH * 0.55);
	capShape.closePath();
	const capGeo = new THREE.ExtrudeGeometry(capShape, { depth: roofD + 0.04, bevelEnabled: false });
	capGeo.translate(0, 0, -(roofD + 0.04) / 2);
	const cap = new THREE.Mesh(capGeo, lowPolyMaterial(SNOW, { flatShading: false }));
	cap.position.y = wallH + roofH * 0.45;
	g.add(cap);

	const front = wallD / 2;
	for (const x of [-0.15, 0.15]) {
		const win = new THREE.Mesh(
			new THREE.PlaneGeometry(0.13, 0.14),
			lowPolyMaterial(GLOW, { emissive: GLOW, emissiveIntensity: 1.4, flatShading: false }),
		);
		win.position.set(x, 0.24, front + 0.005);
		g.add(win);
		const frame = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.17, 0.02), lowPolyMaterial(REDDARK));
		frame.position.set(x, 0.24, front - 0.005);
		g.add(frame);
	}
	const door = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.24, 0.03), lowPolyMaterial(REDDARK));
	door.position.set(0, 0.12, front + 0.005);
	g.add(door);
	const wreath = new THREE.Mesh(
		new THREE.TorusGeometry(0.05, 0.016, 6, 12),
		lowPolyMaterial(GREEN, { flatShading: false }),
	);
	wreath.position.set(0, 0.28, front + 0.02);
	g.add(wreath);

	const chimney = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.2, 0.09), lowPolyMaterial(REDDARK));
	chimney.position.set(0.18, wallH + 0.2, -0.08);
	chimney.castShadow = true;
	g.add(chimney);
	const chimneySnow = new THREE.Mesh(
		new THREE.BoxGeometry(0.11, 0.04, 0.11),
		lowPolyMaterial(SNOW, { flatShading: false }),
	);
	chimneySnow.position.set(0.18, wallH + 0.31, -0.08);
	g.add(chimneySnow);

	const lightColors = [GLOW, RED, GREEN, "#ffffff"];
	for (let i = 0; i < 7; i += 1) {
		const t = i / 6;
		const color = lightColors[i % lightColors.length];
		const bulb = new THREE.Mesh(
			new THREE.SphereGeometry(0.018, 6, 6),
			lowPolyMaterial(color, { emissive: color, emissiveIntensity: 2, flatShading: false }),
		);
		bulb.position.set(-roofW / 2 + t * roofW, wallH + 0.01, front - 0.02);
		g.add(bulb);
	}

	const glow = new THREE.PointLight(new THREE.Color(GLOW), 1.2, 1.4, 2);
	glow.position.set(0, 0.24, front + 0.15);
	g.add(glow);

	return g;
}

// A snow-capped pine tree.
export function buildPineTree(scale: number, seed: number): THREE.Group {
	const g = new THREE.Group();
	const rng = makeRng(seed);
	const trunk = new THREE.Mesh(
		new THREE.CylinderGeometry(0.03 * scale, 0.04 * scale, 0.14 * scale, 6),
		lowPolyMaterial(BROWN),
	);
	trunk.position.y = 0.07 * scale;
	g.add(trunk);
	for (let i = 0; i < 3; i += 1) {
		const r = (0.22 - i * 0.05) * scale;
		const h = 0.2 * scale;
		const y = (0.16 + i * 0.14) * scale;
		const cone = new THREE.Mesh(
			new THREE.ConeGeometry(r, h, 7),
			lowPolyMaterial(rng() > 0.5 ? GREEN : GREENDARK),
		);
		cone.position.y = y;
		cone.castShadow = true;
		g.add(cone);
		const snowCap = new THREE.Mesh(
			new THREE.ConeGeometry(r * 0.9, h * 0.35, 7),
			lowPolyMaterial(SNOW, { flatShading: false }),
		);
		snowCap.position.y = y + h * 0.34;
		g.add(snowCap);
	}
	return g;
}

// A tiny elf that walks back and forth between two points, carrying a gift.
export type Elf = {
	group: THREE.Group;
	update: (elapsed: number) => void;
};

export function buildElf(
	a: THREE.Vector3,
	b: THREE.Vector3,
	speed: number,
	tunic: string,
	hat: string,
	seed: number,
): Elf {
	const g = new THREE.Group();
	const rng = makeRng(seed);

	const body = new THREE.Mesh(
		new THREE.CylinderGeometry(0.03, 0.055, 0.1, 7),
		lowPolyMaterial(tunic),
	);
	body.position.y = 0.06;
	body.castShadow = true;
	g.add(body);
	const head = new THREE.Mesh(
		new THREE.SphereGeometry(0.035, 8, 6),
		lowPolyMaterial(SKIN, { flatShading: false }),
	);
	head.position.y = 0.135;
	g.add(head);
	const hatMesh = new THREE.Mesh(new THREE.ConeGeometry(0.038, 0.08, 7), lowPolyMaterial(hat));
	hatMesh.position.y = 0.185;
	g.add(hatMesh);
	const pom = new THREE.Mesh(
		new THREE.SphereGeometry(0.014, 6, 6),
		lowPolyMaterial(SNOW, { flatShading: false }),
	);
	pom.position.y = 0.225;
	g.add(pom);
	const gift = new THREE.Mesh(
		new THREE.BoxGeometry(0.05, 0.05, 0.05),
		lowPolyMaterial(rng() > 0.5 ? "#e0b93a" : GREEN),
	);
	gift.position.set(0, 0.06, 0.06);
	g.add(gift);

	const phase = rng() * Math.PI * 2;
	const gait = 6 + rng() * 2;
	const dir = new THREE.Vector3();
	const update = (elapsed: number) => {
		const t = Math.sin(elapsed * speed + phase) * 0.5 + 0.5;
		g.position.lerpVectors(a, b, t);
		g.position.y = Math.abs(Math.sin(elapsed * gait + phase)) * 0.02;
		dir
			.copy(b)
			.sub(a)
			.multiplyScalar(Math.cos(elapsed * speed + phase));
		if (dir.lengthSq() > 1e-5) {
			g.rotation.y = Math.atan2(dir.x, dir.z);
		}
	};
	return { group: g, update };
}

// Heavy falling snow bounded to the globe sphere.
export type Snow = {
	points: THREE.Points;
	update: (dt: number) => void;
};

export function buildSnow(
	count: number,
	center: THREE.Vector3,
	radius: number,
	floorY: number,
): Snow {
	const rng = makeRng(99);
	const positions = new Float32Array(count * 3);
	const speeds = new Float32Array(count);
	const spawn = (i: number, top: boolean) => {
		let x = 0;
		let y = 0;
		let z = 0;
		let d = 2;
		while (d > 1) {
			x = rng() * 2 - 1;
			y = rng() * 2 - 1;
			z = rng() * 2 - 1;
			d = x * x + y * y + z * z;
		}
		positions[i * 3] = center.x + x * radius;
		positions[i * 3 + 1] = center.y + (top ? 0.2 + Math.abs(y) * 0.8 : y) * radius;
		positions[i * 3 + 2] = center.z + z * radius;
		speeds[i] = 0.25 + rng() * 0.5;
	};
	for (let i = 0; i < count; i += 1) {
		spawn(i, false);
	}
	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
	const material = new THREE.PointsMaterial({
		map: flakeSprite(),
		color: new THREE.Color("#ffffff"),
		size: 0.15,
		sizeAttenuation: true,
		transparent: true,
		opacity: 1,
		depthWrite: false,
	});
	const points = new THREE.Points(geometry, material);
	const bound = radius * 0.98;
	const update = (dt: number) => {
		const attr = geometry.attributes.position as THREE.BufferAttribute;
		for (let i = 0; i < count; i += 1) {
			let x = attr.getX(i);
			let y = attr.getY(i) - speeds[i] * dt;
			let z = attr.getZ(i);
			x += Math.sin((y + i) * 1.5) * 0.003;
			const dx = x - center.x;
			const dy = y - center.y;
			const dz = z - center.z;
			if (dx * dx + dy * dy + dz * dz > bound * bound || y < floorY) {
				spawn(i, true);
				x = attr.array[i * 3] as number;
				y = attr.array[i * 3 + 1] as number;
				z = attr.array[i * 3 + 2] as number;
			}
			attr.setXYZ(i, x, y, z);
		}
		attr.needsUpdate = true;
	};
	return { points, update };
}

function flakeSprite(): THREE.CanvasTexture {
	const canvas = document.createElement("canvas");
	canvas.width = 32;
	canvas.height = 32;
	const ctx = canvas.getContext("2d");
	if (ctx) {
		const g = ctx.createRadialGradient(16, 16, 0, 16, 16, 16);
		g.addColorStop(0, "rgba(255,255,255,1)");
		g.addColorStop(0.82, "rgba(255,255,255,1)");
		g.addColorStop(1, "rgba(255,255,255,0)");
		ctx.fillStyle = g;
		ctx.beginPath();
		ctx.arc(16, 16, 16, 0, Math.PI * 2);
		ctx.fill();
	}
	const t = new THREE.CanvasTexture(canvas);
	t.colorSpace = THREE.SRGBColorSpace;
	return t;
}
