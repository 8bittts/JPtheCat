import type { KeyboardEvent } from "react";

// One Tab focus-trap for the demo and download native `<dialog>` modals. Keeps Tab / Shift+Tab cycling
// inside the open dialog across its FULL focusable set. This was copy-pasted across 5 modals in two
// files and had diverged — one copy trapped only `<button>`, so a modal's (readOnly) inputs and links
// fell outside the trap and Tab could escape the dialog. Attach as `onKeyDown={trapDialogTab}` on the
// `<dialog>` element.
const FOCUSABLE_SELECTOR =
	'a[href], button, input, select, textarea, [tabindex]:not([tabindex="-1"])';

export function trapDialogTab(e: KeyboardEvent<HTMLDialogElement>) {
	if (e.key !== "Tab") return;
	const dialog = e.currentTarget;
	const focusable = Array.from(dialog.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)).filter(
		// Skip disabled / removed-from-tab-order / visually-hidden elements so the cycle only lands on
		// things the user can actually focus.
		(el) => !el.hasAttribute("disabled") && el.tabIndex !== -1 && el.getClientRects().length > 0,
	);
	if (focusable.length === 0) {
		// A dialog with nothing focusable still must not leak focus to the page behind it.
		e.preventDefault();
		dialog.focus();
		return;
	}
	const first = focusable[0];
	const last = focusable[focusable.length - 1];
	if (e.shiftKey && document.activeElement === first) {
		e.preventDefault();
		last.focus();
	} else if (!e.shiftKey && document.activeElement === last) {
		e.preventDefault();
		first.focus();
	}
}
