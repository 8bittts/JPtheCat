// Supabase-backed atomic rate limiter for the public POST surfaces (the owner-notification
// email on /download and support requests). It reuses the SAME public anon key and the same
// INSERT-only, RLS-guarded pattern as the download telemetry sink — deliberately NO service-role
// key in the web runtime. The bucket key encodes action + identifier + a fixed time window; the
// table's primary key turns "a second hit in the same window" into a unique-violation (HTTP 409)
// that this reads as "rate limited".
//
// FAILS OPEN: missing config, a network error, an absent table (before the 0006 migration is
// applied), or any unexpected status all resolve to { allowed: true } — a throttle outage can
// never block a real download or signup. That is why the code is safe to deploy ahead of the
// migration: until the table exists every request is simply allowed.

const THROTTLE_TABLE = "request_throttle";
const MAX_BUCKET_KEY_LENGTH = 200;

function resolveThrottleRest(): { url: string; key: string } | null {
	const base = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
	const key = process.env.SUPABASE_PUBLISHABLE_KEY?.trim();
	if (!base || !key) {
		return null;
	}
	return { url: `${base.replace(/\/$/, "")}/rest/v1/${THROTTLE_TABLE}`, key };
}

/**
 * Consume one token for (action, identifier) in the current fixed window.
 * Returns { allowed: false } ONLY when the store positively reports the window is already used;
 * every other outcome (unconfigured, no identifier, network/DB error) is { allowed: true }.
 */
export async function consumeRateLimit(
	action: string,
	identifier: string | null | undefined,
	windowSeconds: number,
	now: number = Date.now(),
): Promise<{ allowed: boolean }> {
	const rest = resolveThrottleRest();
	const id = identifier?.trim();
	if (!rest || !id) {
		return { allowed: true };
	}
	const windowStart = Math.floor(now / (windowSeconds * 1000));
	const bucketKey = `${action}:${id}:${windowStart}`.slice(0, MAX_BUCKET_KEY_LENGTH);
	try {
		const response = await fetch(rest.url, {
			method: "POST",
			headers: {
				"Content-Type": "application/json",
				apikey: rest.key,
				Prefer: "return=minimal",
			},
			body: JSON.stringify({ bucket_key: bucketKey }),
		});
		// 409 = primary-key conflict = this (action, id, window) was already counted.
		return { allowed: response.status !== 409 };
	} catch {
		return { allowed: true };
	}
}
