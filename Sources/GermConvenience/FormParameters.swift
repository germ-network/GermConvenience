//
//  FormParameters.swift
//  GermConvenience
//
//  Created by Emelia on 4/11/26.
//
import Foundation

public struct FormParameters: Sendable {
	private var storage: [String: [String]]

	public static var contentType: HTTPContentType { .formUrlEncoded }

	public init() {
		self.storage = [:]
	}

	public init(_ parameters: [String: [String]]) {
		self.storage = parameters
	}

	public init(_ parameters: [String: String]) {
		self.storage = parameters.reduce(into: [:]) {
			storage, parameter in
			storage[parameter.key, default: []].append(parameter.value)
		}
	}

	public subscript(name: String) -> String? {
		get {
			storage[name]?.first
		}

		set(newValue) {
			if let value = newValue {
				storage[name, default: []].append(value)
			} else {
				storage.removeValue(forKey: name)
			}
		}
	}

	public var isEmpty: Bool {
		storage.isEmpty
	}

	public func getAll(name: String) -> [String]? {
		return self.storage[name]
	}

	public func get(name: String) -> String? {
		return storage[name]?.first
	}

	public mutating func set(name: String, value: String) {
		storage[name, default: []].append(value)
	}

	public mutating func delete(name: String) {
		storage.removeValue(forKey: name)
	}

	public func entries() -> [[String]] {
		storage.flatMap({ parameter -> [[String]] in
			parameter.value.map { value -> [String] in
				[parameter.key, value]
			}
		})
	}

	public func asQueryItems() -> [URLQueryItem] {
		storage.flatMap({ parameter -> [URLQueryItem] in
			parameter.value.map({ value -> URLQueryItem in
				.init(name: parameter.key, value: value)
			})
		})
	}

	public var data: Data {
		storage.flatMap { parameter -> [String] in
			guard
				let encodedKey = parameter.key.addingPercentEncoding(
					withAllowedCharacters: .urlQueryAllowed)
			else {
				return []
			}

			return parameter.value.compactMap { value -> String? in
				guard
					let encodedValue = value.addingPercentEncoding(
						withAllowedCharacters: .urlQueryAllowed)
				else {
					return nil
				}

				return [encodedKey, encodedValue].joined(separator: "=")
			}
		}.joined(separator: "&").utf8Data
	}
}
