import { Calculator } from "@/components/library/calculator";
import {
	calculatorBySlug,
	calculatorLeaf,
	calculatorMode,
	calculatorModels,
} from "@/lib/library/content/calculators";
import { createLibraryLeafRoute } from "@/lib/library/leaf-route";

const route = createLibraryLeafRoute({
	param: "calc",
	basePath: "/library/calculators",
	resolve: calculatorBySlug,
	leaf: calculatorLeaf,
	eyebrow: "Calculator",
	crumbParent: { name: "Calculators", href: "/library/calculators" },
	crumbLeafName: (resolved) => resolved.title,
	children: (resolved) => (
		<Calculator
			models={calculatorModels(resolved)}
			notional={resolved.notional}
			mode={calculatorMode(resolved)}
		/>
	),
	cta: () => ({
		heading: "Track your real cost with JP the Cat",
		sub: "A live menu-bar total, priced to the cent from your local logs — including the cache-write split most tools miss.",
	}),
});

export const generateMetadata = route.generateMetadata;
export default route.Page;
