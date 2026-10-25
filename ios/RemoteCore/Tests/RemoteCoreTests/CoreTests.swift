import Foundation
@testable import RemoteCore

struct Failed: Error, CustomStringConvertible {
    let description: String
}

func expect<T: Equatable>(_ got: T, _ want: T, _ line: Int = #line) throws {
    if got != want { throw Failed(description: "linha \(line): \(got) != \(want)") }
}

/// Corre com XCTest no Mac (RemoteCoreTests) e com um runner simples em Linux (sem XCTest).
enum CoreTests {
    static let all: [(String, () throws -> Void)] = [
        ("proto", proto),
        ("frames", frames),
        ("der", der),
        ("rsaKey", rsaKey),
        ("secret", secret),
        ("remote", remote),
        ("sha512", sha512),
        ("bigint", bigint),
        ("srp", srp),
        ("opack", opack),
        ("tlv8", tlv8),
    ]

    static func proto() throws {
        let p = Proto().varint(1, 2).varint(2, 200).message(10, Proto().string(1, "atvremote").string(2, "Olá")).bool(3, true)
        let m = try ProtoMessage(p.bytes)
        try expect(m.int(1), 2)
        try expect(m.int(2), 200)
        try expect(m.message(10).string(2), "Olá")
        try expect(m.bool(3), true)
        try expect(m.has(4), false)
        try expect(Proto().varint(1, 300).bytes, [0x08, 0xAC, 0x02])
    }

    static func frames() throws {
        let big = [UInt8](repeating: 7, count: 300)
        var data = Frame.encode([1, 2, 3]) + Frame.encode(big)
        var reader = Frame.Reader()
        reader.append(data.prefix(2))
        try expect(try reader.next() == nil, true)
        data.removeFirst(2)
        reader.append(data.prefix(3))
        try expect(try reader.next()!, [1, 2, 3])
        try expect(try reader.next() == nil, true)
        reader.append(data.dropFirst(3))
        try expect(try reader.next()!, big)
    }

    static func der() throws {
        try expect(DER.oid([1, 2, 840, 113_549, 1, 1, 11]), [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B])
        try expect(DER.tlv(0x04, [UInt8](repeating: 0, count: 200)).prefix(3).map { $0 }, [0x04, 0x81, 200])
        let date = Date(timeIntervalSince1970: 1_792_800_000) // 2026-10-24 00:00 UTC
        try expect(String(decoding: DER.time(date).dropFirst(2), as: UTF8.self), "261024000000Z")
        let late = Date(timeIntervalSince1970: 2_556_143_999 + 86_400 * 365 * 3) // 2053
        try expect(DER.time(late)[0], 0x18)
    }

    static func rsaKey() throws {
        // PKCS#1 de uma chave pequena: módulo 0x00C5…, expoente 65537.
        let pkcs1 = DER.sequence(DER.tlv(0x02, [0x00, 0xC5, 0x01, 0x02]) + DER.tlv(0x02, [0x01, 0x00, 0x01]))
        let key = RSAKey(pkcs1: pkcs1)
        try expect(key?.modulus, [0xC5, 0x01, 0x02])
        try expect(key?.exponent, [0x01, 0x00, 0x01])
        let tbs = Certificate.tbs(publicKey: pkcs1, commonName: "GoatRemote", serial: [0x80, 1], notBefore: Date(), notAfter: Date())
        let cert = Certificate.assemble(tbs: tbs, signature: [9, 9])
        try expect(RSAKey(certificate: cert), key)
    }

    static func secret() throws {
        let client = RSAKey(modulus: [0xAB, 0xCD], exponent: [1, 0, 1])
        let server = RSAKey(modulus: [0x12, 0x34], exponent: [1, 0, 1])
        let alpha = SHA.sha256([0xAB, 0xCD, 1, 0, 1, 0x12, 0x34, 1, 0, 1, 0x5E, 0x7A])
        let code = String(format: "%02X", alpha[0]) + "5e7a"
        try expect(Pairing.secret(code: code, client: client, server: server), alpha)
        let wrong = String(format: "%02X", alpha[0] ^ 1) + "5E7A"
        try expect(Pairing.secret(code: wrong, client: client, server: server) == nil, true)
        try expect(Pairing.normalize(" ab12 cd "), "AB12CD")
        try expect(Pairing.normalize("AB12C"), nil)
        try expect(Pairing.normalize("AB12CG"), nil)
    }

    static func remote() throws {
        var r = RemoteProtocol(model: "iPhone", appVersion: "1.0")
        let configure = Proto().message(1, Proto().varint(1, 622).message(2, Proto().string(1, "SHIELD").string(2, "NVIDIA")))
        let reply = try ProtoMessage(Array(try r.handle(configure.bytes)[0].dropFirst()))
        try expect(reply.message(1).int(1), 622 & RemoteProtocol.features)
        try expect(r.state.model, "SHIELD")
        try expect(r.ready, false)
        let active = try r.handle(Proto().message(2, Proto().varint(1, 622)).bytes)
        try expect(r.ready, true)
        try expect(try ProtoMessage(Array(active[0].dropFirst())).message(2).int(1), 622 & RemoteProtocol.features)
        let pong = try r.handle(Proto().message(8, Proto().varint(1, 42)).bytes)
        try expect(try ProtoMessage(Array(pong[0].dropFirst())).message(9).int(1), 42)
        _ = try r.handle(Proto().message(40, Proto().bool(1, true)).bytes)
        _ = try r.handle(Proto().message(50, Proto().varint(6, 100).varint(7, 35).bool(8, false)).bytes)
        _ = try r.handle(Proto().message(20, Proto().message(1, Proto().string(12, "com.netflix.ninja"))).bytes)
        _ = try r.handle(Proto().message(21, Proto().varint(1, 7).varint(2, 3)).bytes)
        try expect(r.state.isOn, true)
        try expect(r.state.volume, 35)
        try expect(r.state.currentApp, "com.netflix.ninja")
        _ = try r.handle(Proto().message(22, Proto().message(2, Proto().string(2, "abc").string(6, "Search"))).bytes)
        try expect(r.state.keyboardRequests, 1)
        try expect(r.state.textValue, "abc")
        try expect(r.state.textLabel, "Search")
        let key = try ProtoMessage(Array(r.key(.center).dropFirst())).message(10)
        try expect(key.int(1), 23)
        try expect(key.int(2), 3)
        let text = try ProtoMessage(Array(r.text("olá").dropFirst())).message(21)
        try expect(text.int(1), 7)
        try expect(text.int(2), 3)
        try expect(text.message(3).message(2).string(3), "olá")
        try expect(text.message(3).message(2).int(1), 2)
    }

    static func hex(_ s: String) -> [UInt8] {
        let c = Array(s.utf8)
        return stride(from: 0, to: c.count, by: 2).map { UInt8(String(decoding: c[$0..<$0 + 2], as: UTF8.self), radix: 16)! }
    }

    static func sha512() throws {
        try expect(SHA.hex(SHA512.hash(Array("abc".utf8))), "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
        try expect(SHA.hex(SHA512.hash([UInt8](repeating: 0x61, count: 200))), "4b11459c33f52a22ee8236782714c150a3b2c60994e9acee17fe68947a3e6789f31e7668394592da7bef827cddca88c4e6f86e4df7ed1ae6cba71f3e98faee9f")
        let ikm = (0..<32).map { UInt8($0) }
        try expect(SHA.hex(SHA512.hkdf(salt: "Pair-Verify-Encrypt-Salt", info: "Pair-Verify-Encrypt-Info", key: ikm)), "faf9f3558a8ed1e45219bd94fb6d27e5b43a1bc861157fc2a0d291d8e3df410a")
        try expect(SHA.hex(SHA512.hkdf(salt: "", info: "ClientEncrypt-main", key: ikm)), "9f8aa265911271e6d6e90daf564d82b5913d4b760373afbd6c03e675af681f8d")
    }

    static func bigint() throws {
        let m = BigUInt(bytes: [0x7F] + [UInt8](repeating: 0xFF, count: 30) + [0xED]) // 2^255 − 19
        let b = BigUInt(bytes: hex("45f92c5e0a2c5f6bc5f92c5e0a2c5f6bc5f92c5e0a2c5f6bc5f92c5e0a2c5fc8"))
        let e = BigUInt(bytes: hex(String(repeating: "fedcba9876543210", count: 5)))
        let mont = Montgomery(modulus: m)
        try expect(SHA.hex(mont.power(b, e).padded(32)), "6d88e8b3c6255ef8d9ee4c7acb8636c0baf5e3f006db9c99bc839bb5505685e5")
        try expect(SHA.hex(mont.multiply(b, b).padded(32)), "10e21e9600a7d1310d4c6470adf1b8f809b6aa4b5b3ba0bf0620f0260885b1a5")
        try expect((BigUInt(0xFFFF_FFFF) + BigUInt(1)).bytes, [1, 0, 0, 0, 0])
        try expect((BigUInt(0x1_0000_0000) - BigUInt(1)).bytes, [0xFF, 0xFF, 0xFF, 0xFF])
        try expect((BigUInt(0xFFFF_FFFF) * BigUInt(0xFFFF_FFFF)).bytes, hex("fffffffe00000001"))
        try expect(BigUInt(0).bytes, [0])
    }

    /// O vetor do A.3 da especificação (PIN 1111, sal 01…10, a = 20…3f, b = aa…aa do pyatv).
    static func srp() throws {
        let salt = hex("0102030405060708090a0b0c0d0e0f10")
        let client = SRPClient(privateKey: hex("202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f"))
        try expect(SHA.hex(Array(client.publicKey.prefix(8))), "6823a16e8d3da8dd")
        // B do servidor de teste: k·v + g^b mod N.
        let mont = Montgomery(modulus: SRPClient.prime)
        let g = SRPClient.generator
        let k = BigUInt(bytes: SHA512.hash(SRPClient.prime.bytes + g.padded(384)))
        let x = BigUInt(bytes: SHA512.hash(salt + SHA512.hash(Array("Pair-Setup:1111".utf8))))
        let v = mont.power(g, x)
        let gb = mont.power(g, BigUInt(bytes: [UInt8](repeating: 0xAA, count: 32)))
        var B = mont.multiply(k, v) + gb
        if !(B < SRPClient.prime) { B = B - SRPClient.prime }
        try expect(SHA.hex(Array(B.bytes.prefix(8))), "8a68cfc16b392740")
        guard let result = client.process(salt: salt, serverPublicKey: B.bytes, pin: "1111") else { throw Failed(description: "SRP sem resultado") }
        try expect(SHA.hex(Array(result.sessionKey.prefix(8))), "042ea4421fa34713")
        try expect(SHA.hex(Array(result.proof.prefix(8))), "6bbc4a3fe6fecde3")
        try expect(SHA.hex(Array(result.expectedServerProof.prefix(8))), "1bec131ba64b7033")
    }

    static func opack() throws {
        // Bytes do pyatv (com as referências a valores repetidos).
        let hidC = try OPACK(decoding: hex("e4425f69455f68696443425f740a425f63e2455f6842745309a10e425f7831e803"))
        try expect(hidC["_i"]?.string, "_hidC")
        try expect(hidC["_c"]?["_hidC"]?.int, 6)
        try expect(hidC["_c"]?["_hBtS"]?.int, 1)
        try expect(hidC["_x"]?.int, 1000)
        let touch = try OPACK(decoding: hex("e4425f694b5f746f7563685374617274425f740a425f63e3475f686569676874360000000000408f40445f74466c08465f7769647468a5425f7831eb03"))
        try expect(touch["_c"]?["_width"], .double(1000))
        try expect(try OPACK(decoding: hex("d4436f6f6643626172a0a1".replacingOccurrences(of: "436f6f66", with: "43666f6f"))),
                   .array([.string("foo"), .string("bar"), .string("foo"), .string("bar")]))
        try expect(try OPACK(decoding: hex("df300130 02c10103".replacingOccurrences(of: " ", with: ""))), .array([.int(1), .int(2), .int(2)]))
        try expect(try OPACK(decoding: hex("3500008 03f".replacingOccurrences(of: " ", with: ""))), .double(1))
        try expect(OPACK.int(0x1FF).encoded, hex("31ff01"))
        try expect(OPACK.int(40).encoded, hex("3028"))
        try expect(OPACK.string(String(repeating: "a", count: 33)).encoded.prefix(2).map { $0 }, [0x61, 0x21])
        try expect(OPACK.array([.int(1), .string("test"), .bool(false)]).encoded, hex("d3094474657374" + "02"))
        let many = OPACK.array(Array(repeating: .string("a"), count: 15))
        try expect(many.encoded.first, 0xDF)
        try expect(try OPACK(decoding: many.encoded), many)
        let msg = OPACK.dict(["_i": .string("_launchApp"), "_t": .int(2), "_c": .dict(["_bundleID": .string("com.netflix.Netflix")]),
                              "_x": .int(1001), "f": .double(-10), "d": .data([1, 2, 3])])
        try expect(try OPACK(decoding: msg.encoded), msg)
    }

    static func tlv8() throws {
        let big = (0..<300).map { UInt8($0 % 256) }
        let encoded = TLV8.encode([(6, [1]), (3, big), (4, [9, 9])])
        try expect(encoded.count, 3 + (2 + 255) + (2 + 45) + 4)
        let decoded = TLV8.decode(encoded)
        try expect(decoded[6], [1])
        try expect(decoded[3], big)
        try expect(decoded[4], [9, 9])
        // M1 real (pyatv antigo): {"_pd": TLV{0:00, 6:01}, "_pwTy": 1}
        let m1 = try OPACK(decoding: hex("e2435f706476000100060101455f7077547909"))
        try expect(TLV8.decode(m1["_pd"]?.data ?? [])[6], [1])
        try expect(m1["_pwTy"]?.int, 1)
    }
}
