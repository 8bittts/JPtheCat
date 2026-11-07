import postgres from "postgres";
import type { GrowthDigestFrequency, GrowthDigestSourceData } from "@/lib/analytics/growth-digest";
import { growthDigestWindowDays } from "@/lib/analytics/growth-digest";
import {
	buildGrowthPostgresConnectionString,
	type EnvSource,
	type Fetcher,
} from "./growth-digest-common";
import { queryDownloadData } from "./growth-source-downloads";
import { loadGitHubActivity } from "./growth-source-github";
import { loadSearchConsole } from "./growth-source-search-console";
import { loadVercelAnalytics } from "./growth-source-vercel";

export async function loadGrowthDigestSourceData({
	fetcher = fetch,
	frequency,
	now = new Date(),
	source = process.env,
}: {
	frequency: GrowthDigestFrequency;
	fetcher?: Fetcher;
	now?: Date;
	source?: EnvSource;
}): Promise<GrowthDigestSourceData> {
	const windowDays = growthDigestWindowDays(frequency);
	// `prepare: false` disables prepared-statement caching — pointless for a once-daily single-query
	// cron, and REQUIRED if the connection string is ever moved to Supabase's transaction pooler
	// (:6543), which doesn't support prepared statements. Safe in session mode (:5432) too, so it's a
	// zero-risk forward-compat step. `max: 1` already avoids any pool-exhaustion concern here.
	const sql = postgres(buildGrowthPostgresConnectionString(source), { max: 1, prepare: false });
	try {
		const [downloads, vercel, searchConsole, github] = await Promise.all([
			queryDownloadData(sql, windowDays, now),
			loadVercelAnalytics(windowDays, now, source, fetcher),
			loadSearchConsole(windowDays, now, source, fetcher),
			loadGitHubActivity(windowDays, now, source, fetcher),
		]);

		return {
			botUserAgents: downloads.botUserAgents,
			byLocation: downloads.byLocation,
			bySource: downloads.bySource,
			byVersion: downloads.byVersion,
			generatedAt: now.toISOString(),
			github,
			headline: downloads.headline,
			macRolling: downloads.macRolling,
			rolling: downloads.rolling,
			searchConsole,
			vercel,
			windowDays,
		};
	} finally {
		await sql.end();
	}
}
