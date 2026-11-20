//
//  URL+origin.swift
//  GermConvenience
//
//  Created by Emelia Smith on 11/20/26,
//

import Foundation

extension URL {
	/// The lowercased scheme plus the `URLAuthority`, e.g.
	/// `https://example.com:8443`.
	///
	/// Throws `URLError(.unsupportedURL)` when the URL has no scheme, as `URLSession`
	/// does, and rethrows any `URLAuthority.Errors` from `URLAuthority(of:)`.
	public var origin: String {
		get throws {
			let scheme = try scheme.unwrap(or: URLError(.unsupportedURL)).lowercased()
			return "\(scheme)://\(try URLAuthority(of: self))"
		}
	}
}
