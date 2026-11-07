// The menu-bar display cycle, shared by the demo card's dashboard face and its settings face. A
// NON-COMPONENT module because both faces need it and a `.tsx` file that exports components may
// export nothing else (react-doctor `only-export-components` / Fast Refresh).

import { ORDER, PROVIDERS } from "./menubar-demo-series";

// Mirrors the native `MenuBarDisplayFormat.selectable(...)` cycle: Total, then a DEDICATED
// Total + <provider> <window> and <provider> <window> entry for every official limit window OR a
// token-count fallback (Muse Spark, Copilot, Cursor), plus a rotating "Total + limit" / "Limit" entry when
// MORE THAN ONE window qualifies (the pill cycles windows). Adding a qualifying provider or window
// extends the cycle automatically, like the app.
type MenuBarFormat = { title: string; subtitle: string; rotating?: boolean };

function windowSuffix(official: boolean, windowMinutes: number): string {
	if (!official) return "";
	if (windowMinutes === 10_080) return " week";
	if (windowMinutes === 300) return " 5h";
	return "";
}

function providerFormatEntries(key: (typeof ORDER)[number]): {
	totalPlus: MenuBarFormat[];
	limitOnly: MenuBarFormat[];
} {
	const totalPlus: MenuBarFormat[] = [];
	const limitOnly: MenuBarFormat[] = [];
	// Short menu-bar name ("Claude", not "Claude Code"), matching `ProviderDescriptor.shortName`.
	const shortName = key === "claude" ? "Claude" : PROVIDERS[key].name;
	const provider = PROVIDERS[key];
	const officialWindows = (provider.windows ?? []).filter(
		(window) => window.official && window.resetsInMin > 0,
	);
	const windows =
		officialWindows.length > 0
			? officialWindows
			: provider.todayTokens > 0
				? [{ official: false, windowMinutes: 0 }]
				: [];
	for (const window of windows) {
		const windowedName = `${shortName}${windowSuffix(window.official, window.windowMinutes)}`;
		totalPlus.push({
			title: `Total + ${windowedName}`,
			subtitle: window.official ? "Today total + Limit %" : "Today total + tokens",
		});
		limitOnly.push({
			title: windowedName,
			subtitle: window.official ? "Limit % only" : "Today tokens",
		});
	}
	return { totalPlus, limitOnly };
}

function buildMenuBarFormats(): MenuBarFormat[] {
	const totalPlus: MenuBarFormat[] = [];
	const limitOnly: MenuBarFormat[] = [];
	for (const key of ORDER) {
		const entries = providerFormatEntries(key);
		totalPlus.push(...entries.totalPlus);
		limitOnly.push(...entries.limitOnly);
	}
	if (limitOnly.length > 1) {
		totalPlus.push({ title: "Total + limit", subtitle: "Today total + Limit %", rotating: true });
		limitOnly.push({ title: "Limit", subtitle: "Limit % only", rotating: true });
	}
	return [{ title: "Total", subtitle: "JP badge + today total" }, ...totalPlus, ...limitOnly];
}

export const MENU_BAR_FORMATS: ReadonlyArray<MenuBarFormat> = buildMenuBarFormats();

// A format is "rotating" when the pill cycles through providers (no single pinned provider) — the
// native twin is `MenuBarDisplayFormat.isRotating`. Mirrors the app's green top-chrome "on air"
// light: it gently pulses only while a rotating format is selected.
export const isRotatingFormat = (index: number) => MENU_BAR_FORMATS[index]?.rotating === true;
