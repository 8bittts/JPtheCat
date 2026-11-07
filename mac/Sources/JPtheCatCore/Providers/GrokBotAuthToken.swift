import Foundation

/// Reads the Grok Bot desktop app's Cursor OAuth session for the opt-in plan-usage fetch ONLY.
///
/// [HARD REQUIREMENT] Read-only, and only after the user opts in. The access token is decrypted from
/// `~/Library/Application Support/Grok Bot/sand-secrets.json` using the login Keychain item
/// `Grok Bot Safe Storage` / `Grok Bot Key`, fetched through `/usr/bin/security` — the same pattern
/// as `CursorAuthToken`. JP never uses the refresh token and never writes `sand-secrets.json`.
public enum GrokBotAuthToken {
	public static let keychainService = "Grok Bot Safe Storage"
	public static let keychainAccount = "Grok Bot Key"
	public static let appSupportFolder = "Grok Bot"
	public static let secretsFileName = "sand-secrets.json"

	public static func appSupportURL(
		home: URL = FileManager.default.homeDirectoryForCurrentUser
	) -> URL {
		home.appendingPathComponent("Library/Application Support/\(appSupportFolder)", isDirectory: true)
	}

	public static func secretsURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
		appSupportURL(home: home).appendingPathComponent(secretsFileName)
	}

	/// True when the Grok Bot app has written its credential file. Reads no secret.
	public static func isSourcePresent(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
		FileManager.default.fileExists(atPath: secretsURL(home: home).path)
	}

	/// The first unexpired access token. Nil when the app is absent or the session cannot be opened.
	public static func load(
		now: Date = Date(),
		secretsFile: URL? = nil,
		keychainSecret: () -> String? = readKeychainSecret,
		decrypt: (([UInt8], String) -> Data?)? = nil
	) -> String? {
		let decryptBlob = decrypt ?? { ChromiumOSCrypt.decrypt(key: $0, valueBase64: $1) }
		guard let path = secretsFile ?? Optional(secretsURL()),
			FileManager.default.fileExists(atPath: path.path),
			let data = try? Data(contentsOf: path),
			let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let secret = keychainSecret()?.data(using: .utf8)
		else { return nil }
		let key = ChromiumOSCrypt.deriveKey(secret: secret)
		guard let accounts = parseAccounts(root) else { return nil }
		let active = (accounts["active"] as? String).flatMap { $0.isEmpty ? nil : $0 }
		guard let accountMap = accounts["accounts"] as? [String: Any] else { return nil }
		let accountID = active ?? accountMap.keys.sorted().first
		guard let accountID,
			let entry = accountMap[accountID] as? [String: Any],
			let encrypted = entry["cursor-access-token"] as? String,
			let plain = decryptBlob(key, encrypted),
			let token = String(data: plain, encoding: .utf8).map(trimmedToken),
			CursorAuthToken.isUsable(token, now: now)
		else { return nil }
		return token
	}

	/// `cursor-accounts` is a JSON object on Linux and a JSON string on macOS — accept both.
	static func parseAccounts(_ root: [String: Any]) -> [String: Any]? {
		guard let raw = root["cursor-accounts"] else { return nil }
		if let object = raw as? [String: Any] { return object }
		if let string = raw as? String,
			let data = string.data(using: .utf8),
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		{
			return object
		}
		return nil
	}

	public static func readKeychainSecret() -> String? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
		process.arguments = [
			"find-generic-password", "-s", keychainService, "-a", keychainAccount, "-w",
		]
		let output = Pipe()
		process.standardOutput = output
		process.standardError = FileHandle.nullDevice
		do { try process.run() } catch { return nil }
		let data = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else { return nil }
		return String(data: data, encoding: .utf8).map(trimmedToken)
	}

	private static func trimmedToken(_ raw: String) -> String {
		raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
	}
}
