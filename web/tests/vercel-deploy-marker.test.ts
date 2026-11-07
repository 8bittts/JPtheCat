import { describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * Regression: the deploy marker is matched on the commit SUBJECT only.
 *
 * ignoreCommand used to grep the whole commit message, so the literal string "[deploy]" written
 * anywhere in a commit BODY launched an unintended production build. This executes the configured
 * command against a synthetic message rather than asserting on its text, so a rewrite that
 * reintroduces whole-message matching fails here.
 */

const ignoreCommand = (
	JSON.parse(readFileSync(join(import.meta.dir, "..", "vercel.json"), "utf8")) as {
		ignoreCommand?: string;
	}
).ignoreCommand;

/**
 * Runs the real command the way Vercel does: the commit message arrives in the environment.
 * It runs outside the repo so no `git log` fallback can read this checkout's actual HEAD.
 */
function decide(commitMessage: string): "build" | "skip" {
	const env = { ...process.env, VERCEL_GIT_COMMIT_MESSAGE: commitMessage };
	try {
		execFileSync("/bin/sh", ["-c", ignoreCommand ?? ""], {
			cwd: tmpdir(),
			env,
			stdio: ["ignore", "ignore", "ignore"],
		});
		return "skip"; // exit 0 -> Vercel ignores the build
	} catch {
		return "build"; // exit 1 -> Vercel proceeds
	}
}

describe("Vercel deploy marker", () => {
	test("vercel.json declares an ignoreCommand", () => {
		expect(ignoreCommand).toBeTruthy();
	});

	test("builds when the subject carries the marker", () => {
		expect(decide("feat: ship the thing [deploy]")).toBe("build");
	});

	test("skips when no marker is present", () => {
		expect(decide("chore: update packages")).toBe("skip");
	});

	test("[CRITICAL] skips when the marker appears only in the body", () => {
		expect(decide("chore: update packages\n\nReverts the [deploy] marker discussion.\n")).toBe(
			"skip",
		);
	});

	test("skips an empty message rather than deploying", () => {
		expect(decide("")).toBe("skip");
	});
});
