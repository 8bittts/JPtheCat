import Link from "next/link";
import { usdPerMTok } from "@/lib/library/content/shared";
import { pricingCaveat } from "@/lib/library/pricing-provenance";
import {
	isModelPricingEligible,
	MODEL_DISPLAY_NAME,
	MODEL_SLUG,
	modelsForVendor,
	type PricingVendor,
	perMillion,
	pricing,
} from "@/lib/library/pricing-registry";

export function VendorModelsTable({ vendor }: { vendor: PricingVendor }) {
	const models = modelsForVendor(vendor);
	return (
		<div className="mt-8 overflow-x-auto">
			<table className="sb-table min-w-[520px]">
				<thead>
					<tr>
						<th scope="col" className="pr-3">
							Model
						</th>
						<th scope="col" className="px-3 text-right">
							Input (USD / 1M)
						</th>
						<th scope="col" className="px-3 text-right">
							Output (USD / 1M)
						</th>
						<th scope="col" className="px-3 text-right">
							Cache read (USD / 1M)
						</th>
					</tr>
				</thead>
				<tbody>
					{models.map((id) => {
						const p = pricing(id);
						const cacheRead = p.cache_read_input_token_cost;
						return (
							<tr key={id}>
								<td className="pr-3">
									{isModelPricingEligible(id) ? (
										<Link href={`/library/pricing/${MODEL_SLUG[id]}`} className="sb-text-link">
											{MODEL_DISPLAY_NAME[id]}
										</Link>
									) : (
										MODEL_DISPLAY_NAME[id]
									)}
									{pricingCaveat(id) ? (
										<p className="sb-small mt-1 opacity-70">{pricingCaveat(id)}</p>
									) : null}
								</td>
								<td className="tnum px-3 text-right">
									{usdPerMTok(perMillion(p.input_cost_per_token))}
								</td>
								<td className="tnum px-3 text-right">
									{usdPerMTok(perMillion(p.output_cost_per_token))}
								</td>
								<td className="tnum px-3 text-right">
									{cacheRead === undefined ? "—" : usdPerMTok(perMillion(cacheRead))}
								</td>
							</tr>
						);
					})}
				</tbody>
			</table>
		</div>
	);
}
