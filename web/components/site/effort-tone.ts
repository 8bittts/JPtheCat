import type { ModelEffortLevel } from "@/lib/library/pricing-registry";

/**
 * Effort chip colors, mirrored from the app's `ProviderDetailView` chip: Low and Medium sit on paper
 * behind a hairline, and High carries the honey wash with ginger-deep text. The homepage demo and
 * `/library` share this map so one tier never reads in two palettes; each surface keeps its own chip
 * geometry (`demo-badge` mirrors the native 17px label, library tables use the larger pill).
 */
export const EFFORT_CHIP_TONE: Record<ModelEffortLevel, string> = {
	low: "border-line bg-paper-2/80 text-ink-soft",
	medium: "border-line bg-paper/95 text-ink-soft",
	high: "border-honey/75 bg-honey/18 text-ginger-deep",
};

/** Sticker Bomb effort chips for `/library` and other public marketing tables. */
export const LIBRARY_EFFORT_CHIP_TONE: Record<ModelEffortLevel, string> = {
	low: "sb-effort-chip sb-effort-chip--low",
	medium: "sb-effort-chip sb-effort-chip--medium",
	high: "sb-effort-chip sb-effort-chip--high",
};
