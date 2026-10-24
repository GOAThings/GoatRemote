import Foundation

/// Protobuf mínimo, só o que o protocolo do comando precisa (varints e campos com tamanho). As mensagens são poucas e
/// pequenas: não vale a pena a biblioteca.
public struct Proto: Sendable {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public var data: Data { Data(bytes) }

    public func varint(_ field: Int, _ value: Int) -> Proto {
        var copy = self
        copy.tag(field, 0)
        copy.putVarint(UInt64(bitPattern: Int64(value)))
        return copy
    }

    public func bool(_ field: Int, _ value: Bool) -> Proto { varint(field, value ? 1 : 0) }

    public func bytes(_ field: Int, _ value: [UInt8]) -> Proto {
        var copy = self
        copy.tag(field, 2)
        copy.putVarint(UInt64(value.count))
        copy.bytes += value
        return copy
    }

    public func string(_ field: Int, _ value: String) -> Proto { bytes(field, Array(value.utf8)) }

    public func message(_ field: Int, _ value: Proto) -> Proto { bytes(field, value.bytes) }

    private mutating func tag(_ field: Int, _ wire: UInt64) { putVarint(UInt64(field) << 3 | wire) }

    private mutating func putVarint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            bytes.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        bytes.append(UInt8(v))
    }
}

public enum ProtocolError: Error, Equatable, Sendable {
    case malformed(String)
    case unexpected(String)
    case status(Int)
}

/// Uma mensagem lida: os campos por número, com os valores pela ordem em que vieram.
public struct ProtoMessage: Sendable, CustomStringConvertible {
    enum Value: Sendable {
        case number(UInt64)
        case bytes([UInt8])
    }

    private var fields: [Int: [Value]] = [:]

    public init(_ data: Data) throws { try self.init(Array(data)) }

    public init(_ data: [UInt8]) throws {
        var pos = 0
        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard pos < data.count else { throw ProtocolError.malformed("varint cortado") }
                let b = data[pos]
                pos += 1
                result |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return result }
                shift += 7
                guard shift < 64 else { throw ProtocolError.malformed("varint demasiado longo") }
            }
        }
        while pos < data.count {
            let tag = try varint()
            let field = Int(tag >> 3)
            switch tag & 7 {
            case 0:
                fields[field, default: []].append(.number(try varint()))
            case 2:
                let len = Int(try varint())
                guard len >= 0, pos + len <= data.count else { throw ProtocolError.malformed("campo cortado") }
                fields[field, default: []].append(.bytes(Array(data[pos..<pos + len])))
                pos += len
            case 1: pos += 8
            case 5: pos += 4
            default: throw ProtocolError.malformed("tipo de campo desconhecido")
            }
        }
    }

    public func has(_ field: Int) -> Bool { fields[field] != nil }

    public func int(_ field: Int) -> Int {
        if case .number(let n)? = fields[field]?.last { return Int(Int64(bitPattern: n)) }
        return 0
    }

    public func bool(_ field: Int) -> Bool { int(field) != 0 }

    public func bytes(_ field: Int) -> [UInt8] {
        if case .bytes(let b)? = fields[field]?.last { return b }
        return []
    }

    public func string(_ field: Int) -> String { String(decoding: bytes(field), as: UTF8.self) }

    /// Um campo com uma mensagem lá dentro; vazia se não veio.
    public func message(_ field: Int) -> ProtoMessage { (try? ProtoMessage(bytes(field))) ?? ProtoMessage.empty }

    public func messages(_ field: Int) -> [ProtoMessage] {
        (fields[field] ?? []).compactMap { value in
            if case .bytes(let b) = value { return try? ProtoMessage(b) }
            return nil
        }
    }

    static let empty: ProtoMessage = try! ProtoMessage([UInt8]())

    public var description: String { "[" + fields.keys.sorted().map(String.init).joined(separator: ",") + "]" }
}

/// Cada mensagem vai precedida do tamanho, em varint.
public enum Frame {
    public static let maxSize = 1 << 20

    public static func encode(_ message: [UInt8]) -> Data {
        var out: [UInt8] = []
        var v = UInt64(message.count)
        while v >= 0x80 {
            out.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        out.append(UInt8(v))
        return Data(out + message)
    }

    public static func encode(_ message: Proto) -> Data { encode(message.bytes) }

    /// Junta o que vai chegando da ligação e devolve as mensagens inteiras.
    public struct Reader: Sendable {
        private var buffer: [UInt8] = []

        public init() {}

        public mutating func append(_ data: Data) { buffer += data }

        /// A próxima mensagem inteira, ou nil se ainda falta chegar parte dela.
        public mutating func next() throws -> [UInt8]? {
            var len = 0
            var shift = 0
            var pos = 0
            while true {
                guard pos < buffer.count else { return nil }
                let b = buffer[pos]
                pos += 1
                len |= Int(b & 0x7F) << shift
                if b & 0x80 == 0 { break }
                shift += 7
                guard shift <= 28 else { throw ProtocolError.malformed("tamanho inválido") }
            }
            guard len <= Frame.maxSize else { throw ProtocolError.malformed("mensagem demasiado grande") }
            guard buffer.count - pos >= len else { return nil }
            let message = Array(buffer[pos..<pos + len])
            buffer.removeFirst(pos + len)
            return message
        }
    }
}
