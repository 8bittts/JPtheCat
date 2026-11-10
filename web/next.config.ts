import type { NextConfig } from "next";

const nextConfig: NextConfig = {
	poweredByHeader: false,
	images: {
		formats: ["image/avif", "image/webp"],
		qualities: [75, 90],
	},
	// The /download route handler reads public/stable/version.json at runtime via
	// readFile(join(process.cwd(), ...)). Next's file tracer can miss a dynamic process.cwd()
	// read, which would drop the file from the serverless bundle and 500 the route. Pin it in
	// explicitly so the trusted-release gate always has its version manifest.
	outputFileTracingIncludes: {
		"/download": ["./public/stable/version.json"],
	},
	// Retired pages (release notes, changelog, the paid-era /thanks, and the newsletter /confirmed
	// page) redirect in one hop so old inbound and emailed links never 404 or chain.
	async redirects() {
		// Sticker Bomb consolidation: the standalone marketing topics now live as sections of the one
		// long homepage. These are temporary (307) while the redesign settles, so they can still move.
		const homeSections: [string, string][] = [
			["/pricing", "download"],
			["/buy", "download"],
			["/features", "how"],
			["/how-it-works", "how"],
			["/faq", "faq"],
			["/about", "top"],
			["/widget", "widget"],
			["/themes", "themes"],
			["/accuracy", "honest"],
			["/security", "honest"],
			["/demo", "demo"],
		];
		return [
			...["cursor", "grok-bot"].flatMap((legacy) => [
				{ source: `/library/${legacy}`, destination: "/library/track/grok", permanent: true },
				{ source: `/library/track/${legacy}`, destination: "/library/track/grok", permanent: true },
				{
					source: `/library/limits/${legacy}`,
					destination: "/library/limits/grok",
					permanent: true,
				},
			]),
			{ source: "/release-notes", destination: "/", permanent: false },
			{ source: "/changelog", destination: "/", permanent: false },
			{ source: "/release", destination: "/", permanent: false },
			{ source: "/thanks", destination: "/", permanent: false },
			{ source: "/confirmed", destination: "/", permanent: false },
			{ source: "/api/newsletter/confirm", destination: "/", permanent: false },
			{ source: "/support", destination: "/contact", permanent: false },
			{ source: "/privacy", destination: "/terms#privacy-policy", permanent: true },
			...homeSections.map(([source, anchor]) => ({
				source,
				destination: `/#${anchor}`,
				permanent: false,
			})),
		];
	},
};

export default nextConfig;
