import { describe, expect, it } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import {
	ADMIN_EMAIL_ISSUES_LABEL,
	ADMIN_EMAIL_PLAIN_TEXT_FOOTER,
	adminEmailPlainText,
} from "@/emails/admin-email-content";
import { AdminEmail } from "@/emails/admin-email-shell";
import { EMAIL_FOOTER_DOMAIN_DISPLAY } from "@/emails/email-footer";
import { emailColors } from "@/emails/email-styles";
import { GrowthDigestEmail } from "@/emails/growth-digest";
import { SupportReportEmail, SupportReportPlainText } from "@/emails/support-report";
import { buildGrowthDigest } from "@/lib/analytics/growth-digest";

const SUPPORT_EVENT = {
	appVersion: "1.137",
	contactEmail: "user@example.com",
	message: "The Codex gauge stopped updating.",
	receivedAtIso: "2026-10-20T19:00:00.000Z",
	report: "JP the Cat 1.137\nProviders: codex=stale",
};

function adminEmails(): Record<string, string> {
	const rollup = buildGrowthDigest(
		{
			botUserAgents: [],
			byLocation: [],
			bySource: [],
			byVersion: [],
			generatedAt: "2026-10-20T14:00:00.000Z",
			headline: {
				allHits: 0,
				botUaHits: 0,
				humanDownloads: 0,
				macHumanDownloads: 0,
				networkFlaggable: 0,
				networkFlagged: 0,
				uniqueHumanIps: 0,
			},
			macRolling: { current: 0, deltaPct: null, prior: 0 },
			rolling: { current: 0, deltaPct: null, prior: 0 },
			searchConsole: {
				clicks: null,
				impressions: null,
				position: null,
				status: "skipped",
				topCountries: [],
				topPages: [],
				topQueries: [],
			},
			vercel: {
				downloadCtaClicks: null,
				libraryDownloadCtaClicks: null,
				pageViews: null,
				status: "skipped",
				topCountries: [],
				topPages: [],
				topReferrers: [],
				visitors: null,
			},
			windowDays: 1,
		},
		"daily",
	);
	return {
		growth: renderToStaticMarkup(<GrowthDigestEmail rollup={rollup} />),
		support: renderToStaticMarkup(<SupportReportEmail event={SUPPORT_EVENT} />),
	};
}

describe("admin email shell", () => {
	it("renders every owner notice on one shared shell and token set", () => {
		const emails = adminEmails();
		expect(Object.keys(emails)).toHaveLength(2);
		for (const [name, html] of Object.entries(emails)) {
			// Same canvas, masthead, heading role, and footer in every admin email.
			expect(html, name).toContain("max-width:640px");
			expect(html, name).toContain("https://jpthecat.com/jpthecat-logo.png");
			expect(html, name).toContain(">JP the Cat</p>");
			expect(html, name).toContain(`>${EMAIL_FOOTER_DOMAIN_DISPLAY}</a>`);
			expect(html, name).toContain("JP the Cat owner notice");
			expect(html, name).toContain(`background-color:${emailColors.paper}`);
			// Gmail iOS dark mode force-lightens near-black inline headline text; only rust survives.
			const heading = html.match(/<h1[^>]*>/i)?.[0] ?? "";
			expect(heading, name).toContain(emailColors.gingerDeep);
			expect(heading, name).not.toContain(emailColors.ink);
			expect(html, name).toContain("prefers-color-scheme: dark");
			// Never the customer shell's oversized hero, and never mascot gold as UI.
			expect(html, name).not.toContain("font-size:52px");
			expect(html, name).not.toContain("jp-hero");
			expect(html.toLowerCase(), name).not.toContain("#fdcd2d");
			// Gmail clips HTML past 102KB; spartan mail stays far under it.
			expect(html.length, name).toBeLessThan(40_000);
			// One vocabulary for absent values (lib/email/owner-vocabulary.ts): never an ambiguous
			// "Skipped", a bare dash, or "none yet".
			for (const vague of ["Skipped", "skipped", ">—<", ": —", "none yet", "Not checked"]) {
				expect(html, `${name}: ${vague}`).not.toContain(vague);
			}
		}
		// One text style for every value: the mono face marks only the uppercase section labels.
		for (const [name, html] of Object.entries(emails)) {
			for (const tag of html.match(/<[a-z0-9]+[^>]*JetBrains Mono[^>]*>/g) ?? []) {
				expect(tag, name).toContain("text-transform:uppercase");
			}
		}
		// The all-skipped digest names each leg's state in plain words.
		expect(emails.growth).toContain("Vercel Web Analytics: </strong>not configured");
		expect(emails.growth).not.toContain("Webhook health");
	});

	it("puts the issue block above the heading and in coral, or omits it", () => {
		const html = renderToStaticMarkup(
			<AdminEmail
				content={{
					issues: ["Webhook failed."],
					lede: "Lede.",
					preview: "Preview",
					sections: [{ rows: [{ label: "Row", value: "1" }], title: "Section" }],
					title: "Title",
				}}
			/>,
		);
		expect(html.indexOf(ADMIN_EMAIL_ISSUES_LABEL)).toBeLessThan(html.indexOf("<h1"));
		expect(html.indexOf("<h1")).toBeLessThan(html.indexOf(">Section<"));
		expect(html).toContain(`background-color:${emailColors.coralWash}`);
		expect(html).toContain(`color:${emailColors.coral}`);
		// The dark-mode CSS pins the issue surface so a darkening client cannot wash it out.
		expect(html).toContain(`.jp-issues { background-color: ${emailColors.coralWash} !important; }`);

		const clean = renderToStaticMarkup(
			<AdminEmail
				content={{ issues: [], lede: "Lede.", preview: "P", sections: [], title: "Title" }}
			/>,
		);
		expect(clean).not.toContain(ADMIN_EMAIL_ISSUES_LABEL);
		expect(clean).not.toContain('class="jp-issues"');
	});

	it("drops null rows and empty sections in both the HTML and plain text", () => {
		const content = {
			issues: [],
			lede: "Lede.",
			preview: "P",
			sections: [
				{
					rows: [
						{ label: "Kept", value: "yes" },
						{ label: "Dropped", value: null },
						{ label: "Blank", value: "" },
					],
					title: "Shown",
				},
				{ rows: [{ label: "Gone", value: null }], title: "Empty" },
				{ block: null, title: "No block" },
			],
			title: "Title",
		};
		const html = renderToStaticMarkup(<AdminEmail content={content} />);
		const text = adminEmailPlainText(content);
		for (const output of [html, text]) {
			expect(output).toContain("Kept");
			expect(output).not.toContain("Dropped");
			expect(output).not.toContain("Blank");
			expect(output.toLowerCase()).not.toContain("empty");
			expect(output.toLowerCase()).not.toContain("no block");
		}
		expect(text).toBe(
			["Title", "Lede.", "", "SHOWN", "Kept: yes", "", ADMIN_EMAIL_PLAIN_TEXT_FOOTER].join("\n"),
		);
	});

	it("treats every support report as an issue and keeps the user note before the app report", () => {
		const html = renderToStaticMarkup(<SupportReportEmail event={SUPPORT_EVENT} />);
		expect(html.indexOf(ADMIN_EMAIL_ISSUES_LABEL)).toBeLessThan(html.indexOf("<h1"));
		expect(html).toContain("Reply to user@example.com.");
		expect(html.indexOf(">User note<")).toBeLessThan(html.indexOf(">Contact<"));
		expect(html.indexOf(">Contact<")).toBeLessThan(html.indexOf(">App report<"));
		expect(html).toContain("white-space:pre-wrap");

		const anonymous = SupportReportPlainText({
			event: { ...SUPPORT_EVENT, contactEmail: null, message: null },
		});
		expect(anonymous).toContain("- A user asked for help but left no reply email.");
		expect(anonymous).toContain("Reply email: not provided");
		expect(anonymous).not.toContain("USER NOTE");
		expect(anonymous).toContain("APP REPORT\nJP the Cat 1.137\nProviders: codex=stale");
	});
});
