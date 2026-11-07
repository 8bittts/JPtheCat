import { VendorModelsTable } from "@/components/library/vendor-models-table";
import { vendorBySlug, vendorLeaf } from "@/lib/library/content/vendor";
import { createLibraryLeafRoute } from "@/lib/library/leaf-route";

const route = createLibraryLeafRoute({
	param: "vendor",
	basePath: "/library/pricing/family",
	resolve: vendorBySlug,
	leaf: vendorLeaf,
	eyebrow: "Vendor pricing",
	// Vendor pages nest under Model pricing, so the parent crumb is the pricing hub (not basePath).
	crumbParent: { name: "Model pricing", href: "/library/pricing" },
	crumbLeafName: (_resolved, content) => content.title,
	wide: true,
	children: (resolved) => <VendorModelsTable vendor={resolved} />,
	cta: () => ({
		heading: "Track your real cost with JP the Cat",
		sub: "A live menu-bar total, priced to the cent from your local logs — including the cache-write split most tools miss.",
	}),
});

export const generateMetadata = route.generateMetadata;
export default route.Page;
