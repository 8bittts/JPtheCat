import type { ReactElement } from "react";
import { getResendClient } from "@/lib/email/resend";

const RETRY_DELAYS_MS = [1000, 2000, 4000] as const;
const RETRYABLE_STATUS_CODES = new Set([429, 502, 503, 504]);

type EmailProviderError = {
	message?: string;
	name?: string;
	statusCode?: number;
};

type EmailProviderResult = {
	data: unknown;
	error: EmailProviderError | null;
};

type SendEmailClient = {
	emails: {
		send: (
			payload: {
				bcc?: string | string[];
				from: string;
				react: ReactElement;
				replyTo?: string | string[];
				subject: string;
				tags?: Array<{ name: string; value: string }>;
				text?: string;
				to: string | string[];
			},
			options: { idempotencyKey: string },
		) => Promise<EmailProviderResult>;
	};
};

type SendEmailInput = {
	entityRefId: string;
	from: string;
	idempotencyKey: string;
	react: ReactElement;
	subject: string;
	to: string | string[];
	bcc?: string | string[];
	client?: SendEmailClient | null;
	replyTo?: string | string[];
	sleep?: (ms: number) => Promise<void>;
	tags?: Array<{ name: string; value: string }>;
	text?: string;
};

function defaultSleep(ms: number) {
	return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

function isRetryableError(error: unknown) {
	const statusCode =
		typeof error === "object" && error !== null && "statusCode" in error
			? Number((error as { statusCode?: unknown }).statusCode)
			: undefined;
	return typeof statusCode === "number" && Number.isFinite(statusCode)
		? RETRYABLE_STATUS_CODES.has(statusCode)
		: true;
}

export async function sendEmail({
	bcc,
	client,
	entityRefId,
	from,
	idempotencyKey,
	react,
	replyTo,
	sleep = defaultSleep,
	subject,
	tags,
	text,
	to,
}: SendEmailInput) {
	const resend = client ?? (getResendClient() as SendEmailClient | null);
	if (!resend) {
		// biome-ignore lint/suspicious/noConsole: Production misconfiguration diagnostic.
		console.warn("[email] RESEND_API_KEY not set; skipping send", { entityRefId });
		return null;
	}
	const resendClient = resend;
	const payload = {
		from,
		react,
		subject,
		to,
		...(bcc ? { bcc } : {}),
		...(replyTo ? { replyTo } : {}),
		...(tags ? { tags } : {}),
		...(text ? { text } : {}),
	};

	async function sendAttempt(attempt: number): Promise<EmailProviderResult> {
		try {
			const result = await resendClient.emails.send(payload, { idempotencyKey });
			const retryDelay = RETRY_DELAYS_MS[attempt];
			if (result.error && retryDelay !== undefined && isRetryableError(result.error)) {
				await sleep(retryDelay);
				return sendAttempt(attempt + 1);
			}
			return result;
		} catch (error) {
			const retryDelay = RETRY_DELAYS_MS[attempt];
			if (retryDelay === undefined || !isRetryableError(error)) {
				throw error;
			}
			await sleep(retryDelay);
			return sendAttempt(attempt + 1);
		}
	}

	return sendAttempt(0);
}
