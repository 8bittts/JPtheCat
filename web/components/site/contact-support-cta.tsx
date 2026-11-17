import { SITE } from "@/lib/site";

// Support is a plain email to support@jpthecat.com. There is no support form or report endpoint:
// the site sends no email and stores no message.
export function ContactSupportCta() {
	return (
		<a href={`mailto:${SITE.email}`} className="sb-btn sb-btn--small">
			Get Support
		</a>
	);
}
