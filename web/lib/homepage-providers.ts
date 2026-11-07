import { PROVIDERS, type Provider } from "./site";

// Fixed homepage presentation contract; the native catalog and library stay independent.
export const HOMEPAGE_PROVIDER_KEYS = [
	"claude",
	"codex",
	"grok",
	"museSpark",
	"cursor",
	"openCodeGo",
] as const;
export type HomepageProviderKey = (typeof HOMEPAGE_PROVIDER_KEYS)[number];
const CATALOG_IDS: Record<HomepageProviderKey, string> = {
	claude: "claude",
	codex: "codex",
	grok: "grok",
	museSpark: "muse_spark",
	cursor: "cursor",
	openCodeGo: "opencodego",
};
export const HOMEPAGE_PROVIDERS = HOMEPAGE_PROVIDER_KEYS.map((key) => {
	// Cursor remains a fixed homepage example of local tool activity, not a second native provider.
	const provider: Provider | undefined =
		key === "cursor"
			? {
					id: "cursor",
					name: "Cursor",
					glyph: "Cu",
					tint: "--color-p-cursor",
					icon: "/provider-icons/cursor.svg",
					live: true,
					status: "live",
					statusLabel: "part of Grok",
					sources: ["codexbar", "coding-agent-usage-tracker", "open-island"],
				}
			: PROVIDERS.find((item) => item.id === CATALOG_IDS[key]);
	if (!provider) throw new Error(`Missing homepage provider: ${key}`);
	return provider;
});
