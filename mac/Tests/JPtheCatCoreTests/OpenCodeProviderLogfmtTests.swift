import Foundation
import XCTest

@testable import JPtheCatCore

/// Pins `OpenCodeProvider.parseFields`'s exact logfmt handling — quoting, escapes, and malformed
/// input — so the rewrite from `Array(line)` (a `[Character]` copy at 16 bytes per grapheme) to a
/// byte-indexed scan over `line.utf8` cannot quietly change what a real `opencode.log` line decodes
/// to. Every case below was chosen because the two implementations could plausibly differ on it.
final class OpenCodeProviderLogfmtTests: XCTestCase {
	func testLogfmtParsingTable() {
		let cases: [(name: String, line: String, expected: [String: String])] = [
			(
				"plain pairs", "a=1 b=2 c=three",
				["a": "1", "b": "2", "c": "three"]
			),
			(
				"quoted value keeps its spaces", #"directory="/Users/e/My Project" tokens.input=7"#,
				["directory": "/Users/e/My Project", "tokens.input": "7"]
			),
			(
				"escaped quote inside a quoted value", #"title="say \"hi\" now" n=1"#,
				["title": #"say "hi" now"#, "n": "1"]
			),
			(
				"escaped backslash inside a quoted value", #"path="a\\b" n=1"#,
				["path": #"a\b"#, "n": "1"]
			),
			(
				"escape takes the next byte literally, whatever it is", #"v="a\nb\tc" n=1"#,
				["v": "anbtc", "n": "1"]
			),
			(
				"empty quoted value", #"v="" n=1"#,
				["v": "", "n": "1"]
			),
			(
				"unterminated quote runs to end of line", #"v="never closed"#,
				["v": "never closed"]
			),
			(
				"trailing lone backslash inside a quote stays literal", #"v="ends with \"#,
				["v": #"ends with \"#]
			),
			(
				"trailing key with no value", "a=1 b=",
				["a": "1", "b": ""]
			),
			(
				"bare token with no equals is skipped without eating the next field",
				"message a=1",
				["a": "1"]
			),
			(
				"repeated key keeps the last occurrence", "a=1 a=2",
				["a": "2"]
			),
			(
				"runs of spaces and leading/trailing space", "   a=1     b=2   ",
				["a": "1", "b": "2"]
			),
			(
				"empty line", "",
				[:]
			),
			(
				"only spaces", "     ",
				[:]
			),
			(
				"lone equals produces no key", "=value a=1",
				["a": "1"]
			),
			(
				"dotted keys survive", "tokens.cache.read=40 tokens.cache.write=50",
				["tokens.cache.read": "40", "tokens.cache.write": "50"]
			),
			(
				"multi-byte UTF-8 in an unquoted value", "project=café n=1",
				["project": "café", "n": "1"]
			),
			(
				"multi-byte UTF-8 in a quoted value", #"title="naïve — dash" n=1"#,
				["title": "naïve — dash", "n": "1"]
			),
			(
				"emoji-free non-ASCII key", "клюя=1",
				["клюя": "1"]
			),
			(
				"quote appearing mid-unquoted-value is not special", #"v=a"b n=1"#,
				[#"v"#: #"a"b"#, "n": "1"]
			),
			(
				"carriage return is part of the value, not a separator", "a=1\r",
				["a": "1\r"]
			),
		]

		for testCase in cases {
			XCTAssertEqual(
				OpenCodeProvider.parseFields(testCase.line), testCase.expected, testCase.name)
		}
	}

	/// The pre-rewrite `Array(line)` implementation, verbatim. Kept ONLY as the parity oracle below —
	/// production must never grow a second copy of this parser.
	private func referenceParseFields(_ line: String) -> [String: String] {
		var fields: [String: String] = [:]
		let chars = Array(line)
		var i = 0

		func skipSpaces() {
			while i < chars.count, chars[i] == " " { i += 1 }
		}

		while i < chars.count {
			skipSpaces()
			let keyStart = i
			while i < chars.count, chars[i] != "=", chars[i] != " " { i += 1 }
			guard i < chars.count, chars[i] == "=" else {
				while i < chars.count, chars[i] != " " { i += 1 }
				continue
			}
			let key = String(chars[keyStart..<i])
			i += 1

			let value: String
			if i < chars.count, chars[i] == "\"" {
				i += 1
				var out = ""
				while i < chars.count {
					let ch = chars[i]
					if ch == "\\" && i + 1 < chars.count {
						out.append(chars[i + 1])
						i += 2
						continue
					}
					if ch == "\"" {
						i += 1
						break
					}
					out.append(ch)
					i += 1
				}
				value = out
			} else {
				let valueStart = i
				while i < chars.count, chars[i] != " " { i += 1 }
				value = String(chars[valueStart..<i])
			}
			if !key.isEmpty { fields[key] = value }
		}

		return fields
	}

	/// The byte-indexed rewrite must agree with the original grapheme-indexed parser on every shape the
	/// table above covers, plus a fuzz corpus assembled from the delimiter bytes themselves.
	func testByteScanAgreesWithTheOriginalCharacterScan() {
		var corpus: [String] = [
			"", "   ", "a=1", "a=1 b=2", "message a=1", "=v a=1", "a=", "a=1 a=2",
			#"d="/Users/e/My Project" t=7"#, #"t="say \"hi\"" n=1"#, #"p="a\\b""#, #"v="""#,
			#"v="never closed"#, #"v="ends \"#, "project=café n=1", #"t="naïve — dash""#, "a=1\r",
			#"v=a"b n=1"#, "клюя=1 значение=2",
			#"timestamp=2026-07-07T01:02:03.456Z level=INFO run=r message=updated id=ses directory=/x model=meta/muse-spark-1.1 tokens.input=1 tokens.output=2"#,
		]
		// Deterministic fuzz: every 3-token permutation of delimiter-heavy fragments.
		let fragments = ["a=1", #"q="x y""#, #"e="a\"b""#, "bare", "=", #"""#, #"k="\"#, "  ", "z=", "\\"]
		for first in fragments {
			for second in fragments {
				for third in fragments { corpus.append("\(first) \(second) \(third)") }
			}
		}
		XCTAssertGreaterThan(corpus.count, 500, "fuzz corpus would be vacuous")
		for line in corpus {
			XCTAssertEqual(
				OpenCodeProvider.parseFields(line), referenceParseFields(line),
				"byte scan diverged from the original character scan on: \(line.debugDescription)")
		}
	}

	/// A realistic line still decodes to a real event through both providers' filters.
	func testRealisticLineStillDecodesThroughBothFilters() throws {
		let openCodeLine =
			#"timestamp=2026-07-07T01:02:03.456Z level=INFO run=run_1 message=updated id=ses_1 directory="/Users/e/My Project" model=google/gemini-3-pro-preview tokens.input=1000 tokens.output=200 tokens.reasoning=30 tokens.cache.read=40 tokens.cache.write=50"#
		let event = try XCTUnwrap(OpenCodeProvider.decode(line: openCodeLine))
		XCTAssertEqual(event.messageId, "ses_1")
		XCTAssertEqual(event.model, "gemini-3-pro-preview")
		XCTAssertEqual(event.project, "My Project")
		XCTAssertEqual(event.usage.input, 1_000)
		XCTAssertEqual(event.usage.output, 230)
		XCTAssertNil(MuseSparkProvider.decode(line: openCodeLine))

		let sparkLine = openCodeLine.replacingOccurrences(
			of: "model=google/gemini-3-pro-preview", with: "model=meta/muse-spark-1.1")
		let spark = try XCTUnwrap(MuseSparkProvider.decode(line: sparkLine))
		XCTAssertEqual(spark.provider, .museSpark)
		XCTAssertEqual(spark.model, "muse-spark-1.1")
		XCTAssertNil(
			OpenCodeProvider.decode(line: sparkLine), "muse-spark is owned by MuseSparkProvider")
	}

	/// `decode(line:)` must stay exactly `decode(fields: parseFields(line))` — the shared log traversal
	/// calls the field form directly, so a divergence there would make one provider's events differ
	/// depending on which entry point produced them.
	func testFieldAndLineEntryPointsAgree() throws {
		let line =
			#"timestamp=2026-07-07T01:02:03.456Z run=r id=ses_x model=meta/muse-spark-1.1 tokens.input=5 tokens.output=6"#
		let fields = OpenCodeProvider.parseFields(line)
		XCTAssertEqual(
			MuseSparkProvider.decode(fields: fields)?.messageId,
			MuseSparkProvider.decode(line: line)?.messageId)
		let openCodeLine = line.replacingOccurrences(
			of: "model=meta/muse-spark-1.1", with: "model=openai/gpt-5")
		XCTAssertEqual(
			OpenCodeProvider.decode(fields: OpenCodeProvider.parseFields(openCodeLine))?.model,
			OpenCodeProvider.decode(line: openCodeLine)?.model)
	}
}
