import {
	type AdminEmailContent,
	type AdminListItem,
	type AdminRow,
	type AdminSection,
	adminEmailPlainText,
} from "@/emails/admin-email-content";
import { AdminEmail } from "@/emails/admin-email-shell";
import { formatEmailTimestamp } from "@/emails/format-timestamp";
import type {
	GrowthCountRow,
	GrowthDigest,
	GrowthLegStatus,
	GrowthMetricGroup,
} from "@/lib/analytics/growth-digest";
import { OWNER_VALUE } from "@/lib/email/owner-vocabulary";

type GrowthDigestEmailProps = {
	rollup: GrowthDigest;
};

const SITE_ORIGIN = "https://jpthecat.com";
const RANKED_LIMIT = 5;

const STATUS_LABEL: Record<GrowthLegStatus, string> = {
	error: OWNER_VALUE.failed,
	ok: OWNER_VALUE.connected,
	skipped: OWNER_VALUE.notConfigured,
};

function counted(value: number, unit: string): string {
	return `${value.toLocaleString("en-US")} ${unit}${value === 1 ? "" : "s"}`;
}

function formatNullable(value: number | null) {
	return value === null ? OWNER_VALUE.notAvailable : value.toLocaleString("en-US");
}

/** A ranked list as numbered items under its label; an empty list says so in words. */
function rankedRow(label: string, items: AdminListItem[]): AdminRow {
	return { items: items.slice(0, RANKED_LIMIT), label, value: OWNER_VALUE.noneInWindow };
}

function countItems(rows: GrowthCountRow[], unit: string): AdminListItem[] {
	return rows.map((row) => ({ detail: counted(row.count, unit), text: row.label.trim() }));
}

function versionItems(rows: GrowthCountRow[]): AdminListItem[] {
	return countItems(rows, "download").map((item) =>
		item.text === OWNER_VALUE.unknown ? item : { ...item, text: `v${item.text}` },
	);
}

/** A JPtheCat.com path links to the live page. */
function pageItems(rows: GrowthCountRow[]): AdminListItem[] {
	return countItems(rows, "view").map((item) =>
		item.text.startsWith("/") ? { ...item, href: `${SITE_ORIGIN}${item.text}` } : item,
	);
}

function searchPageItems(rows: GrowthDigest["searchConsole"]["topPages"]): AdminListItem[] {
	return rows.map((row) => {
		const href = row.label.startsWith("https://") ? row.label : undefined;
		return {
			detail: `${counted(row.clicks, "click")} · ${counted(row.impressions, "impression")} · position ${row.position.toFixed(1)}`,
			href,
			text: href ? href.replace(/^https:\/\/[^/]+/, "") || "/" : row.label,
		};
	});
}

function queryItems(rows: GrowthDigest["searchConsole"]["topQueries"]): AdminListItem[] {
	return rows.map((row) => ({
		detail: `${counted(row.clicks, "click")} · ${counted(row.impressions, "impression")}`,
		text: row.query,
	}));
}

function legStatus(status: GrowthLegStatus, message: string | undefined) {
	return message ? `${STATUS_LABEL[status]} (${message})` : STATUS_LABEL[status];
}

function metricRows(rollup: GrowthDigest, group: GrowthMetricGroup): AdminRow[] {
	return rollup.metricCards
		.filter((metric) => metric.group === group)
		.map((metric) => ({
			label: metric.label,
			value: metric.detail ? `${metric.value} (${metric.detail})` : metric.value,
		}));
}

function healthSection(rollup: GrowthDigest): AdminSection {
	return {
		title: "Health",
		rows: [
			{
				label: "Vercel Web Analytics",
				value: legStatus(rollup.vercel.status, rollup.vercel.message),
			},
			{
				label: "Search Console",
				value: legStatus(rollup.searchConsole.status, rollup.searchConsole.message),
			},
			...metricRows(rollup, "health"),
		],
	};
}

function downloadsSection(rollup: GrowthDigest): AdminSection {
	return {
		title: "Downloads",
		rows: [
			...metricRows(rollup, "downloads"),
			rankedRow("By source", countItems(rollup.bySource, "download")),
			rankedRow("By version", versionItems(rollup.byVersion)),
			rankedRow("By location", countItems(rollup.byLocation, "download")),
			rankedRow("Top bot UAs", countItems(rollup.botUserAgents, "hit")),
		],
	};
}

function trafficRows(vercel: GrowthDigest["vercel"]): AdminRow[] {
	return [
		{
			label: "Page views / visitors",
			value: `${formatNullable(vercel.pageViews)} / ${formatNullable(vercel.visitors)}`,
		},
		{ label: "Download CTA clicks", value: formatNullable(vercel.downloadCtaClicks) },
		{ label: "Library CTA clicks", value: formatNullable(vercel.libraryDownloadCtaClicks) },
		rankedRow("Top pages", pageItems(vercel.topPages)),
		rankedRow("Top referrers", countItems(vercel.topReferrers, "view")),
		rankedRow("Top countries", countItems(vercel.topCountries, "view")),
	];
}

function trafficSection(rollup: GrowthDigest): AdminSection {
	return {
		title: "Traffic (Vercel Web Analytics)",
		rows: rollup.vercel.status === "ok" ? trafficRows(rollup.vercel) : [],
	};
}

function searchRows(search: GrowthDigest["searchConsole"]): AdminRow[] {
	return [
		{ label: "Clicks", value: formatNullable(search.clicks) },
		{ label: "Impressions", value: formatNullable(search.impressions) },
		{
			label: "Avg position",
			value: search.position === null ? OWNER_VALUE.noneInWindow : search.position.toFixed(1),
		},
		rankedRow("Top queries", queryItems(search.topQueries)),
		rankedRow("Top pages", searchPageItems(search.topPages)),
		rankedRow("Top countries", countItems(search.topCountries, "impression")),
	];
}

function searchSection(rollup: GrowthDigest): AdminSection {
	return {
		title: "Search (Search Console)",
		rows: rollup.searchConsole.status === "ok" ? searchRows(rollup.searchConsole) : [],
	};
}

function trendSections(rollup: GrowthDigest): AdminSection[] {
	return rollup.trends.map((trend) => ({
		title: trend.label,
		rows: trend.metricCards.map((metric) => ({
			label: metric.label,
			value: metric.detail ? `${metric.value} (${metric.detail})` : metric.value,
		})),
	}));
}

function growthContent(rollup: GrowthDigest): AdminEmailContent {
	return {
		issues: rollup.issues,
		lede: `The ${rollup.windowLabel}, generated ${formatEmailTimestamp(rollup.generatedAt)}. Human downloads exclude bot hits.`,
		preview: rollup.preview,
		sections: [
			healthSection(rollup),
			downloadsSection(rollup),
			trafficSection(rollup),
			searchSection(rollup),
			...trendSections(rollup),
			{ title: "Signals", rows: rollup.opportunities.map((value) => ({ value })) },
		],
		title: rollup.title,
	};
}

export function GrowthDigestEmail({ rollup }: GrowthDigestEmailProps) {
	return <AdminEmail content={growthContent(rollup)} />;
}

export function GrowthDigestPlainText({ rollup }: GrowthDigestEmailProps): string {
	return adminEmailPlainText(growthContent(rollup));
}
