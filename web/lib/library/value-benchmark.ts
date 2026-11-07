/**
 * Cross-vendor "bang for the buck" rankings from the bundled pricing table.
 * Uses the same standard coding-agent session as the library calculators
 * (500K in / 100K out / 2M cache-read) and the qualitative effort labels
 * already on each model page.
 *
 * Only models with an explicit effort tier are ranked, and only under their own id: a gateway
 * billing route (`-go`, `-zen`, `-peak`, `-opencode`) is a rate for a model, not a model.
 */

import { presentationModelId } from "@/lib/model-identity";
import type { ModelId } from "./pricing-data";
import { MODEL_IDS } from "./pricing-data";
import {
	isModelPricingEligible,
	isSubscriptionNotional,
	MODEL_DISPLAY_NAME,
	MODEL_SLUG,
	type ModelEffortLevel,
	modelEffortLevel,
	modelVendor,
	type PricingVendor,
	pricing,
	VENDOR_LABEL,
} from "./pricing-registry";

/** Matches `CALCULATOR_DEFAULTS.session` in `lib/library/calculator-math.ts`. */
export const BENCHMARK_INPUT_K = 500;
export const BENCHMARK_OUTPUT_K = 100;
export const BENCHMARK_CACHE_READ_K = 2000;

const EFFORT_WEIGHT: Record<ModelEffortLevel, number> = {
	low: 1,
	medium: 2,
	high: 3,
};

export interface ValueBenchmarkRow {
	id: ModelId;
	rank: number;
	displayName: string;
	vendor: PricingVendor;
	vendorLabel: string;
	effort: ModelEffortLevel;
	sessionCostUsd: number;
	valueScore: number;
	notional: boolean;
	pricingHref?: string;
}

function tokens(thousands: number): number {
	return Math.max(0, thousands) * 1000;
}

/** Blended session cost at the standard library workload. */
export function benchmarkSessionCost(id: ModelId): number {
	const p = pricing(id);
	const cacheRead = p.cache_read_input_token_cost ?? p.input_cost_per_token * 0.1;
	return (
		tokens(BENCHMARK_INPUT_K) * p.input_cost_per_token +
		tokens(BENCHMARK_OUTPUT_K) * p.output_cost_per_token +
		tokens(BENCHMARK_CACHE_READ_K) * cacheRead
	);
}

/** Higher = more capability per dollar (effort weight ÷ session cost); 0 when unranked. */
export function benchmarkValueScore(id: ModelId): number {
	const cost = benchmarkSessionCost(id);
	const effort = modelEffortLevel(id);
	if (cost <= 0 || !effort) return 0;
	return EFFORT_WEIGHT[effort] / cost;
}

function pricingFingerprint(id: ModelId, effort: ModelEffortLevel): string {
	const p = pricing(id);
	const cacheRead = p.cache_read_input_token_cost ?? p.input_cost_per_token * 0.1;
	return [p.input_cost_per_token, p.output_cost_per_token, cacheRead, effort].join("|");
}

/**
 * One canonical row per distinct rate+effort profile among ranked models: an explicit effort tier and
 * no gateway route suffix.
 */
export function distinctBenchmarkModelIds(): ModelId[] {
	const seen = new Set<string>();
	const ids: ModelId[] = [];
	for (const id of MODEL_IDS) {
		const effort = modelEffortLevel(id);
		if (!effort || presentationModelId(id) !== id) continue;
		const key = pricingFingerprint(id, effort);
		if (seen.has(key)) continue;
		seen.add(key);
		ids.push(id);
	}
	return ids;
}

function toRow(id: ModelId, effort: ModelEffortLevel, rank: number): ValueBenchmarkRow {
	const vendor = modelVendor(id);
	const pricingHref = isModelPricingEligible(id)
		? `/library/pricing/${MODEL_SLUG[id]}`
		: `/library/pricing/family/${vendor}`;
	return {
		id,
		rank,
		displayName: MODEL_DISPLAY_NAME[id],
		vendor,
		vendorLabel: VENDOR_LABEL[vendor],
		effort,
		sessionCostUsd: benchmarkSessionCost(id),
		valueScore: benchmarkValueScore(id),
		notional: isSubscriptionNotional(id),
		pricingHref,
	};
}

/** Top N models by value score across the full catalog. */
export function topValueBenchmarkRows(limit = 8): ValueBenchmarkRow[] {
	const ranked = distinctBenchmarkModelIds()
		.flatMap((id) => {
			const effort = modelEffortLevel(id);
			return effort ? [{ id, effort, score: benchmarkValueScore(id) }] : [];
		})
		.sort((a, b) => b.score - a.score || a.id.localeCompare(b.id));
	return ranked.slice(0, limit).map((entry, index) => toRow(entry.id, entry.effort, index + 1));
}

/** Best value pick within each effort tier (for the tier callout row). */
export function bestValueByEffort(): Record<ModelEffortLevel, ValueBenchmarkRow | undefined> {
	const byEffort: Record<ModelEffortLevel, { id: ModelId; score: number } | undefined> = {
		low: undefined,
		medium: undefined,
		high: undefined,
	};
	for (const id of distinctBenchmarkModelIds()) {
		const effort = modelEffortLevel(id);
		if (!effort) continue;
		const score = benchmarkValueScore(id);
		const current = byEffort[effort];
		if (!current || score > current.score) {
			byEffort[effort] = { id, score };
		}
	}
	return {
		low: byEffort.low ? toRow(byEffort.low.id, "low", 1) : undefined,
		medium: byEffort.medium ? toRow(byEffort.medium.id, "medium", 1) : undefined,
		high: byEffort.high ? toRow(byEffort.high.id, "high", 1) : undefined,
	};
}
