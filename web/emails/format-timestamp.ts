const PACIFIC_STAMP_FORMAT = new Intl.DateTimeFormat("en-US", {
	month: "short",
	day: "numeric",
	hour: "numeric",
	minute: "2-digit",
	hour12: true,
	timeZoneName: "short",
	timeZone: "America/Los_Angeles",
});

/**
 * Turn a raw ISO stamp into a kind Pacific line (e.g. `Jul 3 · 3:53pm PDT`, `Nov 6 · 8:00pm PST`).
 * Shared by every owner-notification email template so the wording never drifts.
 * - empty/nullish input returns `emptyFallback`
 * - an unparseable stamp is passed through verbatim (so a malformed value is at
 *   least visible in the email rather than silently blanked)
 */
export function formatEmailTimestamp(iso: string | null | undefined, emptyFallback = ""): string {
	if (!iso) return emptyFallback;
	const date = new Date(iso);
	if (Number.isNaN(date.getTime())) return iso;
	const parts = PACIFIC_STAMP_FORMAT.formatToParts(date);
	const get = (t: Intl.DateTimeFormatPartTypes) => parts.find((p) => p.type === t)?.value ?? "";
	const dayPeriod = get("dayPeriod").toLowerCase().replace(/\s/g, "");
	return `${get("month")} ${get("day")} · ${get("hour")}:${get("minute")}${dayPeriod} ${get("timeZoneName")}`;
}
