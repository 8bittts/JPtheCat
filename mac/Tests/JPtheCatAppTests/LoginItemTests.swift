import ServiceManagement
import XCTest

@testable import JPtheCatApp

final class LoginItemTests: XCTestCase {
	func testIsEnabledUsesSystemStatusAsSourceOfTruth() {
		XCTAssertTrue(LoginItem.isEnabled(service: FakeLoginItemService(status: .enabled)))
		XCTAssertFalse(LoginItem.isEnabled(service: FakeLoginItemService(status: .notRegistered)))
		XCTAssertFalse(LoginItem.isEnabled(service: FakeLoginItemService(status: .requiresApproval)))
		XCTAssertFalse(LoginItem.isEnabled(service: FakeLoginItemService(status: .notFound)))
	}

	func testSetEnabledRegistersAndReportsSuccess() {
		let service = FakeLoginItemService(status: .notRegistered)

		XCTAssertTrue(LoginItem.setEnabled(true, service: service))

		XCTAssertEqual(service.registerCallCount, 1)
		XCTAssertEqual(service.unregisterCallCount, 0)
	}

	func testSetDisabledUnregistersAndReportsSuccess() {
		let service = FakeLoginItemService(status: .enabled)

		XCTAssertTrue(LoginItem.setEnabled(false, service: service))

		XCTAssertEqual(service.registerCallCount, 0)
		XCTAssertEqual(service.unregisterCallCount, 1)
	}

	func testSetEnabledIsIdempotentForMatchingSystemState() {
		let enabledService = FakeLoginItemService(status: .enabled)
		let disabledService = FakeLoginItemService(status: .notRegistered)

		XCTAssertTrue(LoginItem.setEnabled(true, service: enabledService))
		XCTAssertTrue(LoginItem.setEnabled(false, service: disabledService))

		XCTAssertEqual(enabledService.registerCallCount, 0)
		XCTAssertEqual(enabledService.unregisterCallCount, 0)
		XCTAssertEqual(disabledService.registerCallCount, 0)
		XCTAssertEqual(disabledService.unregisterCallCount, 0)
	}

	func testSetEnabledReturnsFalseWhenServiceThrows() {
		let service = FakeLoginItemService(status: .notFound)
		service.registerError = LoginItemTestError.registerFailed

		XCTAssertFalse(LoginItem.setEnabled(true, service: service))

		XCTAssertEqual(service.registerCallCount, 1)
	}

	func testFailureReasonAttemptsRegistrationEvenFromNotFoundAndSurfacesTheError() {
		// `.notFound` must NOT be treated as a dead-end: we still attempt to register, and a thrown
		// error is surfaced (not swallowed) so the UI can show the real cause.
		let service = FakeLoginItemService(status: .notFound)
		service.registerError = NSError(
			domain: "SMAppServiceErrorDomain", code: 1,
			userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])

		let reason = LoginItem.failureReason(settingEnabled: true, service: service)

		XCTAssertEqual(service.registerCallCount, 1)
		XCTAssertEqual(reason, "Operation not permitted")
	}

	func testFailureReasonIsNilOnSuccess() {
		let service = FakeLoginItemService(status: .notRegistered)
		XCTAssertNil(LoginItem.failureReason(settingEnabled: true, service: service))
		XCTAssertEqual(service.registerCallCount, 1)
	}

	func testSetEnabledAndReadBackUsesSystemStatusAfterRegistrationAttempt() {
		let service = FakeLoginItemService(status: .notRegistered)
		service.statusAfterRegister = .requiresApproval

		XCTAssertFalse(LoginItem.setEnabledAndReadBack(true, service: service))
		XCTAssertEqual(service.registerCallCount, 1)

		service.status = .notRegistered
		service.statusAfterRegister = .enabled

		XCTAssertTrue(LoginItem.setEnabledAndReadBack(true, service: service))
		XCTAssertEqual(service.registerCallCount, 2)
	}

	func testStatusDescriptionExplainsSystemState() {
		XCTAssertEqual(
			LoginItem.statusDescription(service: FakeLoginItemService(status: .enabled)),
			"On")
		XCTAssertEqual(
			LoginItem.statusDescription(service: FakeLoginItemService(status: .requiresApproval)),
			"Needs approval in System Settings")
		// `.notFound` is treated as an attemptable "Off", not a misleading "unavailable" dead-end.
		XCTAssertEqual(
			LoginItem.statusDescription(service: FakeLoginItemService(status: .notFound)),
			"Off")
		XCTAssertEqual(
			LoginItem.statusDescription(service: FakeLoginItemService(status: .notRegistered)),
			"Off")
	}
}

private final class FakeLoginItemService: LoginItemServicing {
	var status: SMAppService.Status
	var registerCallCount = 0
	var unregisterCallCount = 0
	var registerError: Error?
	var unregisterError: Error?
	var statusAfterRegister: SMAppService.Status?
	var statusAfterUnregister: SMAppService.Status?

	init(status: SMAppService.Status) {
		self.status = status
	}

	func register() throws {
		registerCallCount += 1
		if let registerError { throw registerError }
		if let statusAfterRegister { status = statusAfterRegister }
	}

	func unregister() throws {
		unregisterCallCount += 1
		if let unregisterError { throw unregisterError }
		if let statusAfterUnregister { status = statusAfterUnregister }
	}
}

private enum LoginItemTestError: Error {
	case registerFailed
}
