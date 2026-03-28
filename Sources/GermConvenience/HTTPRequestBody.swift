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

public struct HTTPRequestBody: Sendable {
	public var request: HTTPRequest
	public var body: Data?

	public init(request: HTTPRequest, body: Data? = nil) {
		self.request = request
		self.body = body
	}

	public init(
		url: URL,
		method: HTTPRequest.Method,
		httpBody: Data? = nil,
		customHeaders: [HTTPField] = [],
		//the following override the client's custom headers if there is a conflict
		accept: String? = "application/json",
		contentType: String? = "application/json",
		authorization: String? = nil,
	) {
		var headerFields = HTTPFields()
		for header in customHeaders {
			headerFields[header.name] = header.value
		}
		headerFields[.accept] = accept
		headerFields[.contentType] = contentType
		headerFields[.authorization] = authorization

		self.init(
			request: .init(
				method: method,
				url: url,
				headerFields: headerFields
			),
			body: httpBody
		)
	}
}
