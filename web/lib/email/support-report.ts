import { createHash } from "node:crypto";
import {
	SupportReportEmail,
	type SupportReportEvent,
	SupportReportPlainText,
} from "@/emails/support-report";
import { sendOwnerNotification } from "@/lib/email/owner-notification";
import type { sendEmail } from "@/lib/email/send-helper";

const DEFAULT_SUPPORT_REPORT_TO = "support@jpthecat.com";
const SUPPORT_REPORT_TO = process.env.SUPPORT_REPORT_TO?.trim() || DEFAULT_SUPPORT_REPORT_TO;

type NotifySupportReportOptions = {
	client?: Parameters<typeof sendEmail>[0]["client"];
};

export async function notifySupportReport(
	event: SupportReportEvent,
	options: NotifySupportReportOptions = {},
) {
	const hash = createHash("sha256")
		.update([event.contactEmail, event.message, event.report, event.receivedAtIso].join("\n"))
		.digest("hex")
		.slice(0, 24);
	const key = `support-report:${hash}`;
	return sendOwnerNotification({
		label: "support-report",
		client: options.client,
		entityRefId: key,
		idempotencyKey: key,
		react: SupportReportEmail({ event }),
		replyTo: event.contactEmail ?? undefined,
		subject: `JP the Cat support report${event.contactEmail ? `: ${event.contactEmail}` : ""}`,
		tags: [
			{ name: "type", value: "support_report" },
			{ name: "source", value: "mac_app" },
		],
		text: SupportReportPlainText({ event }),
		to: SUPPORT_REPORT_TO,
	});
}
