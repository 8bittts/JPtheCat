import { HOMEBREW_INSTALL_COMMANDS } from "@/lib/homebrew";

export function HomebrewInstallCallout() {
	return (
		<div className="mt-4 border-t-[3px] border-dashed border-[var(--sb-dot)] pt-4 text-left">
			<p className="sb-dialog-fine">
				Prefer Homebrew? Install the same signed, notarized app from JP's public tap.
			</p>
			<pre className="sb-code-block">
				<code>{HOMEBREW_INSTALL_COMMANDS.join("\n")}</code>
			</pre>
			<a
				href="https://github.com/8bittts/homebrew-jpthecat"
				target="_blank"
				rel="noopener noreferrer"
				className="sb-text-link sb-meta mt-2 inline-block"
			>
				View and verify the tap
			</a>
		</div>
	);
}
