// Static poster — first-paint layer + reduced-motion / no-WebGL fallback.
// Mirrors the 3D scene: a Christmas snow globe (dark dusk sky, snow, a Santa
// house, elves) with JP as a little sun, floating on the warm page — no grass,
// the bottom melts into the content below.

import { PAL } from "./palette";

// Values shared with the 3D scene resolve from PAL so the poster can't silently
// desync from the dome (the "poster mirrors scene" invariant); the rest are
// poster-only illustration tones with no 3D counterpart.
const C = {
	cloud: PAL.cloud,
	wood: "#5b3219",
	paper: PAL.paper,
	skyTop: PAL.skyTop,
	skyMid: PAL.skyMid,
	skyHorizon: PAL.skyHorizon,
	globeTop: PAL.globeTop,
	globeBottom: PAL.globeBottom,
	snow: "#f6fbff",
	red: "#c9392b",
	green: "#2f6b40",
	cream: "#f2e7d2",
	glow: "#ffdf8a",
	ray: "#ffd27a",
};

const ALT = {
	privacy:
		"A Christmas snow globe: inside the glass, heavy snow falls over a cozy Santa house with glowing windows, snow-capped pine trees and little elves, with JP the cat glowing like a little sun above them.",
	terms:
		"A Christmas snow globe with heavy falling snow, a cozy Santa house, snow-capped pines, little elves and JP the cat glowing like a little sun above them (the same scene as the privacy page).",
} as const;

const CLOUD_PUFFS: [number, number, number][] = [
	[210, 120, 0.9],
	[1010, 110, 1.0],
	[590, 80, 0.7],
];

// Deterministic snowflake positions inside the globe (rounded strings so SSR and
// hydration never differ on floating-point tails).
const FLAKES: { key: string; cx: string; cy: string; r: string }[] = [];
for (let i = 0; i < 90; i += 1) {
	const a = i * 2.399963;
	const r = 176 * Math.sqrt((i + 0.5) / 90);
	const cx = (600 + Math.cos(a) * r).toFixed(2);
	const cy = (300 + Math.sin(a) * r - 20).toFixed(2);
	FLAKES.push({ key: `f-${cx}-${cy}`, cx, cy, r: (1.6 + ((i * 7) % 5) * 0.7).toFixed(1) });
}

// Sun rays around JP (relative to the sun centre).
const SUN_RAYS: { key: string; x1: string; y1: string; x2: string; y2: string; w: string }[] = [];
for (let i = 0; i < 16; i += 1) {
	const a = (i / 16) * Math.PI * 2;
	const long = i % 2 === 0;
	const r0 = 52;
	const r1 = long ? 92 : 74;
	SUN_RAYS.push({
		key: `ray-${i}`,
		x1: (Math.cos(a) * r0).toFixed(1),
		y1: (Math.sin(a) * r0).toFixed(1),
		x2: (Math.cos(a) * r1).toFixed(1),
		y2: (Math.sin(a) * r1).toFixed(1),
		w: long ? "4" : "2.5",
	});
}

export function ScenePoster({ variant }: { variant: "privacy" | "terms" }) {
	return (
		<>
			<svg
				className="absolute inset-0 h-full w-full"
				viewBox="0 0 1200 620"
				preserveAspectRatio="xMidYMid slice"
				aria-hidden="true"
				focusable="false"
			>
				<title>JP Christmas snow globe</title>
				<defs>
					<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
						<stop offset="0" stopColor={C.skyTop} />
						<stop offset="0.55" stopColor={C.skyMid} />
						<stop offset="1" stopColor={C.skyHorizon} />
					</linearGradient>
					<linearGradient id="globe" x1="0" y1="0" x2="0" y2="1">
						<stop offset="0" stopColor={C.globeTop} />
						<stop offset="1" stopColor={C.globeBottom} />
					</linearGradient>
					<radialGradient id="sunGlow" cx="0.5" cy="0.5" r="0.5">
						<stop offset="0" stopColor="#fff4d0" stopOpacity="0.95" />
						<stop offset="0.4" stopColor={C.glow} stopOpacity="0.5" />
						<stop offset="1" stopColor={C.glow} stopOpacity="0" />
					</radialGradient>
					<radialGradient id="glint" cx="0.5" cy="0.5" r="0.5">
						<stop offset="0" stopColor="#ffffff" stopOpacity="0.9" />
						<stop offset="1" stopColor="#ffffff" stopOpacity="0" />
					</radialGradient>
					<linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">
						<stop offset="0" stopColor={C.paper} stopOpacity="0" />
						<stop offset="1" stopColor={C.paper} stopOpacity="1" />
					</linearGradient>
					<clipPath id="globeClip">
						<circle cx="600" cy="300" r="188" />
					</clipPath>
				</defs>
				<rect width="1200" height="620" fill="url(#sky)" />
				{CLOUD_PUFFS.map(([x, y, s]) => (
					<g key={`c-${x}-${y}`} transform={`translate(${x} ${y}) scale(${s})`} opacity="0.9">
						<ellipse cx="0" cy="0" rx="60" ry="30" fill={C.cloud} />
						<ellipse cx="-42" cy="8" rx="36" ry="22" fill={C.cloud} />
						<ellipse cx="44" cy="10" rx="40" ry="24" fill={C.cloud} />
					</g>
				))}
				{/* pedestal */}
				<ellipse cx="600" cy="474" rx="140" ry="26" fill={C.wood} />
				<path d="M462,470 h276 v34 a138,26 0 0 1 -276,0 z" fill={C.wood} opacity="0.85" />
				{/* globe interior */}
				<g clipPath="url(#globeClip)">
					<circle cx="600" cy="300" r="188" fill="url(#globe)" />
					<ellipse cx="600" cy="446" rx="180" ry="40" fill={C.snow} />
					<g transform="translate(505 405)">
						<polygon points="0,-70 24,0 -24,0" fill={C.green} />
						<polygon points="0,-70 14,-40 -14,-40" fill={C.snow} />
					</g>
					<g transform="translate(700 410)">
						<polygon points="0,-58 20,0 -20,0" fill={C.green} />
						<polygon points="0,-58 12,-34 -12,-34" fill={C.snow} />
					</g>
					<g transform="translate(600 400)">
						<rect x="-46" y="-44" width="92" height="46" fill={C.cream} />
						<polygon points="-58,-44 0,-92 58,-44" fill={C.red} />
						<polygon points="-58,-44 0,-80 58,-44" fill={C.snow} opacity="0.9" />
						<rect x="-14" y="-30" width="28" height="46" fill={C.red} />
						<rect x="-34" y="-30" width="18" height="18" fill={C.glow} />
						<rect x="16" y="-30" width="18" height="18" fill={C.glow} />
					</g>
					<g transform="translate(555 430)">
						<polygon points="0,-16 6,0 -6,0" fill={C.green} />
						<polygon points="0,-24 5,-14 -5,-14" fill={C.red} />
					</g>
					<g transform="translate(655 432)">
						<polygon points="0,-16 6,0 -6,0" fill={C.red} />
						<polygon points="0,-24 5,-14 -5,-14" fill={C.green} />
					</g>
					{FLAKES.map((flake) => (
						<circle key={flake.key} cx={flake.cx} cy={flake.cy} r={flake.r} fill={C.snow} />
					))}
					{/* JP as a little sun, upper-right */}
					<g transform="translate(712 236)">
						<circle r="96" fill="url(#sunGlow)" />
						{SUN_RAYS.map((ray) => (
							<line
								key={ray.key}
								x1={ray.x1}
								y1={ray.y1}
								x2={ray.x2}
								y2={ray.y2}
								stroke={C.ray}
								strokeWidth={ray.w}
								strokeLinecap="round"
								opacity="0.75"
							/>
						))}
						<image href="/jp-paw-lick-purr-poster.webp" x="-46" y="-46" width="92" height="92" />
					</g>
				</g>
				{/* rim + a single top-right glint */}
				<circle
					cx="600"
					cy="300"
					r="188"
					fill="none"
					stroke="#ffffff"
					strokeWidth="2"
					opacity="0.22"
				/>
				<ellipse
					cx="736"
					cy="168"
					rx="26"
					ry="46"
					fill="url(#glint)"
					transform="rotate(-28 736 168)"
				/>
				{/* melt the bottom into the page content */}
				<rect x="0" y="470" width="1200" height="150" fill="url(#fade)" />
			</svg>
			<span className="sr-only">{ALT[variant]}</span>
		</>
	);
}
