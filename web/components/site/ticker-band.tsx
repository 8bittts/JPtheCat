/**
 * The app's full-width animated basis-label ticker band (the web twin of the native
 * `TickerTapeText`), with edge fades. Extracted into its own leaf module so both the menu-bar demo
 * card (`menubar-demo.tsx`) and the Advanced Analytics demo (`advanced-analytics-demo.tsx`) can share
 * it without an import cycle (menubar-demo → demo-dialogs → advanced-analytics-demo).
 */
export function TickerBand({ text }: { text: string }) {
	const seq = `${text}      ·      `;
	return (
		<div
			className="relative h-[18px] overflow-hidden rounded-[5px] border border-line/80 bg-paper-2"
			style={{
				maskImage: "linear-gradient(90deg, transparent, #000 9%, #000 84%, transparent)",
				WebkitMaskImage: "linear-gradient(90deg, transparent, #000 9%, #000 84%, transparent)",
			}}
		>
			<div className="demo-ticker absolute top-0 left-0 flex h-full items-center whitespace-nowrap">
				{/* two identical halves so a -50% translate loops seamlessly */}
				<span className="demo-chip flex pl-1.5">
					{seq}
					{seq}
					{seq}
				</span>
				<span className="demo-chip flex pl-1.5" aria-hidden="true">
					{seq}
					{seq}
					{seq}
				</span>
			</div>
		</div>
	);
}
