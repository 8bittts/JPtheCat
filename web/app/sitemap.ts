import type { MetadataRoute } from "next";
import { libraryUrlEntries } from "@/lib/library/sitemap-entries";
import { SITE } from "@/lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
	const staticEntries: MetadataRoute.Sitemap = ["", "/contact", "/terms"].map((path) => ({
		url: `${SITE.url}${path}`,
		changeFrequency: path === "" ? "weekly" : "monthly",
		priority: path === "" ? 1 : 0.5,
	}));

	// The crawlable-but-unlinked /library hub: only search-eligible URLs enter the sitemap; thin
	// roadmap-provider references remain reachable but noindexed (_docs/08-growth.md SEO guardrails).
	const libraryEntries: MetadataRoute.Sitemap = libraryUrlEntries().map((entry) => ({
		url: `${SITE.url}${entry.path}`,
		changeFrequency: "monthly",
		priority: entry.priority,
	}));

	return [...staticEntries, ...libraryEntries];
}
