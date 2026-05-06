//
//  HexEncodingTests.swift
//  CryptoTests
//

import Foundation
import Testing

@testable import Crypto

@Suite("HexEncoding")
struct HexEncodingTests {

    @Test func lowercaseRoundTrip() {
        let bytes: [UInt8] = [0x00, 0x01, 0x7f, 0x80, 0xab, 0xff]
        let data = Data(bytes)
        #expect(data.hexLowercased == "00017f80abff")
    }

    @Test func uppercaseRoundTrip() {
        let bytes: [UInt8] = [0x04, 0xab, 0x12, 0xcd, 0xef, 0x12, 0x34]
        let data = Data(bytes)
        #expect(data.hexUppercased == "04AB12CDEF1234")
    }

    @Test func emptyData() {
        #expect(Data().hexLowercased == "")
        #expect(Data().hexUppercased == "")
    }

    @Test func decodeLowercase() {
        let data = Data(hexEncoded: "00017f80abff")
        #expect(data == Data([0x00, 0x01, 0x7f, 0x80, 0xab, 0xff]))
    }

    @Test func decodeUppercase() {
        let data = Data(hexEncoded: "04AB12CDEF1234")
        #expect(data == Data([0x04, 0xab, 0x12, 0xcd, 0xef, 0x12, 0x34]))
    }

    @Test func decodeMixedCase() {
        let data = Data(hexEncoded: "AaBbCcDdEeFf")
        #expect(data == Data([0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]))
    }

    @Test func decodeRejectsOddLength() {
        #expect(Data(hexEncoded: "abc") == nil)
    }

    @Test func decodeRejectsNonHex() {
        #expect(Data(hexEncoded: "abcz") == nil)
        #expect(Data(hexEncoded: "GG") == nil)
    }

    @Test func roundTripAllByteValues() {
        let bytes: [UInt8] = (0..<256).map { UInt8($0) }
        let data = Data(bytes)
        let hex = data.hexLowercased
        #expect(hex.count == 512)
        let decoded = Data(hexEncoded: hex)
        #expect(decoded == data)
    }
}
