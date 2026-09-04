import Foundation
import GermCBOR
import Testing

@Suite struct DeterministicCBORTests {
	@Test func integersUseTheShortestHead() throws {
		#expect(try DeterministicCBOR.encode(.integer(0)) == Data(hex: "00"))
		#expect(try DeterministicCBOR.encode(.integer(23)) == Data(hex: "17"))
		#expect(try DeterministicCBOR.encode(.integer(24)) == Data(hex: "1818"))
		#expect(try DeterministicCBOR.encode(.integer(255)) == Data(hex: "18ff"))
		#expect(try DeterministicCBOR.encode(.integer(256)) == Data(hex: "190100"))
		#expect(try DeterministicCBOR.encode(.integer(-1)) == Data(hex: "20"))
		#expect(try DeterministicCBOR.encode(.integer(-8)) == Data(hex: "27"))
	}

	/// A negative integer far enough from zero to need a multi-byte head.
	@Test func mapKeysWithMultiByteNegativeIntegersEncodeCorrectly() throws {
		let encoded = try DeterministicCBOR.encode(
			.map([CBORMapEntry(.integer(-60001), .text("x"))])
		)
		#expect(encoded == Data(hex: "a139ea606178"))
	}

	@Test func mapKeysSortByEncodedBytesRegardlessOfInsertionOrder() throws {
		let scrambled = try DeterministicCBOR.encode(
			.map([
				CBORMapEntry(.integer(-60004), .integer(4)),
				CBORMapEntry(.integer(4), .integer(2)),
				CBORMapEntry(.integer(-60001), .integer(3)),
				CBORMapEntry(.integer(1), .integer(1)),
			])
		)
		let ordered = try DeterministicCBOR.encode(
			.map([
				CBORMapEntry(.integer(1), .integer(1)),
				CBORMapEntry(.integer(4), .integer(2)),
				CBORMapEntry(.integer(-60001), .integer(3)),
				CBORMapEntry(.integer(-60004), .integer(4)),
			])
		)
		#expect(scrambled == ordered)
		// 0x01 < 0x04 < 0x39ea60 < 0x39ea63 — sorted by encoding, not by value.
		#expect(scrambled == Data(hex: "a40101040239ea600339ea6304"))
	}

	@Test func encodingRejectsDuplicateMapKeys() throws {
		#expect(throws: CBORError.duplicateMapKey) {
			try DeterministicCBOR.encode(
				.map([
					CBORMapEntry(.integer(1), .integer(1)),
					CBORMapEntry(.integer(1), .integer(2)),
				])
			)
		}
	}

	@Test func decodeRoundTripsEveryValueKind() throws {
		let value = CBORValue.array([
			.bytes(Data([0x01, 0x02])),
			.map([]),
			.text("hello"),
			.integer(-8),
			.bool(true),
			.null,
		])
		let encoded = try DeterministicCBOR.encode(value)
		#expect(try DeterministicCBOR.decode(encoded) == value)
	}

	@Test func decodeRejectsNonMinimalIntegerHeads() throws {
		// 0x1817 is 23 written in a two-byte head; canonical form is 0x17.
		#expect(throws: CBORError.nonMinimalInteger) {
			try DeterministicCBOR.decode(Data(hex: "1817"))
		}
	}

	@Test func decodeRejectsIndefiniteLength() throws {
		#expect(throws: CBORError.indefiniteLength) {
			try DeterministicCBOR.decode(Data(hex: "9f01ff"))
		}
	}

	@Test func decodeRejectsOutOfOrderMapKeys() throws {
		// {4: 2, 1: 1} — well-formed CBOR, not canonical.
		#expect(throws: CBORError.notCanonical) {
			try DeterministicCBOR.decode(Data(hex: "a204020101"))
		}
	}

	@Test func decodeRejectsDuplicateMapKeys() throws {
		#expect(throws: CBORError.duplicateMapKey) {
			try DeterministicCBOR.decode(Data(hex: "a201010102"))
		}
	}

	@Test func decodeRejectsTrailingBytes() throws {
		#expect(throws: CBORError.trailingBytes) {
			try DeterministicCBOR.decode(Data(hex: "0000"))
		}
	}

	@Test func decodeRejectsTruncatedInput() throws {
		#expect(throws: CBORError.truncated) {
			try DeterministicCBOR.decode(Data(hex: "4801020304"))
		}
	}

	@Test func decodeRejectsFloatsAndTags() throws {
		// A tag (major type 6) is outside this grammar entirely.
		#expect(throws: (any Error).self) {
			try DeterministicCBOR.decode(Data(hex: "c11a514b67b0"))
		}
		// Half-precision float.
		#expect(throws: (any Error).self) {
			try DeterministicCBOR.decode(Data(hex: "f93c00"))
		}
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
