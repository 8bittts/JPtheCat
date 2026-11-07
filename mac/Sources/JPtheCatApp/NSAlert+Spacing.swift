import AppKit

extension NSAlert {
	/// Plain `messageText`/`informativeText` convenience — AppKit's own native layout, no custom
	/// spacing hack.
	///
	/// NSAlert's icon/title/body layout is undocumented AppKit-internal geometry. A leading-newline or
	/// `accessoryView`-body hack has broken it before — verify visually against a real alert before
	/// reintroducing either. Plain native `informativeText` (a little tight, never broken) is the safe
	/// default.
	convenience init(jpTitle: String, jpMessage: String) {
		self.init()
		messageText = jpTitle
		informativeText = jpMessage
	}
}
