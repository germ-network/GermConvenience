import Testing

@testable import GermConvenience

@Suite("FormParameters")
struct name {
	@Test func encoding() async throws {
		var params = FormParameters()
		params.set(name: "foo", value: "bar")

		let encoded = try params.encode()
		let str = String(bytes: encoded, encoding: .utf8)

		#expect(str == "foo=bar")
	}
}
