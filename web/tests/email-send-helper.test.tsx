import { describe, expect, it } from "bun:test";
import { sendEmail } from "@/lib/email/send-helper";

describe("email send helper", () => {
	it("retries transient Resend API errors with SDK idempotency", async () => {
		const attempts: unknown[] = [];
		const delays: number[] = [];
		const client = {
			emails: {
				send: async (payload: unknown, options: unknown) => {
					attempts.push({ options, payload });
					if (attempts.length < 3) {
						return { data: null, error: { message: "try later", statusCode: 503 } };
					}
					return { data: { id: "email_ok" }, error: null };
				},
			},
		};

		const result = await sendEmail({
			client,
			entityRefId: "download:v0.062:test",
			from: "JP the Cat <downloads@jpthecat.com>",
			idempotencyKey: "download:0.062:test:2026-07-03T16",
			react: <div>hello</div>,
			sleep: async (ms) => {
				delays.push(ms);
			},
			subject: "JP the Cat download",
			to: "owner@example.com",
		});

		expect(result).toEqual({ data: { id: "email_ok" }, error: null });
		expect(attempts).toHaveLength(3);
		expect(delays).toEqual([1000, 2000]);
		expect(
			attempts.every((attempt) =>
				JSON.stringify(attempt).includes("download:0.062:test:2026-07-03T16"),
			),
		).toBe(true);
	});

	it("does not retry non-retryable Resend API errors", async () => {
		const attempts: unknown[] = [];
		const client = {
			emails: {
				send: async () => {
					attempts.push("send");
					return { data: null, error: { message: "bad request", statusCode: 400 } };
				},
			},
		};

		const result = await sendEmail({
			client,
			entityRefId: "download:v0.062:test",
			from: "JP the Cat <downloads@jpthecat.com>",
			idempotencyKey: "download:0.062:test:2026-07-03T16",
			react: <div>hello</div>,
			sleep: async () => {
				throw new Error("sleep should not run");
			},
			subject: "JP the Cat download",
			to: "owner@example.com",
		});

		expect(result).toEqual({ data: null, error: { message: "bad request", statusCode: 400 } });
		expect(attempts).toHaveLength(1);
	});

	it("passes an explicit plain-text fallback to Resend", async () => {
		let sentPayload: unknown;
		const client = {
			emails: {
				send: async (payload: unknown) => {
					sentPayload = payload;
					return { data: { id: "email_text" }, error: null };
				},
			},
		};

		await sendEmail({
			client,
			entityRefId: "download:v0.076:text",
			from: "JP the Cat <downloads@jpthecat.com>",
			idempotencyKey: "download:0.076:text:2026-07-04T00",
			react: <div>html fallback</div>,
			subject: "JP the Cat download",
			text: "Curated plain text with the release audit fields.",
			to: "owner@example.com",
		});

		expect(sentPayload).toMatchObject({
			text: "Curated plain text with the release audit fields.",
		});
	});
});
