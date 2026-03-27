//
//  HTTPFetcher.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 3/7/26.
//

import Foundation
import HTTPTypesFoundation

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

///This protocol wraps the HTTP types of https://github.com/apple/swift-http-types
///to provide a mockable fetch interface
///While we intend to primarily depend on Foundation, it is possible to use HTTPTypes independently
///of foundation and define your own extensions of your preferred fetch implementation
public protocol HTTPFetcher: Sendable {
	func data(for: HTTPRequest) async throws -> HTTPDataResponse
}

///Authorization fetches should not follow redirects. This includes
///the protected resource metadata
///https://www.rfc-editor.org/rfc/rfc9728.html#section-3.2
///and auth server metadata
///https://datatracker.ietf.org/doc/html/rfc8414#section-3.2
extension URLSession {
	static public func manualRedirect() -> URLSession {
		URLSession(
			configuration: .default,
			delegate: ManualRedirect(),
			delegateQueue: nil
		)
	}
}

///The default (shared) urlsession does follow redirects, which is permitted for resource requests
extension URLSession: HTTPFetcher {
	public func data(for request: HTTPRequest) async throws -> HTTPDataResponse {
		let (data, httpResponse) = try await data(for: request)

		return .init(data: data, response: httpResponse)
	}
}

final class ManualRedirect: NSObject, URLSessionTaskDelegate {
	func urlSession(
		_ session: URLSession,
		task: URLSessionTask,
		willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest request: URLRequest
	) async -> URLRequest? {
		nil
	}
}
