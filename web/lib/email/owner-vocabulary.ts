// The one vocabulary for an absent, empty, or zero value in owner mail (download, billing,
// lifecycle, support, growth digest). Each word means exactly one thing, so a reader never has to
// guess whether "skipped" meant "not set up", "broke", or "ran and found nothing". A real zero is
// always printed as a number ("0", "$0.00"), never as one of these words.
export const OWNER_VALUE = {
	/** A data source ran and answered. */
	connected: "connected",
	/** A data source has no credentials, so it never ran. */
	notConfigured: "not configured",
	/** A data source ran and errored. */
	failed: "failed",
	/** A data source that ran did not return this one value. */
	notAvailable: "not available",
	/** A data source ran and found nothing in the window. */
	noneInWindow: "none in this window",
	/** The source could not name it (an unresolved location, page, or country). */
	unknown: "unknown",
	/** A visit or download that arrived with no referrer. */
	direct: "direct, no referrer",
	/** A lookup that did not run for this event (the download network check). */
	notChecked: "not checked",
	/** The person left it blank (a support report's reply email). */
	notProvided: "not provided",
} as const;
