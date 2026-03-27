//
//  HTTPScheme.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 2/26/26.
//

public struct URLScheme: Sendable {
	public static let http = URLScheme(rawValue: "http")
	public static let https = URLScheme(rawValue: "https")

	public let rawValue: String
}
