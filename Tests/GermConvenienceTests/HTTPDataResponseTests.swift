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

	//documents a sharp edge rather than endorsing it: success() always has a result
	//type to decode, so a bodiless 2xx fails as a decode error and the status is
	//lost. Callers with no success body want expectSuccess(orError:) instead
	@Test("a 2xx with no body at all fails to decode the result type")
	func emptySuccessBodyFailsToDecode() throws {
		#expect(throws: DecodingError.self) {
			try Self.response(.noContent)
				.success(decodeResult: TokenResult.self, orError: ErrorBody.self)
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

	//behavior is the same before and after the fix - this pins the code-exact
	//branch selection, it is not a regression test
	@Test("a successful but unexpected status code decodes the error body")
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

	@Test("a failure status decodes the error body")
	func failureStatusDecodesErrorBody() throws {
		let parsed =
			try TestHTTPDataResponse
			.response(.badRequest, TestHTTPDataResponse.errorShapedBody)
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
		#expect(status.code == 400)
	}

	//the thrown case is named unsuccessful but carries the 2xx it actually got.
	//matches expect(statusCode:), which has always reported the mismatch this way
	@Test("an unexpected 2xx with an undecodable error body reports that 2xx")
	func mismatchedCodeWithUndecodableErrorBodyReportsActualStatus() throws {
		let thrown = try #require(
			#expect(throws: HTTPResponseError.self) {
				try TestHTTPDataResponse
					.response(.ok, TestHTTPDataResponse.resultShapedBody)
					.success(
						code: 201,
						decodeResult: TokenResult.self,
						orError: ErrorBody.self
					)
			}
		)

		#expect(thrown.code == 200)
	}
}

@Suite("HTTPDataResponse failure reporting") struct TestFailureReporting {
	typealias TokenResult = TestHTTPDataResponse.TokenResult
	typealias ErrorBody = TestHTTPDataResponse.ErrorBody

	//every failure path reports the same case for the same input, so callers never
	//have to match both. Before, expectSuccess() alone reported .unsuccessfulString
	@Test("every failure path reports .unsuccessful with the same payload")
	func failurePathsAgree() throws {
		let body = "plain text failure"
		let response = TestHTTPDataResponse.response(.badRequest, body)

		let thrown: [HTTPResponseError] = [
			try #require(
				#expect(throws: HTTPResponseError.self) {
					try response.expectSuccess()
				}),
			try #require(
				#expect(throws: HTTPResponseError.self) {
					try response.expect(statusCode: 200)
				}),
			try #require(
				#expect(throws: HTTPResponseError.self) {
					try response.success(
						decodeResult: TokenResult.self,
						orError: ErrorBody.self)
				}),
		]

		for error in thrown {
			guard case .unsuccessful(let code, let data) = error else {
				Issue.record("expected .unsuccessful, got \(error)")
				continue
			}
			#expect(code == 400)
			#expect(data == body.utf8Data)
			#expect(error.bodyString == body)
		}
	}

	//an empty body used to report .unsuccessfulString(400, "") because
	//String(data: Data(), encoding: .utf8) is "" rather than nil
	@Test("an empty failure body is not reported as an empty string")
	func emptyFailureBody() throws {
		let thrown = try #require(
			#expect(throws: HTTPResponseError.self) {
				try TestHTTPDataResponse.response(.badRequest).expectSuccess()
			})

		guard case .unsuccessful(let code, let data) = thrown else {
			Issue.record("expected .unsuccessful, got \(thrown)")
			return
		}
		#expect(code == 400)
		#expect(data.isEmpty)
	}
}

@Suite("ErrorResult.get") struct TestErrorResultGet {
	typealias TokenResult = TestHTTPDataResponse.TokenResult
	typealias ErrorBody = TestHTTPDataResponse.ErrorBody

	enum Mapped: Error, Equatable {
		case oauth(ErrorBody, Int)
	}

	@Test("a result is returned without invoking the mapper")
	func resultSkipsMapper() throws {
		var mapperCalled = false
		let parsed = HTTPDataResponse.ErrorResult<TokenResult, ErrorBody>
			.result(.init(accessToken: "abc123"))

		let result = try parsed.get { error, status in
			mapperCalled = true
			return Mapped.oauth(error, status.code)
		}

		#expect(result == TokenResult(accessToken: "abc123"))
		#expect(mapperCalled == false)
	}

	@Test("an error throws exactly what the mapper returns")
	func errorThrowsMappedError() throws {
		let parsed = HTTPDataResponse.ErrorResult<TokenResult, ErrorBody>
			.error(.init(error: "invalid_token"), .badRequest)

		#expect(throws: Mapped.oauth(ErrorBody(error: "invalid_token"), 400)) {
			try parsed.get { Mapped.oauth($0, $1.code) }
		}
	}
}

@Suite("HTTPDataResponse.expectSuccess(orError:)") struct TestExpectSuccessOrError {
	typealias ErrorBody = TestHTTPDataResponse.ErrorBody

	enum Mapped: Error, Equatable {
		case oauth(ErrorBody, Int)
	}

	@Test(
		"a successful status skips decoding entirely",
		arguments: [HTTPResponse.Status.ok, .created, .noContent]
	)
	func successSkipsErrorDecoding(status: HTTPResponse.Status) throws {
		var mapperCalled = false

		try TestHTTPDataResponse.response(status, TestHTTPDataResponse.errorShapedBody)
			.expectSuccess(orError: ErrorBody.self) { error, status in
				mapperCalled = true
				return Mapped.oauth(error, status.code)
			}

		#expect(mapperCalled == false)
	}

	@Test("a decodable error body throws the mapped error")
	func mapsDecodedErrorBody() throws {
		#expect(throws: Mapped.oauth(ErrorBody(error: "invalid_request"), 400)) {
			try TestHTTPDataResponse
				.response(.badRequest, TestHTTPDataResponse.errorShapedBody)
				.expectSuccess(orError: ErrorBody.self) {
					Mapped.oauth($0, $1.code)
				}
		}
	}

	@Test(
		"an undecodable or empty error body preserves the raw response",
		arguments: ["", "not json"]
	)
	func fallsBackToRawResponse(body: String) throws {
		let thrown = try #require(
			#expect(throws: HTTPResponseError.self) {
				try TestHTTPDataResponse.response(.badRequest, body)
					.expectSuccess(orError: ErrorBody.self) {
						Mapped.oauth($0, $1.code)
					}
			}
		)

		guard case .unsuccessful(let code, let data) = thrown else {
			Issue.record("expected .unsuccessful, got \(thrown)")
			return
		}
		#expect(code == 400)
		#expect(data == body.utf8Data)
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
