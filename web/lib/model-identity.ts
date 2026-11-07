/**
 * Web twin of the app's Core `ModelIdentity` + `ModelName`: one model-id pipeline for the homepage
 * demo and `/library`. A locally emitted id can carry a vendor prefix, Claude Code's `[1m]` selector,
 * a snapshot date, a documented alias, an accounting suffix (gateway `-opencode`, `-zen`, `-go`, then
 * an optional `-peak`; Claude `-fast-mode`, then an optional `-us-inference`), or a free-tier suffix.
 * None of those changes which model ran.
 *
 * `tests/fixtures/model-identity-cases.json` is read by BOTH `tests/model-identity.test.ts` and the
 * app's `ModelIdentityTests`, so the two platforms cannot label, group, or classify an id differently.
 */

import { MODEL_ID_ALIASES } from "@/lib/library/pricing-data";

const SNAPSHOT_DATE = /-(?:\d{8}|\d{4}-\d{2}-\d{2})$/;
const FREE_TIER_SUFFIX = "-free";
const PEAK_SUFFIX = "-peak";
/** Claude fast mode. Never bare `-fast`: real ids such as `grok-composer-2.5-fast` end in it. */
const FAST_MODE_SUFFIX = "-fast-mode";
/** Claude US-only inference, priced by a `RATE_MULTIPLIERS` factor on the id it decorates. */
const US_INFERENCE_SUFFIX = "-us-inference";
const ROUTE_SUFFIXES = ["-opencode", "-zen", "-go"] as const;

function removingSuffix(id: string, suffix: string): string {
	return id.length > suffix.length && id.endsWith(suffix) ? id.slice(0, -suffix.length) : id;
}

/** True for an OpenCode free-tier id (`…-free`, including `…-contributor-free`). */
function isFreeTierModel(model: string): boolean {
	return model.endsWith(FREE_TIER_SUFFIX);
}

/** The emitted id without its vendor prefix, `[1m]` selector, and snapshot date. Case preserved. */
export function undecoratedModelId(model: string): string {
	let id = model;
	const slash = id.lastIndexOf("/");
	if (slash >= 0 && slash < id.length - 1) id = id.slice(slash + 1);
	if (id.endsWith("[1m]")) id = id.slice(0, -4);
	return id.replace(SNAPSHOT_DATE, "");
}

/** Grouping and display identity: undecorated, accounting suffix removed, free tier kept. */
export function presentationModelId(model: string): string {
	const claude = removingSuffix(undecoratedModelId(model), US_INFERENCE_SUFFIX);
	const id = removingSuffix(removingSuffix(claude, FAST_MODE_SUFFIX), PEAK_SUFFIX);
	for (const route of ROUTE_SUFFIXES) {
		const stripped = removingSuffix(id, route);
		if (stripped !== id) return stripped;
	}
	return id;
}

/** Model-level key for classification tables: lowercased, free tier removed, then aliased. */
export function modelKey(model: string): string {
	const id = removingSuffix(presentationModelId(model).toLowerCase(), FREE_TIER_SUFFIX);
	return MODEL_ID_ALIASES[id] ?? id;
}

/**
 * Compact tile label: drops the family prefix the surrounding provider already names
 * (`claude-opus-4-5` → `opus-4-5`, `gpt-5.3-codex-spark` → `5.3-spark`, `grok-4.7-build` → `4.7`).
 * A free tier keeps a visible marker (`mimo-v2.5-free` → `mimo-v2.5 free`).
 */
export function shortModel(model: string): string {
	let s = presentationModelId(model);
	const isFree = isFreeTierModel(s) && s.length > FREE_TIER_SUFFIX.length;
	if (isFree) s = s.slice(0, -FREE_TIER_SUFFIX.length);
	const lower = s.toLowerCase();
	if (lower.startsWith("grok-") && lower.endsWith("-build") && lower !== "grok-build") {
		s = s.slice(0, -"-build".length);
	}
	if (/^claude-/i.test(s)) {
		s = s.slice("claude-".length);
	} else if (/^gpt-/i.test(s)) {
		// Under the Codex provider the `codex` token is redundant — `gpt-` already signals the family.
		s = s
			.slice("gpt-".length)
			.split("-")
			.filter((token) => token.length > 0 && token.toLowerCase() !== "codex")
			.join("-");
	} else if (/^grok-/i.test(s)) {
		s = s.slice("grok-".length);
	}
	return isFree ? `${s} free` : s;
}

/** Advanced Analytics keeps the `gpt-` prefix because its table mixes every provider's models. */
export function analyticsShortModel(model: string): string {
	const short = shortModel(model);
	const isGpt = presentationModelId(model).toLowerCase().startsWith("gpt-");
	return isGpt && !short.toLowerCase().startsWith("gpt-") ? `gpt-${short}` : short;
}
