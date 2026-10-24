import Foundation

/// O mínimo de DER/X.509 para o comando: fazer o certificado auto-assinado do telemóvel (a assinatura em si é do
/// sistema) e tirar módulo e expoente RSA dos certificados, que entram no segredo do emparelhamento.
public enum Certificate {
    /// O "to be signed" de um certificado v3 auto-assinado com uma chave RSA ([publicKey] em PKCS#1) e SHA256withRSA.
    public static func tbs(publicKey: [UInt8], commonName: String, serial: [UInt8], notBefore: Date, notAfter: Date) -> [UInt8] {
        let name = DER.sequence(DER.set(DER.sequence(DER.oid([2, 5, 4, 3]) + DER.tlv(0x0C, Array(commonName.utf8)))))
        var serial = serial.drop { $0 == 0 }.map { $0 }
        if serial.isEmpty { serial = [1] }
        if serial[0] & 0x80 != 0 { serial.insert(0, at: 0) }
        return DER.sequence(
            DER.tlv(0xA0, DER.tlv(0x02, [2])) // v3
                + DER.tlv(0x02, serial)
                + sha256WithRSA
                + name
                + DER.sequence(DER.time(notBefore) + DER.time(notAfter))
                + name
                + subjectPublicKeyInfo(publicKey)
        )
    }

    /// O certificado: o "to be signed", o algoritmo e a assinatura.
    public static func assemble(tbs: [UInt8], signature: [UInt8]) -> [UInt8] {
        DER.sequence(tbs + sha256WithRSA + DER.tlv(0x03, [0] + signature))
    }

    /// A chave pública RSA (PKCS#1) dentro de um SubjectPublicKeyInfo.
    public static func subjectPublicKeyInfo(_ pkcs1: [UInt8]) -> [UInt8] {
        DER.sequence(DER.sequence(DER.oid([1, 2, 840, 113_549, 1, 1, 1]) + [0x05, 0x00]) + DER.tlv(0x03, [0] + pkcs1))
    }

    static let sha256WithRSA = DER.sequence(DER.oid([1, 2, 840, 113_549, 1, 1, 11]) + [0x05, 0x00])

    /// SHA-256 do certificado, em hexadecimal: reconhece a mesma TV mais tarde.
    public static func fingerprint(_ der: [UInt8]) -> String { SHA.hex(SHA.sha256(der)) }
}

/// Módulo e expoente de uma chave RSA, sem zeros à esquerda (como entram no segredo).
public struct RSAKey: Equatable, Sendable {
    public var modulus: [UInt8]
    public var exponent: [UInt8]

    public init(modulus: [UInt8], exponent: [UInt8]) {
        self.modulus = Self.unsigned(modulus)
        self.exponent = Self.unsigned(exponent)
    }

    /// De uma chave em PKCS#1 (SEQUENCE { INTEGER módulo, INTEGER expoente }).
    public init?(pkcs1 der: [UInt8]) {
        guard let seq = DER.first(der), seq.tag == 0x30 else { return nil }
        var inner = DER.Reader(seq.content)
        guard let n = inner.next(), n.tag == 0x02, let e = inner.next(), e.tag == 0x02 else { return nil }
        self.init(modulus: n.content, exponent: e.content)
    }

    /// De um certificado X.509 em DER.
    public init?(certificate der: [UInt8]) {
        guard let cert = DER.first(der), cert.tag == 0x30,
              let tbs = DER.first(cert.content), tbs.tag == 0x30 else { return nil }
        var fields = DER.Reader(tbs.content)
        var all: [DER.Element] = []
        while let f = fields.next() { all.append(f) }
        // [0] versão (opcional), série, algoritmo, emissor, validade, sujeito, chave pública.
        let start = all.first?.tag == 0xA0 ? 1 : 0
        guard all.count > start + 5 else { return nil }
        let spki = all[start + 5]
        var parts = DER.Reader(spki.content)
        guard parts.next() != nil, let bits = parts.next(), bits.tag == 0x03, bits.content.count > 1 else { return nil }
        self.init(pkcs1: Array(bits.content.dropFirst()))
    }

    private static func unsigned(_ bytes: [UInt8]) -> [UInt8] {
        let trimmed = Array(bytes.drop { $0 == 0 })
        return trimmed.isEmpty ? [0] : trimmed
    }
}

enum DER {
    struct Element {
        var tag: UInt8
        var content: [UInt8]
    }

    struct Reader {
        private let data: [UInt8]
        private var pos = 0

        init(_ data: [UInt8]) { self.data = data }

        mutating func next() -> Element? {
            guard pos + 2 <= data.count else { return nil }
            let tag = data[pos]
            var len = Int(data[pos + 1])
            pos += 2
            if len & 0x80 != 0 {
                let count = len & 0x7F
                guard count > 0, count <= 4, pos + count <= data.count else { return nil }
                len = 0
                for _ in 0..<count {
                    len = len << 8 | Int(data[pos])
                    pos += 1
                }
            }
            guard pos + len <= data.count else { return nil }
            let content = Array(data[pos..<pos + len])
            pos += len
            return Element(tag: tag, content: content)
        }
    }

    static func first(_ data: [UInt8]) -> Element? {
        var reader = Reader(data)
        return reader.next()
    }

    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        let n = content.count
        let length: [UInt8]
        switch n {
        case ..<0x80: length = [UInt8(n)]
        case ..<0x100: length = [0x81, UInt8(n)]
        case ..<0x10000: length = [0x82, UInt8(n >> 8), UInt8(n & 0xFF)]
        default: length = [0x83, UInt8(n >> 16), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
        }
        return [tag] + length + content
    }

    static func sequence(_ content: [UInt8]) -> [UInt8] { tlv(0x30, content) }

    static func set(_ content: [UInt8]) -> [UInt8] { tlv(0x31, content) }

    static func oid(_ parts: [Int]) -> [UInt8] {
        var out: [UInt8] = [UInt8(parts[0] * 40 + parts[1])]
        for part in parts.dropFirst(2) {
            var chunks: [UInt8] = []
            var v = part
            repeat {
                chunks.insert(UInt8(v & 0x7F), at: 0)
                v >>= 7
            } while v != 0
            for i in 0..<chunks.count - 1 { chunks[i] |= 0x80 }
            out += chunks
        }
        return tlv(0x06, out)
    }

    /// UTCTime até 2049, GeneralizedTime depois (regra do X.509).
    static func time(_ date: Date) -> [UInt8] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = c.year ?? 2000
        func two(_ v: Int?) -> String { String(format: "%02d", v ?? 0) }
        let rest = two(c.month) + two(c.day) + two(c.hour) + two(c.minute) + two(c.second) + "Z"
        if year < 2050 {
            return tlv(0x17, Array((two(year % 100) + rest).utf8))
        }
        return tlv(0x18, Array((String(year) + rest).utf8))
    }
}
