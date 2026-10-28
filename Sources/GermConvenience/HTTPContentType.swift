//
//  HTTPContentType.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 3/28/26.
//

import Foundation

public struct HTTPContentType: Equatable, Sendable {
	public static let json = HTTPContentType(rawValue: "application/json")
	/// The `application/x-www-form-urlencoded` content type.
	public static let formURLEncoded = HTTPContentType(
		rawValue: "application/x-www-form-urlencoded;charset=UTF-8")

	@available(*, deprecated, renamed: "formURLEncoded")
	public static let formUrlEncoded = formURLEncoded
	public static let any = HTTPContentType(rawValue: "*/*")
	public static let none = HTTPContentType(rawValue: "")

	/// Creates a multipart form data content type and its unique boundary.
	public static func makeMultipartFormDataHeader() -> (header: String, boundary: String) {
		let boundary = UUID().uuidString

		return ("multipart/form-data; boundary=\(boundary)", boundary)
	}

	@available(*, deprecated, message: "Use makeMultipartFormDataHeader()")
	public static var formEncoded: (header: String, boundary: String) {
		makeMultipartFormDataHeader()
	}

	public let rawValue: String
}
