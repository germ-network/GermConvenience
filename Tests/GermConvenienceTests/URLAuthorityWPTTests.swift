import Foundation
import GermConvenience
import Testing

/// Runs `URLAuthority` against web-platform-tests' `url/resources/urltestdata.json`,
/// vendored from web-platform-tests/wpt@065d99ab62bf0b6ca04907f423625801c350edb2
/// (BSD-3-Clause, see Resources/WPT-LICENSE.md).
///
/// Only absolute inputs (no `base`) are used. The vectors exercise the WHATWG URL
/// parser, while `URL(string:)` follows RFC 3986, so inputs where the two parsers
/// disagree are listed in `foundationDivergences` and run as known issues.
@Suite("URLAuthority against WPT urltestdata")
struct TestURLAuthorityWPT {
	@Test("Authority matches the WHATWG host", arguments: WPTURLVectors.parsed)
	func testParsed(vector: URLTestVector) throws {
		try withKnownIssue(
			"Foundation's RFC 3986 parser reads this differently from WHATWG"
		) {
			try Self.expectHost(vector)
		} when: {
			Self.foundationDivergences.contains(vector.input)
		}
	}

	@Test("Inputs WHATWG rejects are rejected", arguments: WPTURLVectors.rejected)
	func testRejected(vector: URLTestVector) {
		// Only inputs Foundation also parses with a special scheme reach URLAuthority.
		guard let url = URL(string: vector.input),
			let scheme = url.scheme?.lowercased(),
			WPTURLVectors.specialSchemes.contains(scheme + ":")
		else { return }
		#expect(throws: URLAuthority.Errors.self) { try URLAuthority(of: url) }
	}

	private static func expectHost(_ vector: URLTestVector) throws {
		let url = try #require(URL(string: vector.input))
		#expect(try URLAuthority(of: url).description == vector.host)
	}

	private static let foundationDivergences: Set<String> = [
		// WHATWG allows special-scheme URLs without `//` (or with backslashes);
		// Foundation finds no host, and URLAuthority throws `missingHost`.
		"http:\\\\www.google.com\\foo",
		"http:/example.com/",
		"https:/example.com/",
		"ws:/example.com/",
		"wss:/example.com/",
		"http:example.com/",
		"https:example.com/",
		"ws:example.com/",
		"wss:example.com/",
		"http:@www.example.com",
		"http:/@www.example.com",
		"http:a:b@www.example.com",
		"http:/a:b@www.example.com",
		"http::b@www.example.com",
		"http:/:b@www.example.com",
		"http:a:@www.example.com",
		"http:/a:@www.example.com",
		// WHATWG strips tabs and newlines, trims control characters, treats `\`
		// as `/`, and allows more host code points; `URL(string:)` returns nil.
		"http://a:b@c\\",
		"ws://a@b\\c",
		"http://example.com\\\\foo\\\\bar",
		"\0\u{1B}\u{04}\u{12} http://example.com/\u{1F} \r ",
		"http://ho\tst/",
		"http://ho\nst/",
		"http://ho\rst/",
		"http://!\"$&'()*+,-.;=_`{}~/",
		"h\tt\nt\rp://h\to\ns\rt:9\t0\n0\r0/p\ta\nt\rh?q\tu\ne\rry#f\tr\na\rg",
		"wss://!\"$&'()*+,-.;=_`{}~/",
	]
}

/// One object from `urltestdata.json`; only the fields these tests read.
struct URLTestVector: Decodable, Sendable, CustomTestStringConvertible {
	let input: String
	let base: String?
	let failure: Bool?
	let `protocol`: String?
	let host: String?

	var testDescription: String { input.debugDescription }
}

enum WPTURLVectors {
	static let specialSchemes: Set = ["http:", "https:", "ws:", "wss:"]

	/// Absolute inputs WHATWG parses with a special scheme.
	static let parsed = all.filter {
		$0.base == nil && $0.failure != true && specialSchemes.contains($0.protocol ?? "")
	}

	/// Absolute inputs WHATWG rejects.
	static let rejected = all.filter { $0.base == nil && $0.failure == true }

	private static let all: [URLTestVector] = {
		let url = Bundle.module.url(forResource: "urltestdata", withExtension: "json")!
		// The file interleaves comment strings with the test objects.
		let entries = try! JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
		return entries.compactMap(\.vector)
	}()

	private struct Entry: Decodable {
		let vector: URLTestVector?

		init(from decoder: any Decoder) throws {
			vector = try? decoder.singleValueContainer().decode(URLTestVector.self)
		}
	}
}
