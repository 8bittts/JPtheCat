import { createHash, timingSafeEqual } from "node:crypto";

/**
 * Constant-time check that an `Authorization` header equals `Bearer ${secret}`. Both sides are hashed
 * to a fixed-length digest before comparison so it never throws on a length mismatch and leaks no
 * timing signal about the secret's length or a matching prefix.
 */
export function bearerMatches(
	authorizationHeader: string | null | undefined,
	secret: string | undefined,
): boolean {
	const trimmedSecret = secret?.trim();
	const header = authorizationHeader?.trim();
	if (!trimmedSecret || !header) {
		return false;
	}
	const provided = createHash("sha256").update(header).digest();
	const expected = createHash("sha256").update(`Bearer ${trimmedSecret}`).digest();
	return timingSafeEqual(provided, expected);
}
