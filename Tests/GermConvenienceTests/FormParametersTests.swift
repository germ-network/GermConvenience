import Foundation
import Testing

@testable import GermConvenience

let testVectors = [
	["foo": ["bar", "quux"]],
	["föo": ["bār"]],
	["föo": ["bar"], "foo": ["bar"]],
]

@Suite("FormParameters") struct TestFormParameters {
	@Test("Set multiple with the same key") func testSetMultiple() throws {
		var params = FormParameters()
		params.set(name: "foo", value: "bar")
		params.set(name: "foo", value: "quux")

		#expect(params.entries() == [["foo", "bar"], ["foo", "quux"]])
	}

	@Test("Get first value") func testGetFirstValue() throws {
		let params = FormParameters(["foo": ["bar", "baz"]])

		let value = params.get(name: "foo")
		#expect(value != nil)
		#expect(value == "bar")

		#expect(params.get(name: "unknown") == nil)
	}

	@Test(
		"Encoding to query string",
		arguments: zip(
			testVectors,
			[
				[
					URLQueryItem(name: "foo", value: "bar"),
					URLQueryItem(name: "foo", value: "quux"),
				],
				[URLQueryItem(name: "föo", value: "bār")],
				[
					URLQueryItem(name: "föo", value: "bar"),
					URLQueryItem(name: "foo", value: "bar")
				],
			])) func testQueryItems(
			params: [String: [String]], expected: [URLQueryItem]
		)
	{
		let params = FormParameters(params)
		#expect(params.asQueryItems() == expected)
	}

	@Test(
		"Encoding to form-urlencoded",
		arguments: zip(
			testVectors,
			[
				"foo=bar&foo=quux",
				"f%C3%B6o=b%C4%81r",
				"f%C3%B6o=bar&foo=bar",
			]))
	func testEncoding(params: [String: [String]], expected: String) throws {
		let encoded = try FormParameters(params).data
		let str = String(bytes: encoded, encoding: .utf8)

		debugPrint(str!, expected)
		#expect(str == expected)
	}
}
