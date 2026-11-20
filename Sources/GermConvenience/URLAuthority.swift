//
//  URLAuthority.swift
//  GermConvenience
//
//  Created by Emelia Smith on 11/20/26.
//

import Foundation

/// The host and non-default port of a URL (RFC 3986 §3.2, without user info),
/// normalized so that equivalent spellings compare equal. Its `description` is
/// the RFC 9421 `@authority` value.
public struct URLAuthority: Hashable, Sendable, CustomStringConvertible {
	/// Lowercased, with an IPv6 literal in bracketed RFC 5952 form (`[::1]`).
	public let host: String
	/// `nil` when the URL has no port or uses its scheme's default.
	public let port: Int?

	public enum Errors: LocalizedError, Equatable {
		case missingHost
		case invalidHost(String)
		case invalidIPv4Host(String)
		case invalidIPv6Host(String)
		case invalidPort(Int)

		/// Hosts are quoted and escaped, since an invalid one may hold control
		/// characters (a NUL, a newline) that would otherwise reach logs raw.
		public var errorDescription: String? {
			switch self {
			case .missingHost: "URL is missing a host"
			case .invalidHost(let host):
				"URL host is not a valid hostname: \(host.debugDescription)"
			case .invalidIPv4Host(let host):
				"URL host is not a valid IPv4 address: \(host.debugDescription)"
			case .invalidIPv6Host(let host):
				"URL host is not a valid IPv6 address: \(host.debugDescription)"
			case .invalidPort(let port): "URL port is out of range: \(port)"
			}
		}
	}

	public init(of url: URL) throws(Errors) {
		let host = try url.host.unwrap(or: Errors.missingHost).lowercased()
		// `http://:80/` parses with an empty host rather than a nil one.
		guard !host.isEmpty else {
			throw Errors.missingHost
		}

		// `URL.host` strips an IP literal's brackets (and decodes `%3A` to `:`),
		// so only the raw host tells `[::1]` apart from `ex%3Aample.com`.
		let rawHost = URLComponents(url: url, resolvingAgainstBaseURL: false)?
			.percentEncodedHost

		// IPvFuture (`[v1.fe]`) fails IPv6 parsing here.
		self.host =
			rawHost?.hasPrefix("[") == true
			? "[\(try Self.canonicalIPv6(host))]" : try Self.canonicalDomain(host)

		if let port = url.port {
			guard (0...65535).contains(port) else {
				throw Errors.invalidPort(port)
			}
			self.port = port == Self.defaultPort(for: url.scheme) ? nil : port
		} else {
			self.port = nil
		}
	}

	/// `example.com`, `example.com:8443`, or `[::1]:8080`.
	public var description: String {
		port.map { "\(host):\($0)" } ?? host
	}

	/// The port a scheme implies when none is written, which an authority omits.
	private static func defaultPort(for scheme: String?) -> Int? {
		switch scheme?.lowercased() {
		case "http", "ws": 80
		case "https", "wss": 443
		default: nil
		}
	}

	/// A lowercased, unbracketed host: a domain in punycode, or an IPv4 address
	/// in any WHATWG form, serialized as a dotted quad.
	private static func canonicalDomain(_ host: String) throws(Errors) -> String {
		// The decoded host may hold characters a hostname can't: `ex%20ample.com`
		// decodes to `ex ample.com`, and `ex%3Aample.com` to `ex:ample.com`, which
		// would read back as a port. Checked here rather than left to
		// `URLComponents`, which percent-encodes a NUL on Linux instead of
		// rejecting it as it does on Apple platforms.
		guard !host.unicodeScalars.contains(where: isForbiddenDomainCodePoint) else {
			throw Errors.invalidHost(host)
		}
		// `URLComponents` builds no string for other hosts it can't represent,
		// such as one holding a zero-width space (U+200B).
		var components = URLComponents()
		components.host = host
		// `encodedHost` keeps internationalized hosts in punycode, where
		// `percentEncodedHost` would percent-encode their UTF-8.
		guard components.string != nil, let encodedHost = components.encodedHost else {
			throw Errors.invalidHost(host)
		}
		// Hosts like `0x7f.1` reach the same server as `127.0.0.1`, so they
		// must produce the same authority.
		return endsInANumber(encodedHost) ? try canonicalIPv4(encodedHost) : encodedHost
	}

	/// WHATWG URL "forbidden domain code point": C0 controls, DEL, space, and
	/// `#%/:<>?@[\]^|`.
	private static func isForbiddenDomainCodePoint(_ scalar: Unicode.Scalar) -> Bool {
		scalar.value <= 0x20 || scalar.value == 0x7F
			|| "#%/:<>?@[\\]^|".unicodeScalars.contains(scalar)
	}

	/// A host's dot-separated labels, ignoring a single trailing dot.
	private static func labels(of host: String) -> [Substring] {
		var labels = host.split(separator: ".", omittingEmptySubsequences: false)
		if labels.count > 1, labels.last?.isEmpty == true {
			labels.removeLast()
		}
		return labels
	}

	/// WHATWG URL "ends in a number": a host whose last label is numeric is an
	/// IPv4 address, or invalid.
	private static func endsInANumber(_ host: String) -> Bool {
		guard let last = labels(of: host).last, !last.isEmpty else { return false }
		return last.allSatisfy { $0.isASCII && $0.isNumber } || parseIPv4Number(last) != nil
	}

	/// WHATWG URL IPv4 parser, serialized as a dotted quad: up to four decimal,
	/// octal (`0` prefix) or hex (`0x` prefix) parts, the last filling the
	/// remaining bytes, so `0x7f.1` and `2130706433` are both `127.0.0.1`.
	static func canonicalIPv4(_ host: String) throws(Errors) -> String {
		let parts = labels(of: host)
		guard parts.count <= 4 else {
			throw Errors.invalidIPv4Host(host)
		}
		var numbers: [UInt64] = []
		for part in parts {
			guard let number = parseIPv4Number(part) else {
				throw Errors.invalidIPv4Host(host)
			}
			numbers.append(number)
		}
		let last = numbers.removeLast()
		guard numbers.allSatisfy({ $0 <= 255 }), last < 1 << (8 * (4 - numbers.count))
		else {
			throw Errors.invalidIPv4Host(host)
		}
		var address = last
		for (index, number) in numbers.enumerated() {
			address += number << (8 * (3 - index))
		}
		return [24, 16, 8, 0].map { String(address >> $0 & 0xff) }.joined(separator: ".")
	}

	/// One IPv4 part, or `nil` if it has a digit outside its radix. Values too
	/// large for `UInt64` saturate, since anything over 32 bits is rejected anyway.
	private static func parseIPv4Number(_ part: Substring) -> UInt64? {
		guard !part.isEmpty else { return nil }
		var digits = part
		var radix = 10
		if digits.hasPrefix("0x") || digits.hasPrefix("0X") {
			digits = digits.dropFirst(2)
			radix = 16
		} else if digits.count > 1, digits.hasPrefix("0") {
			digits = digits.dropFirst()
			radix = 8
		}
		guard !digits.isEmpty else { return 0 }
		guard
			digits.allSatisfy({ $0.isASCII && ($0.hexDigitValue ?? radix) < radix })
		else { return nil }
		return UInt64(digits, radix: radix) ?? .max
	}

	/// Parses an IPv6 literal (RFC 4291 §2.2) and re-serializes it in the RFC 5952
	/// canonical form, so equivalent spellings (`0:0::1`, `::0001`, `::1`) produce
	/// the same authority. Zone IDs (`fe80::1%en0`) are rejected, as WHATWG does.
	static func canonicalIPv6(_ literal: String) throws(Errors) -> String {
		guard let groups = parseIPv6(literal) else {
			throw Errors.invalidIPv6Host(literal)
		}
		return formatIPv6(groups)
	}

	/// The eight 16-bit groups of an IPv6 literal, or `nil` if it is malformed.
	private static func parseIPv6(_ literal: String) -> [UInt16]? {
		let halves = literal.split(separator: "::", omittingEmptySubsequences: false)
		switch halves.count {
		case 1:
			guard let groups = parseGroups(halves[0]), groups.count == 8 else {
				return nil
			}
			return groups
		case 2:
			// `::` stands for at least one zero group.
			guard let head = parseGroups(halves[0], allowsIPv4Suffix: false),
				let tail = parseGroups(halves[1]),
				head.count + tail.count <= 7
			else { return nil }
			return head + Array(repeating: 0, count: 8 - head.count - tail.count) + tail
		default:
			return nil
		}
	}

	/// Colon-separated hex groups, optionally ending in a dotted-quad IPv4
	/// address (which fills two groups).
	private static func parseGroups(
		_ part: Substring, allowsIPv4Suffix: Bool = true
	) -> [UInt16]? {
		guard !part.isEmpty else { return [] }
		let pieces = part.split(separator: ":", omittingEmptySubsequences: false)
		var groups: [UInt16] = []
		for (index, piece) in pieces.enumerated() {
			if allowsIPv4Suffix, index == pieces.count - 1, piece.contains(".") {
				guard let ipv4 = parseIPv4(piece) else { return nil }
				groups += ipv4
			} else {
				guard (1...4).contains(piece.count),
					piece.allSatisfy({ $0.isASCII && $0.isHexDigit }),
					let group = UInt16(piece, radix: 16)
				else { return nil }
				groups.append(group)
			}
		}
		return groups
	}

	/// A dotted-quad IPv4 address as two 16-bit groups. Octets with leading
	/// zeros are rejected, since some parsers read them as octal.
	private static func parseIPv4(_ piece: Substring) -> [UInt16]? {
		let octets = piece.split(separator: ".", omittingEmptySubsequences: false)
		guard octets.count == 4 else { return nil }
		var bytes: [UInt16] = []
		for octet in octets {
			guard !octet.isEmpty,
				octet.allSatisfy({ $0.isASCII && $0.isNumber }),
				octet.count == 1 || octet.first != "0",
				let byte = UInt8(octet)
			else { return nil }
			bytes.append(UInt16(byte))
		}
		return [bytes[0] << 8 | bytes[1], bytes[2] << 8 | bytes[3]]
	}

	/// RFC 5952 text form: lowercase hex without leading zeros (§4.1, §4.3), the
	/// longest run of two or more zero groups compressed to `::`, the first on a
	/// tie (§4.2), and IPv4-mapped addresses in dotted-quad form (§5).
	private static func formatIPv6(_ groups: [UInt16]) -> String {
		if groups[0..<5].allSatisfy({ $0 == 0 }), groups[5] == 0xffff {
			let octets = [
				groups[6] >> 8, groups[6] & 0xff, groups[7] >> 8, groups[7] & 0xff,
			]
			return "::ffff:" + octets.map(String.init).joined(separator: ".")
		}

		var longestZeroRun = 0..<0
		var index = 0
		while index < groups.count {
			guard groups[index] == 0 else {
				index += 1
				continue
			}
			let start = index
			while index < groups.count, groups[index] == 0 { index += 1 }
			if index - start >= 2, index - start > longestZeroRun.count {
				longestZeroRun = start..<index
			}
		}

		let hex = groups.map { String($0, radix: 16) }
		guard !longestZeroRun.isEmpty else { return hex.joined(separator: ":") }
		return hex[..<longestZeroRun.lowerBound].joined(separator: ":") + "::"
			+ hex[longestZeroRun.upperBound...].joined(separator: ":")
	}
}
