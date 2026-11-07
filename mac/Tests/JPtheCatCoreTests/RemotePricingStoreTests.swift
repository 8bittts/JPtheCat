import XCTest

@testable import JPtheCatCore

/// The remote pricing layer is **fail-closed**: it may only ever *improve* on the bundled defaults,
/// never regress them to `$0`/unpriced because a fetch hiccuped. These tests pin every branch of that
/// contract — `304`, network error, malformed/empty body — plus the ETag round-trip and the
/// bundled→remote merge semantics.
final class RemotePricingStoreTests: XCTestCase {
	func testDefaultFeedIsIsolatedFromLegacyContextSemantics() {
		XCTAssertEqual(RemotePricingStore.defaultRemoteURL.absoluteString, "https://jpthecat.com/stable/pricing-v1.json")
	}

	func testBundledFeedMeetsTheCurrentPricingRevision() throws {
		let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let body = try Data(contentsOf: root.appendingPathComponent("Sources/JPtheCatCore/Resources/pricing-default.json"))
		XCTAssertEqual(RemotePricingStore.minimumPricingRevision, 2)
		let table = try XCTUnwrap(RemotePricingStore.decodeTable(body))
		XCTAssertEqual(table.price(for: "claude-sonnet-5-5")?.cacheReadInputTokenCost, 1e-7)
		XCTAssertEqual(table.price(for: "claude-haiku-5-5")?.contextTierThreshold, 100_000)
	}

	func testContextThresholdValidation() throws {
		for threshold in [0, -1, 10_000_000] {
			let data = Data("{\"pricing_revision\":2,\"models\":{\"test\":{\"input_cost_per_token\":0.000001,\"output_cost_per_token\":0.000002,\"context_tier_threshold\":\(threshold)}}}".utf8)
			XCTAssertNil(RemotePricingStore.decodeTable(data))
		}
		let data = Data(#"{"pricing_revision":2,"models":{"test":{"input_cost_per_token":0.000001,"output_cost_per_token":0.000002,"context_tier_threshold":256000}}}"#.utf8)
		XCTAssertEqual(try XCTUnwrap(RemotePricingStore.decodeTable(data)?.price(for: "test")).contextTierThreshold, 256000)
	}

	/// A remote table can add an alias for a newly emitted id without an app release, but only onto a
	/// row that exists; a dangling or free-tier alias rejects the whole body so the cache stays intact.
	func testRemoteAliasesMergeAndDanglingAliasesAreRejected() async throws {
		let accepted = Data(#"{"pricing_revision":2,"aliases":{"grok-4.8-build":"grok-4.7"},"models":{"grok-4.7":{"input_cost_per_token":0.000002,"output_cost_per_token":0.000006}}}"#.utf8)
		let temp = makeTempCache()
		let store = RemotePricingStore(
			fetcher: MockPricingFetcher([.success(.updated(data: accepted, etag: "v2"))]),
			cacheURL: temp.cacheURL, etagURL: temp.etagURL)
		XCTAssertNil(store.resolvedTable().price(for: "grok-4.8-build"))
		let refreshed = await store.refresh()
		let merged = try XCTUnwrap(refreshed)
		XCTAssertEqual(merged.price(for: "grok-4.8-build")?.inputCostPerToken, 0.000002)
		XCTAssertEqual(merged.price(for: "grok-4.6-build")?.cacheReadInputTokenCost, 5e-7, "bundled aliases survive the merge")
		XCTAssertEqual(store.resolvedTable().price(for: "grok-4.8-build")?.inputCostPerToken, 0.000002)

		for aliases in [
			#"{"a":"no-such-row"}"#, #"{"x-free":"grok-4.7"}"#, #"{"Grok-4.8-Build":"grok-4.7"}"#,
			#"{"xai/grok-4.8-build":"grok-4.7"}"#, #"{"grok-4.8-build-20261001":"grok-4.7"}"#,
		] {
			let body = Data(#"{"pricing_revision":2,"aliases":\#(aliases),"models":{"grok-4.7":{"input_cost_per_token":0.000002,"output_cost_per_token":0.000006}}}"#.utf8)
			XCTAssertNil(RemotePricingStore.decodeTable(body), aliases)
		}
	}

	/// A running app re-checks the hosted table daily, not only at launch: an app launched before a feed
	/// update kept showing a newly priced model as unpriced until it was relaunched.
	func testRunningAppRechecksTheHostedTableDaily() {
		let launch = Date(timeIntervalSince1970: 1_790_000_000)
		XCTAssertTrue(RemotePricingRefreshPolicy.isDue(lastAttempt: nil, now: launch), "launch fetches")
		XCTAssertFalse(RemotePricingRefreshPolicy.isDue(lastAttempt: launch, now: launch.addingTimeInterval(60)))
		XCTAssertFalse(RemotePricingRefreshPolicy.isDue(
			lastAttempt: launch, now: launch.addingTimeInterval(RemotePricingRefreshPolicy.interval - 1)))
		XCTAssertTrue(RemotePricingRefreshPolicy.isDue(
			lastAttempt: launch, now: launch.addingTimeInterval(RemotePricingRefreshPolicy.interval)))
		XCTAssertTrue(RemotePricingRefreshPolicy.isDue(lastAttempt: launch, now: launch.addingTimeInterval(-60)),
			"a clock moved backwards must not stall the check")
		XCTAssertEqual(RemotePricingRefreshPolicy.interval, 86_400)
	}

	/// A later feed may turn a row this build still bundles into an alias. The bundled row keeps
	/// pricing that id, and the rest of the feed must still apply rather than being rejected whole.
	func testRemoteAliasOverABundledRowDoesNotRejectTheFeed() throws {
		let body = Data(#"{"pricing_revision":2,"aliases":{"gemini-3":"gemini-3-pro-preview"},"models":{"grok-4.7":{"input_cost_per_token":0.000003,"output_cost_per_token":0.000006}}}"#.utf8)
		let remote = try XCTUnwrap(RemotePricingStore.decodeTable(body))
		let merged = PricingTable.bundledDefault().merging(remote)
		XCTAssertEqual(merged.price(for: "grok-4.7")?.inputCostPerToken, 0.000003)
		XCTAssertEqual(merged.price(for: "gemini-3")?.inputCostPerToken, 2e-6)
	}

	func testOldRemoteCannotUndoBundledCorrections() async throws {
		let temp = makeTempCache()
		try FileManager.default.createDirectory(at: temp.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		let old = Data(#"{"models":{"gpt-6-astra":{"input_cost_per_token":0.00001,"output_cost_per_token":0.00005}}}"#.utf8)
		try old.write(to: temp.cacheURL)
		try Data("old-etag".utf8).write(to: temp.etagURL)
		let fetcher = MockPricingFetcher([.success(.updated(data: old, etag: "old-etag"))])
		let store = RemotePricingStore(fetcher: fetcher, cacheURL: temp.cacheURL, etagURL: temp.etagURL)
		XCTAssertEqual(store.resolvedTable().price(for: "gpt-6-astra")?.contextTierThreshold, 272_000)
		let result = await store.refresh()
		XCTAssertNil(result)
		XCTAssertEqual(fetcher.receivedETags.count, 1)
		XCTAssertNil(fetcher.receivedETags[0], "An incompatible cached table must force a full GET")
	}

	func testRevisionOneSonnetCacheCannotOverrideCorrectedBundledPrice() async throws {
		let temp = makeTempCache()
		try FileManager.default.createDirectory(at: temp.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		let old = Data(#"{"pricing_revision":1,"models":{"claude-sonnet-5-5":{"input_cost_per_token":0.000002,"output_cost_per_token":0.00001,"cache_read_input_token_cost":0.0000002}}}"#.utf8)
		try old.write(to: temp.cacheURL)
		try Data("stale-sonnet".utf8).write(to: temp.etagURL)
		let fetcher = MockPricingFetcher([.success(.updated(data: old, etag: "stale-sonnet"))])
		let store = RemotePricingStore(fetcher: fetcher, cacheURL: temp.cacheURL, etagURL: temp.etagURL)
		XCTAssertEqual(store.resolvedTable().price(for: "claude-sonnet-5-5")?.cacheReadInputTokenCost, 1e-7)
		let result = await store.refresh()
		XCTAssertNil(result, "An older feed must not restore Sonnet's previous cache price")
		XCTAssertEqual(fetcher.receivedETags.count, 1)
		XCTAssertNil(fetcher.receivedETags[0], "The stale ETag must not cause a 304")
	}

	// MARK: - Fixtures

	/// A scripted fetcher — consumes responses in order (last repeats), and records every ETag it was
	/// asked to send so we can prove the conditional GET carries the stored tag. `@unchecked Sendable`
	/// with no lock: the store calls `fetch` strictly serially (each `refresh()` is awaited before the
	/// next), so the mutable cursor is never touched concurrently.
	private final class MockPricingFetcher: PricingFetcher, @unchecked Sendable {
		private let responses: [Result<PricingFetchResult, Error>]
		private var callIndex = 0
		private(set) var receivedETags: [String?] = []

		init(_ responses: [Result<PricingFetchResult, Error>]) { self.responses = responses }

		func fetch(etag: String?) async throws -> PricingFetchResult {
			receivedETags.append(etag)
			let response = responses[min(callIndex, responses.count - 1)]
			callIndex += 1
			switch response {
			case let .success(value): return value
			case let .failure(error): throw error
			}
		}
	}

	private struct TempCache {
		let cacheURL: URL
		let etagURL: URL
	}

	private func makeTempCache() -> TempCache {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("jpc-remoteprice-\(UUID().uuidString)", isDirectory: true)
		return TempCache(
			cacheURL: dir.appendingPathComponent("pricing-remote.json"),
			etagURL: dir.appendingPathComponent("pricing-remote.etag"))
	}

	/// A remote body that OVERRIDES an existing bundled model and ADDS a brand-new one, so a single
	/// fixture proves both merge directions at once.
	private func body(overriddenInputPerToken: Double) -> Data {
		let json = """
			{"pricing_revision":2,"models":{
			  "claude-opus-4-5":{"input_cost_per_token":\(overriddenInputPerToken),"output_cost_per_token":0.00009},
			  "jp-fresh-model":{"input_cost_per_token":0.000001,"output_cost_per_token":0.000002}
			}}
			"""
		return Data(json.utf8)
	}

	// MARK: - resolvedTable (synchronous, no network)

	func testResolvedTableIsBundledWhenNoCacheExists() {
		let temp = makeTempCache()
		let store = RemotePricingStore(
			fetcher: MockPricingFetcher([.success(.notModified)]),
			cacheURL: temp.cacheURL, etagURL: temp.etagURL)

		let resolved = store.resolvedTable()
		let bundled = PricingTable.bundledDefault()
		XCTAssertFalse(bundled.knownModels.isEmpty, "bundled default must load — the fail-closed floor")
		XCTAssertEqual(
			resolved.knownModels, bundled.knownModels,
			"with no cache, resolvedTable is exactly the bundled table")
	}

	// MARK: - 200 → persist + merge + hot-swap table

	func test200UpdatesPersistsAndMergesOverBundled() async throws {
		let temp = makeTempCache()
		let bundled = PricingTable.bundledDefault()
		let bundledOverridden = try XCTUnwrap(
			bundled.price(for: "claude-opus-4-5"), "fixture assumes this model ships in the bundled table")
		let newInput = bundledOverridden.inputCostPerToken * 3 + 1e-9  // deliberately different

		let store = RemotePricingStore(
			fetcher: MockPricingFetcher([.success(.updated(data: body(overriddenInputPerToken: newInput), etag: "\"v1\""))]),
			cacheURL: temp.cacheURL, etagURL: temp.etagURL)

		let refreshed = await store.refresh()
		let updated = try XCTUnwrap(refreshed, "a valid 200 must return a new merged table")

		// Remote override wins for its model…
		let overridden = try XCTUnwrap(updated.price(for: "claude-opus-4-5"))
		XCTAssertEqual(overridden.inputCostPerToken, newInput, accuracy: 1e-15)
		// …the remote-only model is now priced…
		XCTAssertNotNil(updated.price(for: "jp-fresh-model"), "remote-only model must be added")
		// …and a bundled-only model the remote never mentioned is still priced (merge, not replace).
		let bundledOnly = try XCTUnwrap(
			bundled.knownModels.subtracting(["claude-opus-4-5"]).first, "need a second bundled model")
		XCTAssertNotNil(
			updated.price(for: bundledOnly), "merge must preserve bundled models absent from the remote")

		// Persistence: a fresh store over the same cache reads the override with NO network.
		let reopened = RemotePricingStore(
			fetcher: MockPricingFetcher([.failure(RemotePricingError.http(status: 500))]),
			cacheURL: temp.cacheURL, etagURL: temp.etagURL)
		let persisted = try XCTUnwrap(reopened.resolvedTable().price(for: "jp-fresh-model"))
		XCTAssertEqual(persisted.inputCostPerToken, 0.000001, accuracy: 1e-15)
		XCTAssertTrue(FileManager.default.fileExists(atPath: temp.etagURL.path), "ETag sidecar must be written")
	}

	// MARK: - 304 → keep cache, send the stored ETag

	func test304KeepsCacheAndSendsStoredETag() async throws {
		let temp = makeTempCache()
		let fetcher = MockPricingFetcher([
			.success(.updated(data: body(overriddenInputPerToken: 0.00005), etag: "\"etag-A\"")),  // seed
			.success(.notModified),  // then unchanged
		])
		let store = RemotePricingStore(fetcher: fetcher, cacheURL: temp.cacheURL, etagURL: temp.etagURL)

		let seed = await store.refresh()
		XCTAssertNotNil(seed, "seed fetch")
		let second = await store.refresh()

		XCTAssertNil(second, "304 must return nil — no hot-swap")
		XCTAssertNotNil(
			store.resolvedTable().price(for: "jp-fresh-model"), "cache survives a 304")
		XCTAssertEqual(fetcher.receivedETags.first ?? "", nil, "first GET has no prior ETag")
		XCTAssertEqual(
			fetcher.receivedETags.last, "\"etag-A\"", "the conditional GET must send the stored ETag")
	}

	// MARK: - fail-closed: malformed / empty / network error never touch the cache

	func testMalformedBodyKeepsPreviousCache() async throws {
		let temp = makeTempCache()
		let store = RemotePricingStore(
			fetcher: MockPricingFetcher([
				.success(.updated(data: body(overriddenInputPerToken: 0.00005), etag: "\"good\"")),
				.success(.updated(data: Data("{ not json".utf8), etag: "\"bad\"")),
			]),
			cacheURL: temp.cacheURL, etagURL: temp.etagURL)

		let seed = await store.refresh()
		XCTAssertNotNil(seed, "seed a good cache")
		let bad = await store.refresh()

		XCTAssertNil(bad, "a malformed body must not hot-swap")
		XCTAssertNotNil(
			store.resolvedTable().price(for: "jp-fresh-model"),
			"the last good override survives a malformed follow-up")
	}

	func testEmptyModelsRejected() async {
		let temp = makeTempCache()
		let store = RemotePricingStore(
			fetcher: MockPricingFetcher([.success(.updated(data: Data(#"{"pricing_revision":2,"models":{}}"#.utf8), etag: "\"empty\""))]),
			cacheURL: temp.cacheURL, etagURL: temp.etagURL)

		let result = await store.refresh()
		XCTAssertNil(result, "an empty table must be rejected so it can't wipe every price to unpriced")
		XCTAssertFalse(
			FileManager.default.fileExists(atPath: temp.cacheURL.path), "empty body must not be persisted")
		XCTAssertEqual(
			store.resolvedTable().knownModels, PricingTable.bundledDefault().knownModels,
			"still exactly bundled after a rejected empty body")
	}

	func testNetworkErrorReturnsNilAndKeepsCache() async throws {
		let temp = makeTempCache()
		let store = RemotePricingStore(
			fetcher: MockPricingFetcher([
				.success(.updated(data: body(overriddenInputPerToken: 0.00005), etag: "\"good\"")),
				.failure(RemotePricingError.http(status: 503)),
			]),
			cacheURL: temp.cacheURL, etagURL: temp.etagURL)

		let seed = await store.refresh()
		XCTAssertNotNil(seed, "seed a good cache")
		let errored = await store.refresh()

		XCTAssertNil(errored, "a thrown fetch must fail-closed to nil")
		XCTAssertNotNil(
			store.resolvedTable().price(for: "jp-fresh-model"), "cache survives a network error")
	}

	// MARK: - URLSessionPricingFetcher header mapping (via a stub URLProtocol)

	func testURLSessionFetcherMapsStatusAndETag() async throws {
		StubURLProtocol.reset()
		let config = URLSessionConfiguration.ephemeral
		config.protocolClasses = [StubURLProtocol.self]
		let session = URLSession(configuration: config)
		let url = URL(string: "https://jpthecat.test/stable/pricing.json")!
		let fetcher = URLSessionPricingFetcher(url: url, session: session)

		// 200 → .updated carrying the response ETag.
		StubURLProtocol.responder = { _ in
			(200, ["ETag": "\"srv-1\""], Data(#"{"pricing_revision":2,"models":{}}"#.utf8))
		}
		guard case let .updated(_, etag) = try await fetcher.fetch(etag: nil) else {
			return XCTFail("200 must map to .updated")
		}
		XCTAssertEqual(etag, "\"srv-1\"", "ETag header must be surfaced")

		// 304 → .notModified, and the If-None-Match we passed must reach the server.
		StubURLProtocol.responder = { request in
			XCTAssertEqual(
				request.value(forHTTPHeaderField: "If-None-Match"), "\"srv-1\"",
				"the prior ETag must be sent as If-None-Match")
			return (304, [:], Data())
		}
		guard case .notModified = try await fetcher.fetch(etag: "\"srv-1\"") else {
			return XCTFail("304 must map to .notModified")
		}

		// 404 → thrown, so the store fails closed.
		StubURLProtocol.responder = { _ in (404, [:], Data()) }
		do {
			_ = try await fetcher.fetch(etag: nil)
			XCTFail("a non-2xx status must throw")
		} catch {
			// expected
		}
	}
}

/// Minimal in-process HTTP stub so the real `URLSessionPricingFetcher` can be exercised without a
/// server. `responder` maps a request to `(status, headers, body)`.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
	nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> (Int, [String: String], Data))?

	static func reset() { responder = nil }

	override class func canInit(with request: URLRequest) -> Bool { true }
	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		guard let responder = StubURLProtocol.responder, let url = request.url else {
			client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
			return
		}
		let (status, headers, body) = responder(request)
		let response = HTTPURLResponse(
			url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: body)
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}
}
