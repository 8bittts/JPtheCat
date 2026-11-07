/** Pure calculator pricing, shared by the client widget and its tests (no pricing-table import). */

import type { CalcModel, CalculatorMode } from "./content/calculators";

export interface TokenMix {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
}

export const CALCULATOR_DEFAULTS: Record<CalculatorMode, TokenMix> = {
	// Matches BENCHMARK_* in lib/library/value-benchmark.ts.
	session: { input: 500, output: 100, cacheRead: 2000, cacheWrite: 0 },
	// One 300K-token prompt: past both the 200K and the OpenAI 272K thresholds.
	request: { input: 200, output: 8, cacheRead: 100, cacheWrite: 0 },
};

/** Same pricing rule as the app's CostCalculator: the whole request moves to the tier rates. */
export function priceTokenMix(model: CalcModel, mix: TokenMix, applyTier: boolean) {
	const tok = (thousands: number) => Math.max(0, thousands) * 1000;
	const prompt = tok(mix.input) + tok(mix.cacheRead) + tok(mix.cacheWrite);
	const tier =
		applyTier && model.tier && prompt > model.tier.lastBaseTokens ? model.tier : undefined;
	const rates = tier ?? model;
	return {
		cost:
			tok(mix.input) * rates.input +
			tok(mix.output) * rates.output +
			tok(mix.cacheRead) * rates.cacheRead +
			tok(mix.cacheWrite) * rates.cacheWrite,
		tiered: tier !== undefined,
	};
}
