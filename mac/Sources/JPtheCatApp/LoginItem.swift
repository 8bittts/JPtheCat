import OSLog
import ServiceManagement

protocol LoginItemServicing {
	var status: SMAppService.Status { get }

	func register() throws
	func unregister() throws
}

extension SMAppService: LoginItemServicing {}

enum LoginItem {
	private static let log = Logger(subsystem: "com.8bittts.jpthecat", category: "LoginItem")

	static func isEnabled(service: LoginItemServicing = SMAppService.mainApp) -> Bool {
		service.status == .enabled
	}

	/// Register/unregister the app as a login item. Returns `nil` on success, or the localized failure
	/// reason (also logged) so the UI can show the REAL cause instead of silently no-op'ing. macOS may
	/// report `.notFound` for a perfectly valid signed app when the Background Task Management database
	/// is confused by duplicate copies of the same bundle id — surfacing the thrown `NSError` is the
	/// only way to see that, so never swallow it.
	static func failureReason(
		settingEnabled enabled: Bool, service: LoginItemServicing = SMAppService.mainApp
	) -> String? {
		if isEnabled(service: service) == enabled { return nil }
		do {
			if enabled {
				try service.register()
			} else {
				try service.unregister()
			}
			return nil
		} catch {
			let ns = error as NSError
			log.error(
				"Launch-at-login \(enabled ? "register" : "unregister", privacy: .public) failed: \(ns.domain, privacy: .public) code=\(ns.code) — \(ns.localizedDescription, privacy: .public)"
			)
			return ns.localizedDescription
		}
	}

	@discardableResult
	static func setEnabled(_ enabled: Bool, service: LoginItemServicing = SMAppService.mainApp) -> Bool {
		failureReason(settingEnabled: enabled, service: service) == nil
	}

	static func setEnabledAndReadBack(_ enabled: Bool, service: LoginItemServicing = SMAppService.mainApp)
		-> Bool
	{
		_ = setEnabled(enabled, service: service)
		return isEnabled(service: service)
	}

	static func statusDescription(service: LoginItemServicing = SMAppService.mainApp) -> String {
		switch service.status {
		case .enabled:
			"On"
		case .requiresApproval:
			"Needs approval in System Settings"
		// `.notFound` is NOT a dead-end: a valid signed app can transiently report it, but `register()`
		// can still succeed and move it to `.enabled`/`.requiresApproval`. Treat it like "off, tap to
		// enable" and let a failed attempt surface the real reason — never claim "unavailable".
		case .notRegistered, .notFound:
			"Off"
		@unknown default:
			"Unknown"
		}
	}
}
