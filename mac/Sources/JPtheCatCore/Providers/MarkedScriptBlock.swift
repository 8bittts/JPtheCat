import Foundation

/// The marked block JP writes into a user-owned shell file after an explicit opt-in: a begin
/// marker, JP's lines, an end marker. Removal is the one operation every such block shares, and
/// it must cut exactly JP's own text so the user's file returns to what it was.
enum MarkedScriptBlock {
	/// `script` without the marked block, the newline that ends it, and the blank lines JP added
	/// in front of it. A script that lacks either marker comes back unchanged.
	static func removing(from script: String, beginMarker: String, endMarker: String) -> String {
		guard
			let begin = script.range(of: beginMarker),
			let end = script.range(of: endMarker)
		else { return script }
		var lower = begin.lowerBound
		var upper = end.upperBound
		if upper < script.endIndex, script[upper] == "\n" { upper = script.index(after: upper) }
		while lower > script.startIndex {
			let prev = script.index(before: lower)
			if script[prev] == "\n" { lower = prev } else { break }
		}
		var out = script
		out.removeSubrange(lower..<upper)
		return out
	}
}
