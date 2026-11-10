import Foundation

/// O que está em contracts/ na raiz do repositório: os mesmos ficheiros que os testes do Android lêem. O runner de
/// Linux copia os testes para outro sítio, por isso diz onde estão em CONTRACTS; no Mac vale o caminho deste ficheiro.
enum Contracts {
    static let dir: URL = {
        if let path = ProcessInfo.processInfo.environment["CONTRACTS"] { return URL(fileURLWithPath: path) }
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("contracts")
    }()

    static func data(_ path: String) throws -> Data { try Data(contentsOf: dir.appendingPathComponent(path)) }

    static func text(_ path: String) throws -> String { String(decoding: try data(path), as: UTF8.self) }

    static func object(_ path: String) throws -> [String: Any] {
        guard let o = try JSONSerialization.jsonObject(with: data(path)) as? [String: Any] else {
            throw Failed(description: "\(path) não é um objeto")
        }
        return o
    }

    private static let vectors: [String: Any] = (try? object("vectors.json")) ?? [:]

    /// Um vetor de vectors.json pelo caminho ("srp.salt").
    static func vectorHex(_ path: String) throws -> String {
        var o: Any? = vectors
        for part in path.split(separator: ".") { o = (o as? [String: Any])?[String(part)] }
        guard let hex = o as? String else { throw Failed(description: "sem o vetor \(path)") }
        return hex
    }

    static func vector(_ path: String) throws -> [UInt8] { CoreTests.hex(try vectorHex(path)) }

    /// O mesmo JSON (as mesmas chaves e valores, por qualquer ordem).
    static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x as [String: Any], y as [String: Any]): return Set(x.keys) == Set(y.keys) && x.keys.allSatisfy { same(x[$0], y[$0]) }
        case let (x as [Any], y as [Any]): return x.count == y.count && zip(x, y).allSatisfy { same($0, $1) }
        case let (x as String, y as String): return x == y
        case (is NSNull, is NSNull): return true
        case let (x as Int, y as Int): return x == y
        case let (x as Bool, y as Bool): return x == y
        case let (x as Double, y as Double): return x == y
        default: return false
        }
    }

    static func string(_ v: Any?) -> String? { v as? String }
    static func int(_ v: Any?) -> Int? { v as? Int }
    static func bool(_ v: Any?) -> Bool? { v is NSNull ? nil : v as? Bool }
    static func list(_ v: Any?) -> [[String: Any]] { v as? [[String: Any]] ?? [] }
}
