import Foundation
import GermConvenienceUtilities
import Testing

@Suite struct CodingTests {
	struct Payload: Codable, Equatable {
		let value: Int
	}

	@Test func encodedAndDecodedRoundTrip() throws {
		let payload = Payload(value: 7)
		let data = try payload.encoded
		let decoded: Payload = try data.decoded()
		#expect(decoded == payload)
	}

	@Test func decodingBadJSONThrowsTypedCodableError() throws {
		let bad = Data("not json".utf8)
		let error = #expect(throws: TypedCodableError.self) {
			let _: Payload = try bad.decoded()
		}
		guard case .decode(let name, _) = error else {
			Issue.record("expected .decode, got \(String(describing: error))")
			return
		}
		#expect(name.contains("Payload"))
	}

	@Test func errorDescriptions() {
		#expect(
			TypedCodableError.typeMismatch.errorDescription
				== "Typed JSON decoding mismatch between declared and expected type"
		)
		#expect(
			TypedCodableError.missingStoredValue.errorDescription
				== "Expect stored value missing")
	}
}
