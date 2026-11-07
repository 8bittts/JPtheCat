import Foundation

/// Fetches Grok Bot's official weekly included usage from Cursor's dashboard API.
///
/// The ONLY data sent is the Grok Bot app's sign-in token as a Bearer header to `api2.cursor.sh` —
/// the same host Grok Bot and Cursor use for plan meters. Request bodies are empty JSON objects.
public struct GrokBotPlanUsageClient: Sendable {
	public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

	private let transport: Transport

	public init(transport: Transport? = nil) {
		self.transport = transport ?? { request in
			try await URLSession.shared.data(for: request)
		}
	}

	public enum FetchError: Error, Equatable {
		case noToken
		case unauthorized
		case undecodable
		case transport
	}

	public func fetch(
		token: String, now: Date = Date(), previous: GrokBotPlanUsage? = nil
	) async throws -> GrokBotPlanUsage {
		let sandResponse = try? await call(CursorPlanUsageClient.grokBotMethod, token: token)
		let planInfo = try? await call(CursorPlanUsageClient.planInfoMethod, token: token)
		guard let sand = sandResponse else {
			if let previous {
				return previous.carryingOver(from: previous, sandFailed: true, now: now)
			}
			throw FetchError.transport
		}
		guard let usage = GrokBotPlanUsage.decode(sand: sand, planInfo: planInfo, fetchedAt: now)
		else { throw FetchError.undecodable }
		return usage.carryingOver(from: previous, sandFailed: false, now: now)
	}

	private func call(_ method: String, token: String) async throws -> Data {
		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await transport(CursorPlanUsageClient.request(method, token: token))
		} catch {
			throw FetchError.transport
		}
		let status = (response as? HTTPURLResponse)?.statusCode ?? 0
		switch status {
		case 200: return data
		case 401, 403: throw FetchError.unauthorized
		default: throw FetchError.transport
		}
	}
}
