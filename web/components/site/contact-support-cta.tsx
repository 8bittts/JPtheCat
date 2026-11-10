"use client";

import Image from "next/image";
import { type FormEvent, type MouseEvent, useEffect, useId, useRef, useState } from "react";
import { trapDialogTab } from "@/lib/dialog-focus-trap";
import { SITE } from "@/lib/site";

type SendState = "idle" | "sending" | "sent" | "error";

// The one plain-English boilerplate the `/api/support-report` route requires every report to start
// with — the same endpoint the native app's support-report sender posts to (see
// `mac/Sources/JPtheCatApp/SupportReportClient.swift`), just without any app/device technical block,
// since a web visitor has none of that to disclose.
function buildReport(message: string) {
	const lines = [
		"JP the Cat support report",
		"Source: Contact page (jpthecat.com/contact)",
		`Message: ${message || "(no message provided)"}`,
	];
	return lines.join("\n");
}

export function ContactSupportCta() {
	const [email, setEmail] = useState("");
	const [message, setMessage] = useState("");
	const [state, setState] = useState<SendState>("idle");
	const dialogRef = useRef<HTMLDialogElement>(null);
	const emailInputRef = useRef<HTMLInputElement>(null);
	const sentRef = useRef<HTMLDivElement>(null);
	const sendingRef = useRef(false);
	const titleId = useId();
	const descId = useId();

	// Mirror the download modal's sibling behavior: once the report is sent, move focus to the
	// confirmation panel so a screen-reader user lands on the result instead of a stale form field.
	useEffect(() => {
		if (state === "sent") sentRef.current?.focus();
	}, [state]);

	// Clear a prior send failure the moment the user edits the form again, so a stale error banner
	// never sits over a fresh attempt (the download modal clears its own error the same way).
	function clearErrorOnEdit() {
		if (state === "error") setState("idle");
	}

	function open() {
		setState("idle");
		setEmail("");
		setMessage("");
		dialogRef.current?.showModal();
		window.setTimeout(() => emailInputRef.current?.focus(), 0);
	}

	function close() {
		dialogRef.current?.close();
	}

	async function handleSubmit(event: FormEvent<HTMLFormElement>) {
		event.preventDefault();
		if (sendingRef.current) return;
		sendingRef.current = true;
		setState("sending");
		try {
			const response = await fetch("/api/support-report", {
				method: "POST",
				headers: { "Content-Type": "application/json" },
				body: JSON.stringify({
					contact_email: email.trim() || undefined,
					message: message.trim() || undefined,
					report: buildReport(message.trim()),
				}),
			});
			if (!response.ok) throw new Error("Support report failed");
			setState("sent");
		} catch {
			setState("error");
		} finally {
			sendingRef.current = false;
		}
	}

	function handleDialogClick(event: MouseEvent<HTMLDialogElement>) {
		if (event.target === dialogRef.current) close();
	}

	return (
		<>
			<button type="button" onClick={open} className="sb-btn sb-btn--small">
				Get Support
			</button>
			<dialog
				ref={dialogRef}
				aria-labelledby={titleId}
				aria-describedby={descId}
				onClose={() => setState("idle")}
				onClick={handleDialogClick}
				onKeyDown={trapDialogTab}
				className="dialog-panel dialog-panel-lg dialog-panel-sb p-4"
			>
				{state === "sent" ? (
					<div
						ref={sentRef}
						role="status"
						aria-live="polite"
						tabIndex={-1}
						className="outline-none"
					>
						<div className="flex items-start gap-2.5">
							<Image
								src="/jpthecat-logo.png"
								alt=""
								width={40}
								height={40}
								className="compact-radius"
								unoptimized
							/>
							<div>
								<h3 className="sb-ui-title">Sent — thanks!</h3>
								<p className="sb-ui-copy mt-0.5">JP's human will follow up from {SITE.email}.</p>
							</div>
						</div>
						<div className="mt-3.5 flex justify-end">
							<button type="button" onClick={close} className="sb-btn sb-btn--small">
								Done
							</button>
						</div>
					</div>
				) : (
					<form onSubmit={handleSubmit}>
						<div className="flex items-start gap-2.5">
							<Image
								src="/jpthecat-logo.png"
								alt=""
								width={40}
								height={40}
								className="compact-radius"
								unoptimized
							/>
							<div>
								<h3 id={titleId} className="sb-ui-title">
									Get support
								</h3>
								<p id={descId} className="sb-ui-copy mt-0.5">
									JP emails {SITE.email}. Your email is optional, but helps JP reply.
								</p>
							</div>
						</div>
						<div className="mt-3 space-y-2">
							<label className="block">
								<span className="sb-ui-label mb-1 block">Your email (optional)</span>
								<input
									ref={emailInputRef}
									type="email"
									value={email}
									onChange={(event) => {
										setEmail(event.target.value);
										clearErrorOnEdit();
									}}
									placeholder="you@example.com"
									autoComplete="email"
									className="sb-form-control"
								/>
							</label>
							<label className="block">
								<span className="sb-ui-label mb-1 block">What happened? (optional)</span>
								<textarea
									value={message}
									onChange={(event) => {
										setMessage(event.target.value);
										clearErrorOnEdit();
									}}
									placeholder="Add context if you want."
									className="sb-form-control sb-form-control--textarea"
								/>
							</label>
							{state === "error" ? (
								<p role="alert" className="sb-ui-label sb-ui-label--alert">
									That didn't go through — try again, or email {SITE.email} directly.
								</p>
							) : null}
						</div>
						<div className="mt-3.5 flex justify-end gap-2">
							<button type="button" onClick={close} className="sb-btn-ghost">
								Cancel
							</button>
							<button
								type="submit"
								disabled={state === "sending"}
								className="sb-btn sb-btn--small disabled:opacity-60"
							>
								{state === "sending" ? "Sending…" : "Send"}
							</button>
						</div>
					</form>
				)}
			</dialog>
		</>
	);
}
