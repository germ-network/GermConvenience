import Foundation
import GermConvenience
import GermConvenienceMocks
import HTTPTypes
import HTTPTypesFoundation
import Testing

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

@Suite("MockHTTPFetcher") struct TestMockHTTPFetcher {
	let tokenUrl = URL(string: "https://as.example/oauth/token")!
	let revokeUrl = URL(string: "https://as.example/oauth/revoke")!
	let tokenResponse = HTTPDataResponse.ok("tokenResponse")

	@Test func registeredURLReturnsQueuedResponse() async throws {
		let mock = await MockHTTPFetcher()
			.on(tokenUrl)
			.enqueue(.success(tokenResponse))

		let request = try BundledHTTPRequest(method: .post, url: tokenUrl, body: Data())
		let result = try await mock.data(for: request)

		#expect(result.data == tokenResponse.data)
		#expect(await mock.allRequested)

		#expect(await mock.requests(for: tokenUrl) == [request])
		#expect(try await mock.firstRequest(for: tokenUrl) == request)
	}

	@Test func enqueuedErrorPropagates() async throws {
		let error = HTTPResponseError.unsuccessful(401, Data())
		let mock = await MockHTTPFetcher()
			.on(tokenUrl)
			.enqueue(.failure(error))

		let request = try BundledHTTPRequest(method: .post, url: tokenUrl, body: Data())

		await #expect(throws: error) {
			try await mock.data(for: request)
		}

		#expect(await mock.allRequested)
		#expect(await mock.requests(for: tokenUrl) == [request])
	}

	@Test func unregisteredMethodThrows() async throws {
		let mock = await MockHTTPFetcher()
			.on(tokenUrl, method: .post)
			.enqueue(.success(tokenResponse))

		let request = try BundledHTTPRequest(
			method: .get,
			url: tokenUrl
		)

		await #expect(
			throws: MockHTTPFetcher.Errors.unmockedRequest(request),
			"Should throw for an unmocked request",
		) {
			try await mock.data(for: request)
		}
	}

	@Test func unregisteredURLThrows() async throws {
		let mock = await MockHTTPFetcher()
			.on(tokenUrl)
			.enqueue(.success(tokenResponse))

		let request = try BundledHTTPRequest(
			method: .post,
			url: revokeUrl
		)

		await #expect(
			throws: MockHTTPFetcher.Errors.unmockedRequest(request),
			"Should throw for an unmocked request",
		) {
			try await mock.data(for: request)
		}
	}

	@Test func unmockedURLThrows() async throws {
		let mock = await MockHTTPFetcher()
			.on(revokeUrl).enqueue(.success(.ok("revoked")))

		let request = try BundledHTTPRequest(method: .post, url: tokenUrl, body: Data())

		await #expect(throws: MockHTTPFetcher.Errors.unmockedRequest(request)) {
			try await mock.data(for: request)
		}
	}

	@Test func tooManyRequestsThrows() async throws {
		let request1 = try BundledHTTPRequest(
			method: .post, url: tokenUrl, body: "one".utf8Data)
		let request2 = try BundledHTTPRequest(
			method: .post, url: tokenUrl, body: "two".utf8Data)

		let response = HTTPDataResponse.ok()

		let mock = await MockHTTPFetcher()
			.on(tokenUrl)
			.enqueue(.success(response))

		_ = try await mock.data(for: request1)  // consume the one response

		await #expect(throws: MockHTTPFetcher.Errors.tooManyRequests) {
			try await mock.data(for: request2)
		}

		// We should have multiple requests, even though the second request failed
		// with tooManyRequests:
		#expect(await mock.requests(for: tokenUrl) == [request1, request2])
		#expect(try await mock.firstRequest(for: tokenUrl) == request1)
		#expect(try await mock.secondRequest(for: tokenUrl) == request2)
	}

	@Test func exactMethodFallsBackToAny() async throws {
		let postResponse = HTTPDataResponse.ok("post")
		let anyResponse = HTTPDataResponse.ok("any")

		let mock = await MockHTTPFetcher()
			.on(tokenUrl, method: .post).enqueue(.success(postResponse))
			.on(tokenUrl).enqueue(.success(anyResponse))

		let postRequest = try BundledHTTPRequest(method: .post, url: tokenUrl, body: Data())
		let getRequest = try BundledHTTPRequest(method: .get, url: tokenUrl)

		#expect(try await mock.data(for: postRequest).data == postResponse.data)
		#expect(try await mock.data(for: getRequest).data == anyResponse.data)

		#expect(await mock.requests(for: tokenUrl).count == 2)
		#expect(await mock.requests(for: tokenUrl, method: .post) == [postRequest])
		#expect(await mock.requests(for: tokenUrl, method: .get) == [getRequest])
	}

	@Test func exhaustedExactHandlerFallsBackToAny() async throws {
		let first = HTTPDataResponse.ok("first")
		let fallback = HTTPDataResponse.ok("fallback")

		let mock = await MockHTTPFetcher()
			.on(tokenUrl, method: .post).enqueue(.success(first))
			.on(tokenUrl).enqueue(.success(fallback))

		let request = try BundledHTTPRequest(method: .post, url: tokenUrl, body: Data())

		// exact
		#expect(try await mock.data(for: request).data == first.data)
		// falls back to to any
		#expect(try await mock.data(for: request).data == fallback.data)
	}

	// with no .any handler to fall back to, a drained exact queue is still a
	// registered one - it should report over-requesting, not "never mocked"
	@Test func exhaustedExactHandlerWithNoFallbackReportsTooManyRequests() async throws {
		let mock = await MockHTTPFetcher()
			.on(tokenUrl, method: .post)
			.enqueue(.success(.ok("first")))

		let request = try BundledHTTPRequest(method: .post, url: tokenUrl, body: Data())

		#expect(try await mock.data(for: request).data == "first".utf8Data)

		await #expect(throws: MockHTTPFetcher.Errors.tooManyRequests) {
			try await mock.data(for: request)
		}
	}

	// a request that matched nothing is still something the code under test sent,
	// so it belongs in the log alongside the tooManyRequests case
	@Test func unmockedRequestsAreStillLogged() async throws {
		let mock = await MockHTTPFetcher()
			.on(revokeUrl)
			.enqueue(.success(.ok("revoked")))

		let request = try BundledHTTPRequest(method: .post, url: tokenUrl, body: Data())

		await #expect(throws: MockHTTPFetcher.Errors.unmockedRequest(request)) {
			try await mock.data(for: request)
		}

		#expect(await mock.requests(for: tokenUrl) == [request])
		#expect(await mock.allRequested == false)
	}

	// HTTPRequest rewrites a bare origin's empty path to "/", so registering on
	// the origin used to key a url that no request could ever match
	@Test func registrationOnABareOriginMatches() async throws {
		let origin = URL(string: "https://as.example")!
		let mock = await MockHTTPFetcher()
			.on(origin)
			.enqueue(.success(.ok("root")))

		let request = try BundledHTTPRequest(method: .post, url: origin, body: Data())

		#expect(try await mock.data(for: request).data == "root".utf8Data)
		#expect(await mock.requests(for: origin) == [request])
		#expect(await mock.allRequested)
	}

	// the queue is not poisoned by an over-request: enqueuing more resumes it
	@Test func enqueueingAfterTooManyRequestsResumes() async throws {
		let mock = await MockHTTPFetcher()
			.on(tokenUrl)
			.enqueue(.success(.ok("first")))

		let request = try BundledHTTPRequest(method: .post, url: tokenUrl, body: Data())
		#expect(try await mock.data(for: request).data == "first".utf8Data)

		await #expect(throws: MockHTTPFetcher.Errors.tooManyRequests) {
			try await mock.data(for: request)
		}

		await mock.on(tokenUrl).enqueue(.success(.ok("second")))
		#expect(try await mock.data(for: request).data == "second".utf8Data)
	}

	// on() carries the url in its return value rather than parking it on the
	// fetcher, so concurrent configuration cannot cross-contaminate
	@Test func concurrentConfigurationDoesNotMisattributeResponses() async throws {
		let mock = MockHTTPFetcher()

		await withTaskGroup(of: Void.self) { group in
			for _ in 0..<8 {
				group.addTask {
					await mock.on(tokenUrl).enqueue(.success(.ok("token")))
				}
				group.addTask {
					await mock.on(revokeUrl).enqueue(.success(.ok("revoke")))
				}
			}
			await group.waitForAll()
		}

		let tokenRequest = try BundledHTTPRequest(
			method: .post, url: tokenUrl, body: Data())
		let revokeRequest = try BundledHTTPRequest(
			method: .post, url: revokeUrl, body: Data())

		for _ in 0..<8 {
			#expect(try await mock.data(for: tokenRequest).data == "token".utf8Data)
			#expect(try await mock.data(for: revokeRequest).data == "revoke".utf8Data)
		}
		#expect(await mock.allRequested)
	}
}
