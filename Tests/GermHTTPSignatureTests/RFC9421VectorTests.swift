import Crypto
import Foundation
import Testing

@testable import GermHTTPSignature

/// Known-answer tests against the reference relay's own `signRequest`.
///
/// RFC 9421 has a lot of surface: component selection, parameter order, and the
/// exact base-string framing are all places a client could silently disagree
/// with the verifier and get nothing but a uniform `401` with no diagnosis.
/// These vectors pin every one of those choices against what the reference
/// actually produces.
@Suite struct RFC9421VectorTests {
	@Test func noBodyRequestMatchesTheReferenceExactly() async throws {
		let signer = try TestEd25519Signer(seed: RFC9421ReferenceVectors.seed)
		#expect(signer.publicKey == RFC9421ReferenceVectors.publicKey)

		let signed = try await RFC9421.sign(
			method: "POST",
			url: URL(string: "https://atproto.ger.mx/pmr/v1/registrations")!,
			nonce: RFC9421ReferenceVectors.nonce,
			keyid: RFC9421ReferenceVectors.keyid,
			created: RFC9421ReferenceVectors.created,
			body: nil,
			sign: signer.sign
		)

		#expect(
			signed.headers["signature-input"]
				== RFC9421ReferenceVectors.NoBody.signatureInput)
		#expect(signed.base == RFC9421ReferenceVectors.NoBody.base)
		#expect(signed.headers["content-digest"] == nil)
	}

	@Test func bodiedRequestMatchesTheReferenceExactly() async throws {
		let signer = try TestEd25519Signer(seed: RFC9421ReferenceVectors.seed)
		let body = Data(RFC9421ReferenceVectors.WithBody.bodyText.utf8)

		let signed = try await RFC9421.sign(
			method: "POST",
			url: URL(string: "https://atproto.ger.mx/pmr/v1/registrations")!,
			nonce: RFC9421ReferenceVectors.nonce,
			keyid: RFC9421ReferenceVectors.keyid,
			created: RFC9421ReferenceVectors.created,
			body: body,
			sign: signer.sign
		)

		#expect(
			signed.headers["content-digest"]
				== RFC9421ReferenceVectors.WithBody.contentDigest)
		#expect(
			signed.headers["signature-input"]
				== RFC9421ReferenceVectors.WithBody.signatureInput)
		#expect(signed.base == RFC9421ReferenceVectors.WithBody.base)
	}

	@Test func deleteRequestMatchesTheReferenceExactly() async throws {
		let signer = try TestEd25519Signer(seed: RFC9421ReferenceVectors.seed)

		let signed = try await RFC9421.sign(
			method: "DELETE",
			url: URL(string: "https://atproto.ger.mx/pmr/v1/registration")!,
			nonce: RFC9421ReferenceVectors.nonce,
			keyid: RFC9421ReferenceVectors.keyid,
			created: RFC9421ReferenceVectors.created,
			body: nil,
			sign: signer.sign
		)

		#expect(
			signed.headers["signature-input"]
				== RFC9421ReferenceVectors.Delete.signatureInput)
		#expect(signed.base == RFC9421ReferenceVectors.Delete.base)
	}

	/// A zero-length body must be treated as no body — the reference checks
	/// `byteLength > 0`, not a bare nil check. Getting this wrong would cover
	/// `content-digest` when the relay's verifier does not require it — or, the
	/// more dangerous direction, treat a real empty body as absent and omit a
	/// digest the verifier DOES require. This pins the boundary explicitly.
	@Test func emptyBodyIsTreatedAsNoBody() async throws {
		let signer = try TestEd25519Signer(seed: RFC9421ReferenceVectors.seed)

		let signed = try await RFC9421.sign(
			method: "POST",
			url: URL(string: "https://atproto.ger.mx/pmr/v1/registrations")!,
			nonce: RFC9421ReferenceVectors.nonce,
			keyid: RFC9421ReferenceVectors.keyid,
			created: RFC9421ReferenceVectors.created,
			body: Data(),
			sign: signer.sign
		)

		#expect(
			signed.headers["signature-input"]
				== RFC9421ReferenceVectors.NoBody.signatureInput)
		#expect(signed.base == RFC9421ReferenceVectors.NoBody.base)
	}

	/// The strongest available check: sign with the real signer, then verify
	/// that signature over the reference's OWN base string. If Swift's base
	/// differed from the reference's by even one byte, this would still pass
	/// (both bases would be self-consistent) — so it is deliberately paired
	/// with the byte-identical `base` assertions above, not a replacement.
	@Test func aRealSignatureVerifiesOverTheReferenceBase() async throws {
		let signer = try TestEd25519Signer(seed: RFC9421ReferenceVectors.seed)
		let signed = try await RFC9421.sign(
			method: "POST",
			url: URL(string: "https://atproto.ger.mx/pmr/v1/registrations")!,
			nonce: RFC9421ReferenceVectors.nonce,
			keyid: RFC9421ReferenceVectors.keyid,
			created: RFC9421ReferenceVectors.created,
			body: nil,
			sign: signer.sign
		)

		let sigHeader = try #require(signed.headers["signature"])
		let b64 =
			sigHeader
			.replacingOccurrences(of: "pmr=:", with: "")
			.replacingOccurrences(of: ":", with: "")
		let signature = try #require(Data(base64Encoded: b64))

		let key = try Curve25519.Signing.PublicKey(
			rawRepresentation: RFC9421ReferenceVectors.publicKey)
		#expect(key.isValidSignature(signature, for: Data(signed.base.utf8)))
		#expect(signed.base == RFC9421ReferenceVectors.NoBody.base)
	}

	@Test func authorityOmitsTheSchemeDefaultPortButKeepsAnExplicitOne() {
		#expect(
			RFC9421.authority(of: URL(string: "https://Atproto.Ger.Mx/x")!)
				== "atproto.ger.mx"
		)
		#expect(
			RFC9421.authority(of: URL(string: "https://example.com:443/x")!)
				== "example.com"
		)
		#expect(
			RFC9421.authority(of: URL(string: "https://localhost:8787/x")!)
				== "localhost:8787"
		)
		#expect(
			RFC9421.authority(of: URL(string: "http://example.com:80/x")!)
				== "example.com"
		)
	}

	/// `RFC9421.sign` is a general-purpose signer — an uppercase-scheme URL or
	/// an IPv6-literal host must not silently authenticate a different base
	/// than a lowercase/hostname one would.
	@Test func authorityHandlesUppercaseSchemesAndIPv6Literals() {
		#expect(
			RFC9421.authority(of: URL(string: "HTTPS://example.com:443/x")!)
				== "example.com"
		)
		#expect(
			RFC9421.authority(of: URL(string: "https://[::1]:8787/x")!)
				== "[::1]:8787"
		)
		#expect(
			RFC9421.authority(of: URL(string: "https://[::1]/x")!)
				== "[::1]"
		)
		#expect(
			RFC9421.authority(of: URL(string: "wss://example.com:443/x")!)
				== "example.com"
		)
		#expect(
			RFC9421.authority(of: URL(string: "ws://example.com:80/x")!)
				== "example.com"
		)
	}

	/// `URL.path` (no arguments) percent-decodes and drops a trailing slash;
	/// the reference's `url.pathname` does neither. A path segment needing
	/// escaping — a DID in a future `blocks/{did}` call — must survive into the
	/// signature base exactly as sent, or the relay verifies a different base.
	@Test func signatureBaseUsesThePercentEncodedPathVerbatim() async throws {
		let signer = try TestEd25519Signer(seed: RFC9421ReferenceVectors.seed)
		let signed = try await RFC9421.sign(
			method: "PUT",
			url: URL(string: "https://atproto.ger.mx/pmr/v1/blocks/did%3Aplc%3Aabc")!,
			nonce: RFC9421ReferenceVectors.nonce,
			keyid: RFC9421ReferenceVectors.keyid,
			created: RFC9421ReferenceVectors.created,
			body: nil,
			sign: signer.sign
		)
		#expect(signed.base.contains("\"@path\": /pmr/v1/blocks/did%3Aplc%3Aabc"))
	}

	/// The verifier refuses a request with a query string that doesn't cover
	/// `@query` — the same class of refusal as an uncovered body. Pins that a
	/// cursor-bearing GET signs it, byte-for-byte against the reference.
	@Test func queryBearingRequestCoversQueryAndMatchesTheReferenceExactly() async throws {
		let signer = try TestEd25519Signer(seed: RFC9421ReferenceVectors.seed)
		let signed = try await RFC9421.sign(
			method: "GET",
			url: URL(string: "https://atproto.ger.mx/pmr/v1/messages?cursor=abc123")!,
			nonce: RFC9421ReferenceVectors.nonce,
			keyid: RFC9421ReferenceVectors.keyid,
			created: RFC9421ReferenceVectors.created,
			body: nil,
			sign: signer.sign
		)
		#expect(
			signed.headers["signature-input"]
				== RFC9421ReferenceVectors.WithQuery.signatureInput)
		#expect(signed.base == RFC9421ReferenceVectors.WithQuery.base)
	}

	/// The other half of the same boundary: a URL with no query string must not
	/// cover `@query`, matching the reference's `search !== ""` check.
	@Test func queryLessRequestOmitsQueryAndMatchesTheReferenceExactly() async throws {
		let signer = try TestEd25519Signer(seed: RFC9421ReferenceVectors.seed)
		let signed = try await RFC9421.sign(
			method: "GET",
			url: URL(string: "https://atproto.ger.mx/pmr/v1/messages")!,
			nonce: RFC9421ReferenceVectors.nonce,
			keyid: RFC9421ReferenceVectors.keyid,
			created: RFC9421ReferenceVectors.created,
			body: nil,
			sign: signer.sign
		)
		#expect(
			signed.headers["signature-input"]
				== RFC9421ReferenceVectors.MessagesFirstPage.signatureInput)
		#expect(signed.base == RFC9421ReferenceVectors.MessagesFirstPage.base)
	}
}
