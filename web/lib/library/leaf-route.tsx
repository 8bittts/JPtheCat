import type { Metadata } from "next";
import { notFound } from "next/navigation";
import type { ReactNode } from "react";
import { LeafBody } from "@/components/library/leaf-body";
import { LibraryShell } from "@/components/library/library-shell";
import type { LeafContent } from "@/lib/library/content/shared";
import { leafJsonLd, libraryCrumbs } from "@/lib/library/json-ld";
import { libraryPageMetadata } from "@/lib/library/metadata";

// Every `/library/<section>/[slug]` leaf route repeated the exact same skeleton — resolve the slug,
// 404 on miss, build the leaf content, stamp metadata, and render `LibraryShell` > `LeafBody`. This
// factory captures that skeleton once; each route file supplies only the parts that actually vary
// (its resolver, content builder, crumb + eyebrow labels, and any family-specific lead/CTA/JSON-LD).

type LeafRouteConfig<T> = {
	/** The dynamic segment name (e.g. `"tool"`, `"model"`). */
	param: string;
	/** The section base, e.g. `/library/alternatives`; the leaf path is `${basePath}/${slug}`. */
	basePath: `/library${string}`;
	/** Resolve the slug to a domain object, or `undefined` for a 404 / empty metadata. */
	resolve: (slug: string) => T | undefined;
	/** Build the uniform leaf content from the resolved object. */
	leaf: (resolved: T) => LeafContent;
	/** The section eyebrow — a constant, or derived from the resolved object (e.g. live vs roadmap). */
	eyebrow: string | ((resolved: T) => string);
	/** The parent breadcrumb (its `href` is NOT always `basePath`, e.g. vendor pages nest under pricing). */
	crumbParent: { name: string; href: string };
	/** The leaf breadcrumb label — from the resolved object and/or its built content. */
	crumbLeafName: (resolved: T, content: LeafContent) => string;
	/** Widen the shell for table-heavy families (alternatives / comparisons / vendor pricing). */
	wide?: boolean;
	/** Extra schema.org nodes appended to the leaf graph (e.g. DefinedTerm, SoftwareApplication). */
	extraJsonLd?: (resolved: T, path: string) => Record<string, unknown>[];
	/** A family-specific lead rendered above the body (pricing table, comparison table, calculator…). */
	children?: (resolved: T, slug: string) => ReactNode;
	/** An optional family CTA block; may itself depend on the resolved object. */
	cta?: (resolved: T) => { heading: string; sub?: string } | undefined;
	/** Optional page-level robots override for useful routes that are not yet search-grade. */
	robots?: (resolved: T) => Metadata["robots"];
};

type RouteParams = { params: Promise<Record<string, string>> };

export function createLibraryLeafRoute<T>(config: LeafRouteConfig<T>) {
	const pathFor = (slug: string): `/library${string}` => `${config.basePath}/${slug}`;

	async function generateMetadata({ params }: RouteParams): Promise<Metadata> {
		const slug = (await params)[config.param];
		const resolved = config.resolve(slug);
		if (!resolved) {
			return {};
		}
		const content = config.leaf(resolved);
		const metadata = libraryPageMetadata({
			title: content.title,
			description: content.description,
			path: pathFor(slug),
		});
		const robots = config.robots?.(resolved);
		return robots ? { ...metadata, robots } : metadata;
	}

	// biome-ignore lint/correctness/noComponentHookFactories: each route module calls this factory once at module scope to export its Page
	async function Page({ params }: RouteParams) {
		const slug = (await params)[config.param];
		const resolved = config.resolve(slug);
		if (!resolved) {
			notFound();
		}
		const content = config.leaf(resolved);
		const path = pathFor(slug);
		const crumbs = libraryCrumbs([
			config.crumbParent,
			{ name: config.crumbLeafName(resolved, content), href: path },
		]);
		const eyebrow =
			typeof config.eyebrow === "function" ? config.eyebrow(resolved) : config.eyebrow;
		const extra = config.extraJsonLd?.(resolved, path) ?? [];
		return (
			<LibraryShell
				title={content.title}
				lede={content.lede}
				eyebrow={eyebrow}
				crumbs={crumbs}
				jsonLd={leafJsonLd(crumbs, path, content.title, content.description, extra)}
				wide={config.wide}
			>
				<LeafBody content={content} cta={config.cta?.(resolved)}>
					{config.children?.(resolved, slug)}
				</LeafBody>
			</LibraryShell>
		);
	}

	return { generateMetadata, Page };
}
