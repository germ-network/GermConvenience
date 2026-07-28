import Foundation
import HTTPTypes
import Testing

@testable import GermConvenience

@Suite("HTTPDataResponse") struct TestHTTPDataResponse {
	struct TokenResult: Codable, Equatable {
		let accessToken: String
	}

	struct ErrorBody: Codable, Equatable {
		let error: String
	}

	static func response(
		_ status: HTTPResponse.Status,
		_ body: String = ""
	) -> HTTPDataResponse {
		.init(data: body.utf8Data, response: .init(status: status))
	}

	//decodes as ErrorBody but not as TokenResult, which is what distinguishes the
	//fixed implementation from the buggy one
	static let errorShapedBody = #"{"error":"invalid_request"}"#
	static let resultShapedBody = #"{"accessToken":"abc123"}"#

	@Test("a successful status decodes the result")
	func successDecodesResult() throws {
		let parsed = try Self.response(.ok, Self.resultShapedBody)
			.success(decodeResult: TokenResult.self, orError: ErrorBody.self)

		guard case .result(let result) = parsed else {
			Issue.record("expected .result, got \(parsed)")
			return
		}
		#expect(result == TokenResult(accessToken: "abc123"))
	}

	//regression: the buggy implementation caught the result decode failure and
	//re-decoded the body as the error type, returning .error for a 2xx
	@Test("a successful status with an undecodable result throws")
	func successWithUndecodableResultThrows() throws {
		#expect(throws: DecodingError.self) {
			try Self.response(.ok, Self.errorShapedBody)
				.success(decodeResult: TokenResult.self, orError: ErrorBody.self)
		}
	}

	@Test("a failure status decodes the error body")
	func failureDecodesErrorBody() throws {
		let parsed = try Self.response(.badRequest, Self.errorShapedBody)
			.success(decodeResult: TokenResult.self, orError: ErrorBody.self)

		guard case .error(let error, let status) = parsed else {
			Issue.record("expected .error, got \(parsed)")
			return
		}
		#expect(error == ErrorBody(error: "invalid_request"))
		#expect(status.code == 400)
	}

	//regression: previously propagated a bare DecodingError, losing the status
	@Test(
		"a failure status with an undecodable error body preserves the response",
		arguments: ["", "not json", "<html>502 Bad Gateway</html>"]
	)
	func failureWithUndecodableErrorBodyPreservesResponse(body: String) throws {
		let thrown = try #require(
			#expect(throws: HTTPResponseError.self) {
				try Self.response(.badGateway, body)
					.success(
						decodeResult: TokenResult.self,
						orError: ErrorBody.self)
			}
		)

		guard case .unsuccessful(let code, let data) = thrown else {
			Issue.record("expected .unsuccessful, got \(thrown)")
			return
		}
		#expect(code == 502)
		#expect(data == body.utf8Data)
	}

	@Test(
		"success is status-kind based, not code exact",
		arguments: [
			HTTPResponse.Status.ok, .created, .accepted, .noContent,
		])
	func successAcceptsAnySuccessfulKind(status: HTTPResponse.Status) throws {
		let parsed = try Self.response(status, Self.resultShapedBody)
			.success(decodeResult: TokenResult.self, orError: ErrorBody.self)

		guard case .result = parsed else {
			Issue.record("expected .result for \(status), got \(parsed)")
			return
		}
	}
}

@Suite("HTTPDataResponse.success(code:)") struct TestHTTPDataResponseSuccessCode {
	typealias TokenResult = TestHTTPDataResponse.TokenResult
	typealias ErrorBody = TestHTTPDataResponse.ErrorBody

	@Test("a matching status code decodes the result")
	func matchingCodeDecodesResult() throws {
		let parsed =
			try TestHTTPDataResponse
			.response(.created, TestHTTPDataResponse.resultShapedBody)
			.success(
				code: 201,
				decodeResult: TokenResult.self,
				orError: ErrorBody.self
			)

		guard case .result(let result) = parsed else {
			Issue.record("expected .result, got \(parsed)")
			return
		}
		#expect(result == TokenResult(accessToken: "abc123"))
	}

	//a 200 is successful but is not the expected 201
	@Test("a mismatched status code decodes the error body")
	func mismatchedCodeDecodesErrorBody() throws {
		let parsed =
			try TestHTTPDataResponse
			.response(.ok, TestHTTPDataResponse.errorShapedBody)
			.success(
				code: 201,
				decodeResult: TokenResult.self,
				orError: ErrorBody.self
			)

		guard case .error(let error, let status) = parsed else {
			Issue.record("expected .error, got \(parsed)")
			return
		}
		#expect(error == ErrorBody(error: "invalid_request"))
		#expect(status.code == 200)
	}

	@Test("a matching status code with an undecodable result throws")
	func matchingCodeWithUndecodableResultThrows() throws {
		#expect(throws: DecodingError.self) {
			try TestHTTPDataResponse
				.response(.created, TestHTTPDataResponse.errorShapedBody)
				.success(
					code: 201,
					decodeResult: TokenResult.self,
					orError: ErrorBody.self
				)
		}
	}
}

@Suite("HTTPResponseError") struct TestHTTPResponseError {
	@Test("code reads from either case")
	func codeReadsFromEitherCase() {
		#expect(HTTPResponseError.unsuccessful(404, Data()).code == 404)
		#expect(HTTPResponseError.unsuccessfulString(500, "boom").code == 500)
	}

	@Test("bodyString reads from either case")
	func bodyStringReadsFromEitherCase() {
		#expect(HTTPResponseError.unsuccessful(400, "oops".utf8Data).bodyString == "oops")
		#expect(HTTPResponseError.unsuccessfulString(400, "oops").bodyString == "oops")
	}

	@Test("bodyString is nil for bytes that are not utf8")
	func bodyStringIsNilForNonUtf8() {
		let invalidUtf8 = Data([0xFF, 0xFE, 0xFD])
		#expect(HTTPResponseError.unsuccessful(400, invalidUtf8).bodyString == nil)
	}
}
