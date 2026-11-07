import { NextResponse } from "next/server";

// Shared helpers for the no-store JSON API routes (support).

/** `X-Robots-Tag` value for API routes that must never be indexed. */
export const API_NOINDEX_HEADER = "noindex, nofollow, noarchive, nosnippet, noimageindex";

/** Basic email-shape check shared by the email-sending endpoints. */
export const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** A JSON response stamped no-store + noindex, merging any caller-supplied `init`. */
export function jsonResponse(payload: Record<string, unknown>, init: ResponseInit = {}) {
	const headers = new Headers(init.headers);
	headers.set("Cache-Control", "no-store");
	headers.set("X-Robots-Tag", API_NOINDEX_HEADER);
	return NextResponse.json(payload, { ...init, headers });
}

/** Trim a value to a non-empty string capped at `max` chars, else `null`. `max` is always explicit
 *  at the call site (each field has its own cap), so this takes no default. */
export function cleanString(value: unknown, max: number): string | null {
	if (typeof value !== "string") return null;
	const trimmed = value.trim();
	if (!trimmed) return null;
	return trimmed.length > max ? trimmed.slice(0, max) : trimmed;
}
