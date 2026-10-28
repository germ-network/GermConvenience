import Foundation
import GermConvenienceUtilities
import Testing

@Suite struct ConvenienceTests {
	@Test func singleElementOnEmptyThrows() throws {
		let empty: [Int] = []
		let error = #expect(throws: (any Error).self) {
			try empty.singleElement()
		}
		#expect(
			(error as? LocalizedError)?.errorDescription
				== "Expected to find one Int, but didn't.")
	}

	@Test func singleElementOnManyThrows() throws {
		let error = #expect(throws: (any Error).self) {
			try [1, 2].singleElement()
		}
		#expect(
			(error as? LocalizedError)?.errorDescription == "Found more than one Int.")
	}

	@Test func singleElementOnSingleReturnsElement() throws {
		#expect(try [7].singleElement() == 7)
	}

	@Test func singleElementIfAnyOnEmptyReturnsNil() throws {
		let empty: [Int] = []
		#expect(try empty.singleElementIfAny() == nil)
	}

	@Test func singleElementIfAnyOnSingleReturnsElement() throws {
		#expect(try [7].singleElementIfAny() == 7)
	}

	@Test func singleElementIfAnyOnManyThrows() throws {
		let error = #expect(throws: (any Error).self) {
			try [1, 2].singleElementIfAny()
		}
		#expect(
			(error as? LocalizedError)?.errorDescription == "Found more than one Int.")
	}

	@Test func debugPrefixEncodesUpToFiveBytes() {
		let sevenBytes = Data([0, 1, 2, 3, 4, 5, 6])
		#expect(sevenBytes.debugPrefix == "AAECAwQ=")

		let threeBytes = Data([9, 8, 7])
		#expect(threeBytes.debugPrefix == threeBytes.base64EncodedString())
	}
}
