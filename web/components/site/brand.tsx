import Image from "next/image";
import { SITE } from "@/lib/site";

// The official JP logo — a tortoiseshell cat on a gold badge. Rendered as an app-style tile.
export function BrandMark({
	size = 40,
	className = "",
	priority = false,
}: {
	size?: number;
	className?: string;
	priority?: boolean;
}) {
	return (
		<Image
			src={SITE.logo}
			alt="JP the cat"
			width={size}
			height={size}
			priority={priority}
			className={className}
		/>
	);
}
