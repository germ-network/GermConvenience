import Crypto
import Foundation

/// RFC 9421 reference vectors, produced by running the reference relay's own
/// `signRequest` over fixed inputs. Generated from that run, not transcribed —
/// any drift here is a wire break between this signer and the verifier.
enum RFC9421ReferenceVectors {
	static let seed = Data(
		hex: "65666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f8081828384"
	)
	static let publicKey = Data(
		hex: "da29e95b02e00ffa15645775fb1d2ba222a1943395eea06b94e2c057b7be69d0"
	)
	static let keyid = "fc1b64b7b94efe680569726ae29a14d5b70f4b63014b5c4550ce81599c2fb199"
	static let nonce = "fixedNonceForVectorTest"
	static let created: Int64 = 1_700_000_000

	enum NoBody {
		static let signatureInput =
			"pmr=(\"@method\" \"@authority\" \"@path\");nonce=\"fixedNonceForVectorTest\";created=1700000000;keyid=\"fc1b64b7b94efe680569726ae29a14d5b70f4b63014b5c4550ce81599c2fb199\";alg=\"ed25519\""
		static let base =
			"\"@method\": POST\n\"@authority\": atproto.ger.mx\n\"@path\": /pmr/v1/registrations\n\"@signature-params\": (\"@method\" \"@authority\" \"@path\");nonce=\"fixedNonceForVectorTest\";created=1700000000;keyid=\"fc1b64b7b94efe680569726ae29a14d5b70f4b63014b5c4550ce81599c2fb199\";alg=\"ed25519\""
	}

	enum WithBody {
		static let bodyText = "hello registration body"
		static let contentDigest =
			"sha-256=:aA5LbY+9W0z+tVLkRV9O9mODcG7EUBd8+wjhdHYBDo4=:"
		static let signatureInput =
			"pmr=(\"@method\" \"@authority\" \"@path\" \"content-digest\");nonce=\"fixedNonceForVectorTest\";created=1700000000;keyid=\"fc1b64b7b94efe680569726ae29a14d5b70f4b63014b5c4550ce81599c2fb199\";alg=\"ed25519\""
		static let base =
			"\"@method\": POST\n\"@authority\": atproto.ger.mx\n\"@path\": /pmr/v1/registrations\n\"content-digest\": sha-256=:aA5LbY+9W0z+tVLkRV9O9mODcG7EUBd8+wjhdHYBDo4=:\n\"@signature-params\": (\"@method\" \"@authority\" \"@path\" \"content-digest\");nonce=\"fixedNonceForVectorTest\";created=1700000000;keyid=\"fc1b64b7b94efe680569726ae29a14d5b70f4b63014b5c4550ce81599c2fb199\";alg=\"ed25519\""
	}

	enum Delete {
		static let signatureInput =
			"pmr=(\"@method\" \"@authority\" \"@path\");nonce=\"fixedNonceForVectorTest\";created=1700000000;keyid=\"fc1b64b7b94efe680569726ae29a14d5b70f4b63014b5c4550ce81599c2fb199\";alg=\"ed25519\""
		static let base =
			"\"@method\": DELETE\n\"@authority\": atproto.ger.mx\n\"@path\": /pmr/v1/registration\n\"@signature-params\": (\"@method\" \"@authority\" \"@path\");nonce=\"fixedNonceForVectorTest\";created=1700000000;keyid=\"fc1b64b7b94efe680569726ae29a14d5b70f4b63014b5c4550ce81599c2fb199\";alg=\"ed25519\""
	}

	/// `GET .../messages?cursor=abc123` — pins the conditional `@query` component.
	enum WithQuery {
		static let signatureInput =
			"pmr=(\"@method\" \"@authority\" \"@path\" \"@query\");nonce=\"fixedNonceForVectorTest\";created=1700000000;keyid=\"fc1b64b7b94efe680569726ae29a14d5b70f4b63014b5c4550ce81599c2fb199\";alg=\"ed25519\""
		static let base =
			"\"@method\": GET\n\"@authority\": atproto.ger.mx\n\"@path\": /pmr/v1/messages\n\"@query\": ?cursor=abc123\n\"@signature-params\": (\"@method\" \"@authority\" \"@path\" \"@query\");nonce=\"fixedNonceForVectorTest\";created=1700000000;keyid=\"fc1b64b7b94efe680569726ae29a14d5b70f4b63014b5c4550ce81599c2fb199\";alg=\"ed25519\""
	}

	/// `GET .../messages` (no cursor): must NOT cover `@query`.
	enum MessagesFirstPage {
		static let signatureInput =
			"pmr=(\"@method\" \"@authority\" \"@path\");nonce=\"fixedNonceForVectorTest\";created=1700000000;keyid=\"fc1b64b7b94efe680569726ae29a14d5b70f4b63014b5c4550ce81599c2fb199\";alg=\"ed25519\""
		static let base =
			"\"@method\": GET\n\"@authority\": atproto.ger.mx\n\"@path\": /pmr/v1/messages\n\"@signature-params\": (\"@method\" \"@authority\" \"@path\");nonce=\"fixedNonceForVectorTest\";created=1700000000;keyid=\"fc1b64b7b94efe680569726ae29a14d5b70f4b63014b5c4550ce81599c2fb199\";alg=\"ed25519\""
	}
}

/// An in-memory Ed25519 signer for the vector tests — holds the private key as
/// plain bytes, exactly what a test wants and nothing a shipping client should.
struct TestEd25519Signer {
	private let seed: Data
	let publicKey: Data

	init(seed: Data) throws {
		let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
		self.seed = seed
		self.publicKey = key.publicKey.rawRepresentation
	}

	func sign(_ message: Data) throws -> Data {
		try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
			.signature(for: message)
	}
}

extension Data {
	/// Test-only hex decoder for the fixed vectors above.
	init(hex: String) {
		var bytes = [UInt8]()
		bytes.reserveCapacity(hex.count / 2)
		var index = hex.startIndex
		while index < hex.endIndex {
			let next = hex.index(index, offsetBy: 2)
			bytes.append(UInt8(hex[index..<next], radix: 16)!)
			index = next
		}
		self = Data(bytes)
	}
}
