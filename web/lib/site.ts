// Single source of truth for brand + copy. Swap `name`/`domain` to rebrand the whole site.
export const SITE = {
	name: "JP the Cat",
	seoName: "JP the Cat",
	mascot: "JP",
	// Display form (CamelCase) — shown to users as a URL wordmark. `url` below is the functional link.
	domain: "JPtheCat.com",
	url: "https://jpthecat.com",
	tagline: "The cat that counts your agent tokens.",
	// Homepage SEO follows its curated roster and qualifies Cursor as local token activity.
	// The independent full provider registry below retains its support tiers.
	description:
		"Free Mac app: track Claude Code, Codex, Grok, Muse Spark, Cursor tokens, and OpenCode Go locally. Clear cost, official limits, and measured gateway usage.",
	// JP's voice: opinionated, bossy, lovable, and extremely picky. Use sparingly for flavor.
	personality:
		"JP is a highly opinionated tortoiseshell with impeccable taste and zero patience for wasted tokens. Everyone wants to be her friend; she is extremely selective about it.",
	minMacOS: "macOS 14",
	email: "support@jpthecat.com",
	contactHref: "/contact",
	twitter: "@8bit",
	supportSocialUrl: "https://x.com/8bit",
	yenUrl: "https://yen.chat/",
	btcEmailUrl: "https://btc.email",
	repoUrl: "https://github.com/8bittts/JPtheCat",
	contributingUrl: "https://github.com/8bittts/JPtheCat/blob/main/CONTRIBUTING.md",
	downloadCtaLabel: "Download Meow",
	downloadCtaHref: "/download",
	ogImage: "/og.jpg",
	logo: "/jpthecat-logo.png",
	photo: "/jp-the-cat.jpeg",
	// Paper surface hex — mirror of `--color-paper` in globals.css, for static
	// metadata surfaces (PWA manifest, viewport theme-color) that can't read CSS vars.
	// Sticker Bomb canvas (`--sb-bg` in sticker.css) — manifest + theme-color.
	paperHex: "#fff6e6",
} as const;

export type Provider = {
	id: string;
	name: string;
	glyph: string; // short mark for the marquee
	tint: string; // css var name for the accent dot
	icon?: string; // self-hosted provider icon, when available
	live: boolean;
	status: ProviderStatus;
	statusLabel: string;
	sources: ProviderSource[];
};

type ProviderStatus =
	| "live"
	| "local-roadmap"
	| "connect-roadmap"
	| "api-roadmap"
	| "candidate-roadmap";

type ProviderSource =
	| "codexbar"
	| "ccusage"
	| "coding-agent-usage-tracker"
	| "open-island"
	| "jp-roadmap";

type ProviderDefinition = Omit<Provider, "tint" | "icon" | "live" | "statusLabel"> & {
	iconFile?: string;
	iconSlug?: string;
};

const PROVIDER_STATUS_LABELS: Record<ProviderStatus, string> = {
	live: "live",
	"local-roadmap": "local next",
	"connect-roadmap": "connect later",
	"api-roadmap": "api later",
	"candidate-roadmap": "candidate",
};

const PROVIDER_TINTS: Record<string, string> = {
	claude: "--color-p-claude",
	codex: "--color-p-codex",
	gemini: "--color-p-gemini",
	copilot: "--color-p-copilot",
	grok: "--color-p-grok",
	grok_bot: "--color-p-grok-bot",
	muse_spark: "--color-p-muse-spark",
	nemotron: "--color-p-nemotron",
	mimo: "--color-p-mimo",
	big_pickle: "--color-p-big-pickle",
	deepseek: "--color-p-deepseek",
	opencode: "--color-p-opencode",
	opencodego: "--color-p-opencodego",
	cursor: "--color-p-cursor",
	windsurf: "--color-p-windsurf",
	aider: "--color-p-aider",
	openai: "--color-p-openai",
	azureopenai: "--color-p-openai",
	openrouter: "--color-p-openrouter",
	litellm: "--color-p-openrouter",
	llmproxy: "--color-p-openrouter",
	ollama: "--color-p-local",
	amp: "--color-p-local",
	factory: "--color-p-local",
	codebuff: "--color-p-local",
	hermes: "--color-p-local",
	pi: "--color-p-local",
	goose: "--color-p-local",
	openclaw: "--color-p-local",
	qwen: "--color-p-local",
	qoder: "--color-p-local",
	codebuddy: "--color-p-local",
	kilo: "--color-p-local",
	kimi: "--color-p-local",
};

const PROVIDER_DEFINITIONS: ProviderDefinition[] = [
	{
		id: "claude",
		name: "Claude Code",
		glyph: "Cl",
		status: "live",
		sources: ["codexbar", "ccusage", "coding-agent-usage-tracker", "open-island"],
		iconSlug: "claude",
	},
	{
		id: "codex",
		name: "Codex",
		glyph: "Cx",
		status: "live",
		sources: ["codexbar", "ccusage", "coding-agent-usage-tracker", "open-island"],
		iconSlug: "codex",
	},
	{
		id: "grok",
		name: "Grok",
		glyph: "Gk",
		status: "live",
		sources: ["codexbar", "jp-roadmap"],
		iconSlug: "grok",
	},
	{
		id: "muse_spark",
		name: "Muse Spark",
		glyph: "Sp",
		status: "live",
		sources: ["jp-roadmap"],
		iconSlug: "muse-spark",
	},
	{
		id: "gemini",
		name: "Gemini",
		glyph: "G",
		status: "local-roadmap",
		sources: ["codexbar", "ccusage", "coding-agent-usage-tracker", "open-island"],
		iconSlug: "gemini",
	},
	{
		id: "copilot",
		name: "GitHub Copilot",
		glyph: "Co",
		status: "local-roadmap",
		sources: ["codexbar", "ccusage", "coding-agent-usage-tracker"],
		iconSlug: "copilot",
	},
	{
		id: "opencode",
		name: "OpenCode Zen",
		glyph: "Oc",
		status: "live",
		sources: ["codexbar", "ccusage", "coding-agent-usage-tracker", "open-island"],
		iconSlug: "opencode",
	},
	{
		id: "amp",
		name: "Amp",
		glyph: "Am",
		status: "local-roadmap",
		sources: ["codexbar", "ccusage", "coding-agent-usage-tracker"],
		iconSlug: "amp",
	},
	{
		id: "factory",
		name: "Droid (Factory)",
		glyph: "Dr",
		status: "local-roadmap",
		sources: ["codexbar", "ccusage", "coding-agent-usage-tracker", "open-island"],
		iconSlug: "factory",
	},
	{
		id: "codebuff",
		name: "Codebuff",
		glyph: "Cb",
		status: "local-roadmap",
		sources: ["codexbar", "ccusage"],
		iconSlug: "codebuff",
	},
	{
		id: "kilo",
		name: "Kilo",
		glyph: "Ki",
		status: "local-roadmap",
		sources: ["codexbar", "ccusage"],
		iconSlug: "kilo",
	},
	{
		id: "kimi",
		name: "Kimi",
		glyph: "Km",
		status: "local-roadmap",
		sources: ["codexbar", "ccusage", "coding-agent-usage-tracker", "open-island"],
		iconSlug: "kimi",
	},
	{
		id: "hermes",
		name: "Hermes Agent",
		glyph: "He",
		status: "local-roadmap",
		sources: ["ccusage"],
		iconSlug: "hermes",
	},
	{
		id: "pi",
		name: "pi-agent",
		glyph: "Pi",
		status: "local-roadmap",
		sources: ["ccusage"],
		iconSlug: "pi",
	},
	{
		id: "goose",
		name: "Goose",
		glyph: "Go",
		status: "local-roadmap",
		sources: ["ccusage"],
		iconSlug: "goose",
	},
	{
		id: "openclaw",
		name: "OpenClaw",
		glyph: "Oc",
		status: "local-roadmap",
		sources: ["ccusage"],
		iconSlug: "openclaw",
	},
	{
		id: "qwen",
		name: "Qwen",
		glyph: "Qw",
		status: "local-roadmap",
		sources: ["ccusage", "open-island"],
		iconFile: "qwen.png",
	},
	{
		id: "qoder",
		name: "Qoder",
		glyph: "Qd",
		status: "candidate-roadmap",
		sources: ["open-island"],
		iconSlug: "qoder",
	},
	{
		id: "codebuddy",
		name: "CodeBuddy",
		glyph: "CB",
		status: "candidate-roadmap",
		sources: ["open-island"],
		iconSlug: "codebuddy",
	},
	{
		id: "openai",
		name: "OpenAI",
		glyph: "OA",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "codex",
	},
	{
		id: "azureopenai",
		name: "Azure OpenAI",
		glyph: "Az",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "codex",
	},
	{
		id: "opencodego",
		name: "OpenCode Go",
		glyph: "Og",
		status: "live",
		sources: ["codexbar", "jp-roadmap"],
		iconSlug: "opencodego",
	},
	{
		id: "alibaba",
		name: "Alibaba",
		glyph: "Al",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "alibaba",
	},
	{
		id: "alibabatokenplan",
		name: "Alibaba Token Plan",
		glyph: "At",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "alibaba",
	},
	{
		id: "antigravity",
		name: "Antigravity",
		glyph: "Ag",
		status: "local-roadmap",
		sources: ["codexbar", "coding-agent-usage-tracker"],
		iconSlug: "antigravity",
	},
	{
		id: "devin",
		name: "Devin",
		glyph: "Dv",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "devin",
	},
	{
		id: "zai",
		name: "z.ai",
		glyph: "Za",
		status: "api-roadmap",
		sources: ["codexbar", "coding-agent-usage-tracker"],
		iconSlug: "zai",
	},
	{
		id: "minimax",
		name: "MiniMax",
		glyph: "Mm",
		status: "api-roadmap",
		sources: ["codexbar", "coding-agent-usage-tracker"],
		iconSlug: "minimax",
	},
	{
		id: "manus",
		name: "Manus",
		glyph: "Ma",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "manus",
	},
	{
		id: "kiro",
		name: "Kiro",
		glyph: "Kr",
		status: "api-roadmap",
		sources: ["codexbar", "coding-agent-usage-tracker"],
		iconSlug: "kiro",
	},
	{
		id: "vertexai",
		name: "Vertex AI",
		glyph: "Vx",
		status: "api-roadmap",
		sources: ["codexbar", "coding-agent-usage-tracker"],
		iconSlug: "vertexai",
	},
	{
		id: "augment",
		name: "Augment",
		glyph: "Au",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "augment",
	},
	{
		id: "jetbrains",
		name: "JetBrains AI",
		glyph: "Jb",
		status: "api-roadmap",
		sources: ["codexbar", "coding-agent-usage-tracker"],
		iconSlug: "jetbrains",
	},
	{
		id: "kimik2",
		name: "Kimi K2 (unofficial)",
		glyph: "K2",
		status: "api-roadmap",
		sources: ["codexbar", "coding-agent-usage-tracker"],
		iconSlug: "kimi",
	},
	{
		id: "moonshot",
		name: "Moonshot / Kimi API",
		glyph: "Mo",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "kimi",
	},
	{
		id: "t3chat",
		name: "T3 Chat",
		glyph: "T3",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "t3chat",
	},
	{
		id: "ollama",
		name: "Ollama",
		glyph: "Ol",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "ollama",
	},
	{
		id: "synthetic",
		name: "Synthetic",
		glyph: "Sy",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "synthetic",
	},
	{
		id: "openrouter",
		name: "OpenRouter",
		glyph: "Or",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "openrouter",
	},
	{
		id: "elevenlabs",
		name: "ElevenLabs",
		glyph: "El",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "elevenlabs",
	},
	{
		id: "warp",
		name: "Warp",
		glyph: "Wp",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "warp",
	},
	{
		id: "windsurf",
		name: "Windsurf",
		glyph: "Ws",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "windsurf",
	},
	{
		id: "zed",
		name: "Zed",
		glyph: "Zd",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "zed",
	},
	{
		id: "perplexity",
		name: "Perplexity",
		glyph: "Px",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "perplexity",
	},
	{
		id: "mimo",
		name: "Xiaomi MiMo",
		glyph: "Mi",
		status: "local-roadmap",
		sources: ["jp-roadmap"],
		iconSlug: "mimo",
	},
	{
		id: "doubao",
		name: "Doubao",
		glyph: "Db",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "doubao",
	},
	{
		id: "sakana",
		name: "Sakana AI",
		glyph: "Sk",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "sakana",
	},
	{
		id: "abacus",
		name: "Abacus AI",
		glyph: "Ab",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "abacus",
	},
	{
		id: "mistral",
		name: "Mistral",
		glyph: "Ms",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "mistral",
	},
	{
		id: "deepseek",
		name: "DeepSeek",
		glyph: "Ds",
		status: "local-roadmap",
		sources: ["jp-roadmap"],
		iconSlug: "deepseek",
	},
	{
		id: "nemotron",
		name: "Nemotron 3",
		glyph: "Nt",
		status: "local-roadmap",
		sources: ["jp-roadmap"],
		iconSlug: "nemotron",
	},
	{
		id: "big_pickle",
		name: "Big Pickle",
		glyph: "BP",
		status: "local-roadmap",
		sources: ["jp-roadmap"],
		iconSlug: "big-pickle",
	},
	{
		id: "crof",
		name: "Crof",
		glyph: "Cr",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "crof",
	},
	{
		id: "venice",
		name: "Venice",
		glyph: "Ve",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "venice",
	},
	{
		id: "commandcode",
		name: "Command Code",
		glyph: "Cc",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "commandcode",
	},
	{
		id: "stepfun",
		name: "StepFun",
		glyph: "Sf",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "stepfun",
	},
	{
		id: "bedrock",
		name: "AWS Bedrock",
		glyph: "Br",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "bedrock",
	},
	{
		id: "groq",
		name: "Groq",
		glyph: "Gq",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "groq",
	},
	{
		id: "llmproxy",
		name: "LLM Proxy",
		glyph: "Lp",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "llmproxy",
	},
	{
		id: "litellm",
		name: "LiteLLM",
		glyph: "Ll",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "litellm",
	},
	{
		id: "deepgram",
		name: "Deepgram",
		glyph: "Dg",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "deepgram",
	},
	{
		id: "poe",
		name: "Poe",
		glyph: "Po",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "poe",
	},
	{
		id: "chutes",
		name: "Chutes",
		glyph: "Ch",
		status: "api-roadmap",
		sources: ["codexbar"],
		iconSlug: "chutes",
	},
	{
		id: "aider",
		name: "Aider",
		glyph: "Ai",
		status: "candidate-roadmap",
		sources: ["jp-roadmap"],
	},
];

// Per-provider identity. `tint` maps to a CSS custom property in globals.css.
export const PROVIDERS: Provider[] = PROVIDER_DEFINITIONS.map((provider) => ({
	...provider,
	tint: PROVIDER_TINTS[provider.id] ?? "--color-p-generic",
	icon: provider.iconFile
		? `/provider-icons/${provider.iconFile}`
		: provider.iconSlug
			? `/provider-icons/${provider.iconSlug}.svg`
			: undefined,
	live: provider.status === "live",
	statusLabel: PROVIDER_STATUS_LABELS[provider.status],
}));

// The website marquee duplicates the full catalog once for a seamless loop.

export const PROVIDER_COUNTS = {
	total: PROVIDERS.length,
	live: PROVIDERS.filter((provider) => provider.live).length,
	codexBarBaseline: PROVIDERS.filter((provider) => provider.sources.includes("codexbar")).length,
	ccusageLocalSources: PROVIDERS.filter((provider) => provider.sources.includes("ccusage")).length,
	codingAgentUsageTracker: PROVIDERS.filter((provider) =>
		provider.sources.includes("coding-agent-usage-tracker"),
	).length,
	openIslandAgents: PROVIDERS.filter((provider) => provider.sources.includes("open-island")).length,
	localRoadmap: PROVIDERS.filter((provider) => provider.status === "local-roadmap").length,
	connectRoadmap: PROVIDERS.filter((provider) => provider.status === "connect-roadmap").length,
	apiRoadmap: PROVIDERS.filter((provider) => provider.status === "api-roadmap").length,
} as const;

// Every homepage section the old standalone pages folded into. JP is free, so there is no pricing link.
export const NAV = [
	{ label: "How it works", href: "/#how" },
	{ label: "Widget", href: "/#widget" },
	{ label: "Privacy", href: "/#honest" },
	{ label: "FAQ", href: "/#faq" },
] as const;
