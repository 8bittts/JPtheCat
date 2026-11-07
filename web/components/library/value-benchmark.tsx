import Link from "next/link";
import { LIBRARY_EFFORT_CHIP_TONE } from "@/components/site/effort-tone";
import { formatUsd } from "@/lib/library/content/shared";
import { modelEffortLevelLabel } from "@/lib/library/pricing-registry";
import {
	BENCHMARK_CACHE_READ_K,
	BENCHMARK_INPUT_K,
	BENCHMARK_OUTPUT_K,
	bestValueByEffort,
	topValueBenchmarkRows,
	type ValueBenchmarkRow,
} from "@/lib/library/value-benchmark";

function EffortChip({ effort }: { effort: ValueBenchmarkRow["effort"] }) {
	return (
		<span className={`sb-meta ${LIBRARY_EFFORT_CHIP_TONE[effort]}`}>
			{modelEffortLevelLabel(effort)}
		</span>
	);
}

function ModelCell({ row }: { row: ValueBenchmarkRow }) {
	const name = row.pricingHref ? (
		<Link href={row.pricingHref} className="sb-text-link font-medium">
			{row.displayName}
		</Link>
	) : (
		<span className="font-medium">{row.displayName}</span>
	);
	return (
		<div className="flex flex-col gap-0.5">
			{name}
			<span className="sb-meta opacity-75">{row.vendorLabel}</span>
		</div>
	);
}

export function LibraryValueBenchmark() {
	const leaders = topValueBenchmarkRows(8);
	const picks = bestValueByEffort();

	return (
		<section className="sb-panel" aria-labelledby="library-value-benchmark-title">
			<p className="sb-page-kicker mb-2">Value benchmark</p>
			<h2 id="library-value-benchmark-title" className="sb-section-title">
				Best bang for the buck
			</h2>
			<p className="sb-body sb-body--measure mt-3 opacity-90">
				Ranked from JP the Cat&apos;s bundled model pricing table using a standard coding-agent
				session — {BENCHMARK_INPUT_K}K input, {BENCHMARK_OUTPUT_K}K output, and{" "}
				{BENCHMARK_CACHE_READ_K}K cache-read tokens — then divided by qualitative effort (high /
				medium / low); models without an effort label are not ranked. Higher effort at lower session
				cost wins. Every non-Claude figure is notional list price, not subscription spend.
			</p>

			<div className="mt-6 grid gap-3 sm:grid-cols-3">
				{(["high", "medium", "low"] as const).map((effort) => {
					const pick = picks[effort];
					if (!pick) return null;
					return (
						<div
							key={effort}
							className="rounded-[16px] border-[3px] border-[var(--sb-ink)] bg-[var(--sb-bg)] px-4 py-3 shadow-[4px_4px_0_var(--sb-ink)]"
						>
							<p className="sb-small mb-1 opacity-70">Best {effort} effort</p>
							<p className="sb-section-title sb-section-title--xs">
								{pick.pricingHref ? (
									<Link href={pick.pricingHref} className="sb-text-link">
										{pick.displayName}
									</Link>
								) : (
									pick.displayName
								)}
							</p>
							<p className="sb-small tnum mt-1 opacity-85">
								{formatUsd(pick.sessionCostUsd)} / session
								{pick.notional ? " · notional" : ""}
							</p>
						</div>
					);
				})}
			</div>

			<div className="mt-6 overflow-x-auto">
				<table className="sb-table min-w-[640px]">
					<caption className="sr-only">
						Top models ranked by effort-adjusted value per standard coding session
					</caption>
					<thead>
						<tr>
							<th scope="col" className="w-10 pr-3">
								#
							</th>
							<th scope="col" className="pr-3">
								Model
							</th>
							<th scope="col" className="px-3">
								Effort
							</th>
							<th scope="col" className="px-3 text-right">
								Session cost
							</th>
							<th scope="col" className="pl-3 text-right">
								Basis
							</th>
						</tr>
					</thead>
					<tbody>
						{leaders.map((row) => (
							<tr key={row.id}>
								<td className="tnum pr-3 opacity-70">{row.rank}</td>
								<td className="pr-3">
									<ModelCell row={row} />
								</td>
								<td className="px-3">
									<EffortChip effort={row.effort} />
								</td>
								<td className="tnum px-3 text-right font-semibold">
									{formatUsd(row.sessionCostUsd)}
								</td>
								<td className="sb-small pl-3 text-right opacity-80">
									{row.notional ? "Notional" : "Real"}
								</td>
							</tr>
						))}
					</tbody>
				</table>
			</div>

			<p className="sb-small mt-4 opacity-75">
				See{" "}
				<Link href="/library/glossary/blended-cost-per-mtok" className="sb-text-link">
					blended $/MTok
				</Link>{" "}
				or{" "}
				<Link href="/library/calculators/tokens-to-dollars" className="sb-text-link">
					tokens-to-dollars
				</Link>{" "}
				to model your own mix.
			</p>
		</section>
	);
}
