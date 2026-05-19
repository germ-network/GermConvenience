//
//  HTTPContentType.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 3/28/26.
//

import Foundation

public struct HTTPContentType: Equatable, Sendable {
	public static let json = HTTPContentType(rawValue: "application/json")
	public static let formUrlEncoded = HTTPContentType(
		rawValue: "application/x-www-form-urlencoded;charset=UTF-8")
	public static let any = HTTPContentType(rawValue: "*/*")
	public static let none = HTTPContentType(rawValue: "")

	public static var formEncoded: (header: String, boundary: String) {
		let boundary = UUID().uuidString

		return ("multipart/form-data; boundary=\(boundary)", boundary)
	}

	public let rawValue: String
}
