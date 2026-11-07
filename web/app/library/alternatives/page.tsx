import { SectionHub } from "@/components/library/section-hub";
import { sectionHubMetadata } from "@/lib/library/metadata";

export const metadata = sectionHubMetadata("alternatives");

export default function Page() {
	return <SectionHub slug="alternatives" />;
}
