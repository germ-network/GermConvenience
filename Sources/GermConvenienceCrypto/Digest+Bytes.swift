//
//  Digest+Bytes.swift
//  GermConvenienceCrypto
//

import Crypto
import Foundation

extension Digest {
	public var bytes: [UInt8] { Array(makeIterator()) }
	public var data: Data { Data(bytes) }
}
