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

	public func test() throws {
		guard !deleting else {
			throw DeletionError.alreadyDeleting
		}
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
