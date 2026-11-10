import { describe, expect, it } from "bun:test";
import { applyEnvText, supabasePoolerUrl, trailingDaysArgument } from "@/lib/analytics/reader-cli";

// The growth readers used to carry three copies of this plumbing. Every value here is a fixture
// passed in by hand: the real environment is never read or written.

describe("growth reader plumbing", () => {
	it("loads KEY=value lines, strips one layer of quotes, and never overrides a set key", () => {
		const env: Record<string, string | undefined> = { ALREADY_SET: "from-shell" };
		applyEnvText(
			[
				"ALREADY_SET=from-file",
				'DOUBLE_QUOTED="two words"',
				"SINGLE_QUOTED='single'",
				"BARE=  padded  ",
				"# a comment",
				"lowercase=ignored",
				"",
			].join("\n"),
			env,
		);

		expect(env).toEqual({
			ALREADY_SET: "from-shell",
			DOUBLE_QUOTED: "two words",
			SINGLE_QUOTED: "single",
			BARE: "padded",
		});
	});

	it("builds the pooler URL from an explicit ref and percent-encodes the password", () => {
		expect(
			supabasePoolerUrl({
				SUPABASE_PROJECT_REF: " fixtureref ",
				SUPABASE_DB_PASSWORD: "p@ss/w:rd",
			}),
		).toBe(
			"postgresql://postgres.fixtureref:p%40ss%2Fw%3Ard@aws-0-us-east-1.pooler.supabase.com:5432/postgres?sslmode=require",
		);
	});

	it("derives the ref from the project URL and honors a pooler host override", () => {
		expect(
			supabasePoolerUrl({
				NEXT_PUBLIC_SUPABASE_URL: "https://derivedref.supabase.co",
				SUPABASE_DB_PASSWORD: "fixture",
				SUPABASE_POOLER_HOST: "pooler.example.test",
			}),
		).toBe(
			"postgresql://postgres.derivedref:fixture@pooler.example.test:5432/postgres?sslmode=require",
		);
	});

	it("fails closed without a password or a project ref", () => {
		expect(() => supabasePoolerUrl({ SUPABASE_PROJECT_REF: "fixtureref" })).toThrow(
			"SUPABASE_DB_PASSWORD not set",
		);
		expect(() => supabasePoolerUrl({ SUPABASE_DB_PASSWORD: "fixture" })).toThrow(
			"SUPABASE_PROJECT_REF or NEXT_PUBLIC_SUPABASE_URL required",
		);
	});

	it("reads the first all-digit argument as the trailing window and defaults to 30", () => {
		expect(trailingDaysArgument(["bun", "script.ts", "--json", "90"])).toBe(90);
		expect(trailingDaysArgument(["bun", "script.ts", "--json"])).toBe(30);
		expect(trailingDaysArgument(["bun", "script.ts", "0"])).toBe(30);
	});
});
