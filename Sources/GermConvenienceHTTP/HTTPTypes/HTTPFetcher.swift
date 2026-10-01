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
