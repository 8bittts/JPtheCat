import { sendEmail } from "@/lib/email/send-helper";

/** The canonical owner/admin `from` address (a verified Resend sender). */
export const OWNER_NOTIFICATION_FROM = "JP the Cat <downloads@jpthecat.com>";

/**
 * Shared send scaffold for the best-effort owner/admin notices
 * (download, support). Each of those hand-rolled the identical
 * from-default + sendEmail + result-error-throw + try/catch→log→null shape;
 * this centralizes it so a fix lands once.
 *
 * `label` names the notice for the thrown error and the `[<label>-notify]` log
 * prefix. `from` is always the owner sender (`RESEND_FROM_EMAIL` override or the
 * canonical downloads@ address) — callers only supply the message fields.
 *
 * A provider failure is swallowed to `null` on purpose: an owner notice must
 * never fail the caller's real flow (a download redirect or a support request).
 */
type OwnerNotificationInput = Omit<Parameters<typeof sendEmail>[0], "from"> & {
	label: string;
};

export async function sendOwnerNotification({ label, ...email }: OwnerNotificationInput) {
	try {
		const result = await sendEmail({
			...email,
			from: process.env.RESEND_FROM_EMAIL?.trim() || OWNER_NOTIFICATION_FROM,
		});
		if (result?.error) {
			throw new Error(`Resend ${label} notification failed: ${result.error.message}`);
		}
		return result?.data ?? null;
	} catch (error) {
		const message = error instanceof Error ? error.message : "Unknown Resend error";
		// biome-ignore lint/suspicious/noConsole: Owner notices are best-effort; a send failure must never fail the caller's flow, but it needs logs.
		console.error(`[${label}-notify] failed`, message);
		return null;
	}
}
