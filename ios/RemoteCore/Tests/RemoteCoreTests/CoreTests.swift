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
}
