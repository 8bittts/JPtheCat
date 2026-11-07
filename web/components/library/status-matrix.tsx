import Link from "next/link";
import { eligibleProviderSlugs, PROVIDER_SLUG } from "@/lib/library/provider-registry";
import { PROVIDERS } from "@/lib/site";

const GROUPS = [
	{ status: "live", label: "Live — tracked today" },
	{ status: "local-roadmap", label: "Local next" },
	{ status: "connect-roadmap", label: "Connect later" },
	{ status: "api-roadmap", label: "API later" },
	{ status: "candidate-roadmap", label: "Candidate" },
] as const;

/** The 65-provider status matrix IS the content of the track hub (_docs/08-growth.md SEO guardrails) — impossible to
 * over-claim: eligible providers link to their page, the rest are shown with their roadmap status. */
export function StatusMatrix() {
	const eligible = new Set(eligibleProviderSlugs());
	return (
		<div className="mt-10 flex flex-col gap-8">
			{GROUPS.map((group) => {
				const providers = PROVIDERS.filter((provider) => provider.status === group.status);
				if (providers.length === 0) {
					return null;
				}
				return (
					<section key={group.status}>
						<h2 className="sb-section-title mb-3">
							{group.label}{" "}
							<span className="sb-body font-normal opacity-70">({providers.length})</span>
						</h2>
						<ul className="flex flex-wrap gap-2">
							{providers.map((provider) => {
								const slug = PROVIDER_SLUG[provider.id];
								return (
									<li key={provider.id}>
										{eligible.has(slug) ? (
											<Link href={`/library/track/${slug}`} className="sb-pill">
												{provider.name}
											</Link>
										) : (
											<span className="sb-pill opacity-70">{provider.name}</span>
										)}
									</li>
								);
							})}
						</ul>
					</section>
				);
			})}
		</div>
	);
}
