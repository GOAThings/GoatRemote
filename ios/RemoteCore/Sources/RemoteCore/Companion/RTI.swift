import Foundation

/// Um valor de property list (o mínimo para o teclado da Apple TV).
public indirect enum Plist: Equatable, Sendable {
    case string(String)
    case int(Int)
    case data([UInt8])
    case uid(Int)
    case bool(Bool)
    case array([Plist])
    case dict([String: Plist])
    case null

    public subscript(key: String) -> Plist? {
        if case .dict(let d) = self { return d[key] }
        return nil
    }
}

/// Property lists binárias ("bplist00"): só os tipos que o teclado da Apple TV usa.
public enum BPlist {
    // MARK: Escrever

    public static func encode(_ root: Plist) -> [UInt8] {
        var objects: [[UInt8]] = []
        var refs: [[Int]] = []      // as referências de cada objeto (preenchidas depois de saber o ref_size)
        var kinds: [UInt8] = []     // marcador de contentor (0xA0 / 0xD0) ou 0 para escalares

        func add(_ v: Plist) -> Int {
            let i = objects.count
            objects.append([])
            refs.append([])
            kinds.append(0)
            switch v {
            case .null: objects[i] = [0x00]
            case .bool(let b): objects[i] = [b ? 0x09 : 0x08]
            case .int(let n): objects[i] = int(n)
            case .uid(let n):
                let b = n <= 0xFF ? [UInt8(n)] : n <= 0xFFFF ? [UInt8(n >> 8), UInt8(n & 0xFF)] : bigEndian(UInt64(n), 4)
                objects[i] = [0x80 | UInt8(b.count - 1)] + b
            case .data(let d): objects[i] = header(0x40, d.count) + d
            case .string(let s):
                if s.utf8.allSatisfy({ $0 < 0x80 }) {
                    objects[i] = header(0x50, s.utf8.count) + Array(s.utf8)
                } else {
                    let units = Array(s.utf16)
                    objects[i] = header(0x60, units.count) + units.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
                }
            case .array(let a):
                kinds[i] = 0xA0
                let r = a.map { add($0) }
                refs[i] = r
            case .dict(let d):
                kinds[i] = 0xD0
                let keys = d.keys.sorted()
                let k = keys.map { add(.string($0)) }
                let v = keys.map { add(d[$0]!) }
                refs[i] = k + v
            }
            return i
        }
        _ = add(root)

        let refSize = objects.count < 256 ? 1 : 2
        for i in objects.indices where kinds[i] != 0 {
            let count = kinds[i] == 0xD0 ? refs[i].count / 2 : refs[i].count
            objects[i] = header(kinds[i], count) + refs[i].flatMap { bigEndian(UInt64($0), refSize) }
        }
        var out = Array("bplist00".utf8)
        var offsets: [Int] = []
        for o in objects {
            offsets.append(out.count)
            out += o
        }
        let tableOffset = out.count
        let offsetSize = tableOffset < 256 ? 1 : tableOffset < 65_536 ? 2 : 4
        for o in offsets { out += bigEndian(UInt64(o), offsetSize) }
        out += [0, 0, 0, 0, 0, 0, UInt8(offsetSize), UInt8(refSize)]
        out += bigEndian(UInt64(objects.count), 8) + bigEndian(0, 8) + bigEndian(UInt64(tableOffset), 8)
        return out
    }

    static func bigEndian(_ v: UInt64, _ size: Int) -> [UInt8] {
        (0..<size).reversed().map { UInt8(truncatingIfNeeded: v >> (UInt64($0) * 8)) }
    }

    static func int(_ n: Int) -> [UInt8] {
        let v = UInt64(bitPattern: Int64(n))
        if n >= 0 && n <= 0xFF { return [0x10] + bigEndian(v, 1) }
        if n >= 0 && n <= 0xFFFF { return [0x11] + bigEndian(v, 2) }
        if n >= 0 && n <= 0xFFFF_FFFF { return [0x12] + bigEndian(v, 4) }
        return [0x13] + bigEndian(v, 8)
    }

    static func header(_ marker: UInt8, _ count: Int) -> [UInt8] {
        count < 15 ? [marker | UInt8(count)] : [marker | 0x0F] + int(count)
    }

    // MARK: Ler

    public static func decode(_ bytes: [UInt8]) throws -> Plist {
        guard bytes.count >= 40, bytes.starts(with: Array("bplist00".utf8)) else { throw ProtocolError.malformed("bplist") }
        let t = Array(bytes.suffix(32))
        let offsetSize = Int(t[6]), refSize = Int(t[7])
        func be(_ b: ArraySlice<UInt8>) -> Int { b.reduce(0) { $0 << 8 | Int($1) } }
        let count = be(t[8..<16]), top = be(t[16..<24]), table = be(t[24..<32])
        guard offsetSize > 0, refSize > 0, table + count * offsetSize <= bytes.count - 32 else { throw ProtocolError.malformed("bplist: tabela") }
        func offset(_ i: Int) throws -> Int {
            guard i < count else { throw ProtocolError.malformed("bplist: objeto \(i)") }
            return be(bytes[(table + i * offsetSize)..<(table + (i + 1) * offsetSize)])
        }
        var depth = 0
        func object(_ i: Int) throws -> Plist {
            depth += 1
            defer { depth -= 1 }
            guard depth < 64 else { throw ProtocolError.malformed("bplist: fundo demais") }
            var p = try offset(i)
            guard p < bytes.count else { throw ProtocolError.malformed("bplist: fora") }
            let marker = bytes[p]
            p += 1
            func length() throws -> Int {
                let low = Int(marker & 0x0F)
                guard low == 0x0F else { return low }
                let intMarker = bytes[p]
                let size = 1 << Int(intMarker & 0x0F)
                defer { p += 1 + size }
                return be(bytes[(p + 1)..<(p + 1 + size)])
            }
            func take(_ n: Int) throws -> ArraySlice<UInt8> {
                guard p + n <= bytes.count else { throw ProtocolError.malformed("bplist: cortado") }
                defer { p += n }
                return bytes[p..<p + n]
            }
            switch marker >> 4 {
            case 0x0: return marker == 0x09 ? .bool(true) : marker == 0x08 ? .bool(false) : .null
            case 0x1: return .int(be(try take(1 << Int(marker & 0x0F))))
            case 0x4: return .data(Array(try take(try length())))
            case 0x5: return .string(String(decoding: try take(try length()), as: UTF8.self))
            case 0x6:
                let raw = Array(try take(try length() * 2))
                let units = stride(from: 0, to: raw.count, by: 2).map { UInt16(raw[$0]) << 8 | UInt16(raw[$0 + 1]) }
                return .string(String(decoding: units, as: UTF16.self))
            case 0x8: return .uid(be(try take(Int(marker & 0x0F) + 1)))
            case 0xA:
                let n = try length()
                let r = try take(n * refSize)
                return .array(try (0..<n).map { try object(be(r[(r.startIndex + $0 * refSize)..<(r.startIndex + ($0 + 1) * refSize)])) })
            case 0xD:
                let n = try length()
                let r = try take(n * 2 * refSize)
                func ref(_ j: Int) -> Int { be(r[(r.startIndex + j * refSize)..<(r.startIndex + (j + 1) * refSize)]) }
                var d: [String: Plist] = [:]
                for j in 0..<n {
                    guard case .string(let key) = try object(ref(j)) else { continue }
                    d[key] = try object(ref(n + j))
                }
                return .dict(d)
            default:
                return .null
            }
        }
        return try object(top)
    }
}

/// O teclado da Apple TV (RTI): o _tiD que a TV manda e os que se lhe mandam (arquivos "RTIKeyedArchiver").
public enum RTI {
    /// O id da sessão de texto e o texto antes do cursor, do _tiD da TV.
    public static func state(_ tiD: [UInt8]) -> (session: [UInt8], text: String)? {
        guard let root = try? BPlist.decode(tiD), case .array(let objects)? = root["$objects"], let top = root["$top"] else { return nil }
        func resolve(_ v: Plist?) -> Plist? {
            if case .uid(let i)? = v { return i < objects.count ? objects[i] : nil }
            return v
        }
        var session: [UInt8]?
        switch resolve(top["sessionUUID"]) {
        case .data(let d)?: session = d
        case .dict(let d)?: if case .data(let b)? = d["NS.uuidbytes"] { session = b }
        default: break
        }
        guard let session else { return nil }
        var text = ""
        if case .string(let s)? = resolve(resolve(resolve(top["documentState"])?["docSt"])?["contextBeforeInput"]) { text = s }
        return (session, text)
    }

    /// Apaga o texto da caixa.
    public static func clear(session: [UInt8]) -> [UInt8] {
        archive(session: session, operation: ["textToAssert": .uid(4)], output: [:], extra: .string(""))
    }

    /// Escreve [text] no cursor.
    public static func insert(_ text: String, session: [UInt8]) -> [UInt8] {
        archive(session: session, operation: [:], output: ["insertionText": .uid(4)], extra: .string(text))
    }

    /// $objects: 0 $null, 1 operações, 2 saída do teclado, 3 classe da saída, 4 texto, 5 uuid, 6 classe NSUUID,
    /// 7 classe das operações.
    static func archive(session: [UInt8], operation: [String: Plist], output: [String: Plist], extra: Plist) -> [UInt8] {
        func cls(_ name: String) -> Plist { .dict(["$classname": .string(name), "$classes": .array([.string(name), .string("NSObject")])]) }
        var ops: [String: Plist] = ["$class": .uid(7), "targetSessionUUID": .uid(5), "keyboardOutput": .uid(2)]
        ops.merge(operation) { $1 }
        var out: [String: Plist] = ["$class": .uid(3)]
        out.merge(output) { $1 }
        return BPlist.encode(.dict([
            "$version": .int(100_000),
            "$archiver": .string("RTIKeyedArchiver"),
            "$top": .dict(["textOperations": .uid(1)]),
            "$objects": .array([
                .string("$null"), .dict(ops), .dict(out), cls("TIKeyboardOutput"), extra,
                .dict(["NS.uuidbytes": .data(session), "$class": .uid(6)]), cls("NSUUID"), cls("RTITextOperations"),
            ]),
        ]))
    }
}
