import { providerLeaf } from "@/lib/library/content/provider";
import { isLibrarySlugEligible } from "@/lib/library/eligibility";
import { softwareApplicationNode } from "@/lib/library/json-ld";
import { createLibraryLeafRoute } from "@/lib/library/leaf-route";
import { providerBySlug } from "@/lib/library/provider-registry";

const route = createLibraryLeafRoute({
	param: "provider",
	basePath: "/library/track",
	resolve: (slug) => (isLibrarySlugEligible("track", slug) ? providerBySlug(slug) : undefined),
	leaf: providerLeaf,
	eyebrow: (resolved) => (resolved.live ? "Tracked today" : "Roadmap"),
	crumbParent: { name: "Track usage", href: "/library/track" },
	crumbLeafName: (resolved) => resolved.name,
	robots: (resolved) =>
		resolved.live
			? { index: true, follow: true }
			: { index: false, follow: true, googleBot: { index: false, follow: true } },
	extraJsonLd: (resolved) => (resolved.live ? [softwareApplicationNode()] : []),
	cta: (resolved) =>
		resolved.live
			? {
					heading: `Track ${resolved.name} with JP the Cat`,
					sub: "Local usage with every dollar and limit labeled by its real or notional basis.",
				}
			: undefined,
});

export const generateMetadata = route.generateMetadata;
export default route.Page;
