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
	public var parameters: FormParameters?
	public var data: Data?

	public init(request: HTTPRequest) {
		self.request = request
		self.data = nil
	}

	public init(request: HTTPRequest, data: Data?) throws {
		if request.method == .get, data != nil {
			throw HTTPRequestError.getMethodWithBody
		}

		self.request = request
		self.data = data
	}

	public init(request: HTTPRequest, body: Data?) throws {
		try self.init(request: request, data: body)
	}

	public init(request: HTTPRequest, parameters: FormParameters) throws {
		if request.method == .get {
			throw HTTPRequestError.getMethodWithBody
		}

		self.request = request
		self.parameters = parameters
	}

	public var body: Data? {
		get throws {
			if let data = data {
				return data
			}
			if let parameters = parameters {
				return parameters.data
			}
			return nil
		}
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
