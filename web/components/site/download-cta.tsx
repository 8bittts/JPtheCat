"use client";

import Link from "next/link";
import { type ComponentProps, type MouseEvent, type ReactNode, useId, useRef } from "react";
import { trackProductEvent } from "@/lib/analytics/product-analytics";
import { trapDialogTab } from "@/lib/dialog-focus-trap";

type DownloadCtaProps = Omit<ComponentProps<typeof Link>, "href" | "onClick"> & {
	children: ReactNode;
	href: string;
	source: "pricing" | "library";
};

export function DownloadCta({ children, href, source, ...props }: DownloadCtaProps) {
	const dialogRef = useRef<HTMLDialogElement>(null);
	const closeRef = useRef<HTMLButtonElement>(null);
	const titleId = useId();
	const descriptionId = useId();
	const downloadHref = `${href}?source=${source}`;

	// pSEO (/library) downloads emit distinctly-named events (and a `channel` property) so SEO-driven
	// downloads are unmistakable from homepage downloads in Vercel Web Analytics.
	const isLibrary = source === "library";
	const channel = isLibrary ? "library" : "home";
	const clickEvent = isLibrary ? "library_download_cta_clicked" : "download_cta_clicked";
	const modalOpenEvent = isLibrary ? "library_download_modal_opened" : "download_modal_opened";

	// Start the DMG download WITHOUT navigating away. /download is same-origin and 302s to the notarized
	// DMG (served as an attachment), so an anchor click downloads the file and leaves the page intact.
	function startDownload() {
		const anchor = document.createElement("a");
		anchor.href = downloadHref;
		anchor.rel = "noopener";
		document.body.appendChild(anchor);
		anchor.click();
		anchor.remove();
	}

	function handleDownloadClick(event: MouseEvent<HTMLAnchorElement>) {
		trackProductEvent(clickEvent, { href, source, channel });
		// A modified click (open-in-new-tab / save-as) keeps the browser's native behaviour.
		if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
			return;
		}
		event.preventDefault();
		// The download ALWAYS starts on the first click; the note below only confirms it.
		startDownload();
		if (!dialogRef.current?.showModal) {
			return;
		}
		if (!dialogRef.current.open) {
			dialogRef.current.showModal();
		}
		window.setTimeout(() => closeRef.current?.focus(), 0);
		trackProductEvent(modalOpenEvent, { source, channel });
	}

	// Light-dismiss: a click on the <dialog> element itself is a backdrop click.
	function handleDialogClick(event: MouseEvent<HTMLDialogElement>) {
		if (event.target === dialogRef.current) {
			dialogRef.current?.close();
		}
	}

	return (
		<>
			<Link
				{...props}
				href={downloadHref}
				prefetch={false}
				data-analytics-event={clickEvent}
				data-analytics-source={source}
				data-analytics-channel={channel}
				onClick={handleDownloadClick}
			>
				{children}
			</Link>
			<dialog
				ref={dialogRef}
				aria-describedby={descriptionId}
				aria-labelledby={titleId}
				onClick={handleDialogClick}
				onKeyDown={trapDialogTab}
				className="dialog-panel dialog-panel-lg dialog-panel-sb"
			>
				<div className="rounded-lg border-[3px] border-[var(--sb-ink)] bg-[var(--sb-white)] p-5 shadow-[4px_4px_0_var(--sb-ink)]">
					<div>
						<p className="sb-page-kicker mb-2">Your download is on the way</p>
						<h2 id={titleId} className="sb-dialog-title">
							JP is on her way to your Mac!
						</h2>
						<p id={descriptionId} className="sb-dialog-body mt-3">
							Check the Downloads folder for the DMG, then drag JP the Cat into Applications.
						</p>
						<form method="dialog" className="mt-5 grid gap-3">
							<button ref={closeRef} type="submit" className="sb-btn sb-btn--small w-full">
								Got it
							</button>
							<p className="sb-dialog-fine text-center">
								Download didn't start?{" "}
								<a href={downloadHref} className="sb-text-link">
									Download it directly
								</a>
								.
							</p>
						</form>
					</div>
				</div>
			</dialog>
		</>
	);
}
