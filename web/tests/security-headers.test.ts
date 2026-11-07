import { describe, expect, it } from "bun:test";
import { NextRequest } from "next/server";
import {
	buildContentSecurityPolicy,
	CSP_REPORT_PATH,
	DOCUMENT_PERMISSIONS_POLICY,
	DOCUMENT_SECURITY_HEADERS,
	proxy,
	config as proxyConfig,
	REPORTING_ENDPOINTS_HEADER,
} from "../proxy";

type VercelHeaderRule = {
	source: string;
	headers: Array<{ key: string; value: string }>;
};

describe("security headers", () => {
	it("keeps the client secret scan wired into every production build", async () => {
		const packageJson = (await Bun.file("package.json").json()) as {
			scripts?: Record<string, string>;
		};

		expect(packageJson.scripts?.build).toContain("bun run scan:secrets");
		expect(packageJson.scripts?.["scan:secrets"]).toBe(
			"bun run scripts/scan-client-bundle-secrets.ts",
		);
	});

	it("pins Node Functions beside the Supabase database", async () => {
		const vercelConfig = (await Bun.file("vercel.json").json()) as {
			regions?: string[];
		};

		expect(vercelConfig.regions).toEqual(["iad1"]);
	});

	it("keeps the document CSP strict while allowing shipped site assets", () => {
		const csp = buildContentSecurityPolicy("test-nonce");

		expect(csp).toContain("default-src 'self'");
		expect(csp).toContain("script-src 'nonce-test-nonce' 'strict-dynamic'");
		expect(csp).toContain("style-src 'self' 'unsafe-inline'");
		expect(csp).toContain("img-src 'self' data: blob:");
		expect(csp).toContain("media-src 'self' blob: data:");
		expect(csp).toContain("font-src 'self' data:");
		expect(csp).toContain("connect-src 'self' https://api.jpthecat.com");
		expect(csp).toContain("manifest-src 'self'");
		expect(csp).toContain("frame-src 'none'");
		expect(csp).toContain("object-src 'none'");
		expect(csp).toContain("base-uri 'self'");
		expect(csp).toContain("form-action 'self'");
		expect(csp).toContain("frame-ancestors 'none'");
		expect(csp).not.toContain("script-src 'self'");
		expect(csp).not.toContain("script-src 'unsafe-inline'");
		expect(csp).not.toContain("connect-src *");
	});

	it("routes CSP violations to the same-origin report sink", () => {
		const csp = buildContentSecurityPolicy("test-nonce");
		// Modern (report-to → Reporting-Endpoints group) + legacy (report-uri) both point at the sink.
		expect(csp).toContain("report-to csp-endpoint");
		expect(csp).toContain(`report-uri ${CSP_REPORT_PATH}`);
		expect(CSP_REPORT_PATH).toBe("/api/csp-report");

		// The proxy must declare the endpoint group the `report-to` directive names.
		const response = proxy(new NextRequest("https://jpthecat.com/"));
		expect(response.headers.get("reporting-endpoints")).toBe(REPORTING_ENDPOINTS_HEADER);
		expect(response.headers.get("reporting-endpoints")).toContain(
			`csp-endpoint="${CSP_REPORT_PATH}"`,
		);
		expect(response.headers.get("content-security-policy")).toContain("report-to csp-endpoint");
	});

	it("keeps document isolation headers aligned with the CSP proxy", () => {
		expect(DOCUMENT_SECURITY_HEADERS).toEqual({
			"cross-origin-opener-policy": "same-origin",
			"cross-origin-resource-policy": "same-origin",
			"x-content-type-options": "nosniff",
			"referrer-policy": "strict-origin-when-cross-origin",
			"permissions-policy": DOCUMENT_PERMISSIONS_POLICY,
		});
		expect(DOCUMENT_PERMISSIONS_POLICY).toContain("interest-cohort=()");
		expect(DOCUMENT_PERMISSIONS_POLICY).toContain("browsing-topics=()");
	});

	it("does not apply nonce CSP to static release metadata or media assets", () => {
		const source = proxyConfig.matcher[0]?.source ?? "";

		for (const extension of [
			"json",
			"xml",
			"txt",
			"webmanifest",
			"mp4",
			"webm",
			"m4a",
			"mp3",
			"wav",
			"ogg",
			"aac",
			"wasm",
			"sha256",
			"dmg",
		]) {
			expect(source).toContain(extension);
		}
	});

	it("keeps public release metadata CORS-open without opening the whole site", async () => {
		const vercelConfig = (await Bun.file("vercel.json").json()) as {
			headers: VercelHeaderRule[];
		};
		const stableRule = vercelConfig.headers.find((rule) => rule.source === "/stable/:path*");
		const globalRule = vercelConfig.headers.find((rule) => rule.source === "/(.*)");

		expect(stableRule?.headers).toContainEqual({
			key: "Access-Control-Allow-Origin",
			value: "*",
		});
		expect(stableRule?.headers).toContainEqual({
			key: "Access-Control-Allow-Methods",
			value: "GET, HEAD, OPTIONS",
		});
		expect(stableRule?.headers).toContainEqual({
			key: "Cross-Origin-Resource-Policy",
			value: "cross-origin",
		});
		expect(globalRule?.headers).not.toContainEqual({
			key: "Access-Control-Allow-Origin",
			value: "*",
		});
		expect(globalRule?.headers).toContainEqual({
			key: "Cross-Origin-Opener-Policy",
			value: "same-origin",
		});
	});

	it("pins crawler and manifest metadata back to the site origin", async () => {
		const vercelConfig = (await Bun.file("vercel.json").json()) as {
			headers: VercelHeaderRule[];
		};

		for (const source of ["/robots.txt", "/sitemap.xml", "/manifest.webmanifest", "/llms.txt"]) {
			const rule = vercelConfig.headers.find((candidate) => candidate.source === source);
			expect(rule?.headers).toContainEqual({
				key: "Access-Control-Allow-Origin",
				value: "https://jpthecat.com",
			});
			expect(rule?.headers).toContainEqual({
				key: "Cross-Origin-Resource-Policy",
				value: "same-origin",
			});
		}
	});

	it("keeps the vercel edge Permissions-Policy identical to the middleware document policy", async () => {
		const vercelConfig = (await Bun.file("vercel.json").json()) as {
			headers: VercelHeaderRule[];
		};
		const globalRule = vercelConfig.headers.find((rule) => rule.source === "/(.*)");
		const permissionsPolicy = globalRule?.headers.find(
			(header) => header.key === "Permissions-Policy",
		);

		expect(permissionsPolicy?.value).toBe(DOCUMENT_PERMISSIONS_POLICY);
	});

	it("keeps every header shared by the vercel edge and the middleware byte-identical", async () => {
		// These headers are intentionally set in TWO places — the vercel.json `/(.*)` edge rule
		// (covers every response, including the static assets the middleware matcher skips) and the
		// proxy.ts DOCUMENT_SECURITY_HEADERS (per-request document responses). JSON can't import the
		// TS constant, so the values are hand-duplicated; this test is the single source of truth that
		// keeps the two copies from drifting. If you change a value in one place, change it in both.
		const vercelConfig = (await Bun.file("vercel.json").json()) as {
			headers: VercelHeaderRule[];
		};
		const globalRule = vercelConfig.headers.find((rule) => rule.source === "/(.*)");
		const edgeValueFor = (key: string) =>
			globalRule?.headers.find((header) => header.key.toLowerCase() === key)?.value;

		// Every DOCUMENT_SECURITY_HEADERS entry that the edge rule ALSO sets must match exactly.
		// (cross-origin-resource-policy is document-only — the edge rule doesn't set it globally — so
		// it legitimately has no edge counterpart to compare against and is skipped here.)
		const sharedKeys = Object.keys(DOCUMENT_SECURITY_HEADERS).filter(
			(key) => edgeValueFor(key) !== undefined,
		);

		expect(sharedKeys).toEqual([
			"cross-origin-opener-policy",
			"x-content-type-options",
			"referrer-policy",
			"permissions-policy",
		]);

		for (const key of sharedKeys) {
			expect(edgeValueFor(key)).toBe(
				DOCUMENT_SECURITY_HEADERS[key as keyof typeof DOCUMENT_SECURITY_HEADERS],
			);
		}
	});
});
