import Foundation
import HTTPTypes
import Testing

@testable import GermConvenience

@Suite("BundledHTTPRequest") struct TestBundledHTTPRequest {
	static let url = URL(string: "https://as.example/oauth/token")!

	@Test("a get with a body is rejected")
	func getRejectsABody() throws {
		#expect(throws: HTTPRequestError.getMethodWithBody) {
			try BundledHTTPRequest(method: .get, url: Self.url, body: Data([1]))
		}
	}

	//this path used to assert(false) before throwing, so in a debug build it
	//trapped instead of surfacing the error, and could not be tested at all
	@Test("a url with no scheme is rejected")
	func schemeIsRequired() throws {
		#expect(throws: HTTPRequestError.missingScheme) {
			try BundledHTTPRequest(url: URL(string: "as.example/token")!)
		}
	}

	//HTTPRequest drops everything after the scheme for these, reporting url == nil,
	//so the request could never be sent and every urn: compared equal to every other
	@Test(
		"a url HTTPRequest cannot represent is rejected",
		arguments: ["urn:isbn:1", "mailto:a@example.com"]
	)
	func unrepresentableURLIsRejected(raw: String) throws {
		let url = URL(string: raw)!
		#expect(throws: HTTPRequestError.unrepresentableURL(url)) {
			try BundledHTTPRequest(url: url)
		}
	}
}

@Suite("BundledHTTPRequest.settingHeader") struct TestSettingHeader {
	static func request() throws -> BundledHTTPRequest {
		try BundledHTTPRequest(
			method: .post,
			url: TestBundledHTTPRequest.url,
			headerFields: [.contentType: "application/json"],
			body: Data([1, 2, 3])
		)
	}

	@Test("sets a field that was not present")
	func setsNewField() throws {
		let updated = try Self.request().settingHeader("Bearer abc", for: .authorization)
		#expect(updated.request.headerFields[.authorization] == "Bearer abc")
	}

	@Test("replaces rather than appends an existing field")
	func replacesExistingField() throws {
		let updated = try Self.request().settingHeader("text/plain", for: .contentType)
		#expect(updated.request.headerFields[.contentType] == "text/plain")
		#expect(updated.request.headerFields[values: .contentType].count == 1)
	}

	@Test("a nil value removes the field")
	func nilRemovesField() throws {
		let updated = try Self.request().settingHeader(nil, for: .contentType)
		#expect(updated.request.headerFields[.contentType] == nil)
	}

	@Test("an empty string is a value, not a removal")
	func emptyStringIsNotRemoval() throws {
		let updated = try Self.request().settingHeader("", for: .contentType)
		#expect(updated.request.headerFields[.contentType] == "")
	}

	@Test("method, url and body are carried through untouched")
	func preservesEverythingElse() throws {
		let original = try Self.request()
		let updated = original.settingHeader("Bearer abc", for: .authorization)

		#expect(updated.request.method == original.request.method)
		#expect(updated.request.url == original.request.url)
		#expect(updated.body == original.body)
	}

	@Test("the original is unchanged")
	func doesNotMutateTheReceiver() throws {
		let original = try Self.request()
		_ = original.settingHeader("Bearer abc", for: .authorization)

		#expect(original.request.headerFields[.authorization] == nil)
	}

	//documented sharp edge: HTTPFields' setter replaces every field of a name,
	//so repeated fields cannot survive a round trip through this API
	@Test("repeated fields collapse to one comma-joined value")
	func repeatedFieldsCollapse() throws {
		var fields = HTTPFields()
		fields.append(HTTPField(name: .acceptEncoding, value: "gzip"))
		fields.append(HTTPField(name: .acceptEncoding, value: "br"))

		let original = try BundledHTTPRequest(
			method: .get, url: TestBundledHTTPRequest.url, headerFields: fields)
		#expect(original.request.headerFields[values: .acceptEncoding].count == 2)

		let roundTripped = original.settingHeader(
			original.request.headerFields[.acceptEncoding], for: .acceptEncoding)

		#expect(roundTripped.request.headerFields[values: .acceptEncoding] == ["gzip, br"])
		#expect(roundTripped != original)
	}
}

@Suite("BundledHTTPRequest: Equatable") struct TestBundledHTTPRequestEquatable {
	@Test("identical requests are equal")
	func identicalRequestsAreEqual() throws {
		let a = try BundledHTTPRequest(
			method: .post, url: TestBundledHTTPRequest.url, body: Data([1]))
		let b = try BundledHTTPRequest(
			method: .post, url: TestBundledHTTPRequest.url, body: Data([1]))

		#expect(a == b)
	}

	@Test("method, body and headers all participate")
	func fieldsParticipate() throws {
		let base = try BundledHTTPRequest(
			method: .post, url: TestBundledHTTPRequest.url, body: Data([1]))

		#expect(
			try base
				!= BundledHTTPRequest(
					method: .put, url: TestBundledHTTPRequest.url,
					body: Data([1])))
		#expect(
			try base
				!= BundledHTTPRequest(
					method: .post, url: TestBundledHTTPRequest.url,
					body: Data([2])))
		#expect(base != base.settingHeader("Bearer abc", for: .authorization))
	}

	@Test("differing paths on the same origin are distinct")
	func pathsAreDistinct() throws {
		let a = try BundledHTTPRequest(url: URL(string: "https://as.example/a")!)
		let b = try BundledHTTPRequest(url: URL(string: "https://as.example/b")!)

		#expect(a != b)
	}
}
