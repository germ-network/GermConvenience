//
//  Url+Origin.swift
//  OAuth
//
//  Created by Emelia Smith on 11/20/26,
//  based the implementation in oauth4swift by Mark @ Germ on 2/24/26.
//

import Foundation

#if canImport(Darwin)
	import Darwin
#elseif canImport(Glibc)
	import Glibc
#elseif canImport(Musl)
	import Musl
#elseif canImport(Android)
	import Android
#endif

public enum URLOriginError: Error, Equatable {
	case missingScheme
	case missingHost
	case invalidHost(String)
	case invalidIPv6Host(String)
	case invalidPort(Int)
}

extension URL {
	public var origin: String {
		get throws {
			let scheme = try scheme.unwrap(or: URLOriginError.missingScheme)
				.lowercased()
			let host = try host.unwrap(or: URLOriginError.missingHost).lowercased()
			// `http://:80/` parses with an empty host rather than a nil one.
			guard !host.isEmpty else {
				throw URLOriginError.missingHost
			}

			var originComponents = URLComponents()
			originComponents.scheme = scheme

			// `URL.host` strips an IP literal's brackets (and decodes `%3A` to `:`),
			// so only the raw host tells `[::1]` apart from `ex%3Aample.com`.
			let rawHost = URLComponents(url: self, resolvingAgainstBaseURL: false)?
				.percentEncodedHost
			if rawHost?.hasPrefix("[") == true {
				// `URLComponents` rejects the bare IPv6 form, so set the bracketed
				// form directly. IPvFuture (`[v1.fe]`) fails `inet_pton` here.
				originComponents.percentEncodedHost =
					"[\(try Self.canonicalIPv6(host))]"
			} else {
				// Unbracketed, a `:` would be read back as a port separator.
				guard !host.contains(":") else {
					throw URLOriginError.invalidHost(host)
				}
				originComponents.host = host
			}

			if let port, !(0...65535).contains(port) {
				throw URLOriginError.invalidPort(port)
			}
			originComponents.port = port == Self.defaultPorts[scheme] ? nil : port

			// `nil` when the decoded host holds characters a hostname can't
			// (`ex%20ample.com` decodes to `ex ample.com`).
			return try originComponents.string.unwrap(
				or: URLOriginError.invalidHost(host))
		}
	}

	/// Ports an origin omits, keyed by lowercased scheme.
	private static let defaultPorts = ["http": 80, "https": 443, "ws": 80, "wss": 443]

	/// Round-trips an IPv6 literal through `inet_pton`/`inet_ntop` so equivalent
	/// spellings (`0:0::1`, `::0001`, `::1`) produce the same origin.
	private static func canonicalIPv6(_ literal: String) throws -> String {
		// WHATWG rejects zone IDs (`fe80::1%en0`) in URL hosts.
		guard !literal.contains("%") else {
			throw URLOriginError.invalidIPv6Host(literal)
		}
		var address = in6_addr()
		guard inet_pton(AF_INET6, literal, &address) == 1 else {
			throw URLOriginError.invalidIPv6Host(literal)
		}
		return try withUnsafeTemporaryAllocation(
			of: CChar.self, capacity: Int(INET6_ADDRSTRLEN)
		) { buffer in
			guard
				let formatted = inet_ntop(
					AF_INET6, &address, buffer.baseAddress,
					socklen_t(buffer.count))
			else {
				throw URLOriginError.invalidIPv6Host(literal)
			}
			return String(cString: formatted)
		}
	}
}
