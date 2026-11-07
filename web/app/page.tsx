import { headers } from "next/headers";
import { Footer } from "@/components/site/footer";
import { Nav } from "@/components/site/nav";
import { StickerHome } from "@/components/sticker/home";
import { homeJsonLd, jsonLdText } from "@/lib/home-json-ld";

export default async function Home() {
	const headerList = await headers();
	const nonce = headerList.get("x-nonce") ?? undefined;
	const structuredData = jsonLdText(homeJsonLd());
	return (
		<>
			<script nonce={nonce} type="application/ld+json" suppressHydrationWarning>
				{structuredData}
			</script>
			<Nav />
			<main id="main-content">
				<StickerHome />
			</main>
			<Footer />
		</>
	);
}
