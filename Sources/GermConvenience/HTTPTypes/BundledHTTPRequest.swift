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
	//not settable from outside, so a caller cannot assign a body onto a .get or
	//flip the method of one that has a body. init() is still the only validation
	//and it is not exhaustive - HTTP methods are case sensitive, so a Method("get")
	//is not .get and is accepted with a body
	public private(set) var request: HTTPRequest
	public let body: Data?

	public init(
		method: HTTPRequest.Method = .get,
		url: URL,
		headerFields: HTTPFields = [:],
		body: Data? = nil
	) throws {
		//works around a runtime crash in the HTTPRequest initializer that
		//has a runtime precondition of non-nil scheme
		guard url.scheme != nil else {
			throw HTTPRequestError.missingScheme
		}
		if method == .get || method == .head, body != nil {
			throw HTTPRequestError.getMethodWithBody
		}

		let request = HTTPRequest(
			method: method,
			url: url,
			headerFields: headerFields
		)

		//HTTPRequest stores scheme, authority and path, and cannot represent a url
		//like urn: or mailto: - it reports url == nil and drops everything after
		//the scheme. Reject rather than carry a request that can never be sent,
		//and that would compare equal to every other url of the same shape
		guard request.url != nil else {
			throw HTTPRequestError.unrepresentableURL(url)
		}

		self.request = request
		self.body = body
	}

	/// Returns a copy with `value` set for `name`, or the field removed when nil.
	///
	/// Header fields cannot invalidate the method/body or scheme checks in `init`,
	/// so they stay settable - through this rather than by exposing `request`.
	///
	/// - Note: this replaces *every* field of that name with a single one, so a
	///   header carried as repeated fields collapses to one comma-joined value.
	/// - Precondition: `name` is not a pseudo header field such as `:method`.
	///   `HTTPFields` traps on those.
	public func settingHeader(_ value: String?, for name: HTTPField.Name) -> Self {
		var copy = self
		copy.request.headerFields[name] = value
		return copy
	}
}

//synthesized: HTTPRequest is Hashable, so this compares scheme, authority and
//path structurally rather than through the derived request.url, which is nil for
//any url HTTPRequest cannot represent. init now rejects those outright, so both
//routes agree - but the structural one does not depend on that staying true
extension BundledHTTPRequest: Equatable {}

public enum HTTPRequestError: LocalizedError, Equatable {
	case getMethodWithBody
	case missingScheme
	case unrepresentableURL(URL)

	public var errorDescription: String? {
		switch self {
		case .getMethodWithBody: "Cannot use .get or .head method with a body"
		case .missingScheme: "URL is missing a scheme"
		case .unrepresentableURL(let url):
			"URL cannot be expressed as an HTTP request: \(url)"
		}
	}
}
