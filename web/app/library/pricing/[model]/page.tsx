import { PricingTable } from "@/components/library/pricing-table";
import { pricingLeaf } from "@/lib/library/content/pricing";
import { isLibrarySlugEligible } from "@/lib/library/eligibility";
import { createLibraryLeafRoute } from "@/lib/library/leaf-route";
import { MODEL_DISPLAY_NAME, MODEL_SLUG_TO_ID } from "@/lib/library/pricing-registry";

const route = createLibraryLeafRoute({
	param: "model",
	basePath: "/library/pricing",
	resolve: (slug) => (isLibrarySlugEligible("pricing", slug) ? MODEL_SLUG_TO_ID[slug] : undefined),
	leaf: pricingLeaf,
	eyebrow: "Model pricing",
	crumbParent: { name: "Model pricing", href: "/library/pricing" },
	crumbLeafName: (id) => MODEL_DISPLAY_NAME[id],
	cta: () => ({
		heading: "Track your real cost with JP the Cat",
		sub: "A live menu-bar total, priced to the cent from your local logs — including the cache-write split most tools miss.",
	}),
	children: (id) => <PricingTable id={id} />,
});

export const generateMetadata = route.generateMetadata;
export default route.Page;
