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
	public var body: Body?

	public enum Body: Sendable {
		public enum Attached: Sendable {
			case parameters(FormParameters)
			case data(Data)

			var data: Data {
				switch self {
				case .parameters(let formParameters):
					formParameters.data
				case .data(let data):
					data
				}
			}
		}
		case attached(Attached)
		//placeholder for
		//https://developer.apple.com/documentation/foundation/uploading-streams-of-data?language=objc
		case stream(Stream)

		//needs to be able to conform to StreamDelegate
		public struct Stream: Sendable {
		}
	}

	public init(request: HTTPRequest, body: Body?) throws {
		self.request = request
		if request.method == .get, body != nil {
			throw HTTPRequestError.getMethodWithBody
		}

		self.body = body
	}

	//convenience
	public init(request: HTTPRequest, data: Data) throws {
		try self.init(request: request, body: .attached(.data(data)))
	}

	public init(request: HTTPRequest, parameters: FormParameters) throws {
		try self.init(request: request, body: .attached(.parameters(parameters)))
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
