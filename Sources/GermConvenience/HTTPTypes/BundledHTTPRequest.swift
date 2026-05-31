//
//  HTTPRequestBody.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 3/27/26.
//

import Foundation
import HTTPTypes

//unlike URLRequest, HTTPRequest doesn't carry the request body,
//for convenience we pass them together

public struct BundledHTTPRequest: Sendable {
	public var request: HTTPRequest
	public var body: Data?

	public init(
		method: HTTPRequest.Method = .get,
		url: URL,
		headerFields: HTTPFields = [:],
		body: Data? = nil
	) throws {
		//works around a runtime crash in the HTTPRequest initializer that
		//has a runtime precondition of non-nil scheme
		guard url.scheme != nil else {
			assert(false)
			throw HTTPRequestError.missingScheme
		}
		if method == .get || method == .head, body != nil {
			throw HTTPRequestError.getMethodWithBody
		}

		self.request = .init(
			method: method,
			url: url,
			headerFields: headerFields
		)
		self.body = body
	}
}

public enum HTTPRequestError: LocalizedError {
	case getMethodWithBody
	case missingScheme

	public var errorDescription: String? {
		switch self {
		case .getMethodWithBody: "Cannot use .get or .head method with a body"
		case .missingScheme: "URL is missing a scheme"
		}
	}
}
