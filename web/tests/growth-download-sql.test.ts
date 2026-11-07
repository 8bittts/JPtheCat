import { describe, expect, test } from "bun:test";
import { humanDownloadsCte } from "@/lib/analytics/growth-download-sql";

// Renders the CTE through a plain tagged template so the guard pins the actual SQL text both real
// clients receive. Numeric constants are interpolated back in for readability.
function renderedSql(): string {
	const values: unknown[] = [];
	const sql = (strings: TemplateStringsArray, ...vals: unknown[]) => {
		values.push(...vals);
		return strings.reduce((acc, s, i) => acc + s + (i < vals.length ? String(vals[i]) : ""), "");
	};
	return humanDownloadsCte(sql);
}

describe("humanDownloadsCte", () => {
	const sql = renderedSql();

	test("keeps the UA-bot and owner-smoke exclusions", () => {
		expect(sql).toContain("d.is_bot = false");
		expect(sql).toContain("'smoke-test', 'production-test'");
		expect(sql).toContain("JP-the-Cat-smoke-test-bot/%");
	});

	test("excludes datacenter/hosting and anonymizing networks", () => {
		expect(sql).toContain("coalesce(d.network_is_hosting, false) = false");
		expect(sql).toContain("coalesce(d.network_is_anonymous, false) = false");
	});

	test("excludes same-IP multi-source bursts AND slow multi-day repeat monitors", () => {
		expect(sql).toContain("burst_ips");
		expect(sql).toContain("monitor_ips");
		// The monitor rule counts DISTINCT days, not raw hits — a same-day double download stays human.
		expect(sql).toContain("count(distinct created_at::date) >= 4");
	});

	test("honors the durable exclusion stamp the redaction job writes before nulling the IP", () => {
		// Without this, a monitor caught today becomes "human" the day its IP is redacted
		// (GrowthScan/0.1: 136 rows in Oct 2026).
		expect(sql).toContain("d.exclusion is null");
	});

	test("exposes the Mac-only headline population on top of human", () => {
		expect(sql).toContain("mac_human as (");
		expect(sql).toContain("h.is_mac = true");
	});

	test("keeps the burst and monitor constants in step with migration 0011's redaction job", async () => {
		const migration = await Bun.file(
			new URL(
				"../../supabase/migrations/0011_downloads_platform_and_exclusion.sql",
				import.meta.url,
			),
		).text();
		expect(migration).toContain("count(distinct created_at::date) >= 4");
		expect(migration).toContain("<= 8");
		expect(sql).toContain(") <= 8");
	});
});
