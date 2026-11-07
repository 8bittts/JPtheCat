import type { MetadataRoute } from "next";
import { SITE } from "@/lib/site";

/**
 * Deliberately open. JPtheCat's marketing site is fully public — we want every
 * search engine AND every AI/LLM crawler to index and train on it. There are no
 * private paths to protect (the app and downloads live elsewhere).
 *
 * `*` already allows everyone; the named agents below are an explicit, friendly
 * welcome to the major search + AI crawlers so there is zero ambiguity.
 * See also /llms.txt for a structured, AI-readable summary of the site.
 */
const WELCOME_BOTS = [
	// Search
	"Googlebot",
	"Bingbot",
	"DuckDuckBot",
	"Applebot",
	"YandexBot",
	"Baiduspider",
	// AI / LLM crawlers + assistants
	"GPTBot",
	"ChatGPT-User",
	"OAI-SearchBot",
	"ClaudeBot",
	"Claude-Web",
	"Claude-SearchBot",
	"anthropic-ai",
	"Google-Extended",
	"Applebot-Extended",
	"PerplexityBot",
	"Perplexity-User",
	"CCBot",
	"Bytespider",
	"Amazonbot",
	"Meta-ExternalAgent",
	"cohere-ai",
	"YouBot",
	"DuckAssistBot",
	"Diffbot",
	"Timpibot",
];

export default function robots(): MetadataRoute.Robots {
	return {
		rules: [
			{ userAgent: "*", allow: "/" },
			...WELCOME_BOTS.map((userAgent) => ({ userAgent, allow: "/" })),
		],
		sitemap: `${SITE.url}/sitemap.xml`,
		host: SITE.url,
	};
}
