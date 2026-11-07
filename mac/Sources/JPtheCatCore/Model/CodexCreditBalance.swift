import CoreFoundation
import Foundation

/// Codex's last reported credit balance. Credits are neither dollars nor subscription headroom.
public struct CodexCreditBalance: Codable, Sendable, Equatable {
	public let hasCredits: Bool?
	public let unlimited: Bool?
	public let balance: Double?

	public init(hasCredits: Bool? = nil, unlimited: Bool? = nil, balance: Double? = nil) {
		self.hasCredits = hasCredits
		self.unlimited = unlimited
		self.balance = balance.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
	}

	init?(json: Any?) {
		guard let raw = json as? [String: Any] else { return nil }
		func flag(_ key: String) -> Bool? {
			guard let value = raw[key] as? NSNumber,
				CFGetTypeID(value) == CFBooleanGetTypeID()
			else { return nil }
			return value.boolValue
		}
		let amount: Double?
		if let text = raw["balance"] as? String {
			amount = Double(text)
		} else if let number = raw["balance"] as? NSNumber,
			CFGetTypeID(number) != CFBooleanGetTypeID()
		{
			amount = number.doubleValue
		} else {
			amount = nil
		}
		self.init(hasCredits: flag("has_credits"), unlimited: flag("unlimited"), balance: amount)
		guard hasCredits != nil || unlimited != nil || balance != nil else { return nil }
	}

	/// Round down for display so a small balance never promises more credit than was reported.
	public var displayValue: String {
		if unlimited == true { return "Unlimited" }
		if let balance {
			if balance > 0 && balance < 0.01 { return "<0.01" }
			let formatter = NumberFormatter()
			formatter.locale = Locale(identifier: "en_US")
			formatter.numberStyle = .decimal
			formatter.maximumFractionDigits = 2
			formatter.roundingMode = .down
			return formatter.string(from: NSNumber(value: balance)) ?? String(balance)
		}
		if hasCredits == false { return "None available" }
		return hasCredits == true ? "Available · balance not reported" : "Not reported"
	}

	private enum CodingKeys: String, CodingKey {
		case hasCredits = "has_credits"
		case unlimited, balance
	}
}
