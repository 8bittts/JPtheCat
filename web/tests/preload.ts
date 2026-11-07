// Tests must never inherit real provider credentials from the login shell.
for (const name of Object.keys(process.env)) {
	if (/(?:API_KEY|_TOKEN|_SECRET|SECRET_KEY|_PASSWORD|SERVICE_ROLE_KEY)$/.test(name)) {
		delete process.env[name];
	}
}
