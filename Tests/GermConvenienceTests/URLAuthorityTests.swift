import Foundation
import Testing

@testable import GermConvenience

@Suite("URLAuthority")
struct TestURLAuthority {
	@Test(
		"Authority keeps host and non-default port, without user info",
		arguments: [
			("https://user:pass@Example.COM:443/path", "example.com", nil),
			("https://example.com:8443/", "example.com", 8443),
			("http://[::1]:8080/", "[::1]", 8080),
			("wss://[0:0::1]/", "[::1]", nil),
			// With no scheme there is no default port to drop.
			("//example.com:443/", "example.com", 443),
		] as [(String, String, Int?)])
	func testHostAndPort(input: String, host: String, port: Int?) throws {
		let authority = try URLAuthority(of: #require(URL(string: input)))
		#expect(authority.host == host)
		#expect(authority.port == port)
	}

	@Test(
		"Description is the RFC 9421 @authority value",
		arguments: [
			("https://example.com/", "example.com"),
			("https://example.com:8443/", "example.com:8443"),
			("http://[::1]:8080/", "[::1]:8080"),
		])
	func testDescription(input: String, expected: String) throws {
		let authority = try URLAuthority(of: #require(URL(string: input)))
		#expect(authority.description == expected)
	}

	@Test(
		"Only the scheme's default port is dropped",
		arguments: [
			("http://example.com", nil),
			("http://example.com:80", nil),
			("https://example.com:443", nil),
			("ws://example.com:80", nil),
			("wss://example.com:443", nil),
			("WSS://example.com:443", nil),
			("http://example.com:443", 443),
			("https://example.com:80", 80),
			("ws://example.com:443", 443),
			("WS://example.com:443", 443),
			("http://example.com:8080", 8080),
			("https://example.com:8443", 8443),
			("http://localhost:3000/callback", 3000),
			("http://127.0.0.1:8080/", 8080),
			("http://example.com:0", 0),
			("http://example.com:65535", 65535),
		] as [(String, Int?)])
	func testDefaultPort(input: String, port: Int?) throws {
		let authority = try URLAuthority(of: #require(URL(string: input)))
		#expect(authority.port == port)
	}

	@Test("Ports above 65535 are rejected")
	func testPortOutOfRange() throws {
		let url = try #require(URL(string: "http://example.com:99999/"))
		#expect(throws: URLAuthority.Errors.invalidPort(99999)) {
			try URLAuthority(of: url)
		}
	}

	@Test(
		"Authority throws when there is no host",
		arguments: [
			"mailto:someone@example.com",
			"file:///tmp",
			"urn:foo",
			// Parses with an empty host rather than a nil one.
			"http://:80/",
		])
	func testThrowsWithoutHost(input: String) throws {
		let url = try #require(URL(string: input))
		#expect(throws: URLAuthority.Errors.missingHost) { try URLAuthority(of: url) }
	}

	@Test(
		"Hosts that decode to characters a hostname can't hold are rejected",
		arguments: [
			("http://ex%20ample.com/", "ex ample.com"),
			("http://ex%2Fample.com/", "ex/ample.com"),
			("http://ex%40ample.com/", "ex@ample.com"),
			("http://ex%5Bample.com/", "ex[ample.com"),
			("http://ex%3Aample.com/", "ex:ample.com"),
			("http://ex%25ample.com/", "ex%ample.com"),
			("http://ex%09ample.com/", "ex\tample.com"),
			("http://%E2%80%8B.com/", "\u{200B}.com"),
		])
	func testInvalidHost(input: String, decodedHost: String) throws {
		let url = try #require(URL(string: input))
		#expect(throws: URLAuthority.Errors.invalidHost(decodedHost)) {
			try URLAuthority(of: url)
		}
	}

	// Linux's `URL.host` leaves `%00` encoded where Apple platforms decode it to
	// NUL, so the host carried by the error differs; only its case is checked.
	@Test("Hosts containing NUL are rejected")
	func testNULHost() throws {
		let url = try #require(URL(string: "http://ex%00ample.com/"))
		let error = #expect(throws: URLAuthority.Errors.self) { try URLAuthority(of: url) }
		if case .invalidHost? = error { return }
		Issue.record("Expected .invalidHost, got \(String(describing: error))")
	}

	@Test("Internationalized hosts are converted to punycode")
	func testInternationalizedHost() throws {
		let authority = try URLAuthority(of: #require(URL(string: "http://bücher.de/")))
		#expect(authority.host == "xn--bcher-kva.de")
	}

	@Test(
		"IPv6 hosts keep their brackets and are canonical",
		arguments: [
			("http://[::1]:8080/path", "[::1]:8080"),
			("http://[::1]/", "[::1]"),
			("https://[::1]:443/", "[::1]"),
			("http://[0:0::1]:8080/", "[::1]:8080"),
			("http://[::0001]/", "[::1]"),
			("https://[2001:DB8:0:0:0:0:0:1]/", "[2001:db8::1]"),
			("http://[::ffff:127.0.0.1]/", "[::ffff:127.0.0.1]"),
		])
	func testIPv6Host(input: String, expected: String) throws {
		let authority = try URLAuthority(of: #require(URL(string: input)))
		#expect(authority.description == expected)
	}

	// Zone IDs are rejected per WHATWG; IPvFuture literals would otherwise
	// collide with the DNS name `v1.fe` once their brackets are stripped.
	@Test(
		"IPv6 zone IDs and IPvFuture literals are rejected",
		arguments: [
			("http://[fe80::1%25en0]/", "fe80::1%en0"),
			("http://[v1.fe]/", "v1.fe"),
			("http://[V1.fe]/", "v1.fe"),
		])
	func testInvalidIPLiteral(input: String, literal: String) throws {
		let url = try #require(URL(string: input))
		#expect(throws: URLAuthority.Errors.invalidIPv6Host(literal)) {
			try URLAuthority(of: url)
		}
	}

	@Test("Equivalent spellings compare equal")
	func testEquivalentSpellings() throws {
		let canonical = try URLAuthority(of: #require(URL(string: "https://example.com/")))
		let variant = try URLAuthority(
			of: #require(URL(string: "HTTPS://Example.COM:443/x")))
		#expect(canonical == variant)
		#expect(Set([canonical, variant]).count == 1)
	}

	@Test(
		"Numeric hosts serialize as dotted-quad IPv4",
		arguments: [
			("127.0.0.1", "127.0.0.1"),
			("0x7f.1", "127.0.0.1"),
			("0177.0.0.1", "127.0.0.1"),
			("2130706433", "127.0.0.1"),
			("127.1", "127.0.0.1"),
			("127.0.1", "127.0.0.1"),
			("1.2.3.4.", "1.2.3.4"),
			("0x", "0.0.0.0"),
			("0xffffffff", "255.255.255.255"),
		])
	func testCanonicalIPv4(host: String, expected: String) throws {
		#expect(try URLAuthority.canonicalIPv4(host) == expected)
	}

	@Test(
		"Malformed numeric hosts are rejected",
		arguments: [
			"256.0.0.1",
			"1.2.3.4.5",
			"0x100000000",
			"4294967296",
			"1.2.3.08",
			"1..2",
			"foo.1",
		])
	func testMalformedIPv4(host: String) throws {
		#expect(throws: URLAuthority.Errors.invalidIPv4Host(host)) {
			try URLAuthority.canonicalIPv4(host)
		}
	}

	@Test(
		"Only hosts ending in a number are parsed as IPv4",
		arguments: [
			("http://0x7f.1/", "127.0.0.1"),
			("http://example.com/", "example.com"),
			("http://1.2.3.4.example/", "1.2.3.4.example"),
			("http://example.123abc/", "example.123abc"),
		])
	func testEndsInANumber(input: String, expectedHost: String) throws {
		let authority = try URLAuthority(of: #require(URL(string: input)))
		#expect(authority.host == expectedHost)
	}

	@Test(
		"IPv6 literals serialize in RFC 5952 canonical form",
		arguments: [
			("::", "::"),
			("::1", "::1"),
			("1::", "1::"),
			("2001:0DB8::0001", "2001:db8::1"),
			// §4.2.1: the longest run of zero groups is compressed.
			("1:0:0:2:0:0:0:3", "1:0:0:2::3"),
			// §4.2.2: a single zero group is not compressed.
			("2001:db8:0:1:1:1:1:1", "2001:db8:0:1:1:1:1:1"),
			// §4.2.3: on a tie, the first run is compressed.
			("2001:db8:0:0:1:0:0:1", "2001:db8::1:0:0:1"),
			// §5: IPv4-mapped addresses keep the dotted quad, whichever way they're written.
			("::ffff:7f00:1", "::ffff:127.0.0.1"),
			("::FFFF:127.0.0.1", "::ffff:127.0.0.1"),
			// Other embedded IPv4 forms are written as hex.
			("::1.2.3.4", "::102:304"),
			("64:ff9b::192.0.2.33", "64:ff9b::c000:221"),
		])
	func testCanonicalIPv6(literal: String, expected: String) throws {
		#expect(try URLAuthority.canonicalIPv6(literal) == expected)
	}

	@Test(
		"Malformed IPv6 literals are rejected",
		arguments: [
			"",
			":",
			":::",
			"1:2:3:4:5:6:7",
			"1:2:3:4:5:6:7:8:9",
			"1:2:3:4:5:6:7:8::",
			"1::2::3",
			":1::2",
			"1::2:",
			"12345::",
			"::g",
			"::+1",
			"::-1",
			"1.2.3.4::",
			"::1.2.3",
			"::1.2.3.4.5",
			"::256.0.0.1",
			"::01.2.3.4",
			"::1.2.3.4:5",
			"fe80::1%en0",
		])
	func testMalformedIPv6(literal: String) throws {
		#expect(throws: URLAuthority.Errors.invalidIPv6Host(literal)) {
			try URLAuthority.canonicalIPv6(literal)
		}
	}
}
