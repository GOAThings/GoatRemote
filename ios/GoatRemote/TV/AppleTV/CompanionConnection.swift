import CryptoKit
import Foundation
import Network
import RemoteCore

/// A ligação à Apple TV (protocolo Companion): TCP simples com tramas [tipo, tamanho de 3 bytes, conteúdo OPACK].
/// Depois da verificação, cada trama vai cifrada com ChaCha20-Poly1305 (cabeçalho como dados autenticados, nonce
/// = contador de 12 bytes little-endian por sentido).
final class CompanionConnection: @unchecked Sendable {
    enum Frame: UInt8 {
        case pairSetupStart = 3, pairSetupNext = 4, pairVerifyStart = 5, pairVerifyNext = 6, opack = 8
    }

    enum Failure: Error {
        case unreachable(String)
        case closed
        case tv(String)
        case timeout(String)
    }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "cc.slokker.goatremote.appletv")
    private var buffer: [UInt8] = []
    private var outKey: SymmetricKey?
    private var inKey: SymmetricKey?
    private var outCounter: UInt64 = 0
    private var inCounter: UInt64 = 0
    private var xid = UInt64.random(in: 0..<65_536)
    private let lock = NSLock()

    init(host: String, port: UInt16) {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 6
        tcp.enableKeepalive = true
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: NWParameters(tls: nil, tcp: tcp))
    }

    func open() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { [weak self] state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    cont.resume()
                case .failed(let error), .waiting(let error):
                    resumed = true
                    self?.connection.cancel()
                    cont.resume(throwing: Failure.unreachable(error.localizedDescription))
                case .cancelled:
                    resumed = true
                    cont.resume(throwing: Failure.closed)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    func close() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    /// Passa a cifrar (depois da M4 da verificação).
    func encrypt(out: SymmetricKey, in incoming: SymmetricKey) {
        lock.lock()
        outKey = out
        inKey = incoming
        outCounter = 0
        inCounter = 0
        lock.unlock()
    }

    /// O próximo número de transação (_x).
    func nextXID() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        xid += 1
        return xid
    }

    // MARK: Tramas

    func send(_ frame: Frame, _ message: OPACK) async throws {
        var body = message.encoded
        lock.lock()
        var header: [UInt8]
        if let key = outKey, !body.isEmpty {
            header = [frame.rawValue] + Self.length(body.count + 16)
            let nonce = try ChaChaPoly.Nonce(data: Self.nonce(outCounter))
            outCounter += 1
            lock.unlock()
            let box = try ChaChaPoly.seal(body, using: key, nonce: nonce, authenticating: header)
            body = Array(box.ciphertext) + Array(box.tag)
        } else {
            header = [frame.rawValue] + Self.length(body.count)
            lock.unlock()
        }
        let data = Data(header + body)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: Failure.unreachable(error.localizedDescription)) } else { cont.resume() }
            })
        }
    }

    /// A próxima trama inteira (já decifrada).
    func receive() async throws -> (UInt8, OPACK) {
        while true {
            if buffer.count >= 4 {
                let length = Int(buffer[1]) << 16 | Int(buffer[2]) << 8 | Int(buffer[3])
                if buffer.count >= 4 + length {
                    let header = Array(buffer[0..<4])
                    var body = Array(buffer[4..<(4 + length)])
                    buffer.removeFirst(4 + length)
                    lock.lock()
                    let key = inKey
                    let counter = inCounter
                    if key != nil, !body.isEmpty { inCounter += 1 }
                    lock.unlock()
                    if let key, !body.isEmpty {
                        guard body.count >= 16 else { throw Failure.tv("trama cifrada curta") }
                        let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: Self.nonce(counter)),
                                                           ciphertext: body.dropLast(16), tag: body.suffix(16))
                        body = Array(try ChaChaPoly.open(box, using: key, authenticating: header))
                    }
                    return (header[0], body.isEmpty ? .dict([:]) : try OPACK(decoding: body))
                }
            }
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, complete, error in
                    if let error { cont.resume(throwing: Failure.unreachable(error.localizedDescription)) }
                    else if let data, !data.isEmpty { cont.resume(returning: data) }
                    else if complete { cont.resume(throwing: Failure.closed) }
                    else { cont.resume(returning: Data()) }
                }
            }
            buffer += chunk
        }
    }

    static func length(_ n: Int) -> [UInt8] { [UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)] }

    static func nonce(_ counter: UInt64) -> [UInt8] {
        (0..<8).map { UInt8(truncatingIfNeeded: counter >> (UInt64($0) * 8)) } + [0, 0, 0, 0]
    }

    /// Os nonces do emparelhamento: 4 zeros e 8 letras ("PS-Msg05", "PV-Msg02", …).
    static func pairingNonce(_ label: String) throws -> ChaChaPoly.Nonce {
        try ChaChaPoly.Nonce(data: [0, 0, 0, 0] + Array(label.utf8))
    }
}

/// O que fica guardado depois de emparelhar com uma Apple TV (no Keychain, por TV).
struct CompanionCredentials: Codable {
    /// A chave pública Ed25519 da TV.
    var tvPublicKey: Data
    /// A nossa chave privada Ed25519 (32 bytes).
    var privateKey: Data
    /// O identificador da TV (da M6).
    var tvID: Data
    /// O nosso identificador (UUID em texto, 36 bytes ASCII).
    var clientID: Data

    private static let service = "cc.slokker.goatremote.appletv"

    static func load(_ tvID: String) -> CompanionCredentials? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: tvID,
                                      kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(CompanionCredentials.self, from: data)
    }

    func save(_ tvID: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let match: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: tvID]
        SecItemDelete(match as CFDictionary)
        var add = match
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete(_ tvID: String) {
        let match: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: tvID]
        SecItemDelete(match as CFDictionary)
    }
}
