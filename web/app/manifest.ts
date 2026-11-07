import type { MetadataRoute } from "next";
import { SITE } from "@/lib/site";

export default function manifest(): MetadataRoute.Manifest {
	return {
		name: SITE.name,
		short_name: SITE.name,
		description: SITE.description,
		start_url: "/",
		display: "standalone",
		background_color: SITE.paperHex,
		theme_color: SITE.paperHex,
		icons: [
			{ src: "/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
			{ src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
			// Dedicated maskable icon: the face sits inside the safe zone on a full-bleed cream
			// background (no transparent corners), so Android's adaptive mask never crops the mascot.
			{ src: "/icon-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
		],
	};
}
