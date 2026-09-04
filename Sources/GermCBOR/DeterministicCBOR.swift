import Foundation

/// A CBOR value in a narrow grammar: integer- or text-keyed maps, arrays,
/// byte strings, text strings, booleans and null.
///
/// No tags, no floats, no bignums, no indefinite lengths. The grammar is
/// narrow on purpose — this library targets canonical round-tripping of a
/// small, fixed value shape, and a wider decoder is accepted input nobody
/// needs.
public enum CBORValue: Sendable, Hashable {
	case integer(Int64)
	case bytes(Data)
	case text(String)
	case array([CBORValue])
	case map([CBORMapEntry])
	case bool(Bool)
	case null
}

/// One map entry. A `Dictionary` would lose duplicate keys silently, and
/// rejecting duplicates is a decoding requirement rather than a nicety.
public struct CBORMapEntry: Sendable, Hashable {
	public let key: CBORValue
	public let value: CBORValue

	public init(_ key: CBORValue, _ value: CBORValue) {
		self.key = key
		self.value = value
	}
}

public enum CBORError: Error, Equatable, Sendable {
	case truncated
	case unsupportedMajorType(UInt8)
	case indefiniteLength
	case nonMinimalInteger
	case integerOutOfRange
	case invalidUTF8
	case duplicateMapKey
	case trailingBytes
	case notCanonical
	case unsupportedSimpleValue(UInt8)
	case depthLimitExceeded
}

/// RFC 8949 §4.2.1 deterministic CBOR.
///
/// The profile is fixed and not meant to vary: encoding is always
/// deterministic and decoding rejects anything that isn't, because an
/// alternate encoding of the same value changes the bytes anywhere they are
/// hashed or compared.
public enum DeterministicCBOR {
	/// Guards against a hostile nesting depth blowing the stack — far above
	/// anything a legitimate value of this grammar would need.
	static let maximumDepth = 32

	// MARK: - Encoding

	public static func encode(_ value: CBORValue) throws -> Data {
		var out = Data()
		try encode(value, into: &out, depth: 0)
		return out
	}

	private static func encode(
		_ value: CBORValue,
		into out: inout Data,
		depth: Int
	) throws {
		guard depth <= maximumDepth else { throw CBORError.depthLimitExceeded }

		switch value {
		case .integer(let v):
			if v >= 0 {
				encodeHead(major: 0, argument: UInt64(v), into: &out)
			} else {
				// ~v == -1 - v for two's complement, and stays in range at
				// Int64.min where `-1 - v` would overflow.
				encodeHead(major: 1, argument: UInt64(bitPattern: ~v), into: &out)
			}
		case .bytes(let d):
			encodeHead(major: 2, argument: UInt64(d.count), into: &out)
			out.append(d)
		case .text(let s):
			let utf8 = Data(s.utf8)
			encodeHead(major: 3, argument: UInt64(utf8.count), into: &out)
			out.append(utf8)
		case .array(let items):
			encodeHead(major: 4, argument: UInt64(items.count), into: &out)
			for item in items { try encode(item, into: &out, depth: depth + 1) }
		case .map(let entries):
			encodeHead(major: 5, argument: UInt64(entries.count), into: &out)
			// §4.2.1: keys sort by the bytewise lexicographic order of their
			// own deterministic encodings — not by type, not by numeric value.
			var encoded: [(key: Data, value: CBORValue)] = []
			encoded.reserveCapacity(entries.count)
			for entry in entries {
				var keyBytes = Data()
				try encode(entry.key, into: &keyBytes, depth: depth + 1)
				encoded.append((keyBytes, entry.value))
			}
			encoded.sort { lexicographicallyPrecedes($0.key, $1.key) }
			for index in encoded.indices.dropFirst()
			where encoded[index].key == encoded[index - 1].key {
				throw CBORError.duplicateMapKey
			}
			for (keyBytes, entryValue) in encoded {
				out.append(keyBytes)
				try encode(entryValue, into: &out, depth: depth + 1)
			}
		case .bool(let b):
			out.append(0xE0 | (b ? 21 : 20))
		case .null:
			out.append(0xE0 | 22)
		}
	}

	private static func encodeHead(
		major: UInt8,
		argument: UInt64,
		into out: inout Data
	) {
		let prefix = major << 5
		switch argument {
		case ..<24:
			out.append(prefix | UInt8(argument))
		case ..<0x100:
			out.append(prefix | 24)
			out.append(UInt8(argument))
		case ..<0x1_0000:
			out.append(prefix | 25)
			appendBigEndian(UInt16(argument), to: &out)
		case ..<0x1_0000_0000:
			out.append(prefix | 26)
			appendBigEndian(UInt32(argument), to: &out)
		default:
			out.append(prefix | 27)
			appendBigEndian(argument, to: &out)
		}
	}

	private static func appendBigEndian<T: FixedWidthInteger>(
		_ value: T,
		to out: inout Data
	) {
		withUnsafeBytes(of: value.bigEndian) { out.append(contentsOf: $0) }
	}

	static func lexicographicallyPrecedes(_ lhs: Data, _ rhs: Data) -> Bool {
		lhs.lexicographicallyPrecedes(rhs)
	}

	// MARK: - Decoding

	/// Decodes exactly one value, requiring it to consume the whole input and
	/// to have been canonically encoded.
	///
	/// Canonicality is checked by re-encoding and comparing byte for byte,
	/// which is stronger than any per-field flag: re-encoding produces *the*
	/// canonical form, so a mismatch catches non-minimal integer heads,
	/// out-of-order map keys, and indefinite lengths in one test.
	public static func decode(_ data: Data) throws -> CBORValue {
		var cursor = Cursor(data)
		let value = try decodeValue(&cursor, depth: 0)
		guard cursor.isAtEnd else { throw CBORError.trailingBytes }
		guard try encode(value) == data else { throw CBORError.notCanonical }
		return value
	}

	/// Internal rather than `private` so a value can be decoded one step at a
	/// time, without going through `decode(_:)`'s whole-buffer contract.
	struct Cursor {
		let data: Data
		var offset: Int

		init(_ data: Data) {
			self.data = data
			self.offset = data.startIndex
		}

		var isAtEnd: Bool { offset >= data.endIndex }

		mutating func byte() throws -> UInt8 {
			guard offset < data.endIndex else { throw CBORError.truncated }
			defer { offset += 1 }
			return data[offset]
		}

		mutating func take(_ count: Int) throws -> Data {
			guard count >= 0, data.endIndex - offset >= count else {
				throw CBORError.truncated
			}
			defer { offset += count }
			return data[offset..<(offset + count)]
		}
	}

	/// Internal rather than `private` for the same reason as `Cursor` above.
	static func decodeValue(
		_ cursor: inout Cursor,
		depth: Int
	) throws -> CBORValue {
		guard depth <= maximumDepth else { throw CBORError.depthLimitExceeded }

		let initial = try cursor.byte()
		let major = initial >> 5
		let additional = initial & 0x1F

		if major == 7 {
			switch additional {
			case 20: return .bool(false)
			case 21: return .bool(true)
			case 22: return .null
			default: throw CBORError.unsupportedSimpleValue(additional)
			}
		}

		let argument = try decodeArgument(additional, &cursor)

		switch major {
		case 0:
			guard argument <= UInt64(Int64.max) else {
				throw CBORError.integerOutOfRange
			}
			return .integer(Int64(argument))
		case 1:
			guard argument <= UInt64(Int64.max) else {
				throw CBORError.integerOutOfRange
			}
			return .integer(~Int64(argument))
		case 2:
			return .bytes(try cursor.take(Int(clampToInt(argument))))
		case 3:
			let raw = try cursor.take(Int(clampToInt(argument)))
			guard let string = String(data: raw, encoding: .utf8) else {
				throw CBORError.invalidUTF8
			}
			return .text(string)
		case 4:
			var items: [CBORValue] = []
			for _ in 0..<clampToInt(argument) {
				items.append(try decodeValue(&cursor, depth: depth + 1))
			}
			return .array(items)
		case 5:
			var entries: [CBORMapEntry] = []
			var seen: [Data] = []
			for _ in 0..<clampToInt(argument) {
				let key = try decodeValue(&cursor, depth: depth + 1)
				let keyBytes = try encode(key)
				if seen.contains(keyBytes) { throw CBORError.duplicateMapKey }
				seen.append(keyBytes)
				let value = try decodeValue(&cursor, depth: depth + 1)
				entries.append(CBORMapEntry(key, value))
			}
			return .map(entries)
		default:
			throw CBORError.unsupportedMajorType(major)
		}
	}

	private static func decodeArgument(
		_ additional: UInt8,
		_ cursor: inout Cursor
	) throws -> UInt64 {
		switch additional {
		case 0..<24:
			return UInt64(additional)
		case 24:
			let value = UInt64(try cursor.byte())
			guard value >= 24 else { throw CBORError.nonMinimalInteger }
			return value
		case 25:
			let value = try readBigEndian(&cursor, byteCount: 2)
			guard value > 0xFF else { throw CBORError.nonMinimalInteger }
			return value
		case 26:
			let value = try readBigEndian(&cursor, byteCount: 4)
			guard value > 0xFFFF else { throw CBORError.nonMinimalInteger }
			return value
		case 27:
			let value = try readBigEndian(&cursor, byteCount: 8)
			guard value > 0xFFFF_FFFF else { throw CBORError.nonMinimalInteger }
			return value
		case 31:
			throw CBORError.indefiniteLength
		default:
			throw CBORError.nonMinimalInteger
		}
	}

	private static func readBigEndian(
		_ cursor: inout Cursor,
		byteCount: Int
	) throws -> UInt64 {
		let raw = try cursor.take(byteCount)
		return raw.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
	}

	/// A length larger than the buffer can possibly satisfy is a truncation,
	/// caught by `take`; clamping keeps the loop bounds representable first.
	private static func clampToInt(_ value: UInt64) -> Int {
		value > UInt64(Int.max) ? Int.max : Int(value)
	}
}
