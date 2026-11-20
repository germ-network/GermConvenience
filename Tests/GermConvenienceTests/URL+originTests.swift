import Foundation
import Testing

@testable import GermConvenience

@Suite("URL+origin")
struct TestURLOrigin {
	@Test(
		"Origin strips path, query, fragment, and user info",
		arguments: [
			("https://user@example.com/a?b#c", "https://example.com"),
			("https://example.com", "https://example.com"),
			("https://example.com/", "https://example.com"),
			("https://example.com/path/to/thing", "https://example.com"),
			("https://example.com/path?query=1#fragment", "https://example.com"),
			("https://user:pass@example.com/path", "https://example.com"),
			("http://sub.example.com/", "http://sub.example.com"),
		])
	func testStripsNonOriginParts(input: String, expected: String) throws {
		let url = try #require(URL(string: input))
		#expect(try url.origin == expected)
	}

	@Test(
		"Origin omits default ports",
		arguments: [
			("http://example.com:80/", "http://example.com"),
			("https://example.com:443/", "https://example.com"),
		])
	func testOmitsDefaultPorts(input: String, expected: String) throws {
		let url = try #require(URL(string: input))
		#expect(try url.origin == expected)
	}

	@Test(
		"Origin keeps non-default ports",
		arguments: [
			("http://example.com:8080/", "http://example.com:8080"),
			("https://example.com:8443/", "https://example.com:8443"),
			("http://example.com:443/", "http://example.com:443"),
			("https://example.com:80/", "https://example.com:80"),
			("http://localhost:3000/callback", "http://localhost:3000"),
			("http://127.0.0.1:8080/", "http://127.0.0.1:8080"),
		])
	func testKeepsNonDefaultPorts(input: String, expected: String) throws {
		let url = try #require(URL(string: input))
		#expect(try url.origin == expected)
	}

	@Test(
		"Origin of an IPv6 host keeps brackets and is canonical",
		arguments: [
			("http://[::1]:8080/path", "http://[::1]:8080"),
			("http://[::1]/", "http://[::1]"),
			("https://[::1]:443/", "https://[::1]"),
			("http://[0:0::1]:8080/", "http://[::1]:8080"),
			("http://[::0001]/", "http://[::1]"),
			("https://[2001:DB8:0:0:0:0:0:1]/", "https://[2001:db8::1]"),
			("http://[::ffff:127.0.0.1]/", "http://[::ffff:127.0.0.1]"),
		])
	func testIPv6Host(input: String, expected: String) throws {
		let url = try #require(URL(string: input))
		#expect(try url.origin == expected)
	}

	// Zone IDs are rejected per WHATWG; IPvFuture literals would otherwise
	// collide with the DNS name `v1.fe` once their brackets are stripped.
	@Test(
		"Origin rejects IPv6 zone IDs and IPvFuture literals",
		arguments: [
			("http://[fe80::1%25en0]/", "fe80::1%en0"),
			("http://[v1.fe]/", "v1.fe"),
			("http://[V1.fe]/", "v1.fe"),
		])
	func testInvalidIPLiteral(input: String, literal: String) throws {
		let url = try #require(URL(string: input))
		#expect(throws: URLOriginError.invalidIPv6Host(literal)) { try url.origin }
	}

	@Test(
		"Origin rejects hosts that decode to characters a hostname can't hold",
		arguments: [
			("http://ex%20ample.com/", "ex ample.com"),
			("http://ex%2Fample.com/", "ex/ample.com"),
			("http://ex%40ample.com/", "ex@ample.com"),
			("http://ex%00ample.com/", "ex\0ample.com"),
			("http://ex%5Bample.com/", "ex[ample.com"),
			("http://ex%3Aample.com/", "ex:ample.com"),
			("http://%E2%80%8B.com/", "\u{200B}.com"),
		])
	func testInvalidHost(input: String, decodedHost: String) throws {
		let url = try #require(URL(string: input))
		#expect(throws: URLOriginError.invalidHost(decodedHost)) { try url.origin }
	}

	@Test("Origin converts internationalized hosts to punycode")
	func testInternationalizedHost() throws {
		let url = try #require(URL(string: "http://bücher.de/"))
		#expect(try url.origin == "http://xn--bcher-kva.de")
	}

	@Test(
		"Origin validates the port range",
		arguments: [
			("http://example.com:0/", "http://example.com:0"),
			("http://example.com:65535/", "http://example.com:65535"),
		])
	func testPortRange(input: String, expected: String) throws {
		let url = try #require(URL(string: input))
		#expect(try url.origin == expected)
	}

	@Test("Origin rejects ports above 65535")
	func testPortOutOfRange() throws {
		let url = try #require(URL(string: "http://example.com:99999/"))
		#expect(throws: URLOriginError.invalidPort(99999)) { try url.origin }
	}

	// Differently-cased spellings of one origin must produce the same string,
	// or they become distinct nonce-cache keys.
	@Test(
		"Origin lowercases scheme and host",
		arguments: [
			("HTTPS://Example.COM:443/Path", "https://example.com"),
			("HTTP://EXAMPLE.com:80/", "http://example.com"),
			("HTTPS://Example.COM:8443/", "https://example.com:8443"),
		])
	func testCaseNormalization(input: String, expected: String) throws {
		let url = try #require(URL(string: input))
		#expect(try url.origin == expected)
	}

	@Test(
		"Origin throws when there is no host",
		arguments: [
			"mailto:someone@example.com",
			"file:///tmp",
			"urn:foo",
			"http://:80/",
		])
	func testThrowsWithoutHost(input: String) throws {
		let url = try #require(URL(string: input))
		#expect(throws: URLOriginError.missingHost) { try url.origin }
	}

	@Test(
		"Origin throws when there is no scheme",
		arguments: [
			"/relative/path",
			"//example.com/path",
		])
	func testThrowsWithoutScheme(input: String) throws {
		let url = try #require(URL(string: input))
		#expect(throws: URLOriginError.missingScheme) { try url.origin }
	}

	@Test(
		"non default HTTP ports",
		arguments: [
			("http://example.com", nil),
			("http://example.com:80", nil),
			("https://example.com:443", nil),
			("http://example.com:443", 443),
			("https://example.com:8443", 8443),
			("ws://example.com:80", nil),
			("wss://example.com:443", nil),
			("WSS://example.com:443", nil),
			("ws://example.com:443", 443),
			("WS://example.com:443", 443),
		] as [(String, Int?)])
	func testNonDefaultHTTPort(input: String, expectedPort: Int?) throws {
		let url = try #require(URL(string: input))
		let originUrl = try #require(URL(string: url.origin))
		#expect(originUrl.port == expectedPort)
	}
}
