//
//  HTTPRequest+construct.swift
//  AtprotoClient
//
//  Created by Mark @ Germ on 2/27/26.
//

import Foundation
import HTTPTypes
import HTTPTypesFoundation

extension HTTPRequest {
	public static func createRequest(
		url: URL,
		method: Method,
		httpBody: Data? = nil,
		accept: String? = "application/json",
		contentType: String? = "application/json",
		authorization: String? = nil,
	) -> HTTPRequestBody {
		var headerFields = HTTPFields()
		headerFields[.accept] = accept
		headerFields[.contentType] = contentType
		headerFields[.authorization] = authorization

		return .init(
			request: .init(
				method: method,
				url: url,
				headerFields: headerFields
			),
			body: httpBody
		)
	}
}
