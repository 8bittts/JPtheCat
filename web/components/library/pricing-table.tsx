import { LIBRARY_EFFORT_CHIP_TONE } from "@/components/site/effort-tone";
import { usdPerMTok } from "@/lib/library/content/shared";
import type { ModelId } from "@/lib/library/pricing-data";
import {
	MODEL_DISPLAY_NAME,
	modelEffortLevel,
	modelEffortLevelLabel,
	perMillion,
	pricing,
} from "@/lib/library/pricing-registry";

interface Row {
	label: string;
	value?: number;
	text?: string;
	hint?: string;
}

export function PricingTable({ id }: { id: ModelId }) {
	const p = pricing(id);
	const splitWrites =
		p.cache_creation_input_token_cost !== p.cache_creation_input_token_cost_above_1hr;
	const effort = modelEffortLevel(id);
	const threshold = `${p.context_tier_inclusive ? "≥" : ">"}${(p.context_tier_threshold ?? 200_000) / 1000}K context`;
	const splitTierWrites =
		p.cache_creation_input_token_cost_above_200k_tokens !==
		p.cache_creation_input_token_cost_above_1hr_above_200k_tokens;

	const rows: Row[] = [
		{
			label: "Effort",
			text: effort ? modelEffortLevelLabel(effort) : undefined,
			hint: "qualitative reasoning depth",
		},
		{ label: "Input", value: p.input_cost_per_token, hint: "per 1M tokens" },
		{ label: "Output", value: p.output_cost_per_token },
		{
			label: splitWrites ? "Cache write · 5-minute" : "Cache write",
			value: p.cache_creation_input_token_cost,
			hint: "per 1M tokens",
		},
		{
			label: "Cache write · 1-hour",
			value: splitWrites ? p.cache_creation_input_token_cost_above_1hr : undefined,
			hint: "per 1M tokens",
		},
		{ label: "Cache read", value: p.cache_read_input_token_cost, hint: "per 1M tokens" },
		{
			label: `Input · ${threshold}`,
			value: p.input_cost_per_token_above_200k_tokens,
		},
		{
			label: `Output · ${threshold}`,
			value: p.output_cost_per_token_above_200k_tokens,
		},
		{
			label: `${splitTierWrites ? "Cache write · 5-minute" : "Cache write"} · ${threshold}`,
			value: p.cache_creation_input_token_cost_above_200k_tokens,
		},
		{
			label: `Cache write · 1-hour · ${threshold}`,
			value: splitTierWrites
				? p.cache_creation_input_token_cost_above_1hr_above_200k_tokens
				: undefined,
		},
		{
			label: `Cache read · ${threshold}`,
			value: p.cache_read_input_token_cost_above_200k_tokens,
		},
	];
	const shown = rows.filter((row) => row.value !== undefined || row.text !== undefined);

	return (
		<table className="sb-table">
			<caption className="sr-only">
				{MODEL_DISPLAY_NAME[id]} price per million tokens in USD
			</caption>
			<thead>
				<tr>
					<th scope="col">Token rate</th>
					<th scope="col" className="text-right">
						USD / 1M tokens
					</th>
				</tr>
			</thead>
			<tbody>
				{shown.map((row) => (
					<tr key={row.label}>
						<td>
							{row.label}
							{row.hint ? <span className="sb-small ml-2 opacity-70">{row.hint}</span> : null}
						</td>
						<td className="tnum text-right font-semibold">
							{row.value === undefined && row.text ? (
								<span className={effort ? LIBRARY_EFFORT_CHIP_TONE[effort] : undefined}>
									{row.text}
								</span>
							) : row.value === undefined ? null : (
								usdPerMTok(perMillion(row.value))
							)}
						</td>
					</tr>
				))}
			</tbody>
		</table>
	);
}
