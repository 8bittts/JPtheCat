import {
	Body,
	Column,
	Container,
	Heading,
	Html,
	Img,
	Link,
	Preview,
	Row,
	Section,
	Text,
} from "@react-email/components";
import type { CSSProperties } from "react";
import {
	ADMIN_EMAIL_FOOTER_TEXT,
	ADMIN_EMAIL_ISSUES_LABEL,
	type AdminEmailContent,
	type AdminListItem,
	type AdminRow,
	type AdminSection,
	hasItems,
	hasValue,
	visibleSections,
} from "@/emails/admin-email-content";
import { EMAIL_FOOTER_DOMAIN_DISPLAY, EMAIL_FOOTER_DOMAIN_HREF } from "@/emails/email-footer";
import { EmailHead } from "@/emails/email-head";
import { emailColors, emailFonts, emailRadius } from "@/emails/email-styles";

// "Owner Ledger" — the ONE shell for every owner/admin notice (download, billing,
// lifecycle, support, growth digest). Spartan on purpose: a small logo row, an
// issue block when something needs attention, a short heading, then labeled
// sections of `Label: value` bullets. No hero, badges, buttons, or signature.
// Templates build an `AdminEmailContent` (admin-email-content.ts) and pass it here.
//
// Shared email tokens and client rules: Row/Column
// tables, an explicit background on every surface, `color-scheme: light`, and a
// ginger-deep inline headline color that Gmail iOS dark mode leaves alone.

const LOGO_SRC = "https://jpthecat.com/jpthecat-logo.png";

// Dark-mode re-assertion: every class that sits on a pinned-light surface is listed,
// so a client that darkens cannot leave light text on a light background.
const BACKGROUND_CLASSES: Array<readonly [string, string]> = [
	["jp-page", emailColors.paper],
	["jp-sheet", emailColors.card],
	["jp-issues", emailColors.coralWash],
	["jp-block", emailColors.cream],
];
const TEXT_CLASSES: Array<readonly [string, string]> = [
	["jp-ink", emailColors.ink],
	["jp-soft", emailColors.soft],
	["jp-title", emailColors.gingerDeep],
	["jp-link", emailColors.gingerDeep],
	["jp-alert", emailColors.coral],
];

function cssRules(pairs: Array<readonly [string, string]>, property: string, prefix = "") {
	return pairs
		.map(([name, hex]) => `${prefix}.${name} { ${property}: ${hex} !important; }`)
		.join("\n");
}

const ADMIN_DARK_MODE_CSS = `
:root { color-scheme: light; supported-color-schemes: light; }
@media (prefers-color-scheme: dark) {
${cssRules(BACKGROUND_CLASSES, "background-color")}
${cssRules(TEXT_CLASSES, "color")}
}
${cssRules(TEXT_CLASSES, "color", "[data-ogsc] ")}
${cssRules(BACKGROUND_CLASSES, "background-color", "[data-ogsb] ")}
`;

const page: CSSProperties = {
	backgroundColor: emailColors.paper,
	color: emailColors.ink,
	fontFamily: emailFonts.sans,
	margin: "0",
	padding: "0",
	width: "100%",
};

const container: CSSProperties = {
	margin: "0 auto",
	maxWidth: "640px",
	padding: "28px 12px 36px",
	width: "100%",
};

const sheet: CSSProperties = {
	backgroundColor: emailColors.card,
	border: `1px solid ${emailColors.lineStrong}`,
	borderRadius: emailRadius.card,
	padding: "26px 32px 22px",
};

const masthead: CSSProperties = {
	borderBottom: `1px solid ${emailColors.line}`,
	margin: "0 0 24px",
	paddingBottom: "16px",
};

const logo: CSSProperties = {
	border: `1px solid ${emailColors.lineStrong}`,
	borderRadius: "999px",
	display: "block",
	height: "36px",
	width: "36px",
};

const wordmark: CSSProperties = {
	color: emailColors.ink,
	fontFamily: emailFonts.serif,
	fontSize: "18px",
	fontWeight: 600,
	lineHeight: "24px",
	margin: "0",
};

const issueBlock: CSSProperties = {
	backgroundColor: emailColors.coralWash,
	border: `1px solid ${emailColors.coralLine}`,
	borderRadius: emailRadius.compact,
	margin: "0 0 22px",
	padding: "14px 18px",
};

const sectionLabel: CSSProperties = {
	color: emailColors.soft,
	fontFamily: emailFonts.mono,
	fontSize: "12px",
	fontWeight: 800,
	letterSpacing: "0.08em",
	lineHeight: "16px",
	margin: "0 0 8px",
	textTransform: "uppercase" as const,
};

const issueLabel: CSSProperties = { ...sectionLabel, color: emailColors.coral };

const titleStyle: CSSProperties = {
	// Ginger-deep, NOT ink: Gmail iOS dark mode force-lightens large near-black inline text.
	color: emailColors.gingerDeep,
	fontFamily: emailFonts.serif,
	fontSize: "26px",
	fontWeight: 600,
	letterSpacing: "0",
	lineHeight: "32px",
	margin: "0 0 6px",
};

const ledeStyle: CSSProperties = {
	color: emailColors.soft,
	fontFamily: emailFonts.sans,
	fontSize: "16px",
	lineHeight: "24px",
	margin: "0 0 24px",
};

const sectionWrap: CSSProperties = { margin: "0 0 20px" };

const list: CSSProperties = {
	color: emailColors.ink,
	fontFamily: emailFonts.sans,
	fontSize: "16px",
	lineHeight: "24px",
	margin: "0",
	paddingLeft: "20px",
};

const listItem: CSSProperties = { margin: "0 0 6px", wordBreak: "break-word" as const };

const link: CSSProperties = { color: emailColors.gingerDeep, textDecoration: "underline" };

// A ranked list sits one level under its label as 1. 2. 3., never a long "·"-joined line.
const rankedList: CSSProperties = {
	listStyleType: "decimal",
	margin: "4px 0 0",
	paddingLeft: "22px",
};

const rankedItem: CSSProperties = { margin: "0 0 2px", wordBreak: "break-word" as const };

const block: CSSProperties = {
	backgroundColor: emailColors.cream,
	border: `1px solid ${emailColors.creamDeep}`,
	borderRadius: emailRadius.compact,
	color: emailColors.ink,
	fontFamily: emailFonts.sans,
	fontSize: "16px",
	lineHeight: "24px",
	margin: "0",
	padding: "12px 14px",
	whiteSpace: "pre-wrap" as const,
	wordBreak: "break-word" as const,
};

const footer: CSSProperties = {
	borderTop: `1px solid ${emailColors.line}`,
	margin: "8px 0 0",
	paddingTop: "14px",
};

const footerText: CSSProperties = {
	color: emailColors.soft,
	fontFamily: emailFonts.sans,
	fontSize: "13px",
	lineHeight: "20px",
	margin: "0",
};

function ItemText({ item }: { item: AdminListItem }) {
	if (item.href) {
		return (
			<Link className="jp-link" href={item.href} style={link}>
				{item.text}
			</Link>
		);
	}
	return item.text;
}

function RowBody({ row }: { row: AdminRow }) {
	if (hasItems(row)) {
		return (
			<ol style={rankedList}>
				{row.items.map((item) => (
					<li className="jp-ink" key={`${item.text}|${item.detail ?? ""}`} style={rankedItem}>
						<ItemText item={item} />
						{item.detail ? ` (${item.detail})` : null}
					</li>
				))}
			</ol>
		);
	}
	return row.value;
}

function SectionBody({ section }: { section: AdminSection }) {
	if (!("rows" in section)) {
		return (
			<Text className="jp-block jp-ink" style={block}>
				{section.block}
			</Text>
		);
	}
	return (
		<ul style={list}>
			{section.rows.filter(hasValue).map((row) => (
				<li className="jp-ink" key={row.label ?? row.value ?? ""} style={listItem}>
					{row.label ? <strong>{row.label}: </strong> : null}
					<RowBody row={row} />
				</li>
			))}
		</ul>
	);
}

function IssueBlock({ issues }: { issues: string[] }) {
	if (!issues.length) return null;
	return (
		<Section className="jp-issues" style={issueBlock}>
			<Text className="jp-alert" style={issueLabel}>
				{ADMIN_EMAIL_ISSUES_LABEL}
			</Text>
			<ul style={list}>
				{issues.map((issue) => (
					<li className="jp-ink" key={issue} style={listItem}>
						{issue}
					</li>
				))}
			</ul>
		</Section>
	);
}

export function AdminEmail({ content }: { content: AdminEmailContent }) {
	return (
		<Html lang="en">
			<EmailHead css={ADMIN_DARK_MODE_CSS} />
			<Preview>{content.preview}</Preview>
			<Body className="jp-page" style={page}>
				<Container style={container}>
					<Section className="jp-sheet" style={sheet}>
						<Section style={masthead}>
							<Row>
								<Column style={{ verticalAlign: "middle", width: "48px" }}>
									<Img alt="JP the Cat" height="36" src={LOGO_SRC} style={logo} width="36" />
								</Column>
								<Column style={{ verticalAlign: "middle" }}>
									<Text className="jp-ink" style={wordmark}>
										JP the Cat
									</Text>
								</Column>
							</Row>
						</Section>
						<IssueBlock issues={content.issues} />
						<Heading as="h1" className="jp-title" style={titleStyle}>
							{content.title}
						</Heading>
						<Text className="jp-soft" style={ledeStyle}>
							{content.lede}
						</Text>
						{visibleSections(content.sections).map((section) => (
							<Section key={section.title} style={sectionWrap}>
								<Text className="jp-soft" style={sectionLabel}>
									{section.title}
								</Text>
								<SectionBody section={section} />
							</Section>
						))}
						<Section style={footer}>
							<Text className="jp-soft" style={footerText}>
								{ADMIN_EMAIL_FOOTER_TEXT} ·{" "}
								<Link className="jp-link" href={EMAIL_FOOTER_DOMAIN_HREF} style={link}>
									{EMAIL_FOOTER_DOMAIN_DISPLAY}
								</Link>
							</Text>
						</Section>
					</Section>
				</Container>
			</Body>
		</Html>
	);
}
