import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { consumeRateLimit } from "@/lib/analytics/rate-limit";

// consumeRateLimit reads env at call time and uses the GLOBAL fetch, so we swap both per-test.
const REAL_FETCH = globalThis.fetch;
const ENV_KEYS = ["NEXT_PUBLIC_SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY"] as const;

let savedEnv: Record<string, string | undefined>;

beforeEach(() => {
	savedEnv = {};
	for (const k of ENV_KEYS) savedEnv[k] = process.env[k];
});

afterEach(() => {
	globalThis.fetch = REAL_FETCH;
	for (const k of ENV_KEYS) {
		if (savedEnv[k] === undefined) delete process.env[k];
		else process.env[k] = savedEnv[k];
	}
});

/** Configure the throttle store as "present" so the fetch path is exercised. */
function configureStore() {
	process.env.NEXT_PUBLIC_SUPABASE_URL = "https://example.supabase.co";
	process.env.SUPABASE_PUBLISHABLE_KEY = "test-key";
}

describe("consumeRateLimit", () => {
	it("fails OPEN (and never calls the store) when unconfigured", async () => {
		for (const k of ENV_KEYS) delete process.env[k];
		let called = false;
		globalThis.fetch = (async () => {
			called = true;
			return new Response(null, { status: 409 });
		}) as unknown as typeof fetch;

		expect(await consumeRateLimit("download", "1.2.3.4", 3600)).toEqual({ allowed: true });
		expect(called).toBe(false);
	});

	it("fails OPEN (and never calls the store) when the identifier is blank/missing", async () => {
		configureStore();
		let called = false;
		globalThis.fetch = (async () => {
			called = true;
			return new Response(null, { status: 409 });
		}) as unknown as typeof fetch;

		for (const id of [null, undefined, "", "   "]) {
			expect(await consumeRateLimit("download", id, 3600)).toEqual({ allowed: true });
		}
		expect(called).toBe(false);
	});

	it("blocks only on a 409 unique-violation from the store", async () => {
		configureStore();

		globalThis.fetch = (async () => new Response(null, { status: 409 })) as unknown as typeof fetch;
		expect(await consumeRateLimit("download", "1.2.3.4", 3600)).toEqual({ allowed: false });

		globalThis.fetch = (async () => new Response(null, { status: 201 })) as unknown as typeof fetch;
		expect(await consumeRateLimit("download", "1.2.3.4", 3600)).toEqual({ allowed: true });
	});

	it("fails OPEN when the store errors — a throttle outage never blocks a real request", async () => {
		configureStore();
		globalThis.fetch = (async () => {
			throw new Error("network down");
		}) as unknown as typeof fetch;

		expect(await consumeRateLimit("newsletter", "a@b.com", 3600)).toEqual({ allowed: true });
	});

	it("buckets by (action, identifier, fixed window): same window collides, next window is fresh", async () => {
		configureStore();
		const bodies: string[] = [];
		globalThis.fetch = (async (_url: unknown, init: RequestInit) => {
			bodies.push(String(init.body));
			return new Response(null, { status: 201 });
		}) as unknown as typeof fetch;

		const windowSeconds = 3600;
		const base = 1_000_000_000_000; // fixed ms; a window is windowSeconds*1000 wide
		await consumeRateLimit("download", "1.2.3.4", windowSeconds, base);
		await consumeRateLimit("download", "1.2.3.4", windowSeconds, base + 1000); // same window
		await consumeRateLimit("download", "1.2.3.4", windowSeconds, base + windowSeconds * 1000); // next window

		const keys = bodies.map((b) => JSON.parse(b).bucket_key as string);
		expect(keys[0]).toBe(keys[1]); // same fixed window → identical bucket key
		expect(keys[0]).not.toBe(keys[2]); // rolled into the next window → distinct key
		expect(keys[0]).toMatch(/^download:1\.2\.3\.4:\d+$/);
	});
});
