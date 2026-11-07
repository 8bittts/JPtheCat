import { EMAIL_FOOTER_DOMAIN_DISPLAY } from "@/emails/email-footer";

// The content model every owner/admin notice builds. `AdminEmail`
// (admin-email-shell.tsx) renders it as HTML and `adminEmailPlainText` renders it
// as the plain-text part, so the two can never disagree. Rows with a null value and
// sections left empty drop out, so templates never print a dead "—".

/** One entry of a ranked list, such as a top page or a download source. */
export type AdminListItem = {
	text: string;
	/** Trailing context with its unit, such as "21 views". */
	detail?: string;
	/** An absolute https link; the HTML links the text and the plain text prints the URL. */
	href?: string;
};

export type AdminRow = {
	/** Omit for a bare bullet (e.g. a growth signal). */
	label?: string;
	/** Shown when the row has no items, so an empty list still says what happened. */
	value: string | null;
	/** A ranked list renders as a numbered sub-list under the label, never one long joined line. */
	items?: AdminListItem[];
};

export type AdminSection =
	| { title: string; rows: AdminRow[] }
	| { title: string; block: string | null };

export type AdminEmailContent = {
	preview: string;
	title: string;
	lede: string;
	/** Anything the owner should notice first. Empty means the email has no issue block. */
	issues: string[];
	sections: AdminSection[];
};

export const ADMIN_EMAIL_ISSUES_LABEL = "Needs attention";
export const ADMIN_EMAIL_FOOTER_TEXT = "JP the Cat owner notice";
export const ADMIN_EMAIL_PLAIN_TEXT_FOOTER = `${ADMIN_EMAIL_FOOTER_TEXT} · ${EMAIL_FOOTER_DOMAIN_DISPLAY}`;

export function hasItems(row: AdminRow): row is AdminRow & { items: AdminListItem[] } {
	return (row.items?.length ?? 0) > 0;
}

export function hasValue(row: AdminRow): boolean {
	return hasItems(row) || (row.value !== null && row.value !== "");
}

/** A link whose text is only its own path prints the URL alone; any other text keeps its words. */
function itemLabel(item: AdminListItem): string {
	if (!item.href) return item.text;
	return item.href.endsWith(item.text) ? item.href : `${item.text} — ${item.href}`;
}

function itemLine(item: AdminListItem, index: number): string {
	return `  ${index + 1}. ${itemLabel(item)}${item.detail ? ` (${item.detail})` : ""}`;
}

function rowLines(row: AdminRow): string[] {
	const head = row.label ? `${row.label}:` : "-";
	if (hasItems(row)) return [head, ...row.items.map(itemLine)];
	return [row.label ? `${head} ${row.value}` : `- ${row.value}`];
}

/** Drops null rows, then any section left with nothing to show. */
export function visibleSections(sections: AdminSection[]): AdminSection[] {
	return sections.flatMap((section): AdminSection[] => {
		if ("rows" in section) {
			const rows = section.rows.filter(hasValue);
			return rows.length ? [{ ...section, rows }] : [];
		}
		return section.block ? [section] : [];
	});
}

function sectionLines(section: AdminSection): string[] {
	if (!("rows" in section)) return section.block ? [section.block] : [];
	return section.rows.filter(hasValue).flatMap(rowLines);
}

/** The plain-text part, rendered from the same content as the HTML. */
export function adminEmailPlainText(content: AdminEmailContent): string {
	const lines = [content.title, content.lede, ""];
	if (content.issues.length) {
		lines.push(ADMIN_EMAIL_ISSUES_LABEL.toUpperCase(), ...content.issues.map((i) => `- ${i}`), "");
	}
	for (const section of visibleSections(content.sections)) {
		lines.push(section.title.toUpperCase(), ...sectionLines(section), "");
	}
	lines.push(ADMIN_EMAIL_PLAIN_TEXT_FOOTER);
	return lines.join("\n");
}
