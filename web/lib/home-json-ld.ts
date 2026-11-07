import { SITE } from "@/lib/site";

type JsonLdNode = Record<string, unknown>;

const ORGANIZATION_ID = `${SITE.url}/#organization`;
const WEBSITE_ID = `${SITE.url}/#website`;

export function homeJsonLd(): JsonLdNode[] {
	return [
		{
			"@context": "https://schema.org",
			"@type": "Organization",
			"@id": ORGANIZATION_ID,
			name: SITE.name,
			url: SITE.url,
			logo: `${SITE.url}${SITE.logo}`,
			description: SITE.description,
			sameAs: [`https://x.com/${SITE.twitter.replace("@", "")}`],
		},
		{
			"@context": "https://schema.org",
			"@type": "WebSite",
			"@id": WEBSITE_ID,
			url: SITE.url,
			name: SITE.name,
			publisher: { "@id": ORGANIZATION_ID },
		},
		{
			"@context": "https://schema.org",
			"@type": "SoftwareApplication",
			"@id": `${SITE.url}/#app`,
			name: SITE.name,
			applicationCategory: "DeveloperApplication",
			operatingSystem: "macOS 14+",
			url: SITE.url,
			description: SITE.description,
			publisher: { "@id": ORGANIZATION_ID },
			isAccessibleForFree: true,
			offers: {
				"@type": "Offer",
				// JP is a free download.
				price: "0",
				priceCurrency: "USD",
				availability: "https://schema.org/InStock",
				url: `${SITE.url}/#download`,
			},
		},
	];
}

export function jsonLdText(nodes: JsonLdNode[]): string {
	return JSON.stringify(nodes)
		.replace(/&/g, "\\u0026")
		.replace(/</g, "\\u003c")
		.replace(/>/g, "\\u003e");
}
