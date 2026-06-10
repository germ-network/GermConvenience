import Foundation
import GermConvenience
import HTTPTypes

extension BundledHTTPRequest: Equatable {
	public static func == (lhs: BundledHTTPRequest, rhs: BundledHTTPRequest) -> Bool {
		lhs.request.method == rhs.request.method && lhs.request.url == rhs.request.url
			&& lhs.request.headerFields == rhs.request.headerFields
			&& lhs.body == rhs.body
	}
}

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
		case missingOnUrl
		case tooManyRequests
		case notRequested
		case unmockedRequest(_ request: BundledHTTPRequest)
	}

	private struct RequestKey: Hashable {
		let url: URL
		let method: MethodMatcher
	}

	public init() {}

	private var currentUrl: URL?
	private var currentMethod: MethodMatcher = .post
	private var handlers: [RequestKey: [Result<HTTPDataResponse, Error>]] = [:]
	private var requests: [RequestKey: [BundledHTTPRequest]] = [:]
	private var requestLog: [URL: [BundledHTTPRequest]] = [:]

	@discardableResult
	public func on(_ url: URL, method: MethodMatcher = .any) -> Self {
		currentUrl = url
		currentMethod = method
		return self
	}

	@discardableResult
	public func enqueue(_ response: Result<HTTPDataResponse, Error>) throws -> Self {
		guard let url = currentUrl else {
			throw Errors.missingOnUrl
		}
		handlers[RequestKey(url: url, method: currentMethod), default: []].append(response)
		return self
	}

	public func data(for request: BundledHTTPRequest) throws -> HTTPDataResponse {
		guard let url = request.request.url else {
			throw Errors.unmockedRequest(request)
		}
		let exactKey = RequestKey(url: url, method: .method(request.request.method))
		let anyKey = RequestKey(url: url, method: .any)
		let exactHandlerCount = handlers[exactKey, default: []].count
		let exactRequestCount = requests[exactKey, default: []].count
		let key: RequestKey =
			(exactHandlerCount > 0 && exactRequestCount < exactHandlerCount)
			? exactKey : anyKey

		let handlerCount = handlers[key, default: []].count
		if handlerCount == 0 {
			throw Errors.unmockedRequest(request)
		}

		requests[key, default: []].append(request)
		requestLog[url, default: []].append(request)
		let requestCount = requests[key, default: []].count
		if requestCount > handlerCount {
			throw Errors.tooManyRequests
		}

		return try handlers[key, default: []][requestCount - 1].get()
	}

	public func requests(for url: URL) -> [BundledHTTPRequest] {
		requestLog[url, default: []]
	}

	public func requests(for url: URL, method: MethodMatcher) -> [BundledHTTPRequest] {
		requestLog[url, default: []].filter {
			switch method {
			case .any: return true
			case .method(let m): return $0.request.method == m
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
