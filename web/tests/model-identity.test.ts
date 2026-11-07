import { describe, expect, it } from "bun:test";
import { MODEL_ID_ALIASES, MODEL_IDS, type ModelId } from "@/lib/library/pricing-data";
import { modelEffortLevel, pricing } from "@/lib/library/pricing-registry";
import {
	analyticsShortModel,
	modelKey,
	presentationModelId,
	shortModel,
	undecoratedModelId,
} from "@/lib/model-identity";
import fixture from "@/tests/fixtures/model-identity-cases.json";

// The app's `ModelIdentityTests` reads the same fixture, so the homepage demo, `/library`, and the
// native dashboard cannot label, group, or classify an emitted id differently.
describe("shared model identity", () => {
	it("matches the app on every shared fixture case", () => {
		expect(fixture.cases.length).toBeGreaterThan(20);
		for (const item of fixture.cases) {
			expect([item.model, presentationModelId(item.model)]).toEqual([
				item.model,
				item.presentation,
			]);
			expect([item.model, shortModel(item.model)]).toEqual([item.model, item.short]);
			expect([item.model, analyticsShortModel(item.model)]).toEqual([item.model, item.analytics]);
			expect([item.model, modelEffortLevel(item.model) ?? null]).toEqual([item.model, item.effort]);
		}
	});

	it("resolves decorators and aliases the way pricing does", () => {
		expect(undecoratedModelId("anthropic/claude-opus-4-8[1m]")).toBe("claude-opus-4-8");
		expect(undecoratedModelId("gpt-5.2-2025-12-11")).toBe("gpt-5.2");
		expect(modelKey("gpt-reserve")).toBe("gpt-5.6-luna");
		expect(modelKey("grok-4.7-build")).toBe("grok-4.7");
		expect(modelKey("grok-4.7-opencode")).toBe("grok-4.7");
		expect(modelKey("mimo-v2.5-free")).toBe("mimo-v2.5");
	});

	it("points every alias at a real pricing row, never at another alias or from a free tier", () => {
		const rows = new Set<string>(MODEL_IDS);
		for (const [alias, target] of Object.entries(MODEL_ID_ALIASES)) {
			expect([alias, rows.has(target)]).toEqual([alias, true]);
			expect([alias, rows.has(alias)]).toEqual([alias, false]);
			expect([alias, target in MODEL_ID_ALIASES]).toEqual([alias, false]);
			expect([alias, alias.endsWith("-free")]).toEqual([alias, false]);
		}
		expect(pricing(MODEL_ID_ALIASES["grok-4.6-build"] as ModelId).cache_read_input_token_cost).toBe(
			5e-7,
		);
	});

	it("gives a gateway route the same effort tier as the model it bills", () => {
		for (const id of MODEL_IDS) {
			const base = presentationModelId(id);
			if (base === id) continue;
			expect([id, modelEffortLevel(id)]).toEqual([id, modelEffortLevel(base)]);
		}
	});
});
