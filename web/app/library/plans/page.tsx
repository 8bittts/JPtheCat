import { SectionHub } from "@/components/library/section-hub";
import { sectionHubMetadata } from "@/lib/library/metadata";

export const metadata = sectionHubMetadata("plans");

export default function Page() {
	return <SectionHub slug="plans" />;
}
