//
//  HTTPStreamFetcherTests.swift
//  GermConvenienceTests
//
//  No real network call — a URLProtocol stub intercepts the request, so this
//  proves the real `URLSession: HTTPStreamFetcher` conformance (not a mock of
//  it) without depending on a live endpoint. This package had no existing
//  test of `URLSession`'s own `HTTPFetcher` conformance either; this is the
//  first, and the pattern is reusable for that gap too.
//
//  Apple-only, deliberately: this exercises the Darwin `bytes(for:)`
//  implementation specifically, and whether `URLProtocol` interception via
//  `protocolClasses` behaves identically on corelibs Foundation is not
//  something this file can claim without evidence. The Linux/Android
//  delegate path is a genuinely different implementation and needs its own
//  off-Apple verification, not this test compiled somewhere it was never
//  designed to prove anything.
//

#if canImport(Darwin)
	import Foundation
	import HTTPTypes
	import Testing

	@testable import GermConvenience

	@Suite("URLSession: HTTPStreamFetcher", .serialized)
	struct HTTPStreamFetcherTests {
		private static func session() -> URLSession {
			let configuration = URLSessionConfiguration.ephemeral
			configuration.protocolClasses = [StubURLProtocol.self]
			return URLSession(configuration: configuration)
		}

		private static func request(path: String = "/probe") throws -> BundledHTTPRequest {
			try BundledHTTPRequest(url: URL(string: "https://stream.example\(path)")!)
		}

		@Test("the response is delivered, and the body reassembles byte-identical")
		func responseAndBodyRoundTrip() async throws {
			let body = Data((0..<200_000).map { UInt8($0 % 256) })
			StubURLProtocol.nextResponse = (status: 200, body: body)

			let (response, stream) = try await Self.session().streamingData(
				for: Self.request())
			#expect(response.status.code == 200)

			var reassembled = Data()
			for try await chunk in stream {
				reassembled.append(chunk)
			}
			#expect(reassembled == body)
		}

		@Test("a non-2xx status is delivered, not thrown — the caller decides")
		func nonSuccessStatusIsNotThrown() async throws {
			StubURLProtocol.nextResponse = (status: 404, body: Data("not found".utf8))

			let (response, stream) = try await Self.session().streamingData(
				for: Self.request())
			#expect(response.status.code == 404)

			var reassembled = Data()
			for try await chunk in stream {
				reassembled.append(chunk)
			}
			#expect(reassembled == Data("not found".utf8))
		}

		@Test("an empty body still finishes the stream, not just the response")
		func emptyBodyFinishesCleanly() async throws {
			StubURLProtocol.nextResponse = (status: 204, body: Data())

			let (response, stream) = try await Self.session().streamingData(
				for: Self.request())
			#expect(response.status.code == 204)

			var sawAnyChunk = false
			for try await _ in stream { sawAnyChunk = true }
			#expect(!sawAnyChunk)
		}
	}

	/// Serves one canned (status, body) pair per request, split into several
	/// `didLoad` calls so the body genuinely arrives as multiple chunks — a
	/// single-shot `didLoad` would not exercise the accumulate-and-yield loop at
	/// all, just its zero/one-chunk edges.
	private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
		nonisolated(unsafe) static var nextResponse: (status: Int, body: Data) = (
			200, Data()
		)

		override class func canInit(with request: URLRequest) -> Bool { true }
		override class func canonicalRequest(for request: URLRequest) -> URLRequest {
			request
		}

		override func startLoading() {
			let (status, body) = Self.nextResponse
			let response = HTTPURLResponse(
				url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
				headerFields: nil)!
			client?.urlProtocol(
				self, didReceive: response, cacheStoragePolicy: .notAllowed)

			if body.isEmpty {
				client?.urlProtocolDidFinishLoading(self)
				return
			}
			let chunkSize = max(1, body.count / 7)
			var offset = body.startIndex
			while offset < body.endIndex {
				//`index(_:offsetBy:)` alone traps when it overshoots endIndex —
				//exactly the last, short chunk every non-exact-multiple body has.
				//`limitedBy:` is the clamping form.
				let end =
					body.index(
						offset, offsetBy: chunkSize,
						limitedBy: body.endIndex)
					?? body.endIndex
				client?.urlProtocol(self, didLoad: body[offset..<end])
				offset = end
			}
			client?.urlProtocolDidFinishLoading(self)
		}

		override func stopLoading() {}
	}
#endif
