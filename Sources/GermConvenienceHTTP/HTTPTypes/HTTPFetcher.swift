//
//  HTTPFetcher.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 3/7/26.
//

import Foundation

///This protocol wraps the HTTP types of https://github.com/apple/swift-http-types
///to provide a mockable fetch interface
///While we intend to primarily depend on Foundation, it is possible to use HTTPTypes independently
///of foundation and define your own extensions of your preferred fetch implementation
public protocol HTTPFetcher: Sendable {
	func data(for: BundledHTTPRequest) async throws -> HTTPDataResponse
}

///An `HTTPFetcher` that never follows a redirect: a 3xx answer is returned as the
///response (status and headers) rather than being fetched through.
///
///This is a semantic promise the compiler cannot check, so conformance is opt-in.
///Require it where a followed redirect would bypass validation that ran once,
///before the request, such as host screening of attacker-influenced input or
///authorization metadata fetches. A plain `HTTPFetcher` does not satisfy it.
public protocol RedirectRefusingHTTPFetcher: HTTPFetcher {}
