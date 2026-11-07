import type { ReactNode } from "react";

/**
 * The provenance primitive that makes every money surface honest by construction (_docs/08-growth.md SEO guardrails). `notional` tone carries the list-price marker for subscription providers
 * (Codex/Gemini); `neutral` carries the real-cost note for Claude.
 */
export function HonestyNote({
	children,
	tone = "neutral",
}: {
	children: ReactNode;
	tone?: "neutral" | "notional";
}) {
	const isNotional = tone === "notional";
	return (
		<p className={`sb-notice ${isNotional ? "sb-notice--notional" : ""}`}>
			{isNotional ? <strong>Notional list price. </strong> : null}
			{children}
		</p>
	);
}
