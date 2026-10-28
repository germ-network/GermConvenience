import Foundation
import GermConvenience
import GermConvenienceMocks
import Testing

@Suite("FormParameters+Parsing")
struct TestFormParametersParsing {
	static let testVectors = [
		["grant_type": ["authorization_code"]],
		["client_id": ["foo"], "code": ["bar123"]],
		["code": ["abc123=="]],
		["scope": ["read", "write"]],
		["state": ["hello world"]],
		[:],
	]

	@Test("Parsing from .encodedData", arguments: testVectors) func testInOutData(
		vector: [String: [String]]
	) throws {
		let form = FormParameters(vector)
		let parsed = FormParameters(parsing: form.encodedData)

		#expect(parsed == form)
	}

	@Test("Parsing from .queryItems", arguments: testVectors) func testInOutQueryItems(
		vector: [String: [String]]
	) throws {
		let form = FormParameters(vector)
		let parsed = FormParameters(parsing: form.queryItems)

		#expect(parsed == form)
	}
}
