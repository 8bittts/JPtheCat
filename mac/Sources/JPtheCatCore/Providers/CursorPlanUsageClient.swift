import Foundation

/// Finds the Cursor sign-in token that Cursor itself stored on this Mac, for the opt-in plan-usage
/// fetch ONLY.
///
/// [HARD REQUIREMENT] Read-only, and only after the user opts in. Two sources, in order:
/// 1. The Cursor app's `state.vscdb`, key `cursorAuth/accessToken` only. The query projects that one
///    key; no chat, composer, or workspace row is read.
/// 2. The Cursor CLI's login item (service `cursor-access-token`), read through `/usr/bin/security`.
///    Cursor's item trusts that tool, so the read never raises a macOS password prompt, and JP
///    never opens another app's Keychain item through the Security framework directly.
/// JP never uses Cursor's refresh token: refreshing would rotate Cursor's own session. An expired
/// token means "no reading" until Cursor signs in again.
public enum CursorAuthToken {
	public static let keychainService = "cursor-access-token"
	public static let keychainAccount = "cursor-user"
	static let stateDatabaseKey = "cursorAuth/accessToken"

	public static func stateDatabaseURL(
		home: URL = FileManager.default.homeDirectoryForCurrentUser
	) -> URL {
		home.appendingPathComponent(
			"Library/Application Support/Cursor/User/globalStorage/state.vscdb", isDirectory: false)
	}

	/// True when Cursor (app or CLI) is installed and could hold a sign-in. Reads no secret.
	public static func isSourcePresent(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
		FileManager.default.fileExists(atPath: stateDatabaseURL(home: home).path)
			|| CursorHookSetup.isCursorCLIDetected()
	}

	/// The first unexpired token, app database first. Nil when neither source has one.
	public static func load(
		now: Date = Date(),
		stateDatabase: URL? = nil,
		keychain: () -> String? = readKeychainToken
	) -> String? {
		if let token = readStateDatabaseToken(at: stateDatabase ?? stateDatabaseURL()),
			isUsable(token, now: now)
		{
			return token
		}
		if let token = keychain(), isUsable(token, now: now) { return token }
		return nil
	}

	static func readStateDatabaseToken(at url: URL) -> String? {
		guard FileManager.default.fileExists(atPath: url.path),
			let db = try? SQLiteDatabase(readOnlyPath: url.path),
			let stmt = try? db.prepare("SELECT value FROM ItemTable WHERE key = ?1 LIMIT 1")
		else { return nil }
		stmt.bind(1, stateDatabaseKey)
		guard (try? stmt.step()) == true else { return nil }
		return stmt.text(0).map(trimmedToken)
	}

	public static func readKeychainToken() -> String? {
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

	/// A JWT whose `exp` is still ahead. Decodes the payload only; the signature is Cursor's to check.
	static func isUsable(_ token: String, now: Date) -> Bool {
		guard let exp = expiry(of: token) else { return false }
		return exp > now
	}

	static func expiry(of token: String) -> Date? {
		let parts = token.split(separator: ".")
		guard parts.count == 3 else { return nil }
		var payload = String(parts[1])
			.replacingOccurrences(of: "-", with: "+")
			.replacingOccurrences(of: "_", with: "/")
		payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
		guard let data = Data(base64Encoded: payload),
			let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
			let exp = JSONNumber.double(object["exp"])
		else { return nil }
		return Date(timeIntervalSince1970: exp)
	}
}

/// Fetches Cursor's official plan usage from Cursor's own dashboard API.
///
/// The ONLY data sent is the Cursor sign-in token, as a Bearer header, to `api2.cursor.sh` — the
/// host Cursor's own app and CLI use. Request bodies are empty JSON objects. Nothing about local
/// usage, prompts, code, paths, or JP's license leaves the Mac in these calls.
public struct CursorPlanUsageClient: Sendable {
	public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

	public static let baseURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/")!
	static let currentPeriodMethod = "GetCurrentPeriodUsage"
	static let grokBotMethod = "GetSandUsageStatus"
	static let planInfoMethod = "GetPlanInfo"

	public enum FetchError: Error, Equatable {
		case noToken
		case unauthorized
		case http(Int)
		case undecodable
		case transport
	}

	private let transport: Transport

	public init(transport: Transport? = nil) {
		self.transport = transport ?? { request in
			try await URLSession.shared.data(for: request)
		}
	}

	/// Fetches all three responses. The plan meters are required; Grok Bot and plan name are
	/// best-effort, so an account without Grok Bot still gets its plan meters.
	///
	/// When a best-effort call FAILS (network or HTTP error, as opposed to answering "no access"),
	/// the still-current Grok Bot meter and plan name from `previous` carry over, so one dropped
	/// request cannot blank a meter until the next fetch.
	public func fetch(
		token: String, now: Date = Date(), previous: CursorPlanUsage? = nil,
		allowEmptyEntitlement: Bool = false
	) async throws -> CursorPlanUsage {
		async let periodResponse = callResult(Self.currentPeriodMethod, token: token)
		async let grokBotResponse = try? call(Self.grokBotMethod, token: token)
		async let planInfoResponse = try? call(Self.planInfoMethod, token: token)
		let periodResult = await periodResponse
		let grokBot = await grokBotResponse
		let planInfo = await planInfoResponse
		let period: Data
		switch periodResult {
		case .success(let data): period = data
		case .failure(let error):
			guard grokBot != nil else { throw error }
			period = Data("{}".utf8)
		}
		guard let usage = CursorPlanUsage.decode(
			currentPeriod: period, grokBot: grokBot, planInfo: planInfo, fetchedAt: now)
		else {
			// Only an explicit successful "no included limit" plus a valid monthly response can
			// remove all cached pools. A malformed/failed response must not erase a good reading.
			if allowEmptyEntitlement, case .success = periodResult,
				(try? JSONSerialization.jsonObject(with: period)) is [String: Any],
				let grokBot, let sand = (try? JSONSerialization.jsonObject(with: grokBot)) as? [String: Any],
				sand["hasNonZeroIncludedLimit"] as? Bool == false {
				return CursorPlanUsage(planName: nil, isTeam: false, meters: [], fetchedAt: now)
			}
			throw FetchError.undecodable
		}
		return usage.carryingOver(
			from: previous, grokBotFailed: grokBot == nil, planNameFailed: planInfo == nil && grokBot == nil,
			now: now)
	}

	static func request(_ method: String, token: String) -> URLRequest {
		var request = URLRequest(url: baseURL.appendingPathComponent(method))
		request.httpMethod = "POST"
		request.timeoutInterval = 15
		request.cachePolicy = .reloadIgnoringLocalCacheData
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.httpBody = Data("{}".utf8)
		return request
	}

	private func callResult(_ method: String, token: String) async -> Result<Data, FetchError> {
		do { return .success(try await call(method, token: token)) }
		catch { return .failure((error as? FetchError) ?? .transport) }
	}

	private func call(_ method: String, token: String) async throws -> Data {
		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await transport(Self.request(method, token: token))
		} catch {
			throw FetchError.transport
		}
		let status = (response as? HTTPURLResponse)?.statusCode ?? 0
		switch status {
		case 200: return data
		case 401, 403: throw FetchError.unauthorized
		default: throw FetchError.http(status)
		}
	}
}
