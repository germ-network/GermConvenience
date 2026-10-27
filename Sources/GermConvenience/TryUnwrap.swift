//
//  TryUnwrap.swift
//  GermConvenience
//
//  Created by Mark @ Germ on 2/25/26.
//

import Foundation

enum UnwrapError: Error, Equatable {
	case missing(String)
}

extension Optional {
	/// The wrapped value, or a `UnwrapError.missing` error when `nil`.
	public var unwrapped: Wrapped {
		get throws {
			try unwrap(or: UnwrapError.missing("\(Wrapped.self)"))
		}
	}

	/// Returns the wrapped value, or throws `error` when `nil`.
	public func unwrap<E: Error>(or error: E) throws(E) -> Wrapped {
		guard let self else {
			throw error
		}
		return self
	}

	@available(*, deprecated, renamed: "unwrapped")
	public var tryUnwrap: Wrapped {
		get throws { try unwrapped }
	}

	@available(*, deprecated, renamed: "unwrap(or:)")
	public func tryUnwrap<E: Error>(_ error: E) throws(E) -> Wrapped {
		try unwrap(or: error)
	}
}
