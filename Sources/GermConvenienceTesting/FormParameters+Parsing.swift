import Foundation
import GermConvenience

extension FormParameters {
	public init(parsing data: Data) {
		let segments = String(decoding: data, as: UTF8.self).split(separator: "&")
		self.init(
			segments.reduce(
				into: [:],
				{ storage, field in
					let parts = field.split(separator: "=", maxSplits: 1)
					let key: String
					if let rawKey = parts.first {
						key = decodeString(rawKey)
					} else {
						return
					}

					let rawValue = parts.dropFirst().joined(separator: "=")
					storage[key, default: []].append(decodeString(rawValue))
				})
		)
	}

	public init(parsing components: URLComponents) {
		let items: [URLQueryItem] =
			components.queryItems
			?? []

		self.init(parsing: items)
	}

	public init(parsing items: [URLQueryItem]) {
		self.init(
			items.reduce(into: [:]) { storage, item in
				storage[item.name, default: []].append(item.value ?? "")
			})
	}

}

private func decodeString(_ input: Substring) -> String {
	return input.removingPercentEncoding ?? String(input)
}

private func decodeString(_ input: String) -> String {
	return input.removingPercentEncoding ?? input
}
