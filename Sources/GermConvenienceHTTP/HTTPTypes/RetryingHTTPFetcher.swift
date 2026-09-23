import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

/// Wraps a fetcher to retry idempotent (GET/HEAD) requests around 429 rate
/// limiting, transient network errors, and 5xx responses. Every other method
/// bypasses this decorator entirely, and every other status passes through
/// untouched.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
public struct RetryingHTTPFetcher: HTTPFetcher {
	private let wrapped: any HTTPFetcher
	private let policy: Policy
	private let sleep: @Sendable (Duration) async throws -> Void
	private let now: @Sendable () -> Date

	/// - Parameters:
	///   - sleep: Called for every backoff/rate-limit wait. Overridable so
	///     tests never really sleep.
	///   - now: Used to turn `ratelimit-reset` (a unix-epoch timestamp) into
	///     a wait duration. Overridable for deterministic tests.
	public init(
		wrapping fetcher: any HTTPFetcher,
		policy: Policy = .default,
		sleep: @escaping @Sendable (Duration) async throws -> Void = {
			try await Task.sleep(for: $0)
		},
		now: @escaping @Sendable () -> Date = Date.init
	) {
		self.wrapped = fetcher
		self.policy = policy
		self.sleep = sleep
		self.now = now
	}

	public func data(for request: BundledHTTPRequest) async throws -> HTTPDataResponse {
		guard Self.isIdempotent(request.request.method) else {
			return try await wrapped.data(for: request)
		}

		var attempt = 1
		while true {
			let isLastAttempt = attempt >= policy.maxAttempts
			let outcome: Decision
			do {
				let response = try await attemptOnce(request: request)
				outcome = decision(
					for: response, attempt: attempt,
					isLastAttempt: isLastAttempt)
			} catch {
				guard let kind = transientKind(of: error) else {
					throw error
				}
				outcome =
					isLastAttempt
					? .fail(kind == .timedOut ? .timedOut : .offline)
					: .retry(after: backoffDelay(attempt: attempt))
			}

			switch outcome {
			case .respond(let response):
				return response
			case .retry(let delay):
				try await sleep(delay)
				attempt += 1
			case .fail(let error):
				throw error
			}
		}
	}

	private static func isIdempotent(_ method: HTTPRequest.Method) -> Bool {
		method == .get || method == .head
	}

	/// Races the real attempt against `policy.perAttemptTimeout`; the loser
	/// is cancelled. A timeout surfaces as `URLError(.timedOut)`, the same
	/// error a real network timeout would throw, so both feed the same
	/// retry/exhaustion path below.
	private func attemptOnce(request: BundledHTTPRequest) async throws -> HTTPDataResponse {
		try await withThrowingTaskGroup(of: HTTPDataResponse.self) { group in
			group.addTask { try await wrapped.data(for: request) }
			group.addTask {
				try await Task.sleep(for: policy.perAttemptTimeout)
				throw URLError(.timedOut)
			}
			defer { group.cancelAll() }

			guard let result = try await group.next() else {
				throw URLError(.timedOut)
			}
			return result
		}
	}

	private enum Decision {
		case respond(HTTPDataResponse)
		case retry(after: Duration)
		case fail(Failure)
	}

	private static let retryable5xxStatusCodes: Set<Int> = [500, 502, 503, 504]

	private func decision(
		for response: HTTPDataResponse,
		attempt: Int,
		isLastAttempt: Bool
	) -> Decision {
		let status = response.response.status.code
		if status == 429 {
			return rateLimitDecision(
				response: response, attempt: attempt, isLastAttempt: isLastAttempt)
		}
		if Self.retryable5xxStatusCodes.contains(status), !isLastAttempt {
			return .retry(after: backoffDelay(attempt: attempt))
		}
		// Passes through untouched: every other 4xx, every 3xx (redirects
		// are never followed here), 2xx, and a 5xx once attempts are
		// exhausted.
		return .respond(response)
	}

	private func rateLimitDecision(
		response: HTTPDataResponse,
		attempt: Int,
		isLastAttempt: Bool
	) -> Decision {
		let wait = requiredRateLimitWait(for: response)
		if let wait, wait > policy.maxRateLimitWait {
			return .fail(.rateLimited(retryAfter: wait))
		}
		if isLastAttempt {
			return .fail(
				.rateLimited(retryAfter: wait ?? backoffDelay(attempt: attempt)))
		}
		return .retry(after: wait ?? backoffDelay(attempt: attempt))
	}

	/// `ratelimit-reset` (absolute unix-epoch seconds — the convention used
	/// by AT Protocol / Bluesky services, not the IETF draft's delta-seconds)
	/// takes precedence over `retry-after` (delta seconds only; an HTTP-date
	/// is not parsed) when `ratelimit-reset` yields a wait in the future. If
	/// `ratelimit-reset` is missing, non-numeric, non-finite (`inf`, `-inf`,
	/// `nan`), or resolves to at-or-before now (e.g. a delta-form value
	/// misread as a 1970 date), this falls through to `retry-after` instead.
	/// `nil` - "no wait required by a header, fall back to ordinary backoff"
	/// - means neither header yielded a future wait.
	///
	/// A parsed value is capped in `Double` space before it reaches
	/// `Duration.seconds`: a crafted header (e.g. `1e30`) parses as a finite
	/// `Double` but would trap `Duration.seconds`. The cap is
	/// `maxReportableRateLimitWait`, or just past the budget if that's larger,
	/// so a realistic wait is still reported exactly.
	private func requiredRateLimitWait(for response: HTTPDataResponse) -> Duration? {
		guard let rawSeconds = parsedRateLimitSeconds(for: response), rawSeconds > 0 else {
			return nil
		}
		let ceiling = max(
			Self.maxReportableRateLimitWait.secondsDouble,
			policy.maxRateLimitWait.secondsDouble + 1)
		return .seconds(min(rawSeconds, ceiling))
	}

	/// Well above any real rate-limit window (daily limits included), far
	/// below where `Duration.seconds(Double)` traps.
	static let maxReportableRateLimitWait: Duration = .seconds(365 * 24 * 60 * 60)

	private func parsedRateLimitSeconds(for response: HTTPDataResponse) -> Double? {
		let headers = response.response.headerFields
		if let resetString = headers[.rateLimitReset],
			let resetEpochSeconds = TimeInterval(resetString),
			resetEpochSeconds.isFinite
		{
			let wait = resetEpochSeconds - now().timeIntervalSince1970
			if wait > 0 {
				return wait
			}
		}
		if let retryAfterString = headers[.retryAfter],
			let deltaSeconds = TimeInterval(retryAfterString), deltaSeconds.isFinite
		{
			return deltaSeconds
		}
		return nil
	}

	/// Guards against a pathological `Policy`: a huge `attempt` together with
	/// a zero `baseDelay` would otherwise compute `0 * .infinity` (`NaN`), and
	/// a negative `baseDelay` combined with a huge `attempt` would compute
	/// `-.infinity` - both trap in `Duration.seconds`. The exponent is capped
	/// well below where `pow` overflows to `.infinity`, a negative base is
	/// treated as zero, and any non-finite result (belt and suspenders) falls
	/// back to `maxDelay`.
	private func backoffDelay(attempt: Int) -> Duration {
		let base = max(policy.baseDelay.secondsDouble, 0)
		let exponent = min(Double(max(attempt - 1, 0)), 62)
		let exponential = base * pow(2.0, exponent)
		guard exponential.isFinite else {
			return policy.maxDelay
		}
		return .seconds(min(exponential, policy.maxDelay.secondsDouble))
	}

	private enum TransientKind {
		case timedOut
		case offline
	}

	private func transientKind(of error: any Error) -> TransientKind? {
		guard let urlError = error as? URLError else { return nil }
		switch urlError.code {
		case .timedOut:
			return .timedOut
		case .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
			.cannotFindHost, .dnsLookupFailed:
			return .offline
		default:
			return nil
		}
	}
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension RetryingHTTPFetcher {
	/// Tuning for `RetryingHTTPFetcher`.
	public struct Policy: Sendable, Equatable {
		/// Total attempts for an idempotent request, including the first.
		public var maxAttempts: Int
		/// Starting point for exponential backoff between attempts.
		public var baseDelay: Duration
		/// Upper bound on any single backoff delay.
		public var maxDelay: Duration
		/// Bound on a single attempt's duration; a timeout counts as a retryable
		/// attempt. Only bounds latency if the wrapped fetcher itself honors
		/// task cancellation - the timeout race cancels the losing attempt, but
		/// can't force it to stop if it ignores that.
		public var perAttemptTimeout: Duration
		/// A rate-limit wait longer than this fails fast instead of sleeping.
		public var maxRateLimitWait: Duration

		public init(
			maxAttempts: Int = 3,
			baseDelay: Duration = .milliseconds(200),
			maxDelay: Duration = .seconds(10),
			perAttemptTimeout: Duration = .seconds(30),
			maxRateLimitWait: Duration = .seconds(60)
		) {
			self.maxAttempts = maxAttempts
			self.baseDelay = baseDelay
			self.maxDelay = maxDelay
			self.perAttemptTimeout = perAttemptTimeout
			self.maxRateLimitWait = maxRateLimitWait
		}

		public static let `default` = Self()
	}

	/// Errors `RetryingHTTPFetcher` throws once retries are exhausted.
	public enum Failure: Error, Sendable, Equatable {
		/// Every rate-limited attempt was exhausted, or the required wait
		/// exceeded `Policy.maxRateLimitWait`. `retryAfter` is the server's
		/// requested wait when a header supplied one, otherwise the backoff
		/// delay that would have been used for the next attempt.
		case rateLimited(retryAfter: Duration)
		/// A transient network error (no route, DNS failure, connection lost, …)
		/// persisted through every retry.
		case offline
		/// A per-attempt timeout persisted through every retry.
		case timedOut
	}
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension RetryingHTTPFetcher.Failure: LocalizedError {
	public var errorDescription: String? {
		switch self {
		case .rateLimited(let retryAfter):
			"rate limited, retry after \(retryAfter)"
		case .offline: "network is offline or unreachable"
		case .timedOut: "request timed out"
		}
	}
}

extension HTTPField.Name {
	fileprivate static let rateLimitReset = Self("ratelimit-reset")!
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension Duration {
	fileprivate var secondsDouble: Double {
		let components = components
		return Double(components.seconds) + Double(components.attoseconds) / 1e18
	}
}
