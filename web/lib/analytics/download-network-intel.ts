import type { DownloadNotificationEvent } from "@/lib/email/download-notification";

const UNKNOWN = "Unknown";
const MAX_TEXT_LENGTH = 240;

// ipapi.is ships two response shapes. With an API key, `asn` and `company` are objects and the
// `is_*` flags are booleans. The keyless free tier (since 2026-09-01) flattens `asn` to one string
// ("AS12322 Free SAS"), `company` to a name, and omits every `is_*` flag. Both shapes are parsed,
// and a missing flag stays `null` so the growth readers can see that the datacenter filter is blind
// instead of reading the row as "not hosting".
type IpapiAsn = {
	asn?: unknown;
	org?: unknown;
};

type IpapiLookupResponse = {
	asn?: IpapiAsn | string;
	company?:
		| {
				name?: unknown;
		  }
		| string;
	error?: unknown;
	is_datacenter?: unknown;
	is_proxy?: unknown;
	is_tor?: unknown;
	is_vpn?: unknown;
};

type FetchLike = typeof fetch;

function cleanText(value: unknown, maxLength = MAX_TEXT_LENGTH): string {
	if (typeof value !== "string") {
		return UNKNOWN;
	}
	const trimmed = value.trim();
	return trimmed ? trimmed.slice(0, maxLength) : UNKNOWN;
}

function normalizeAsn(value: unknown): string {
	if (typeof value === "number" && Number.isFinite(value)) {
		return `AS${value}`;
	}
	if (typeof value !== "string") {
		return UNKNOWN;
	}
	const trimmed = value.trim();
	if (!trimmed) {
		return UNKNOWN;
	}
	return /^AS/i.test(trimmed) ? trimmed.toUpperCase().slice(0, 32) : `AS${trimmed.slice(0, 30)}`;
}

function cleanBoolean(value: unknown): boolean | null {
	return typeof value === "boolean" ? value : null;
}

/** `{asn, org}` with a key; `"AS12322 Free SAS"` (number then operator) without one. */
function parseAsn(value: IpapiLookupResponse["asn"]): { asn: string; org: string } {
	if (typeof value === "string") {
		const match = value.trim().match(/^(AS\d+)\s*(.*)$/i);
		if (!match) {
			return { asn: UNKNOWN, org: UNKNOWN };
		}
		return { asn: normalizeAsn(match[1]), org: cleanText(match[2]) };
	}
	return { asn: normalizeAsn(value?.asn), org: cleanText(value?.org) };
}

function parseCompany(value: IpapiLookupResponse["company"]): string {
	return typeof value === "string" ? cleanText(value) : cleanText(value?.name);
}

/** `true`/`false` only when at least one anonymizer flag arrived; `null` when the tier omits them. */
function parseAnonymous(payload: IpapiLookupResponse): boolean | null {
	const flags = [payload.is_vpn, payload.is_proxy, payload.is_tor].map(cleanBoolean);
	if (flags.every((flag) => flag === null)) {
		return null;
	}
	return flags.some((flag) => flag === true);
}

export async function enrichDownloadNetworkIntel(
	event: DownloadNotificationEvent,
	fetchImpl: FetchLike = fetch,
): Promise<DownloadNotificationEvent> {
	if (!event.ipAddress || event.ipAddress === UNKNOWN) {
		return event;
	}

	try {
		const url = new URL("https://api.ipapi.is/");
		url.searchParams.set("q", event.ipAddress);
		const key = process.env.IPAPI_IS_KEY?.trim();
		if (key) {
			url.searchParams.set("key", key);
		}
		const response = await fetchImpl(url, {
			headers: { Accept: "application/json" },
			signal: AbortSignal.timeout(1200),
		});
		if (!response.ok) {
			return event;
		}
		const payload = (await response.json()) as IpapiLookupResponse;
		if (payload.error) {
			return event;
		}
		const { asn, org } = parseAsn(payload.asn);
		return {
			...event,
			network: {
				asn,
				org: org === UNKNOWN ? parseCompany(payload.company) : org,
				isAnonymous: parseAnonymous(payload),
				isHosting: cleanBoolean(payload.is_datacenter),
			},
		};
	} catch {
		return event;
	}
}
