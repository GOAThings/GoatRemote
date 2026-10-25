import Foundation

/// OPACK, a serialização das mensagens da Apple TV (CoreUtils). Escreve-se sem referências (sempre válido);
/// lê-se como o pyatv, que é o que bate certo com as TVs (tabela de valores repetidos).
public indirect enum OPACK: Equatable, Sendable, CustomStringConvertible {
    case null
    case bool(Bool)
    case int(UInt64)
    case double(Double)
    case string(String)
    case data([UInt8])
    case array([OPACK])
    case dict([String: OPACK])

    // MARK: Ler valores

    public subscript(key: String) -> OPACK? {
        if case .dict(let d) = self { return d[key] }
        return nil
    }

    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var data: [UInt8]? { if case .data(let d) = self { return d }; return nil }
    public var dict: [String: OPACK]? { if case .dict(let d) = self { return d }; return nil }
    public var array: [OPACK]? { if case .array(let a) = self { return a }; return nil }

    public var int: Int? {
        switch self {
        case .int(let v): return v <= UInt64(Int.max) ? Int(v) : nil
        case .double(let d): return Int(exactly: d)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    public var description: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return "\(b)"
        case .int(let v): return "\(v)"
        case .double(let d): return "\(d)"
        case .string(let s): return "\"\(s)\""
        case .data(let d): return "<\(d.count) bytes>"
        case .array(let a): return "[" + a.map(\.description).joined(separator: ", ") + "]"
        case .dict(let d): return "{" + d.keys.sorted().map { "\($0): \(d[$0]!)" }.joined(separator: ", ") + "}"
        }
    }

    // MARK: Escrever

    public var encoded: [UInt8] {
        var out: [UInt8] = []
        Self.write(self, into: &out)
        return out
    }

    static func write(_ v: OPACK, into out: inout [UInt8]) {
        func le(_ value: UInt64, _ width: Int) { for i in 0..<width { out.append(UInt8(truncatingIfNeeded: value >> UInt64(8 * i))) } }
        switch v {
        case .null: out.append(0x04)
        case .bool(let b): out.append(b ? 0x01 : 0x02)
        case .int(let n):
            switch n {
            case 0...0x27: out.append(UInt8(n) + 8)
            case 0...0xFF: out.append(0x30); le(n, 1)
            case 0...0xFFFF: out.append(0x31); le(n, 2)
            case 0...0xFFFF_FFFF: out.append(0x32); le(n, 4)
            default: out.append(0x33); le(n, 8)
            }
        case .double(let d): out.append(0x36); le(d.bitPattern, 8)
        case .string(let s):
            let b = Array(s.utf8)
            if b.count <= 32 { out.append(0x40 + UInt8(b.count)) } else if b.count <= 0xFF { out.append(0x61); le(UInt64(b.count), 1) } else { out.append(0x62); le(UInt64(b.count), 2) }
            out += b
        case .data(let b):
            if b.count <= 32 { out.append(0x70 + UInt8(b.count)) } else if b.count <= 0xFF { out.append(0x91); le(UInt64(b.count), 1) } else { out.append(0x92); le(UInt64(b.count), 2) }
            out += b
        case .array(let a):
            out.append(0xD0 + UInt8(min(a.count, 15)))
            for x in a { write(x, into: &out) }
            if a.count >= 15 { out.append(0x03) }
        case .dict(let d):
            out.append(0xE0 + UInt8(min(d.count, 15)))
            // Ordem fixa (a TV não liga à ordem; assim os testes são estáveis).
            for k in d.keys.sorted() {
                write(.string(k), into: &out)
                write(d[k]!, into: &out)
            }
            if d.count >= 15 { out.append(0x03) }
        }
    }

    // MARK: Ler

    public init(decoding bytes: [UInt8]) throws {
        var reader = Reader(bytes: bytes)
        self = try reader.read()
    }

    struct Reader {
        let bytes: [UInt8]
        var pos = 0
        var table: [OPACK] = []

        mutating func take(_ n: Int) throws -> [UInt8] {
            guard n >= 0, pos + n <= bytes.count else { throw ProtocolError.malformed("OPACK cortado") }
            defer { pos += n }
            return Array(bytes[pos..<pos + n])
        }

        mutating func le(_ n: Int) throws -> UInt64 {
            try take(n).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << UInt64(8 * $1.offset) }
        }

        mutating func remember(_ v: OPACK) -> OPACK {
            if !table.contains(v) { table.append(v) }
            return v
        }

        mutating func read() throws -> OPACK {
            let t = try take(1)[0]
            switch t {
            case 0x01: return .bool(true)
            case 0x02: return .bool(false)
            case 0x04: return .null
            case 0x05: return remember(.data(try take(16)))
            case 0x06: return remember(.data(try take(8)))
            case 0x08...0x2F: return .int(UInt64(t - 8))
            case 0x30...0x33: return remember(.int(try le(1 << Int(t & 0xF))))
            case 0x35: return remember(.double(Double(Float(bitPattern: UInt32(try le(4))))))
            case 0x36: return remember(.double(Double(bitPattern: try le(8))))
            case 0x40...0x60: return remember(.string(String(decoding: try take(Int(t - 0x40)), as: UTF8.self)))
            case 0x61...0x64: return remember(.string(String(decoding: try take(Int(try le(Int(t - 0x60)))), as: UTF8.self)))
            case 0x70...0x90: return remember(.data(try take(Int(t - 0x70))))
            case 0x91...0x94: return remember(.data(try take(Int(try le([1, 2, 4, 8][Int(t - 0x91)])))))
            case 0xA0...0xC0: return try ref(Int(t - 0xA0))
            case 0xC1...0xC4: return try ref(Int(try le(Int(t - 0xC0))))
            case 0xD0...0xDF:
                var a: [OPACK] = []
                if t == 0xDF {
                    while pos < bytes.count, bytes[pos] != 0x03 { a.append(try read()) }
                    _ = try take(1)
                } else {
                    for _ in 0..<Int(t & 0xF) { a.append(try read()) }
                }
                return .array(a)
            case 0xE0...0xEF:
                var d: [String: OPACK] = [:]
                if t == 0xEF {
                    while pos < bytes.count, bytes[pos] != 0x03 { let (k, v) = try pair(); d[k] = v }
                    _ = try take(1)
                } else {
                    for _ in 0..<Int(t & 0xF) { let (k, v) = try pair(); d[k] = v }
                }
                return .dict(d)
            default:
                throw ProtocolError.malformed(String(format: "OPACK 0x%02x", t))
            }
        }

        mutating func pair() throws -> (String, OPACK) {
            let key = try read()
            return (key.string ?? key.description, try read())
        }

        func ref(_ i: Int) throws -> OPACK {
            guard i < table.count else { throw ProtocolError.malformed("OPACK: referência \(i) fora da tabela") }
            return table[i]
        }
    }
}

/// TLV8 (emparelhamento HomeKit): tipo, tamanho (até 255) e valor; valores maiores vão em pedaços seguidos.
public enum TLV8 {
    public static func encode(_ items: [(UInt8, [UInt8])]) -> [UInt8] {
        var out: [UInt8] = []
        for (tag, value) in items {
            var rest = value[...]
            repeat {
                let chunk = rest.prefix(255)
                out += [tag, UInt8(chunk.count)] + chunk
                rest = rest.dropFirst(chunk.count)
            } while !rest.isEmpty
        }
        return out
    }

    /// Os pedaços com o mesmo tipo juntam-se.
    public static func decode(_ bytes: [UInt8]) -> [UInt8: [UInt8]] {
        var out: [UInt8: [UInt8]] = [:]
        var i = 0
        while i + 2 <= bytes.count {
            let tag = bytes[i], n = Int(bytes[i + 1])
            let end = min(i + 2 + n, bytes.count)
            out[tag, default: []] += bytes[(i + 2)..<end]
            i = end
        }
        return out
    }
}
