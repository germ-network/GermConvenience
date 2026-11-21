import Foundation
import GermConvenience
import GermConvenienceHTTP
import HTTPTypes

extension HTTPDataResponse {
	public static func ok(_ data: Data = Data()) -> Self {
		Self(data: data, response: HTTPResponse(status: .ok))
	}
	public static func ok(_ body: String) -> Self {
		.ok(body.utf8Data)
	}
	public static func status(_ status: HTTPResponse.Status, data: Data = Data()) -> Self {
		Self(data: data, response: HTTPResponse(status: status))
	}
}

public enum MethodMatcher: Hashable, Sendable {
	case method(HTTPRequest.Method)
	case any

	public static let options: Self = .method(.options)
	public static let head: Self = .method(.head)
	public static let get: Self = .method(.get)
	public static let post: Self = .method(.post)
	public static let put: Self = .method(.put)
	public static let patch: Self = .method(.patch)
	public static let delete: Self = .method(.delete)
}

///Returns only what was registered, so it never follows a redirect.
public actor MockHTTPFetcher: RedirectRefusingHTTPFetcher {
	public enum Errors: Equatable, Error {
		case tooManyRequests
		case notRequested
		case unmockedRequest(_ request: BundledHTTPRequest)
	}

	private struct RequestKey: Hashable {
		let url: URL
		let method: MethodMatcher
	}

	/// The target of a registration, produced by `on(_:method:)`.
	///
	/// Carrying the url and method in the value rather than on the fetcher keeps
	/// `on(…).enqueue(…)` and `on(…).always(…)` atomic: two chains configuring
	/// the same fetcher concurrently cannot register a response against each
	/// other's url.
	///
	/// - Note: responses enqueued concurrently against the *same* url have no
	///   defined order relative to each other.
	public struct Registration: Sendable {
		fileprivate let fetcher: MockHTTPFetcher
		fileprivate let url: URL
		fileprivate let method: MethodMatcher

		@discardableResult
		public func enqueue(
			_ response: Result<HTTPDataResponse, Error>
		) async -> MockHTTPFetcher {
			await fetcher.append(url: url, method: method, response)
			return fetcher
		}

		/// Answers every request with `response` once responses enqueued for the
		/// same url and method are used up, so a test can script the first few
		/// responses and then a steady state. An exact-method `always` answers
		/// before any `.any` registration for the url, queued or not. Replaces an
		/// earlier `always` for this url and method. Never used up, so
		/// `allRequested` ignores it.
		@discardableResult
		public func always(
			_ response: Result<HTTPDataResponse, Error>
		) async -> MockHTTPFetcher {
			await fetcher.setFallback(url: url, method: method, response)
			return fetcher
		}
	}

	public init() {}

	/// What is registered for one url and method.
	private struct Responses {
		/// Consumed in order: the nth request takes `queued[n]`.
		var queued: [Result<HTTPDataResponse, Error>] = []
		/// How many of `queued` have been taken.
		var consumed = 0
		/// Answers every request once `queued` is used up; never used up itself.
		var fallback: Result<HTTPDataResponse, Error>?

		var remaining: Int { queued.count - consumed }

		/// The next queued response, then `fallback` once `queued` is used up, or
		/// `nil` if there is neither.
		mutating func next() -> Result<HTTPDataResponse, Error>? {
			guard consumed < queued.count else { return fallback }
			// after the guard, so neither a drained queue nor the fallback
			// advances `consumed`
			defer { consumed += 1 }
			return queued[consumed]
		}
	}

	private var handlers: [RequestKey: Responses] = [:]
	private var requestLog: [URL: [BundledHTTPRequest]] = [:]

	public nonisolated func on(_ url: URL, method: MethodMatcher = .any) -> Registration {
		Registration(fetcher: self, url: url, method: method)
	}

	//lookup keys off request.request.url, which HTTPRequest has round-tripped
	//through its pseudo header fields - that rewrites a bare origin's empty path
	//to "/". Register through the same round trip or on(origin) never matches
	private nonisolated static func normalized(_ url: URL) -> URL {
		guard url.scheme != nil else { return url }
		return HTTPRequest(method: .get, url: url).url ?? url
	}

	fileprivate func append(
		url: URL,
		method: MethodMatcher,
		_ response: Result<HTTPDataResponse, Error>
	) {
		let key = RequestKey(url: Self.normalized(url), method: method)
		handlers[key, default: Responses()].queued.append(response)
	}

	fileprivate func setFallback(
		url: URL,
		method: MethodMatcher,
		_ response: Result<HTTPDataResponse, Error>
	) {
		let key = RequestKey(url: Self.normalized(url), method: method)
		handlers[key, default: Responses()].fallback = response
	}

	public func data(for request: BundledHTTPRequest) throws -> HTTPDataResponse {
		guard let url = request.request.url else {
			throw Errors.unmockedRequest(request)
		}
		// log every attempt, so a rejected request is still visible to assertions
		requestLog[url, default: []].append(request)

		let exactKey = RequestKey(url: url, method: .method(request.request.method))
		let anyKey = RequestKey(url: url, method: .any)
		// the most specific registration wins: the exact method's queue, then its
		// fallback. `??` only consults .any once that has nothing, so a general
		// handler can cover the remaining requests
		if let response = handlers[exactKey]?.next() ?? handlers[anyKey]?.next() {
			return try response.get()
		} else if handlers[exactKey] != nil || handlers[anyKey] != nil {
			// registered, but every queued response has been consumed and no fallback
			// is registered. `consumed` is not advanced, so enqueuing more responses
			// resumes here
			throw Errors.tooManyRequests
		} else {
			throw Errors.unmockedRequest(request)
		}
	}

	/// Every request sent to `url`, including ones rejected as unmocked or over
	/// the queue length. `allRequested` counts only those that consumed a
	/// response, so the two can disagree after a rejection.
	public func requests(for url: URL) -> [BundledHTTPRequest] {
		requestLog[Self.normalized(url), default: []]
	}

	public func requests(for url: URL, method: MethodMatcher) -> [BundledHTTPRequest] {
		requests(for: url).filter {
			switch method {
			case .any: true
			case .method(let m): $0.request.method == m
			}
		}
	}

	public func request(
		at index: Int,
		for url: URL,
		method: MethodMatcher = .any
	) throws
		-> BundledHTTPRequest
	{
		let matchingRequests = requests(for: url, method: method)
		guard matchingRequests.indices.contains(index) else {
			throw Errors.notRequested
		}
		return matchingRequests[index]
	}

	public func firstRequest(for url: URL, method: MethodMatcher = .any) throws
		-> BundledHTTPRequest
	{
		try request(at: 0, for: url, method: method)
	}

	public func secondRequest(for url: URL, method: MethodMatcher = .any) throws
		-> BundledHTTPRequest
	{
		try request(at: 1, for: url, method: method)
	}

	public var allRequested: Bool {
		// a fallback is never used up, so only queued responses count
		handlers.values.allSatisfy { $0.remaining <= 0 }
	}
}
