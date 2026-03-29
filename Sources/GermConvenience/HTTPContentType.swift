//
//  HTTPContentType.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 3/28/26.
//

import Foundation

public struct HTTPContentType: Sendable {
	public static let json = HTTPContentType(rawValue: "application/json")
	public static let formData = HTTPContentType(
		rawValue: "application/x-www-form-urlencoded;charset=UTF-8")
	public static let any = HTTPContentType(
		rawValue: "*/*")

	public let rawValue: String
}
