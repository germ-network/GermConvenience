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

	public init(request: HTTPRequest) {
		self.request = request
		self.body = nil
	}

	public init(request: HTTPRequest, body: Data?) throws {
		if request.method == .get, body != nil {
			throw HTTPRequestError.getMethodWithBody
		}

		self.request = request
		self.body = body
	}
}

public enum HTTPRequestError: Error {
	case getMethodWithBody
}

extension HTTPRequestError: LocalizedError {
	public var errorDescription: String? {
		switch self {
		case .getMethodWithBody:
			return "Cannot use .get method with a body"
		}
	}
}
