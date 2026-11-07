import { SITE } from "@/lib/site";

// One source of truth for the "Tell others" social-share surface, shared by the homepage demo
// (`menubar-demo.tsx`).

export const SHARE_URL = SITE.url;
// Copy strings are module-local — consumers only import SHARE_URL + SHARE_DESTINATIONS.
const SHARE_TEXT =
	"JP the Cat counts what Claude Code, Codex, Grok, and Muse Spark cost while keeping prompts on your Mac. The cat that counts your agent tokens.";
/** The X/Twitter variant appends the creator handle from `SITE` (never a hardcoded literal). */
const SHARE_TEXT_X = `${SHARE_TEXT} ${SITE.twitter}`;

export type ShareDestination = {
	id: string;
	label: string;
	/** Screen-reader `aria-label` for the destination link, and the demo's row subtitle. */
	description: string;
	/** Icon name resolved by each consumer's own icon renderer. */
	icon: string;
	href: string;
};

export const SHARE_DESTINATIONS: readonly ShareDestination[] = [
	{
		id: "x",
		label: "X / Twitter",
		description: `Posts with ${SITE.twitter} at the end`,
		icon: "bubbles",
		href: `https://twitter.com/intent/tweet?${new URLSearchParams({
			text: SHARE_TEXT_X,
			url: SHARE_URL,
		})}`,
	},
	{
		id: "facebook",
		label: "Facebook",
		description: "Shares the JP the Cat homepage",
		icon: "people",
		href: `https://www.facebook.com/sharer/sharer.php?${new URLSearchParams({
			u: SHARE_URL,
		})}`,
	},
	{
		id: "linkedin",
		label: "LinkedIn",
		description: "Shares the local-first AI-cost angle",
		icon: "briefcase",
		href: `https://www.linkedin.com/shareArticle?${new URLSearchParams({
			mini: "true",
			url: SHARE_URL,
			title: "JP the Cat counts agent tokens",
			summary: SHARE_TEXT,
			source: "JP the Cat",
		})}`,
	},
	{
		id: "reddit",
		label: "Reddit",
		description: "Starts a post with crafted title copy",
		icon: "text-bubble",
		href: `https://www.reddit.com/submit?${new URLSearchParams({
			url: SHARE_URL,
			title: SHARE_TEXT,
		})}`,
	},
	{
		id: "email",
		label: "Email",
		description: "Opens a ready-to-send note",
		icon: "mail",
		href: `mailto:?subject=${encodeURIComponent("JP the Cat counts agent tokens")}&body=${encodeURIComponent(`${SHARE_TEXT}\n\n${SHARE_URL}`)}`,
	},
] as const;
