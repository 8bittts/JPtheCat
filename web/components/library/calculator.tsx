"use client";

import { useId, useMemo, useState } from "react";
import { CALCULATOR_DEFAULTS, priceTokenMix } from "@/lib/library/calculator-math";
import type { CalcModel, CalculatorMode } from "@/lib/library/content/calculators";
import { formatUsd } from "@/lib/library/content/shared";

// Pure-React state math — no eval, no workers, CSP-safe. SSR renders the default worked example, so
// the page is non-thin and useful with JavaScript disabled (_docs/08-growth.md SEO guardrails).
export function Calculator({
	models,
	notional: entryNotional,
	mode = "session",
}: {
	models: CalcModel[];
	mode?: CalculatorMode;
	/** Whole-calculator notional flag (scenario/model entries); per-model notional wins when mixed. */
	notional: boolean;
}) {
	const [index, setIndex] = useState(0);
	const [inputK, setInputK] = useState(CALCULATOR_DEFAULTS[mode].input);
	const [outputK, setOutputK] = useState(CALCULATOR_DEFAULTS[mode].output);
	const [cacheK, setCacheK] = useState(CALCULATOR_DEFAULTS[mode].cacheRead);
	const [writeK, setWriteK] = useState(CALCULATOR_DEFAULTS[mode].cacheWrite);
	const selectId = useId();
	const model = models[Math.min(index, models.length - 1)];
	const notional = entryNotional || model.notional;

	const request = mode === "request";
	const { perRun, baseRun, tiered } = useMemo(() => {
		const mix = { input: inputK, output: outputK, cacheRead: cacheK, cacheWrite: writeK };
		const priced = priceTokenMix(model, mix, request);
		return {
			perRun: priced.cost,
			baseRun: priceTokenMix(model, mix, false).cost,
			tiered: priced.tiered,
		};
	}, [inputK, outputK, cacheK, writeK, model, request]);

	const fields = [
		{ id: "in", label: "Input tokens (K)", value: inputK, set: setInputK },
		{ id: "out", label: "Output tokens (K)", value: outputK, set: setOutputK },
		{ id: "cache", label: "Cache-read tokens (K)", value: cacheK, set: setCacheK },
		{ id: "write", label: "Cache-write tokens (K)", value: writeK, set: setWriteK },
	];

	return (
		<div className="sb-form-panel">
			{models.length > 1 ? (
				<div className="mb-4">
					<label htmlFor={selectId} className="sb-form-label">
						Model
					</label>
					<select
						id={selectId}
						aria-label="Model"
						value={index}
						onChange={(event) => setIndex(Number(event.target.value))}
						className="sb-form-control"
					>
						{models.map((option, optionIndex) => (
							<option key={option.id} value={optionIndex}>
								{option.label}
								{option.notional ? " (notional)" : ""}
							</option>
						))}
					</select>
				</div>
			) : null}

			<div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
				{fields.map((field) => (
					<div key={field.id}>
						<label htmlFor={field.id} className="sb-form-label">
							{field.label}
						</label>
						<input
							id={field.id}
							aria-label={field.label}
							type="number"
							min={0}
							inputMode="numeric"
							value={field.value}
							onChange={(event) => {
								const value = event.currentTarget.valueAsNumber;
								if (Number.isFinite(value)) field.set(value);
							}}
							className="sb-form-control"
						/>
					</div>
				))}
			</div>

			<div className="mt-6 flex flex-wrap items-baseline justify-between gap-2 border-t-[3px] border-dashed border-[var(--sb-dot)] pt-5">
				<div>
					<p className="sb-eyebrow mb-1">Estimated cost{notional ? " (notional)" : ""}</p>
					<p className="sb-money-figure tnum">{formatUsd(perRun)}</p>
				</div>
				{request ? (
					<p className="sb-dialog-body">
						{tiered
							? `Long-context rates apply; ${formatUsd(baseRun)} at base rates`
							: model.tier
								? `Below the ${Math.round((model.tier.lastBaseTokens + 1) / 1000)}K threshold; base rates apply`
								: "This model has no long-context surcharge"}
					</p>
				) : (
					<p className="sb-dialog-body">≈ {formatUsd(perRun * 30)} across 30 similar days</p>
				)}
			</div>
		</div>
	);
}
