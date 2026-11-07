"use client";

import Link from "next/link";
import { useState } from "react";
import { NAV, SITE } from "@/lib/site";

// Sticker Bomb header shared by every route: a tilted yellow JP badge, hand-written links,
// and the same hamburger contract on mobile. It stays silent — JP's meow lives on the hero only.
export function Nav() {
	const [open, setOpen] = useState(false);

	return (
		<header className="sb-nav relative top-0 z-50 md:sticky">
			<div className="home-shell flex h-[76px] items-center justify-between gap-4">
				<Link href="/" className="sb-logo" aria-label={`${SITE.name} home`}>
					{/* biome-ignore lint/performance/noImgElement: tiny static avatar, no optimizer needed */}
					<img src={SITE.photo} alt="" width={34} height={34} />
					<span className="sb-trim">{SITE.name}</span>
				</Link>

				<nav aria-label="Primary navigation" className="hidden items-center gap-6 lg:flex">
					{NAV.map((item) => (
						<Link key={item.href} href={item.href} className="sb-link">
							{item.label}
						</Link>
					))}
				</nav>

				<button
					type="button"
					onClick={() => setOpen((v) => !v)}
					className="flex h-11 w-11 items-center justify-center rounded-full border-[3px] border-[var(--sb-ink)] bg-white text-ink lg:hidden"
					aria-label="Toggle navigation menu"
					aria-expanded={open}
					aria-controls="mobile-site-nav"
				>
					<svg
						className="size-6"
						fill="none"
						stroke="currentColor"
						viewBox="0 0 24 24"
						aria-hidden="true"
					>
						<title>{open ? "Close menu" : "Open menu"}</title>
						<path
							strokeLinecap="round"
							strokeLinejoin="round"
							strokeWidth={2.5}
							d={open ? "M6 18L18 6M6 6l12 12" : "M4 6h16M4 12h16M4 18h16"}
						/>
					</svg>
				</button>
			</div>

			{open && (
				<nav
					id="mobile-site-nav"
					aria-label="Mobile primary navigation"
					className="border-t-[3px] border-[var(--sb-ink)] bg-[var(--sb-bg)] lg:hidden"
				>
					<div className="home-shell flex flex-col gap-1 py-3">
						{NAV.map((item) => (
							<Link
								key={item.href}
								href={item.href}
								onClick={() => setOpen(false)}
								className="sb-link"
							>
								{item.label}
							</Link>
						))}
					</div>
				</nav>
			)}
		</header>
	);
}
