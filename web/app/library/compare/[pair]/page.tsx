import { ComparisonTable } from "@/components/library/comparison-table";
import {
	compareBySlug,
	compareLeaf,
	comparePairTitle,
	compareTable,
} from "@/lib/library/content/compare";
import { createLibraryLeafRoute } from "@/lib/library/leaf-route";

const route = createLibraryLeafRoute({
	param: "pair",
	basePath: "/library/compare",
	resolve: compareBySlug,
	leaf: compareLeaf,
	eyebrow: "Comparison",
	crumbParent: { name: "Comparisons", href: "/library/compare" },
	crumbLeafName: (resolved) => comparePairTitle(resolved),
	wide: true,
	children: (resolved) => <ComparisonTable {...compareTable(resolved)} />,
	cta: () => ({
		heading: "Track your real cost with JP the Cat",
		sub: "A live menu-bar total, priced to the cent from your local logs — official limits, honest notional labels.",
	}),
});

export const generateMetadata = route.generateMetadata;
export default route.Page;
