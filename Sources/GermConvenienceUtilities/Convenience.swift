//
//  Convenience.swift
//  GermConvenienceUtilities
//

import Foundation

extension Array {
	public func expectOne() throws -> Element {
		guard count != 0 else {
			throw ConvenienceError.expectedObjectMissing("\(Element.self)")
		}
		guard count == 1, let result = first else {
			throw ConvenienceError.unexpectedlyManyResults("\(Element.self)")
		}
		return result
	}
}

extension Array {
	public func expectOneOrLess() throws -> Element? {
		guard count < 2 else {
			throw ConvenienceError.unexpectedlyManyResults("\(Element.self)")
		}
		return first
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
