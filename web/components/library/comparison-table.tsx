import type { CompareTable } from "@/lib/library/content/compare";

export function ComparisonTable({ headers, rows }: CompareTable) {
	return (
		<div className="mt-8 overflow-x-auto">
			<table className="sb-table min-w-[520px]">
				<thead>
					<tr>
						<th scope="col" className="pr-3">
							Attribute
						</th>
						{headers.map((header) => (
							<th key={header} scope="col" className="px-3">
								{header}
							</th>
						))}
					</tr>
				</thead>
				<tbody>
					{rows.map((row) => (
						<tr key={row.label} className="align-top">
							<th scope="row" className="pr-3 font-medium opacity-80">
								{row.label}
							</th>
							{row.values.map((value, valueIndex) => (
								<td key={headers[valueIndex]} className="px-3">
									{value}
								</td>
							))}
						</tr>
					))}
				</tbody>
			</table>
		</div>
	);
}
