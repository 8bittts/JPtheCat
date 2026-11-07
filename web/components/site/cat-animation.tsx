import Image from "next/image";
import { preload } from "react-dom";
import { SITE } from "@/lib/site";
import { MascotVideo } from "./mascot-video";
import { PurrOnHover } from "./purr-on-hover";

/**
 * JP's animated mascot — a transparent-alpha loop. Motion users get the looping
 * video; anyone with `prefers-reduced-motion: reduce`, or a browser that can't
 * decode the sources, gets the static transparent poster instead
 * (WCAG 2.3.3 / 2.2.2). CSS swaps the visible poster, while `MascotVideo` also
 * withholds video sources under reduced motion so the loop is not downloaded.
 */
export function CatAnimation({
	size = 640,
	className = "",
}: {
	size?: number;
	className?: string;
}) {
	// The video poster is the motion user's largest paint, but `<video poster>` loads late and at
	// low priority, and the `priority` Image below preloads a different, optimized URL.
	preload(SITE.catAnim.poster, { as: "image", fetchPriority: "high" });

	return (
		<PurrOnHover trigger="mascot-animation" className={`relative ${className}`}>
			<MascotVideo
				size={size}
				webm={SITE.catAnim.webm}
				mp4={SITE.catAnim.mp4}
				poster={SITE.catAnim.poster}
			/>
			<Image
				src={SITE.catAnim.poster}
				alt="JP the cat"
				width={size}
				height={size}
				priority
				className="hidden h-full w-full object-contain motion-reduce:block"
			/>
		</PurrOnHover>
	);
}
