import Foundation
import GermConvenienceUtilities
import Testing

@Suite struct ConvenienceTests {
	@Test func expectOneOnEmptyThrows() throws {
		let empty: [Int] = []
		#expect(throws: (any Error).self) {
			try empty.expectOne()
		}
	}

	@Test func expectOneOnManyThrows() throws {
		#expect(throws: (any Error).self) {
			try [1, 2].expectOne()
		}
	}

	@Test func expectOneOnSingleReturnsElement() throws {
		#expect(try [7].expectOne() == 7)
	}

	@Test func expectOneOrLessOnEmptyReturnsNil() throws {
		let empty: [Int] = []
		#expect(try empty.expectOneOrLess() == nil)
	}

	@Test func expectOneOrLessOnSingleReturnsElement() throws {
		#expect(try [7].expectOneOrLess() == 7)
	}

	@Test func expectOneOrLessOnManyThrows() throws {
		#expect(throws: (any Error).self) {
			try [1, 2].expectOneOrLess()
		}
	}

	@Test func debugPrefixEncodesUpToFiveBytes() {
		let sevenBytes = Data([0, 1, 2, 3, 4, 5, 6])
		#expect(sevenBytes.debugPrefix == Data([0, 1, 2, 3, 4]).base64EncodedString())

		let threeBytes = Data([9, 8, 7])
		#expect(threeBytes.debugPrefix == threeBytes.base64EncodedString())
	}
}
