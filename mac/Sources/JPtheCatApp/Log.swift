import OSLog

enum Log {
	static let subsystem = "com.8bittts.jpthecat"

	enum Category: String {
		case updater
		case usage
		case api
	}

	// Kept as named logger entry points for the category-scoped OSLog contract.
	static let updater = Logger(subsystem: subsystem, category: Category.updater.rawValue)
	static let usage = Logger(subsystem: subsystem, category: Category.usage.rawValue)
	static let api = Logger(subsystem: subsystem, category: Category.api.rawValue)
}
