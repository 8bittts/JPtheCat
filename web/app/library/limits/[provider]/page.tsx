import { limitLeaf } from "@/lib/library/content/limits";
import { isLibrarySlugEligible } from "@/lib/library/eligibility";
import { createLibraryLeafRoute } from "@/lib/library/leaf-route";
import { providerBySlug } from "@/lib/library/provider-registry";

const route = createLibraryLeafRoute({
	param: "provider",
	basePath: "/library/limits",
	resolve: (slug) => (isLibrarySlugEligible("limits", slug) ? providerBySlug(slug) : undefined),
	leaf: limitLeaf,
	eyebrow: "Usage limits",
	crumbParent: { name: "Usage limits", href: "/library/limits" },
	crumbLeafName: (resolved) => resolved.name,
});

export const generateMetadata = route.generateMetadata;
export default route.Page;
