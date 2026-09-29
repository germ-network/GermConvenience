import Crypto
import Foundation
import GermConvenienceCrypto
import Testing

@Suite struct DigestTests {
	@Test func bytesAndDataMatchTheDigest() {
		let digest = SHA256.hash(data: Data("abc".utf8))
		#expect(digest.bytes.count == 32)
		#expect(digest.bytes == Array(digest))
		#expect(digest.data == Data(digest.bytes))
	}

	@Test func matchesTheKnownFIPS1802Vector() {
		let digest = SHA256.hash(data: Data("abc".utf8))
		let expected =
			"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
		#expect(digest.data.map { String(format: "%02x", $0) }.joined() == expected)
	}
}
