//
//  Convenience.swift
//  GermConvenienceUtilities
//

import Foundation

extension Array {
	/// Returns the only element, throwing when the array is empty or has multiple
	/// elements.
	public func singleElement() throws -> Element {
		guard count != 0 else {
			throw ConvenienceError.expectedObjectMissing("\(Element.self)")
		}
		guard count == 1, let result = first else {
			throw ConvenienceError.unexpectedlyManyResults("\(Element.self)")
		}
		return result
	}

	@available(*, deprecated, renamed: "singleElement()")
	public func expectOne() throws -> Element {
		try singleElement()
	}
}

extension Array {
	/// Returns the element when present, or `nil` when empty; throws when there
	/// are multiple elements.
	public func singleElementIfAny() throws -> Element? {
		guard count < 2 else {
			throw ConvenienceError.unexpectedlyManyResults("\(Element.self)")
		}
		return first
	}

	@available(*, deprecated, renamed: "singleElementIfAny()")
	public func expectOneOrLess() throws -> Element? {
		try singleElementIfAny()
	}
}

extension Data {
	public var debugPrefix: String {
		prefix(5).base64EncodedString()
	}
}

enum ConvenienceError: Error {
	case expectedObjectMissing(String)
	case unexpectedlyManyResults(String)
}

extension ConvenienceError: LocalizedError {
	var errorDescription: String? {
		switch self {
		case .expectedObjectMissing(let type): "Expected to find one \(type), but didn't."
		case .unexpectedlyManyResults(let type): "Found more than one \(type)."
		}
	}
}
