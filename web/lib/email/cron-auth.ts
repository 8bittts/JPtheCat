import { bearerMatches } from "@/lib/http/bearer-auth";

export function isCronRequestAuthorized(
	request: Request,
	source: Record<string, string | undefined> = process.env,
) {
	return bearerMatches(request.headers.get("authorization"), source.CRON_SECRET);
}
