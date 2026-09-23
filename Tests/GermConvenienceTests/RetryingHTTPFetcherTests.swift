import Foundation
import GermConvenienceMocks
import HTTPTypes
import Testing

@testable import GermConvenienceHTTP

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

/// Records every delay the fetcher asks it to wait, without ever really
/// sleeping.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private actor RecordingSleeper {
	private(set) var delays: [Duration] = []
	func callAsFunction(_ duration: Duration) async throws {
		delays.append(duration)
	}
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct HangingFetcher: HTTPFetcher {
	func data(for request: BundledHTTPRequest) async throws -> HTTPDataResponse {
		try await Task.sleep(for: .seconds(5))
		return .ok()
	}
}

private let testURL = URL(string: "https://example.com/api/some-endpoint")!
private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

private func request(method: HTTPRequest.Method = .get) throws -> BundledHTTPRequest {
	try BundledHTTPRequest(method: method, url: testURL)
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private func makeFetcher(
	wrapping fetcher: any HTTPFetcher,
	policy: RetryingHTTPFetcher.Policy,
	sleeper: RecordingSleeper,
	now: @escaping @Sendable () -> Date = { fixedNow }
) -> RetryingHTTPFetcher {
	RetryingHTTPFetcher(
		wrapping: fetcher,
		policy: policy,
		sleep: { try await sleeper($0) },
		now: now
	)
}

@Suite("RetryingHTTPFetcher")
struct RetryingHTTPFetcherTests {
	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("429 with retry-after retries once, sleeping the header's duration")
	func rateLimitedRetryAfterThenSuccess() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(
			.success(
				.init(
					data: Data(),
					response: .init(
						status: 429, headerFields: [.retryAfter: "2"]))))
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 200)
		#expect(await sleeper.delays == [.seconds(2)])
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("429 with ratelimit-reset sleeps reset-minus-now")
	func rateLimitedResetHeaderHonored() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		let resetEpoch = Int(fixedNow.timeIntervalSince1970) + 5
		await registration.enqueue(
			.success(
				.init(
					data: Data(),
					response: .init(
						status: 429,
						headerFields: [
							HTTPField.Name("ratelimit-reset")!: String(
								resetEpoch)
						]))))
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 200)
		#expect(await sleeper.delays == [.seconds(5)])
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A rate-limit wait beyond the policy's budget fails fast without sleeping")
	func rateLimitBeyondBudgetFailsFast() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		let farFutureEpoch = Int(fixedNow.timeIntervalSince1970) + 1000
		await registration.enqueue(
			.success(
				.init(
					data: Data(),
					response: .init(
						status: 429,
						headerFields: [
							HTTPField.Name("ratelimit-reset")!: String(
								farFutureEpoch)
						]))))
		let sleeper = RecordingSleeper()
		let policy = RetryingHTTPFetcher.Policy(maxRateLimitWait: .seconds(60))
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		do {
			_ = try await fetcher.data(for: request())
			Issue.record("expected rateLimited to be thrown")
		} catch let error as RetryingHTTPFetcher.Failure {
			#expect(error == .rateLimited(retryAfter: .seconds(1000)))
		} catch {
			Issue.record(
				"expected RetryingHTTPFetcher.Failure.rateLimited, got \(error)")
		}
		#expect(await sleeper.delays.isEmpty)
		#expect(await mock.requests(for: testURL).count == 1)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("429 exhausted after maxAttempts throws rateLimited")
	func rateLimitedExhausted() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		let policy = RetryingHTTPFetcher.Policy(maxAttempts: 3)
		for _ in 0..<policy.maxAttempts {
			await registration.enqueue(
				.success(
					.init(
						data: Data(),
						response: .init(
							status: 429,
							headerFields: [.retryAfter: "1"]))))
		}
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		do {
			_ = try await fetcher.data(for: request())
			Issue.record("expected rateLimited to be thrown")
		} catch let error as RetryingHTTPFetcher.Failure {
			#expect(error == .rateLimited(retryAfter: .seconds(1)))
		} catch {
			Issue.record(
				"expected RetryingHTTPFetcher.Failure.rateLimited, got \(error)")
		}
		#expect(await sleeper.delays.count == policy.maxAttempts - 1)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A 5xx retries with backoff then succeeds")
	func serverErrorThenSuccess() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(.success(.status(503)))
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 200)
		#expect(await sleeper.delays.count == 1)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("5xx exhausted returns the last response instead of throwing")
	func serverErrorExhaustedReturnsLastResponse() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		let policy = RetryingHTTPFetcher.Policy(maxAttempts: 2)
		await registration.enqueue(.success(.status(503)))
		await registration.enqueue(.success(.status(502)))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 502)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A 404 passes through untouched with no retry")
	func notFoundPassesThrough() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(.success(.status(404)))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 404)
		#expect(await sleeper.delays.isEmpty)
		#expect(await mock.requests(for: testURL).count == 1)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A 302 passes through untouched - redirects are never followed here")
	func redirectPassesThrough() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(.success(.status(302)))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 302)
		#expect(await sleeper.delays.isEmpty)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A persistent transient network error exhausts to offline")
	func networkErrorExhaustedIsOffline() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		let policy = RetryingHTTPFetcher.Policy(maxAttempts: 3)
		for _ in 0..<policy.maxAttempts {
			await registration.enqueue(.failure(URLError(.cannotConnectToHost)))
		}
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		do {
			_ = try await fetcher.data(for: request())
			Issue.record("expected offline to be thrown")
		} catch let error as RetryingHTTPFetcher.Failure {
			#expect(error == .offline)
		} catch {
			Issue.record("expected RetryingHTTPFetcher.Failure.offline, got \(error)")
		}
		#expect(await sleeper.delays.count == policy.maxAttempts - 1)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A persistent timeout exhausts to timedOut")
	func timeoutExhaustedIsTimedOut() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		let policy = RetryingHTTPFetcher.Policy(maxAttempts: 2)
		for _ in 0..<policy.maxAttempts {
			await registration.enqueue(.failure(URLError(.timedOut)))
		}
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		do {
			_ = try await fetcher.data(for: request())
			Issue.record("expected timedOut to be thrown")
		} catch let error as RetryingHTTPFetcher.Failure {
			#expect(error == .timedOut)
		} catch {
			Issue.record("expected RetryingHTTPFetcher.Failure.timedOut, got \(error)")
		}
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("The per-attempt timeout race converts a hang into timedOut")
	func perAttemptTimeoutFires() async throws {
		let policy = RetryingHTTPFetcher.Policy(
			maxAttempts: 1, perAttemptTimeout: .milliseconds(20))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(
			wrapping: HangingFetcher(), policy: policy, sleeper: sleeper)

		do {
			_ = try await fetcher.data(for: request())
			Issue.record("expected timedOut to be thrown")
		} catch let error as RetryingHTTPFetcher.Failure {
			#expect(error == .timedOut)
		} catch {
			Issue.record("expected RetryingHTTPFetcher.Failure.timedOut, got \(error)")
		}
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A CancellationError is rethrown immediately, never retried")
	func cancellationNotRetried() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(.failure(CancellationError()))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		do {
			_ = try await fetcher.data(for: request())
			Issue.record("expected CancellationError to be thrown")
		} catch is CancellationError {
			// expected
		} catch {
			Issue.record("expected CancellationError, got \(error)")
		}
		#expect(await sleeper.delays.isEmpty)
		#expect(await mock.requests(for: testURL).count == 1)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("POST requests bypass the decorator entirely - no retry")
	func postNotRetried() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .post)
		await registration.enqueue(.success(.status(503)))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		let response = try await fetcher.data(for: request(method: .post))

		#expect(response.response.status.code == 503)
		#expect(await sleeper.delays.isEmpty)
		#expect(await mock.requests(for: testURL, method: .post).count == 1)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("Backoff delays grow exponentially then hit the configured cap")
	func backoffDelaysCapAtMaxDelay() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		let policy = RetryingHTTPFetcher.Policy(
			maxAttempts: 6, baseDelay: .seconds(1), maxDelay: .seconds(5))
		for _ in 0..<policy.maxAttempts {
			await registration.enqueue(.success(.status(503)))
		}
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 503)
		#expect(
			await sleeper.delays == [
				.seconds(1), .seconds(2), .seconds(4), .seconds(5), .seconds(5),
			])
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test(
		"A ratelimit-reset at or before now floors the wait at ordinary backoff, never 0s",
		arguments: [0, -5]
	)
	func rateLimitResetAtOrBeforeNowFloorsAtBackoff(secondsFromNow: Int) async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		let resetEpoch = Int(fixedNow.timeIntervalSince1970) + secondsFromNow
		await registration.enqueue(
			.success(
				.init(
					data: Data(),
					response: .init(
						status: 429,
						headerFields: [
							HTTPField.Name("ratelimit-reset")!: String(
								resetEpoch)
						]))))
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let policy = RetryingHTTPFetcher.Policy(baseDelay: .milliseconds(200))
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 200)
		#expect(await sleeper.delays == [.milliseconds(200)])
	}

	// Crafted/malformed rate-limit headers must never crash the process
	// (`TimeInterval` happily parses "inf"/"nan"/huge numbers, and
	// `Duration.seconds(Double)` traps on those) and must behave sensibly -
	// absent/unparseable/non-finite falls back to normal backoff, a huge but
	// finite value fails fast.

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test(
		"A crafted retry-after never crashes and behaves sensibly",
		arguments: [
			("inf", false), ("-inf", false), ("nan", false), ("-5", false),
			("banana", false),
			("1e30", true),
		]
	)
	func craftedRetryAfterIsSafe(headerValue: String, expectFailFast: Bool) async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(
			.success(
				.init(
					data: Data(),
					response: .init(
						status: 429,
						headerFields: [.retryAfter: headerValue]))))
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let policy = RetryingHTTPFetcher.Policy(
			baseDelay: .milliseconds(50), maxRateLimitWait: .seconds(60))
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		if expectFailFast {
			do {
				_ = try await fetcher.data(for: request())
				Issue.record("expected rateLimited to be thrown for \(headerValue)")
			} catch let error as RetryingHTTPFetcher.Failure {
				#expect(
					error
						== .rateLimited(
							retryAfter: RetryingHTTPFetcher
								.maxReportableRateLimitWait))
			}
			#expect(await sleeper.delays.isEmpty)
			#expect(await mock.requests(for: testURL).count == 1)
		} else {
			let response = try await fetcher.data(for: request())
			#expect(response.response.status.code == 200)
			#expect(await sleeper.delays == [.milliseconds(50)])
		}
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test(
		"A crafted ratelimit-reset never crashes and behaves sensibly",
		arguments: [
			("inf", false), ("-inf", false), ("nan", false), ("banana", false),
			("1e30", true),
		]
	)
	func craftedRateLimitResetIsSafe(headerValue: String, expectFailFast: Bool) async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(
			.success(
				.init(
					data: Data(),
					response: .init(
						status: 429,
						headerFields: [
							HTTPField.Name("ratelimit-reset")!:
								headerValue
						]))))
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let policy = RetryingHTTPFetcher.Policy(
			baseDelay: .milliseconds(50), maxRateLimitWait: .seconds(60))
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		if expectFailFast {
			do {
				_ = try await fetcher.data(for: request())
				Issue.record("expected rateLimited to be thrown for \(headerValue)")
			} catch let error as RetryingHTTPFetcher.Failure {
				#expect(
					error
						== .rateLimited(
							retryAfter: RetryingHTTPFetcher
								.maxReportableRateLimitWait))
			}
			#expect(await sleeper.delays.isEmpty)
			#expect(await mock.requests(for: testURL).count == 1)
		} else {
			let response = try await fetcher.data(for: request())
			#expect(response.response.status.code == 200)
			#expect(await sleeper.delays == [.milliseconds(50)])
		}
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A negative ratelimit-reset never crashes and falls back to backoff")
	func negativeRateLimitResetIsSafe() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(
			.success(
				.init(
					data: Data(),
					response: .init(
						status: 429,
						headerFields: [
							HTTPField.Name("ratelimit-reset")!: "-5"
						]))))
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let policy = RetryingHTTPFetcher.Policy(
			baseDelay: .milliseconds(50), maxRateLimitWait: .seconds(60))
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 200)
		#expect(await sleeper.delays == [.milliseconds(50)])
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("Three bare 429s with no headers throw rateLimited with the exact backoff value")
	func rateLimitedExhaustedWithNoHeaderReportsBackoffValue() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		let policy = RetryingHTTPFetcher.Policy.default
		for _ in 0..<policy.maxAttempts {
			await registration.enqueue(.success(.status(429)))
		}
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		do {
			_ = try await fetcher.data(for: request())
			Issue.record("expected rateLimited to be thrown")
		} catch let error as RetryingHTTPFetcher.Failure {
			#expect(error == .rateLimited(retryAfter: .milliseconds(800)))
		} catch {
			Issue.record(
				"expected RetryingHTTPFetcher.Failure.rateLimited, got \(error)")
		}
		#expect(await sleeper.delays == [.milliseconds(200), .milliseconds(400)])
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A future ratelimit-reset wins over a differing retry-after")
	func rateLimitResetWinsOverRetryAfterWhenBothPresent() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		let resetEpoch = Int(fixedNow.timeIntervalSince1970) + 30
		await registration.enqueue(
			.success(
				.init(
					data: Data(),
					response: .init(
						status: 429,
						headerFields: [
							HTTPField.Name("ratelimit-reset")!: String(
								resetEpoch),
							.retryAfter: "99",
						]))))
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 200)
		#expect(await sleeper.delays == [.seconds(30)])
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test(
		"A ratelimit-reset at or before now falls through to retry-after when present",
		arguments: [0, -5]
	)
	func rateLimitResetAtOrBeforeNowFallsThroughToRetryAfter(secondsFromNow: Int) async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		let resetEpoch = Int(fixedNow.timeIntervalSince1970) + secondsFromNow
		await registration.enqueue(
			.success(
				.init(
					data: Data(),
					response: .init(
						status: 429,
						headerFields: [
							HTTPField.Name("ratelimit-reset")!: String(
								resetEpoch),
							.retryAfter: "7",
						]))))
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 200)
		#expect(await sleeper.delays == [.seconds(7)])
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A rate-limit wait beyond maxReportableRateLimitWait reports budget+1")
	func rateLimitBeyondReportableCeilingReportsBudgetPlusOne() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(
			.success(
				.init(
					data: Data(),
					response: .init(
						status: 429,
						headerFields: [.retryAfter: "1e30"]))))
		let sleeper = RecordingSleeper()
		let policy = RetryingHTTPFetcher.Policy(maxRateLimitWait: .seconds(63_072_000))
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		do {
			_ = try await fetcher.data(for: request())
			Issue.record("expected rateLimited to be thrown")
		} catch let error as RetryingHTTPFetcher.Failure {
			#expect(error == .rateLimited(retryAfter: .seconds(63_072_001)))
		} catch {
			Issue.record(
				"expected RetryingHTTPFetcher.Failure.rateLimited, got \(error)")
		}
		#expect(await sleeper.delays.isEmpty)
		#expect(await mock.requests(for: testURL).count == 1)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A HEAD request is retried on 503, same as GET")
	func headRetriedOn503() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .head)
		await registration.enqueue(.success(.status(503)))
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		let response = try await fetcher.data(for: request(method: .head))

		#expect(response.response.status.code == 200)
		#expect(await sleeper.delays.count == 1)
		#expect(await mock.requests(for: testURL, method: .head).count == 2)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test(
		"PUT, DELETE, and PATCH bypass the decorator entirely - no retry",
		arguments: [HTTPRequest.Method.put, .delete, .patch]
	)
	func nonIdempotentMethodsNotRetried(method: HTTPRequest.Method) async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .method(method))
		await registration.enqueue(.success(.status(503)))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		let response = try await fetcher.data(for: request(method: method))

		#expect(response.response.status.code == 503)
		#expect(await sleeper.delays.isEmpty)
		#expect(await mock.requests(for: testURL, method: .method(method)).count == 1)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A URLError(.cancelled) is rethrown immediately, never retried")
	func urlErrorCancelledNotRetried() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(.failure(URLError(.cancelled)))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		do {
			_ = try await fetcher.data(for: request())
			Issue.record("expected URLError(.cancelled) to be thrown")
		} catch let error as URLError {
			#expect(error.code == .cancelled)
		} catch {
			Issue.record("expected URLError(.cancelled), got \(error)")
		}
		#expect(await sleeper.delays.isEmpty)
		#expect(await mock.requests(for: testURL).count == 1)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test(
		"Each retryable 5xx status is retried with backoff then succeeds",
		arguments: [500, 502, 503, 504]
	)
	func retryable5xxStatusesAreRetried(status: Int) async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(.success(.status(HTTPResponse.Status(code: status))))
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 200)
		#expect(await sleeper.delays.count == 1)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A 501 is not retried - passes through untouched")
	func status501NotRetried() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(.success(.status(HTTPResponse.Status(code: 501))))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 501)
		#expect(await sleeper.delays.isEmpty)
		#expect(await mock.requests(for: testURL).count == 1)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test(
		"Every mapped transient URLError code is retried then succeeds",
		arguments: [
			URLError.Code.networkConnectionLost, .notConnectedToInternet,
			.cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
		]
	)
	func transientURLErrorCodesAreRetried(code: URLError.Code) async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(.failure(URLError(code)))
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: .default, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 200)
		#expect(await sleeper.delays.count == 1)
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test(
		"A successful attempt returns promptly - the timeout race's loser is cancelled, not awaited",
		.timeLimit(.minutes(1))
	)
	func successReturnsPromptlyDespiteLongPerAttemptTimeout() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		// Long relative to how fast the mock responds, but short enough that a
		// missing `cancelAll()` (which would force this test to wait out the
		// full timeout rather than cancel the loser) fails fast in CI instead
		// of hanging.
		let policy = RetryingHTTPFetcher.Policy(perAttemptTimeout: .seconds(20))
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)
		let clock = ContinuousClock()

		let start = clock.now
		let response = try await fetcher.data(for: request())
		let elapsed = clock.now - start

		#expect(response.response.status.code == 200)
		#expect(elapsed < .seconds(1))
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("An extreme maxAttempts with a zero baseDelay never crashes; delays stay bounded")
	func extremeMaxAttemptsWithZeroBaseDelayNeverCrashes() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		// A small perAttemptTimeout keeps this bounded: each of the ~2000
		// attempts races the (instant) mock response against this timeout.
		let policy = RetryingHTTPFetcher.Policy(
			maxAttempts: 2000, baseDelay: .zero, maxDelay: .seconds(5),
			perAttemptTimeout: .milliseconds(20))
		for _ in 0..<(policy.maxAttempts - 1) {
			await registration.enqueue(.success(.status(503)))
		}
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 200)
		let delays = await sleeper.delays
		#expect(delays.count == policy.maxAttempts - 1)
		#expect(delays.allSatisfy { $0 >= .zero && $0 <= policy.maxDelay })
	}

	@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
	@Test("A negative baseDelay never crashes; delays stay finite, non-negative, and bounded")
	func negativeBaseDelayNeverCrashes() async throws {
		let mock = MockHTTPFetcher()
		let registration = mock.on(testURL, method: .get)
		let policy = RetryingHTTPFetcher.Policy(
			maxAttempts: 5, baseDelay: .seconds(-1), maxDelay: .seconds(5),
			perAttemptTimeout: .milliseconds(20))
		for _ in 0..<(policy.maxAttempts - 1) {
			await registration.enqueue(.success(.status(503)))
		}
		await registration.enqueue(.success(.ok()))
		let sleeper = RecordingSleeper()
		let fetcher = makeFetcher(wrapping: mock, policy: policy, sleeper: sleeper)

		let response = try await fetcher.data(for: request())

		#expect(response.response.status.code == 200)
		let delays = await sleeper.delays
		#expect(delays.count == policy.maxAttempts - 1)
		#expect(delays.allSatisfy { $0 >= .zero && $0 <= policy.maxDelay })
	}
}
