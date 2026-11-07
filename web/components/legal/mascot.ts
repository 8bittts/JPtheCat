// JP herself — the real hand-drawn mascot, rendered on a disc so we get a clean
// circular medallion. Unlit + un-tonemapped for true illustration colors, with
// a thin gold rim and a gentle floating idle. Positioned by the scene.

import * as THREE from "three";

type Mascot = {
	group: THREE.Group;
	update: (dt: number, elapsed: number) => void;
};

function buildMascot(diameter = 2.6): Mascot {
	const group = new THREE.Group();
	const radius = diameter / 2;

	// A failed poster fetch must not leave a blank white medallion floating in the scene: hide the
	// disc and keep the gold rim, so the composition degrades to an empty ring rather than a defect.
	const texture = new THREE.TextureLoader().load(
		"/jp-paw-lick-purr-poster.webp",
		undefined,
		undefined,
		() => {
			disc.visible = false;
		},
	);
	texture.colorSpace = THREE.SRGBColorSpace;
	texture.anisotropy = 16;

	const material = new THREE.MeshBasicMaterial({
		map: texture,
		transparent: true,
		alphaTest: 0.02,
		toneMapped: false,
		side: THREE.DoubleSide,
	});
	const disc = new THREE.Mesh(new THREE.CircleGeometry(radius, 56), material);
	group.add(disc);

	const rim = new THREE.Mesh(
		new THREE.TorusGeometry(radius * 0.995, radius * 0.03, 10, 56),
		new THREE.MeshStandardMaterial({
			color: new THREE.Color("#e7b53a"),
			roughness: 0.45,
			metalness: 0.2,
		}),
	);
	group.add(rim);

	const update = (_dt: number, elapsed: number) => {
		const bob = Math.sin(elapsed * 0.9) * 0.09;
		disc.position.y = bob;
		rim.position.y = bob;
		disc.rotation.z = Math.sin(elapsed * 0.5) * 0.02;
		rim.rotation.z = disc.rotation.z;
	};

	return { group, update };
}

export type Sun = {
	group: THREE.Group;
	update: (dt: number, elapsed: number) => void;
};

// JP as a little sun: the mascot disc + a warm glow halo, spinning rays, and a
// few pulsing lens flares.
export function buildSun(diameter = 0.9): Sun {
	const group = new THREE.Group();

	const glowMat = new THREE.MeshBasicMaterial({
		map: sunGlowTexture(),
		transparent: true,
		blending: THREE.AdditiveBlending,
		depthWrite: false,
		opacity: 0.55,
	});
	const glow = new THREE.Mesh(new THREE.PlaneGeometry(diameter * 3.2, diameter * 3.2), glowMat);
	glow.position.z = -0.06;
	group.add(glow);

	const raysMat = new THREE.MeshBasicMaterial({
		map: sunRaysTexture(),
		transparent: true,
		blending: THREE.AdditiveBlending,
		depthWrite: false,
		opacity: 0.7,
	});
	const rays = new THREE.Mesh(new THREE.PlaneGeometry(diameter * 3.7, diameter * 3.7), raysMat);
	rays.position.z = -0.05;
	group.add(rays);

	const mascot = buildMascot(diameter);
	group.add(mascot.group);

	const flareTex = flareSprite();
	const flares: { mesh: THREE.Mesh; angle: number; dist: number; ph: number }[] = [];
	for (let i = 0; i < 4; i += 1) {
		const mesh = new THREE.Mesh(
			new THREE.PlaneGeometry(diameter * 0.28, diameter * 0.28),
			new THREE.MeshBasicMaterial({
				map: flareTex,
				transparent: true,
				blending: THREE.AdditiveBlending,
				depthWrite: false,
				opacity: 0.5,
			}),
		);
		mesh.position.z = 0.05;
		group.add(mesh);
		flares.push({
			mesh,
			angle: (i / 4) * Math.PI * 2,
			dist: diameter * (0.85 + (i % 2) * 0.35),
			ph: i * 1.7,
		});
	}

	const update = (dt: number, elapsed: number) => {
		rays.rotation.z += dt * 0.1;
		glow.scale.setScalar(1 + Math.sin(elapsed * 1.6) * 0.06);
		glowMat.opacity = 0.5 + Math.sin(elapsed * 1.6) * 0.1;
		raysMat.opacity = 0.6 + Math.sin(elapsed * 2) * 0.12;
		mascot.update(dt, elapsed);
		for (const f of flares) {
			const a = f.angle + elapsed * 0.28;
			f.mesh.position.set(Math.cos(a) * f.dist, Math.sin(a) * f.dist, 0.05);
			(f.mesh.material as THREE.MeshBasicMaterial).opacity =
				0.2 + (Math.sin(elapsed * 3 + f.ph) * 0.5 + 0.5) * 0.55;
		}
	};

	return { group, update };
}

function sunGlowTexture(): THREE.CanvasTexture {
	const canvas = document.createElement("canvas");
	canvas.width = 256;
	canvas.height = 256;
	const ctx = canvas.getContext("2d");
	if (ctx) {
		const g = ctx.createRadialGradient(128, 128, 0, 128, 128, 128);
		g.addColorStop(0, "rgba(255,244,208,0.95)");
		g.addColorStop(0.35, "rgba(255,214,120,0.5)");
		g.addColorStop(1, "rgba(255,200,90,0)");
		ctx.fillStyle = g;
		ctx.fillRect(0, 0, 256, 256);
	}
	const t = new THREE.CanvasTexture(canvas);
	t.colorSpace = THREE.SRGBColorSpace;
	return t;
}

function sunRaysTexture(): THREE.CanvasTexture {
	const canvas = document.createElement("canvas");
	canvas.width = 256;
	canvas.height = 256;
	const ctx = canvas.getContext("2d");
	if (ctx) {
		const cx = 128;
		const cy = 128;
		const count = 16;
		for (let i = 0; i < count; i += 1) {
			const a = (i / count) * Math.PI * 2;
			const long = i % 2 === 0;
			const r0 = 60;
			const r1 = long ? 126 : 100;
			const w = long ? 0.055 : 0.04;
			ctx.beginPath();
			ctx.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1);
			ctx.lineTo(cx + Math.cos(a - w) * r0, cy + Math.sin(a - w) * r0);
			ctx.lineTo(cx + Math.cos(a + w) * r0, cy + Math.sin(a + w) * r0);
			ctx.closePath();
			ctx.fillStyle = long ? "rgba(255,220,130,0.85)" : "rgba(255,205,110,0.6)";
			ctx.fill();
		}
	}
	const t = new THREE.CanvasTexture(canvas);
	t.colorSpace = THREE.SRGBColorSpace;
	return t;
}

function flareSprite(): THREE.CanvasTexture {
	const canvas = document.createElement("canvas");
	canvas.width = 32;
	canvas.height = 32;
	const ctx = canvas.getContext("2d");
	if (ctx) {
		const g = ctx.createRadialGradient(16, 16, 0, 16, 16, 16);
		g.addColorStop(0, "rgba(255,248,224,1)");
		g.addColorStop(0.5, "rgba(255,226,150,0.5)");
		g.addColorStop(1, "rgba(255,226,150,0)");
		ctx.fillStyle = g;
		ctx.beginPath();
		ctx.arc(16, 16, 16, 0, Math.PI * 2);
		ctx.fill();
	}
	const t = new THREE.CanvasTexture(canvas);
	t.colorSpace = THREE.SRGBColorSpace;
	return t;
}
