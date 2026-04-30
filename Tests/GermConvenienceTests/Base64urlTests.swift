//
//  Base64urlTests.swift
//
//
//  Created by Mark @ Germ on 6/24/24.
//

import CryptoKit
import Foundation
import Testing

struct Test {

	@Test func testBase64url() async throws {
		// Write your test here and use APIs like `#expect(...)` to check expected conditions.

		let data = SymmetricKey(size: .bits256).dataRepresentation
		let base64URLEncoded = data.base64URLEncodedString()
		#expect(data == Data(base64URLEncoded: base64URLEncoded))
	}

}
