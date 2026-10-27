//
//  DeleteFuse.swift
//  GermConvenienceUtilities
//

import Foundation

//insert in a domain isolation (e.g. actor) to block

public class DeleteFuse {
	private(set) var deleting: Bool = false

	public init() {}

	public func trip() {
		assert(!deleting)
		deleting = true
	}

	/// Throws `DeletionError.alreadyDeleting` when deletion has already begun.
	public func checkNotDeleting() throws {
		guard !deleting else {
			throw DeletionError.alreadyDeleting
		}
	}

	@available(*, deprecated, renamed: "checkNotDeleting()")
	public func test() throws {
		try checkNotDeleting()
	}
}

public enum DeletionError: Error {
	case alreadyDeleting
}

extension DeletionError: LocalizedError {
	public var errorDescription: String? {
		switch self {
		case .alreadyDeleting: "Already deleting"
		}
	}
}
