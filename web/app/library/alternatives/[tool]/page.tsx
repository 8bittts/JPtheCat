import { AlternativesList } from "@/components/library/alternatives-list";
import {
	alternativeAnchor,
	alternativesFor,
	alternativesLeaf,
} from "@/lib/library/content/alternatives";
import { createLibraryLeafRoute } from "@/lib/library/leaf-route";

const route = createLibraryLeafRoute({
	param: "tool",
	basePath: "/library/alternatives",
	resolve: alternativeAnchor,
	leaf: alternativesLeaf,
	eyebrow: "Alternatives",
	crumbParent: { name: "Alternatives", href: "/library/alternatives" },
	crumbLeafName: (anchor) => `${anchor.name} alternatives`,
	wide: true,
	children: (_anchor, tool) => <AlternativesList tools={alternativesFor(tool)} />,
	cta: (anchor) => ({
		heading: `Try JP the Cat instead of ${anchor.name}`,
		sub: "Light-themed, honest-provenance menu-bar meter — real $ for Claude, official % where providers expose it.",
	}),
});

export const generateMetadata = route.generateMetadata;
export default route.Page;
