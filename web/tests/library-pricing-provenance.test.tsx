import { describe, expect, it } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { VendorModelsTable } from "@/components/library/vendor-models-table";
import { pricingHonestyNote, pricingLead, pricingLeaf } from "@/lib/library/content/pricing";
import { MODEL_IDS, type ModelPricing, PRICING_MODELS } from "@/lib/library/pricing-data";
import { pricingCaveat, UNVERIFIED_PRICING_IDS } from "@/lib/library/pricing-provenance";
import { modelVendor } from "@/lib/library/pricing-registry";

describe("public pricing provenance", () => {
	it("qualifies every retained unverified rate on its model and family page", () => {
		expect(UNVERIFIED_PRICING_IDS).toHaveLength(4);
		for (const id of UNVERIFIED_PRICING_IDS) {
			expect(pricingHonestyNote(id)).toContain("not verified");
			expect(pricingLead(id)).toContain("not verified");
			expect(pricingLeaf(id).description).toContain("historical unverified");
			expect(renderToStaticMarkup(VendorModelsTable({ vendor: modelVendor(id) }))).toContain(
				pricingCaveat(id) as string,
			);
		}
	});
	it("never invents a context surcharge or an absent cache discount", () => {
		for (const id of MODEL_IDS) {
			const p: ModelPricing = PRICING_MODELS[id];
			if (p.input_cost_per_token_above_200k_tokens === undefined)
				expect(pricingLead(id)).not.toContain("premium tier");
			expect(pricingLeaf(id).sections[0].body).not.toContain("roughly a tenth");
		}
	});
});
