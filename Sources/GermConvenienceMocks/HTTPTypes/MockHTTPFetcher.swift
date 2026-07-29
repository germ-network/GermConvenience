import Foundation
import GermConvenience
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

public actor MockHTTPFetcher: HTTPFetcher {
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
	/// `on(…).enqueue(…)` atomic: two chains configuring the same fetcher
	/// concurrently cannot enqueue a response against each other's url.
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
	}

	public init() {}

	private var handlers: [RequestKey: [Result<HTTPDataResponse, Error>]] = [:]
	private var requests: [RequestKey: [BundledHTTPRequest]] = [:]
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
		handlers[RequestKey(url: Self.normalized(url), method: method), default: []]
			.append(response)
	}

	private func remaining(_ key: RequestKey) -> Int {
		handlers[key, default: []].count - requests[key, default: []].count
	}

	public func data(for request: BundledHTTPRequest) throws -> HTTPDataResponse {
		guard let url = request.request.url else {
			throw Errors.unmockedRequest(request)
		}
		// log every attempt, so a rejected request is still visible to assertions
		requestLog[url, default: []].append(request)

		let exactKey = RequestKey(url: url, method: .method(request.request.method))
		let anyKey = RequestKey(url: url, method: .any)

		let key: RequestKey
		if remaining(exactKey) > 0 {
			key = exactKey
		} else if remaining(anyKey) > 0 {
			// a drained exact queue falls back to .any, so a general handler can
			// cover the remaining requests
			key = anyKey
		} else if handlers[exactKey] != nil || handlers[anyKey] != nil {
			// registered, but every queued response has been consumed. Nothing is
			// recorded against the key, so enqueuing more responses resumes here
			throw Errors.tooManyRequests
		} else {
			throw Errors.unmockedRequest(request)
		}

		let index = requests[key, default: []].count
		requests[key, default: []].append(request)
		return try handlers[key, default: []][index].get()
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
		handlers.allSatisfy { key, queue in
			requests[key, default: []].count >= queue.count
		}
	}
}
