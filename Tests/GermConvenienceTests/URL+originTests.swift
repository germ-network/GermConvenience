import Foundation
import Testing

@testable import GermConvenience

/// `URL.origin` is the lowercased scheme plus `URLAuthority`; host and port
/// normalization is covered in `URLAuthorityTests`.
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

	// Differently-cased spellings of one origin must produce the same string,
	// or they become distinct nonce-cache keys.
	@Test(
		"Origin is the lowercased scheme plus the authority",
		arguments: [
			("HTTPS://Example.COM:443/Path", "https://example.com"),
			("HTTP://EXAMPLE.com:80/", "http://example.com"),
			("HTTPS://Example.COM:8443/", "https://example.com:8443"),
			("http://[0:0::1]:8080/path", "http://[::1]:8080"),
			("http://bücher.de/", "http://xn--bcher-kva.de"),
		])
	func testSchemeAndAuthority(input: String, expected: String) throws {
		let url = try #require(URL(string: input))
		#expect(try url.origin == expected)
	}

	@Test(
		"Origin throws when there is no scheme",
		arguments: [
			"/relative/path",
			"//example.com/path",
		])
	func testThrowsWithoutScheme(input: String) throws {
		let url = try #require(URL(string: input))
		#expect(throws: URLError(.unsupportedURL)) { try url.origin }
	}

	@Test("Origin passes authority errors through")
	func testAuthorityErrors() throws {
		let noHost = try #require(URL(string: "http://:80/"))
		#expect(throws: URLAuthority.Errors.missingHost) { try noHost.origin }

		let badPort = try #require(URL(string: "http://example.com:99999/"))
		#expect(throws: URLAuthority.Errors.invalidPort(99999)) { try badPort.origin }
	}
}
