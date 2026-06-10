//
//  URLScheme.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 5/20/26.
//

public struct URLScheme: Sendable {
	public static let http = URLScheme(rawValue: "http")
	public static let https = URLScheme(rawValue: "https")

	public let rawValue: String
}
