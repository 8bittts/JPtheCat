import { planBySlug, planLeaf } from "@/lib/library/content/plans";
import { createLibraryLeafRoute } from "@/lib/library/leaf-route";

const route = createLibraryLeafRoute({
	param: "plan",
	basePath: "/library/plans",
	resolve: planBySlug,
	leaf: planLeaf,
	eyebrow: "Subscription plans",
	crumbParent: { name: "Plans", href: "/library/plans" },
	crumbLeafName: (resolved) => resolved.displayName,
	cta: (resolved) => ({
		heading: `Track your ${resolved.displayName} usage with JP the Cat`,
		sub: "Real Claude Code usage against this plan, from your local logs — official percentages, not estimates.",
	}),
});

export const generateMetadata = route.generateMetadata;
export default route.Page;
