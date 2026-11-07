import { createHash } from "node:crypto";
import { OWNER_VALUE } from "@/lib/email/owner-vocabulary";

export type GrowthDigestFrequency = "daily" | "weekly" | "monthly";
export type GrowthLegStatus = "ok" | "skipped" | "error";

export type GrowthCountRow = {
	label: string;
	count: number;
};

/** One open GitHub issue or pull request from someone other than the owner, ranked for triage. */
export type OpenSourcePriority = {
	kind: "issue" | "pull_request";
	number: number;
	title: string;
	author: string;
	url: string;
	reason: string;
	ageDays: number;
	/** Comments plus reactions. */
	engagement: number;
};

export type GrowthDigestSourceData = {
	generatedAt: string;
	windowDays: number;
	headline: {
		allHits: number;
		botUaHits: number;
		humanDownloads: number;
		/** `human` rows whose browser can open the DMG — the headline. */
		macHumanDownloads: number;
		/** Non-bot rows in the window whose ipapi.is lookup returned a hosting flag. */
		networkFlagged: number;
		/** Non-bot rows in the window; `networkFlagged < networkFlaggable` means the datacenter rule was blind. */
		networkFlaggable: number;
		uniqueHumanIps: number;
	};
	rolling: {
		current: number;
		prior: number;
		deltaPct: number | null;
	};
	macRolling: {
		current: number;
		prior: number;
		deltaPct: number | null;
	};
	bySource: GrowthCountRow[];
	byVersion: GrowthCountRow[];
	byLocation: GrowthCountRow[];
	botUserAgents: GrowthCountRow[];
	vercel: {
		status: GrowthLegStatus;
		downloadCtaClicks: number | null;
		libraryDownloadCtaClicks: number | null;
		pageViews: number | null;
		topCountries: GrowthCountRow[];
		topPages: GrowthCountRow[];
		topReferrers: GrowthCountRow[];
		visitors: number | null;
		repoLinkClicks: number | null;
		message?: string;
	};
	github: {
		status: GrowthLegStatus;
		stars: number | null;
		forks: number | null;
		openIssues: number | null;
		openPullRequests: number | null;
		newIssues: number | null;
		newPullRequests: number | null;
		mergedPullRequests: number | null;
		/** Distinct non-owner, non-bot people who opened or merged work in the window. */
		windowContributors: number | null;
		/** Distinct non-owner, non-bot commit authors on the default branch, all time. */
		codeContributors: number | null;
		priorities: OpenSourcePriority[];
		message?: string;
	};
	searchConsole: {
		status: GrowthLegStatus;
		clicks: number | null;
		impressions: number | null;
		position: number | null;
		topCountries: GrowthCountRow[];
		topPages: Array<{ clicks: number; impressions: number; label: string; position: number }>;
		topQueries: Array<{ query: string; clicks: number; impressions: number; position: number }>;
		message?: string;
	};
};

/** Which owner-digest section a metric belongs to. */
export type GrowthMetricGroup = "health" | "downloads";

type GrowthDigestMetric = {
	group: GrowthMetricGroup;
	label: string;
	value: string;
	/** A terse parenthetical; empty when the value says it all. */
	detail: string;
	status: "good" | "watch" | "attention";
};

/** A longer-window headline added to the daily report on Mondays (7 days) and the 1st (30 days). */
export type GrowthTrend = {
	label: string;
	metricCards: GrowthDigestMetric[];
};

export type GrowthDigest = {
	frequency: GrowthDigestFrequency;
	trends: GrowthTrend[];
	title: string;
	subject: string;
	preview: string;
	generatedAt: string;
	windowDays: number;
	windowLabel: string;
	metricCards: GrowthDigestMetric[];
	/** Problems the owner should see first: failed data legs and blind filters. */
	issues: string[];
	opportunities: string[];
	bySource: GrowthCountRow[];
	byVersion: GrowthCountRow[];
	byLocation: GrowthCountRow[];
	botUserAgents: GrowthCountRow[];
	vercel: GrowthDigestSourceData["vercel"];
	github: GrowthDigestSourceData["github"];
	searchConsole: GrowthDigestSourceData["searchConsole"];
};

const FREQUENCY_LABEL: Record<GrowthDigestFrequency, string> = {
	daily: "Daily",
	weekly: "Weekly",
	monthly: "Monthly",
};

const FREQUENCY_WINDOW_DAYS: Record<GrowthDigestFrequency, number> = {
	daily: 1,
	weekly: 7,
	monthly: 30,
};

const NUMBER_FORMAT = new Intl.NumberFormat("en-US");
function formatNumber(value: number | null): string {
	return value === null ? OWNER_VALUE.notAvailable : NUMBER_FORMAT.format(value);
}

function formatDelta(value: number | null): string {
	// Null means the prior window had none, so no percentage exists; say that rather than "0%".
	if (value === null) return "none in prior window";
	if (value === 0) return "flat";
	return `${value > 0 ? "+" : ""}${Number.isInteger(value) ? value : value.toFixed(1)}%`;
}

function metric(
	group: GrowthMetricGroup,
	label: string,
	value: string,
	detail: string,
	status: GrowthDigestMetric["status"] = "good",
): GrowthDigestMetric {
	return { group, label, value, detail, status };
}

/**
 * Fingerprints the digest body so a reused idempotency key always means an
 * identical send. Resend rejects a key that is reused with a modified body,
 * and the rollup moves whenever the underlying analytics do, so a
 * frequency+date key alone fails closed on any same-day re-run.
 */
export function growthDigestBodyFingerprint(rollup: GrowthDigest): string {
	return createHash("sha256").update(JSON.stringify(rollup)).digest("hex").slice(0, 24);
}

export function growthDigestIdempotencyKey(
	frequency: GrowthDigestFrequency,
	dateKey: string,
	bodyFingerprint: string,
): string {
	return `growth_digest:${frequency}:${dateKey}:${bodyFingerprint}`;
}

export function growthDigestWindowDays(frequency: GrowthDigestFrequency): number {
	return FREQUENCY_WINDOW_DAYS[frequency];
}

function buildOpportunities(data: GrowthDigestSourceData): string[] {
	const out: string[] = [];
	const botShare =
		data.headline.allHits > 0 ? (data.headline.botUaHits / data.headline.allHits) * 100 : 0;

	if (data.headline.humanDownloads === 0) {
		out.push(
			"No organic human downloads are visible yet; keep treating Search Console and off-site links as the next growth bottleneck.",
		);
	}
	if (botShare >= 50) {
		out.push(
			"Bot pressure is high; keep the owner email gate human-only and keep leading reports with human downloads, not raw hits.",
		);
	}
	if (
		data.vercel.status === "ok" &&
		(data.vercel.downloadCtaClicks ?? 0) + (data.vercel.libraryDownloadCtaClicks ?? 0) >
			data.headline.humanDownloads
	) {
		out.push(
			"CTA clicks are ahead of verified human downloads; compare modal completion, bot pressure, and release-host redirects before changing copy.",
		);
	}
	if (out.length === 0) {
		out.push("No major growth warning crossed the digest thresholds for this window.");
	}
	return out.slice(0, 4);
}

function pluralS(count: number | null): string {
	return count === 1 ? "" : "s";
}

const LEG_NAMES = {
	github: "GitHub",
	searchConsole: "Search Console",
	vercel: "Vercel Web Analytics",
} as const;

function legIssue(name: string, status: GrowthLegStatus, message: string | undefined) {
	return status === "error" ? [`${name} failed: ${message ?? "needs config"}.`] : [];
}

function buildIssues(data: GrowthDigestSourceData): string[] {
	const flaggable = data.headline.networkFlaggable;
	const unflagged = flaggable - data.headline.networkFlagged;
	return [
		...legIssue(LEG_NAMES.vercel, data.vercel.status, data.vercel.message),
		...legIssue(LEG_NAMES.github, data.github.status, data.github.message),
		...legIssue(LEG_NAMES.searchConsole, data.searchConsole.status, data.searchConsole.message),
		// The datacenter/VPN rule is only as good as the ipapi.is lookup behind it. The keyless free
		// tier stopped returning the flags on 2026-09-01 and the metric silently rose 36%; any gap in
		// coverage is a blind filter, so it leads the digest instead of hiding inside a bigger number.
		...(unflagged > 0
			? [
					`Datacenter filter blind: ${formatNumber(unflagged)} of ${formatNumber(flaggable)} non-bot download${pluralS(flaggable)} got no hosting flag from ipapi.is (set IPAPI_IS_KEY).`,
				]
			: []),
	];
}

function rollingDetail(rolling: GrowthDigestSourceData["rolling"]): string {
	const delta = formatDelta(rolling.deltaPct);
	return rolling.deltaPct === null ? delta : `${delta} vs prior ${formatNumber(rolling.prior)}`;
}

function headlineMetricCards(data: GrowthDigestSourceData) {
	const humanDownloads = data.headline.humanDownloads;
	const macDownloads = data.headline.macHumanDownloads;
	return [
		metric(
			"downloads",
			"Mac downloads",
			formatNumber(macDownloads),
			`macOS browsers only · ${rollingDetail(data.macRolling)}`,
			macDownloads > 0 ? "good" : "watch",
		),
		metric(
			"downloads",
			"Human downloads",
			formatNumber(humanDownloads),
			`all platforms · ${formatNumber(data.headline.allHits)} raw hits · ${rollingDetail(data.rolling)}`,
			humanDownloads > 0 ? "good" : "watch",
		),
		metric(
			"downloads",
			"Unique human IPs",
			formatNumber(data.headline.uniqueHumanIps),
			"after bot and burst filtering",
			data.headline.uniqueHumanIps > 0 ? "good" : "watch",
		),
		metric(
			"downloads",
			"Bot UA hits",
			formatNumber(data.headline.botUaHits),
			"kept out of human totals",
			data.headline.botUaHits > data.headline.humanDownloads ? "attention" : "watch",
		),
	];
}

function windowLabelFor(frequency: GrowthDigestFrequency): string {
	return frequency === "daily" ? "last 24 hours" : `last ${growthDigestWindowDays(frequency)} days`;
}

/** The headline cards only: a trend is a comparison, not a second copy of every section. */
export function buildGrowthTrend(
	data: GrowthDigestSourceData,
	frequency: GrowthDigestFrequency,
): GrowthTrend {
	return {
		label: `Trend: ${windowLabelFor(frequency)}`,
		metricCards: [...headlineMetricCards(data).slice(0, 3)],
	};
}

export function buildGrowthDigest(
	data: GrowthDigestSourceData,
	frequency: GrowthDigestFrequency,
	trends: GrowthTrend[] = [],
): GrowthDigest {
	const label = FREQUENCY_LABEL[frequency];
	const lowerLabel = label.toLowerCase();
	const windowLabel = windowLabelFor(frequency);
	const macDownloads = data.headline.macHumanDownloads;
	const rollingDelta = formatDelta(data.macRolling.deltaPct);
	const issues = buildIssues(data);
	const issueSuffix = issues.length ? ` · ${issues.length} issue${pluralS(issues.length)}` : "";
	const triage = data.github.priorities.length;
	const triageSuffix = triage ? ` · ${triage} open-source item${pluralS(triage)} to triage` : "";

	return {
		frequency,
		trends,
		title: `${label} JP the Cat report`,
		subject: `JP the Cat ${lowerLabel} report: ${formatNumber(macDownloads)} Mac download${pluralS(macDownloads)}${triageSuffix}${issueSuffix}`,
		preview: `${label} report: ${formatNumber(macDownloads)} Mac download${pluralS(macDownloads)}, ${rollingDelta} vs prior window.`,
		generatedAt: data.generatedAt,
		windowDays: data.windowDays,
		windowLabel,
		metricCards: headlineMetricCards(data),
		issues,
		opportunities: buildOpportunities(data),
		bySource: data.bySource,
		byVersion: data.byVersion,
		byLocation: data.byLocation,
		botUserAgents: data.botUserAgents,
		vercel: data.vercel,
		github: data.github,
		searchConsole: data.searchConsole,
	};
}
