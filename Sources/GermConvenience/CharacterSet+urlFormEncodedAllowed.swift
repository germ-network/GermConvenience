import Foundation

extension CharacterSet {
	/// Creates a CharacterSet from RFC 3986 allowed characters.
	///
	/// RFC 3986 states that the following characters are "reserved" characters.
	///
	/// - General Delimiters: ":", "#", "[", "]", "@", "?", "/"
	/// - Sub-Delimiters: "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "="
	///
	/// In RFC 3986 - Section 3.4, it states that the "?" and "/" characters should not be escaped to allow
	/// query strings to include a URL. Therefore, all "reserved" characters with the exception of "?" and "/"
	/// should be percent-escaped in the query string.
	public static let urlFormEncodedAllowed: CharacterSet = {
		// does not include "?" or "/" due to RFC 3986 - Section 3.4
		let generalDelimitersToEncode = ":#[]@"
		let subDelimitersToEncode = "!$&'()*+,;="
		let encodableDelimiters = CharacterSet(
			charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")

		return CharacterSet.urlQueryAllowed.subtracting(encodableDelimiters)

		// typealias c = UnicodeScalar

		// // https://url.spec.whatwg.org/#urlencoded-serializing
		// var allowed = CharacterSet()
		// allowed.insert(c(0x2A))
		// allowed.insert(charactersIn: c(0x2D)...c(0x2E))
		// allowed.insert(charactersIn: c(0x30)...c(0x39))
		// allowed.insert(charactersIn: c(0x41)...c(0x5A))
		// allowed.insert(c(0x5F))
		// allowed.insert(charactersIn: c(0x61)...c(0x7A))

		// // and we'll deal with ` ` later…
		// allowed.insert(" ")

		// return allowed
	}()
}
