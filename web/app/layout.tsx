import { Analytics } from "@vercel/analytics/next";
import { SpeedInsights } from "@vercel/speed-insights/next";
import type { Metadata, Viewport } from "next";
import {
	Bagel_Fat_One,
	Fraunces,
	Gaegu,
	Hanken_Grotesk,
	JetBrains_Mono,
	Space_Grotesk,
} from "next/font/google";
import { SITE } from "@/lib/site";
import "./globals.css";
import "./sticker.css";

// The nonce CSP (see proxy.ts) is per-request, so every page must render
// per-request to receive a matching nonce — otherwise strict-dynamic blocks the
// framework scripts on statically-prerendered pages.
export const dynamic = "force-dynamic";

const fraunces = Fraunces({
	subsets: ["latin"],
	style: ["normal", "italic"],
	variable: "--font-fraunces",
	display: "swap",
});

const hanken = Hanken_Grotesk({
	subsets: ["latin"],
	variable: "--font-hanken",
	display: "swap",
});

// Sticker Bomb skin (see app/sticker.css): chunky display, hand-written asides, grotesk body.
const bagel = Bagel_Fat_One({
	weight: "400",
	subsets: ["latin"],
	variable: "--font-bagel",
	display: "swap",
});

const gaegu = Gaegu({
	weight: ["400", "700"],
	subsets: ["latin"],
	variable: "--font-gaegu",
	display: "swap",
});

const space = Space_Grotesk({
	subsets: ["latin"],
	variable: "--font-space",
	display: "swap",
});

const jetbrains = JetBrains_Mono({
	subsets: ["latin"],
	variable: "--font-jb",
	display: "swap",
});

export const metadata: Metadata = {
	metadataBase: new URL(SITE.url),
	title: {
		default: `${SITE.seoName} — ${SITE.tagline}`,
		template: `%s — ${SITE.name}`,
	},
	description: SITE.description,
	applicationName: SITE.name,
	category: "technology",
	authors: [{ name: SITE.name, url: SITE.url }],
	creator: SITE.name,
	publisher: SITE.name,
	openGraph: {
		type: "website",
		url: SITE.url,
		title: `${SITE.seoName} — ${SITE.tagline}`,
		description: SITE.description,
		siteName: SITE.name,
		locale: "en_US",
		images: [
			{
				url: SITE.ogImage,
				width: 1200,
				height: 630,
				alt: `${SITE.seoName} — ${SITE.tagline}`,
			},
		],
	},
	twitter: {
		card: "summary_large_image",
		title: `${SITE.seoName} — ${SITE.tagline}`,
		description: SITE.description,
		site: SITE.twitter,
		creator: SITE.twitter,
		images: [SITE.ogImage],
	},
	alternates: { canonical: SITE.url },
	robots: {
		index: true,
		follow: true,
		googleBot: { index: true, follow: true, "max-image-preview": "large" },
	},
};

export const viewport: Viewport = {
	themeColor: SITE.paperHex,
	colorScheme: "light",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
	return (
		<html
			lang="en"
			className={`${fraunces.variable} ${hanken.variable} ${jetbrains.variable} ${bagel.variable} ${gaegu.variable} ${space.variable}`}
		>
			<body className="font-sans antialiased">
				<a
					href="#main-content"
					className="sr-only rounded-lg border border-line-strong bg-card px-4 py-2 text-ink shadow-[var(--shadow-pop)] focus:not-sr-only focus:fixed focus:top-3 focus:left-3 focus:z-[100]"
				>
					Skip to content
				</a>
				{children}
				<Analytics />
				<SpeedInsights />
			</body>
		</html>
	);
}
