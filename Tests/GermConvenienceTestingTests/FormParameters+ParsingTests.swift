import Foundation
import Testing

@testable import GermConvenience
@testable import GermConvenienceTesting

let testVectors = [
	["grant_type": ["authorization_code"]],
	["client_id": ["foo"], "code": ["bar123"]],
	["code": ["abc123=="]],
	["scope": ["read", "write"]],
	["state": ["hello world"]],
	[:],
]

@Suite("FormParameters+Parsing") struct TestFormParameters {
	@Test("Parsing from .data", arguments: testVectors) func testInOutData(
		vector: [String: [String]]
	) throws {
		let form = FormParameters(vector)
		let parsed = FormParameters(parsing: form.data)

		#expect(parsed == form)
	}

	@Test("Parsing from .asQueryItems()", arguments: testVectors) func testInOutQueryItems(
		vector: [String: [String]]
	) throws {
		let form = FormParameters(vector)
		let parsed = FormParameters(parsing: form.asQueryItems())

		#expect(parsed == form)
	}
}
