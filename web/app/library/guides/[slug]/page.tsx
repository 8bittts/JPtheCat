import { guideBySlug, guideLeaf } from "@/lib/library/content/guides";
import { createLibraryLeafRoute } from "@/lib/library/leaf-route";

const route = createLibraryLeafRoute({
	param: "slug",
	basePath: "/library/guides",
	resolve: guideBySlug,
	leaf: guideLeaf,
	eyebrow: "Guide",
	crumbParent: { name: "Guides", href: "/library/guides" },
	crumbLeafName: (resolved) => resolved.title,
	cta: () => ({
		heading: "See your real numbers with JP the Cat",
		sub: "A light, local menu-bar meter for Claude Code, Codex, Grok, Muse Spark, OpenCode Zen, and OpenCode Go — real cost, honest limits.",
	}),
});

export const generateMetadata = route.generateMetadata;
export default route.Page;
