// The shared tones the legal-page WebGL scene reads from one place (THREE.Color accepts hex strings
// directly). This is NOT the full scene palette — most geometry colors are set inline in
// world.ts / village.ts / lowpoly.ts / mascot.ts. Only the values actually referenced live here;
// keep it that way (unused entries are dead weight, not documentation).

export const PAL = {
	honey: "#edb454",
	skyTop: "#f4d7a6",
	skyMid: "#fae8cf",
	skyHorizon: "#fdf5e6",
	grassDark: "#6f9a58",
	cloud: "#fffdf8",
	// Globe backdrop dusk gradient — shared by the 3D `buildGlobeBackdrop` and the SVG poster so the
	// poster can't drift from the scene's dome.
	globeTop: "#1b2b49",
	globeBottom: "#43567c",
	// The page paper tone (mirrors `--color-paper` in app/globals.css) — the scene's bottom melts into
	// it in both the SVG poster and the WebGL stage's fade gradient. Sourced here so the two surfaces
	// use one value instead of each re-hardcoding the hex.
	paper: "#faf6ec",
} as const;
