import Image from "next/image";
import { PurrOnHover } from "@/components/site/purr-on-hover";
import { SITE } from "@/lib/site";

// JP's hero portrait. PurrOnHover plays /meow.m4a on pointerenter, on tap (pointerdown), and on
// keyboard focus; it de-duplicates bursts of enter events, primes audio on the first gesture,
// and swallows autoplay rejections, so a blocked play is silent instead of throwing.
export function MeowCat() {
	return (
		<PurrOnHover trigger="hero-jp" className="sb-catwrap">
			<button type="button" className="sb-cat" aria-label={`Pet ${SITE.mascot} — plays her meow`}>
				<Image
					src={SITE.photo}
					alt={`${SITE.mascot}, a tortoiseshell cat, sitting on a pink bed`}
					width={1170}
					height={1522}
					priority
					sizes="(max-width: 640px) 64vw, 360px"
				/>
			</button>
			<span className="sb-meow-bubble" aria-hidden="true">
				<span className="sb-trim">meow!</span>
			</span>
		</PurrOnHover>
	);
}
