import { Resend } from "resend";

let resendClient: Resend | null = null;

export function getResendClient() {
	if (!process.env.RESEND_API_KEY) {
		return null;
	}
	if (!resendClient) {
		resendClient = new Resend(process.env.RESEND_API_KEY);
	}
	return resendClient;
}
