import { useState } from "react";
import { SHARE_URL } from "./share";

/**
 * Shared "copy jpthecat.com to the clipboard" state for the homepage
 * demo's {@link SharePopup} (`components/site/demo-dialogs.tsx`). It previously reimplemented the
 * identical `copied` flag + clipboard write; this hook is the single source so they can't drift.
 */
export function useCopyLink() {
	const [copied, setCopied] = useState(false);
	async function copyLink() {
		try {
			await navigator.clipboard.writeText(SHARE_URL);
			setCopied(true);
		} catch {
			setCopied(false);
		}
	}
	return { copied, copyLink };
}
