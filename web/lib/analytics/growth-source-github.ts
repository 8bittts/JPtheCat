import type { GrowthDigestSourceData, OpenSourcePriority } from "@/lib/analytics/growth-digest";
import { SITE } from "@/lib/site";
import type { EnvSource, Fetcher } from "./growth-digest-common";

const DAY_MS = 86_400_000;
const PRIORITY_LIMIT = 5;
const SECURITY_LABEL = /security|vulnerab/i;
const BUG_LABEL = /bug|crash|regression/i;

type GitHubUser = { login: string; type?: string };

type GitHubIssue = {
	number: number;
	title: string;
	html_url: string;
	user: GitHubUser | null;
	labels: Array<{ name?: string } | string>;
	created_at: string;
	comments: number;
	draft?: boolean;
	reactions?: { total_count?: number };
	pull_request?: { merged_at?: string | null };
};

type GitHubRepo = {
	stargazers_count: number;
	forks_count: number;
	owner: GitHubUser;
};

/** The public repository the site links to, as `owner/name`. */
function repositorySlug(): string {
	return new URL(SITE.repoUrl).pathname.replace(/^\/+|\/+$/g, "");
}

async function githubJson<T>(path: string, source: EnvSource, fetcher: Fetcher): Promise<T> {
	const headers: Record<string, string> = {
		accept: "application/vnd.github+json",
		"user-agent": "jpthecat-growth-digest",
		"x-github-api-version": "2022-11-28",
	};
	// Public data needs no token; one only lifts the shared-IP rate limit.
	const token = source.GITHUB_TOKEN?.trim();
	if (token) headers.authorization = `Bearer ${token}`;
	const response = await fetcher(`https://api.github.com/repos/${repositorySlug()}${path}`, {
		headers,
	});
	if (!response.ok) {
		throw new Error(`GitHub ${path.split("?")[0] || "/"} returned ${response.status}`);
	}
	return (await response.json()) as T;
}

function isCommunity(user: GitHubUser | null, owner: string): user is GitHubUser {
	if (!user) return false;
	return user.login !== owner && user.type !== "Bot" && !user.login.endsWith("[bot]");
}

function labelText(issue: GitHubIssue): string {
	return issue.labels
		.map((label) => (typeof label === "string" ? label : (label.name ?? "")))
		.join(" ");
}

/** Lower tiers are triaged first; the reason says why in the owner email. */
function triageTier(issue: GitHubIssue): { tier: number; reason: string } {
	const labels = labelText(issue);
	if (SECURITY_LABEL.test(labels)) return { reason: "security label", tier: 0 };
	if (issue.pull_request && !issue.draft)
		return { reason: "pull request awaiting review", tier: 1 };
	if (BUG_LABEL.test(labels)) return { reason: "bug report", tier: 2 };
	if (issue.pull_request) return { reason: "draft pull request", tier: 4 };
	return { reason: "open issue", tier: 3 };
}

/** Ranks open community items: tier, then engagement, then the longest wait. */
function rankOpenSourcePriorities(
	openItems: GitHubIssue[],
	owner: string,
	now: Date,
): OpenSourcePriority[] {
	return openItems
		.filter((issue) => isCommunity(issue.user, owner))
		.map((issue) => {
			const { tier, reason } = triageTier(issue);
			const createdMs = Date.parse(issue.created_at);
			const priority: OpenSourcePriority = {
				ageDays: Math.max(0, Math.floor((now.getTime() - createdMs) / DAY_MS)),
				author: issue.user?.login ?? "",
				engagement: issue.comments + (issue.reactions?.total_count ?? 0),
				kind: issue.pull_request ? "pull_request" : "issue",
				number: issue.number,
				reason,
				title: issue.title,
				url: issue.html_url,
			};
			return { createdMs, priority, tier };
		})
		.sort(
			(left, right) =>
				left.tier - right.tier ||
				right.priority.engagement - left.priority.engagement ||
				left.createdMs - right.createdMs,
		)
		.slice(0, PRIORITY_LIMIT)
		.map((entry) => entry.priority);
}

function windowActivity(recent: GitHubIssue[], owner: string, sinceMs: number) {
	const createdInWindow = recent.filter((issue) => Date.parse(issue.created_at) >= sinceMs);
	const merged = recent.filter((issue) => {
		const mergedAt = issue.pull_request?.merged_at;
		return mergedAt ? Date.parse(mergedAt) >= sinceMs : false;
	});
	const people = new Set(
		[...createdInWindow, ...merged]
			.map((issue) => issue.user)
			.filter((user) => isCommunity(user, owner))
			.map((user) => user.login),
	);
	return {
		mergedPullRequests: merged.length,
		newIssues: createdInWindow.filter((issue) => !issue.pull_request).length,
		newPullRequests: createdInWindow.filter((issue) => issue.pull_request).length,
		windowContributors: people.size,
	};
}

function failed(message: string): GrowthDigestSourceData["github"] {
	return {
		codeContributors: null,
		forks: null,
		mergedPullRequests: null,
		message,
		newIssues: null,
		newPullRequests: null,
		openIssues: null,
		openPullRequests: null,
		priorities: [],
		stars: null,
		status: "error",
		windowContributors: null,
	};
}

export async function loadGitHubActivity(
	windowDays: number,
	now: Date,
	source: EnvSource,
	fetcher: Fetcher,
): Promise<GrowthDigestSourceData["github"]> {
	const since = new Date(now.getTime() - windowDays * DAY_MS);
	try {
		const [repo, openItems, recent, contributors] = await Promise.all([
			githubJson<GitHubRepo>("", source, fetcher),
			githubJson<GitHubIssue[]>("/issues?state=open&per_page=100", source, fetcher),
			githubJson<GitHubIssue[]>(
				`/issues?state=all&per_page=100&since=${since.toISOString()}`,
				source,
				fetcher,
			),
			githubJson<GitHubUser[]>("/contributors?per_page=100", source, fetcher),
		]);
		const owner = repo.owner.login;
		return {
			codeContributors: contributors.filter((user) => isCommunity(user, owner)).length,
			forks: repo.forks_count,
			openIssues: openItems.filter((issue) => !issue.pull_request).length,
			openPullRequests: openItems.filter((issue) => issue.pull_request).length,
			priorities: rankOpenSourcePriorities(openItems, owner, now),
			stars: repo.stargazers_count,
			status: "ok",
			...windowActivity(recent, owner, since.getTime()),
		};
	} catch (error) {
		return failed(error instanceof Error ? error.message : "Unknown GitHub error");
	}
}
