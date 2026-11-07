import type { ReactNode } from "react";

/** Shared hero block for library, legal, and other inner marketing routes. */
export function StickerPageHero({
	kicker,
	title,
	lede,
	meta,
}: {
	kicker?: string;
	title: ReactNode;
	lede: ReactNode;
	meta?: ReactNode;
}) {
	return (
		<header className="sb-page-head">
			{kicker ? <p className="sb-page-kicker">{kicker}</p> : null}
			<h1 className="sb-page-title">{title}</h1>
			<p className="sb-page-lede">{lede}</p>
			{meta ? <div className="sb-page-meta">{meta}</div> : null}
		</header>
	);
}
