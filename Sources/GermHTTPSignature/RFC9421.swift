import Crypto
import Foundation

/// RFC 9421 HTTP Message Signatures — the client half.
///
/// Mirrors the reference relay's `http-sig/sign.ts` exactly: covered
/// components, parameter order, and the signature-base line format are all
/// pinned byte-for-byte against it (see `RFC9421VectorTests`). The
/// canonicalization is not this library's to invent — RFC 9421 exists
/// precisely so two independent implementations agree on "exactly what is
/// signed" without a shared paragraph of prose.
public enum RFC9421 {
	/// The label every signature on this profile is carried under. A
	/// constant, not configurable — a client and the relay must agree on it
	/// or neither header parses.
	public static let defaultLabel = "pmr"

	public struct SignedRequest: Sendable {
		public let headers: [String: String]
		/// The exact bytes that were signed, exposed for byte-identity
		/// testing against the reference. Not needed to send the request —
		/// the headers already carry everything.
		public let base: String
	}

	/// Builds and signs one request under this profile.
	///
	/// Covered components are `@method`, `@authority`, `@path`, plus
	/// `@query` whenever the URL carries one and `content-digest` whenever
	/// `body` is non-**empty** — an empty `Data` is treated as no body,
	/// matching the reference's `byteLength > 0` check exactly rather than a
	/// bare nil check. Getting either wrong desyncs from what the relay's
	/// verifier decides to require: `http-sig/verify.ts` refuses a request
	/// with a query string that doesn't cover `@query` (a captured signature
	/// could otherwise be replayed against any query the endpoint accepts),
	/// the same way it refuses a bodied request that doesn't cover
	/// `content-digest`.
	public static func sign(
		method: String,
		url: URL,
		nonce: String,
		keyid: String,
		created: Int64,
		body: Data?,
		label: String = defaultLabel,
		sign: (Data) async throws -> Data
	) async throws -> SignedRequest {
		let hasBody = (body?.isEmpty == false)
		let hasQuery =
			!(URLComponents(url: url, resolvingAgainstBaseURL: false)?
			.percentEncodedQuery ?? "").isEmpty
		var headers: [String: String] = [:]
		var components = ["@method", "@authority", "@path"]
		if hasQuery {
			components.append("@query")
		}
		if hasBody {
			let digest = Data(SHA256.hash(data: body!))
			headers["content-digest"] = "sha-256=:\(digest.base64EncodedString()):"
			components.append("content-digest")
		}

		// Param order — nonce, created, keyid, alg — is part of the signed
		// bytes, not cosmetic: the relay takes `@signature-params` from the
		// header verbatim rather than re-serializing, so any reordering here
		// would only break interop with an implementation that reordered the
		// same way, which is nobody.
		let signatureParams =
			"(\(components.map { "\"\($0)\"" }.joined(separator: " ")))"
			+ ";nonce=\"\(nonce)\";created=\(created);keyid=\"\(keyid)\";alg=\"ed25519\""
		headers["signature-input"] = "\(label)=\(signatureParams)"

		let base = signatureBase(
			method: method,
			url: url,
			components: components,
			headers: headers,
			signatureParams: signatureParams
		)

		let signature = try await sign(Data(base.utf8))
		headers["signature"] = "\(label)=:\(signature.base64EncodedString()):"

		return SignedRequest(headers: headers, base: base)
	}

	/// RFC 9421 §2.5. One line per covered component, then
	/// `@signature-params` last, joined by `\n` with no trailing newline.
	static func signatureBase(
		method: String,
		url: URL,
		components: [String],
		headers: [String: String],
		signatureParams: String
	) -> String {
		var lines: [String] = []
		for component in components {
			lines.append(
				"\"\(component)\": \(componentValue(component, method: method, url: url, headers: headers))"
			)
		}
		lines.append("\"@signature-params\": \(signatureParams)")
		return lines.joined(separator: "\n")
	}

	private static func componentValue(
		_ component: String,
		method: String,
		url: URL,
		headers: [String: String]
	) -> String {
		switch component {
		case "@method":
			return method.uppercased()
		case "@authority":
			return authority(of: url)
		case "@path":
			// `URLComponents.percentEncodedPath` preserves both the
			// percent-encoding and any trailing slash — matching the
			// reference's WHATWG `url.pathname` — where `URL.path` (no
			// arguments) percent-DECODES and strips the trailing slash. Used
			// in preference to `URL.path(percentEncoded:)` so this stays on
			// GermConvenience's iOS 15 floor. Every path signed today is fixed
			// ASCII, but the first escaped segment (a DID in
			// `PUT /pmr/v1/blocks/{did}`, say) must survive verbatim or the
			// relay verifies a base this never produced, for a bare 401.
			let path =
				URLComponents(url: url, resolvingAgainstBaseURL: false)?
				.percentEncodedPath ?? ""
			return path.isEmpty ? "/" : path
		case "@query":
			// WHATWG `url.search`: the leading `?` plus the raw, percent-
			// encoded query string — the exact bytes the relay's
			// `new URL(request.url).search` sees. `URLComponents.percentEncodedQuery`
			// (not `URL.query(percentEncoded:)`) keeps this on the iOS 15 floor.
			let query =
				URLComponents(url: url, resolvingAgainstBaseURL: false)?
				.percentEncodedQuery ?? ""
			return "?\(query)"
		default:
			// This profile covers only registered headers we ourselves set
			// (content-digest today), so a missing entry is a caller bug,
			// not a peer input to validate — unlike the relay's verifier,
			// which must handle an arbitrary attacker-supplied component
			// list and therefore refuses instead of trapping.
			return (headers[component] ?? "").trimmingCharacters(in: .whitespaces)
		}
	}

	/// Host, lowercased, with the port included only when present **and**
	/// not the scheme's default — RFC 9421's authority component, chosen so
	/// that an equivalent request cannot produce a different base.
	///
	/// Checked against the scheme's default explicitly rather than trusting
	/// `URL.port == nil`: Foundation preserves an *explicit* default port
	/// (`https://host:443`) as `.port == 443` rather than normalizing it
	/// away the way a WHATWG URL parser does, so a nil check alone would
	/// authenticate a different base than the reference for that input.
	///
	/// Two more Foundation-vs-WHATWG gaps closed here, neither reachable
	/// against `.germ` today but both real for a general-purpose signer:
	/// `URL.scheme` preserves the input's case (`HTTPS://` would otherwise
	/// miss the default-port comparison entirely), and `URL.host` strips
	/// the brackets that distinguish an IPv6 literal from a bare port
	/// number — re-added here since the authority component requires them.
	/// `ws`/`wss` share `http`/`https`'s default ports (RFC 6455), ahead of
	/// the events socket signing one.
	static func authority(of url: URL) -> String {
		let scheme = (url.scheme ?? "").lowercased()
		var host = (url.host ?? "").lowercased()
		if host.contains(":") && !host.hasPrefix("[") {
			host = "[\(host)]"
		}
		guard let port = url.port else { return host }
		let defaultPort: Int?
		switch scheme {
		case "https", "wss": defaultPort = 443
		case "http", "ws": defaultPort = 80
		default: defaultPort = nil
		}
		return port == defaultPort ? host : "\(host):\(port)"
	}
}
