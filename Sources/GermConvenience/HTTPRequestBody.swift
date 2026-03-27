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
}
