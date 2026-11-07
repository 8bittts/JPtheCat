import { Head } from "@react-email/components";

// The one <head> for every JP email shell: pin the light scheme so dark clients
// cannot invert the pinned-light surfaces, and carry the shell's own dark-mode
// re-assertion CSS (Apple Mail media query + Outlook.com [data-ogsc]/[data-ogsb]).
export function EmailHead({ css }: { css: string }) {
	return (
		<Head>
			<meta content="light" name="color-scheme" />
			<meta content="light" name="supported-color-schemes" />
			<meta content="width=device-width, initial-scale=1" name="viewport" />
			<meta name="x-apple-disable-message-reformatting" />
			{/** biome-ignore lint/security/noDangerouslySetInnerHtml: static, non-user CSS. */}
			<style dangerouslySetInnerHTML={{ __html: css }} type="text/css" />
		</Head>
	);
}
