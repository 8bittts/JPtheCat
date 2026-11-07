"use client";

import type { ComponentProps } from "react";
import {
	type RepoLinkPlacement,
	type RepoLinkTarget,
	trackRepoLink,
} from "@/lib/analytics/product-analytics";
import { SITE } from "@/lib/site";

const TARGET_HREF: Record<RepoLinkTarget, string> = {
	contributing: SITE.contributingUrl,
	repo: SITE.repoUrl,
};

type RepoLinkProps = Omit<ComponentProps<"a">, "href" | "onClick" | "rel" | "target"> & {
	placement: RepoLinkPlacement;
	target: RepoLinkTarget;
};

/** An outbound link to the public repository that the owner digest counts. */
export function RepoLink({ placement, target, ...props }: RepoLinkProps) {
	return (
		<a
			{...props}
			href={TARGET_HREF[target]}
			target="_blank"
			rel="noopener noreferrer"
			data-analytics-event="repo_link_clicked"
			onClick={() => trackRepoLink(placement, target)}
		/>
	);
}
