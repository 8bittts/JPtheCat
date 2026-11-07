// The owner roll-up goes out once a day at 20:00 on the Los Angeles clock (PST in winter, PDT in
// summer). Vercel Cron only speaks UTC, so vercel.json fires at both 03:00 and 04:00 UTC and this gate
// lets exactly one of the two through: 20:00 PDT is 03:00 UTC, 20:00 PST is 04:00 UTC.

const ROLLUP_TIME_ZONE = "America/Los_Angeles";
const ROLLUP_LOCAL_HOUR = 20;

const LA_PARTS = new Intl.DateTimeFormat("en-US", {
	day: "2-digit",
	hour: "2-digit",
	hourCycle: "h23",
	month: "2-digit",
	timeZone: ROLLUP_TIME_ZONE,
	weekday: "short",
	year: "numeric",
});

function laParts(now: Date) {
	const parts = LA_PARTS.formatToParts(now);
	const get = (type: Intl.DateTimeFormatPartTypes) =>
		parts.find((part) => part.type === type)?.value ?? "";
	return {
		date: `${get("year")}-${get("month")}-${get("day")}`,
		day: Number(get("day")),
		hour: Number(get("hour")),
		weekday: get("weekday"),
	};
}

/** True only on the cron firing that lands on 20:xx Los Angeles time. */
export function isRollupHour(now: Date): boolean {
	return laParts(now).hour === ROLLUP_LOCAL_HOUR;
}

/** The Los Angeles calendar date of the report, used in its idempotency key and title. */
export function rollupDateKey(now: Date): string {
	return laParts(now).date;
}

/** Monday adds the last-7-days trend; the 1st adds the last-30-days trend (both Los Angeles dates). */
export function rollupTrendDue(now: Date): { weekly: boolean; monthly: boolean } {
	const parts = laParts(now);
	return { monthly: parts.day === 1, weekly: parts.weekday === "Mon" };
}
