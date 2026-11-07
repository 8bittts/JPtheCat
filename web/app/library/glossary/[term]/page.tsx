import { glossaryBySlug, glossaryLeaf } from "@/lib/library/content/glossary";
import { definedTermNode } from "@/lib/library/json-ld";
import { createLibraryLeafRoute } from "@/lib/library/leaf-route";

const route = createLibraryLeafRoute({
	param: "term",
	basePath: "/library/glossary",
	resolve: glossaryBySlug,
	leaf: glossaryLeaf,
	eyebrow: "Glossary",
	crumbParent: { name: "Glossary", href: "/library/glossary" },
	crumbLeafName: (resolved) => resolved.term,
	extraJsonLd: (resolved, path) => [definedTermNode(path, resolved.term, resolved.short)],
	cta: () => ({
		heading: "See it in your real numbers",
		sub: "JP the Cat prices your actual local usage at the shipped rates — not an estimate.",
	}),
});

export const generateMetadata = route.generateMetadata;
export default route.Page;
