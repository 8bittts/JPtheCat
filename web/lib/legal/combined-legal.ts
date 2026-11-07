import { SITE } from "@/lib/site";

export const POLICY_SECTIONS = [
	{
		id: "local-usage-records",
		title: "Local usage records",
		body: `${SITE.name} reads local session logs and usage files written by supported AI coding tools. The app uses that local data to calculate usage, cost, and official or estimated plan-window percentages on your Mac. It never reads Claude Code's stored credentials or asks for your macOS password to label a plan.`,
	},
	{
		id: "no-cloud-for-your-work",
		title: "No JP cloud for your work",
		body: `There is no ${SITE.name} cloud sync account for usage data. Prompts, code, transcripts, token history, computed costs, local usage database contents, and provider credentials are not uploaded to JP.`,
	},
	{
		id: "website-telemetry",
		title: "Website telemetry",
		body: "This website uses Vercel Web Analytics and Speed Insights for aggregate page traffic, download and repository link click events, and performance telemetry. Website telemetry does not include prompts, code, transcripts, token history, computed costs, provider credentials, or local usage database contents from the Mac app.",
	},
	{
		id: "downloads-and-updates",
		title: "Downloads and updates",
		body: "The public DMG, update feed, and release files may be served through Vercel and the Supabase-backed api.jpthecat.com release host. Successful non-bot downloads may send an owner notification through Resend or another email provider with the release filename, download source, referrer, user agent, timestamp, and coarse Vercel edge location context (city, region, country, and timezone; no postal code is kept, and never latitude/longitude). Download redirects are also stored in an INSERT-only Supabase table for aggregate growth review, including your IP address (kept to detect automated and same-network burst downloads), approximate geo fields, network/ASN and hosting/anonymizer signals, and bot rows so bot pressure can be measured. For network intelligence, JP may send the download IP address to ipapi.is to identify the network operator and whether the address appears to be hosting, VPN, proxy, or other anonymous infrastructure. JP does not collect email addresses on download and sends no newsletter. To prevent abuse, support and download requests are rate-limited using a short-lived record of your IP address. Sparkle update checks may request the update feed and release files. The app makes no license, trial, or purchase calls: it is free and does not identify your Mac to JP's servers. No raw hardware identifiers (serial number or platform UUID) ever leave your Mac. Update checks do not include prompts, code, transcripts, token history, computed costs, provider credentials, or local usage database contents. If you turn on Grok plan usage in Live data (off by default), the app uses the sign-in Cursor or Grok Bot already saved on your Mac and sends only that bearer token to api2.cursor.sh to fetch official weekly and billing-cycle percentages. It never uses refresh tokens and never sends prompts, code, transcripts, local usage, or paths. One shared five-minute cadence covers the unified Grok view. Turning it off stops the calls and deletes unified and legacy saved plan readings. Local Grok Build and optional Cursor stop-hook activity stay on your Mac.",
	},
	{
		id: "support",
		title: "Support",
		body: "Support requests and the optional redacted support report from the app go to JP by email. Support records may include the email address you use to contact us, the app and macOS versions you share, and the messages you send. JP does not sell anything, so there is no checkout and no payment data.",
	},
	{
		id: "ai-providers-are-separate",
		title: "AI providers are separate",
		body: `${SITE.name} is not affiliated with Anthropic, OpenAI, Google, GitHub, Cursor, or other listed AI providers. Their products, APIs, invoices, websites, and privacy policies are separate from JP.`,
	},
	{
		id: "your-choices",
		title: "Your choices",
		body: "You can stop using the app, delete local app data, remove the app, or contact us about any records we hold. Mac app product analytics are off by default. If opt-in diagnostics or crash reporting ship later, the control will be clearly labeled and will not include prompts, code, transcripts, or token history.",
	},
	{
		id: "children",
		title: "Children",
		body: `${SITE.name} is a developer tool and is not directed to children under 13. We do not knowingly collect children's personal information.`,
	},
] as const;

export const THIRD_PARTIES = [
	["Vercel", "Website hosting, Web Analytics, Speed Insights, security, and operations."],
	["Supabase", "Release downloads, update hosting, and download-growth rows on api.jpthecat.com."],
	[
		"Sparkle",
		"The macOS update framework that checks the public update feed and downloads app updates.",
	],
	[
		"Resend or email provider",
		"Owner download notifications and support email if transactional mail is enabled.",
	],
	[
		"ipapi.is",
		"Download-network intelligence: ASN/network operator plus hosting, VPN, proxy, or anonymizer signals for owner review.",
	],
] as const;

export const TERMS_CLAUSES = [
	{
		id: "free-to-use",
		title: "Free to use",
		body: `${SITE.name} is free. You may download it and run it on as many of your own Macs as you like, including updates. There is no account, license key, trial, or payment.`,
	},
	{
		id: "earlier-purchases",
		title: "Earlier purchases",
		body: `Before ${SITE.name} became free it was sold as a paid license. The app no longer checks licenses, so every feature is available to everyone, including earlier buyers. Questions about an earlier purchase go through the contact page.`,
	},
	{
		id: "what-jp-provides",
		title: "What JP provides",
		body: `${SITE.name} estimates AI usage and cost from logs on your machine. We work hard to be accurate, but figures are provided as estimates for your convenience and may differ from a provider's official billing. Always treat your provider's invoice as the source of truth.`,
	},
	{
		id: "fair-use",
		title: "Fair use",
		body: "Do not resell, rent, or host the app as a paid service, tamper with the update system, interfere with the website, or use the app in a way that violates the rules of your AI provider or applicable law.",
	},
	{
		id: "third-party-providers",
		title: "Third-party providers",
		body: `${SITE.name} is independent from Anthropic, OpenAI, Google, GitHub, Cursor, and every other listed AI provider. Provider names are used only to identify the local usage data the app can interpret or plans to interpret. You are responsible for your provider accounts, invoices, API usage, and provider terms.`,
	},
	{
		id: "updates-and-availability",
		title: "Updates and availability",
		body: "We may change features, provider support, website copy, or download availability.",
	},
	{
		id: "no-warranty",
		title: "No warranty",
		body: "The app and website are provided as-is. We do not promise that every provider file will be parseable, that estimates will match invoices exactly, or that the app will be free of bugs or interruptions.",
	},
	{
		id: "liability-limit",
		title: "Liability limit",
		body: `To the maximum extent allowed by law, ${SITE.name}'s liability is limited to the amount you paid for the app, which is nothing for the free app. We are not liable for lost profits, lost data, business interruption, provider charges, or indirect damages.`,
	},
	{
		id: "changes",
		title: "Changes",
		body: "If these terms change materially, we will update this page. Continuing to use the app or website after an update means you accept the revised terms.",
	},
] as const;

export const COMBINED_LEGAL_TOC = [
	{ id: "privacy-policy", title: "Privacy policy" },
	...POLICY_SECTIONS.map((section) => ({ id: section.id, title: section.title })),
	{ id: "third-party-processors", title: "Who may process what" },
	{ id: "privacy-contact", title: "Privacy contact" },
	{ id: "terms-of-service", title: "Terms of service" },
	...TERMS_CLAUSES.map((clause) => ({ id: clause.id, title: clause.title })),
] as const;
