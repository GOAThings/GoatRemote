import Foundation
import Network
import RemoteCore

/// Uma ligação TLS a uma porta da TV (6467 emparelhar, 6466 comando), às mensagens inteiras. A TV tem um certificado
/// auto-assinado: aceita-se qualquer um e guarda-se, porque o que dá segurança é o emparelhamento.
final class TVConnection: @unchecked Sendable {
    enum Failure: Error {
        /// Não chegou à TV (desligada da rede, IP errado).
        case unreachable(String)
        /// Chegou mas a TV fechou: no comando, quase sempre é porque este iPhone ainda não está emparelhado.
        case closed
    }

    private let connection: NWConnection
    private let queue: DispatchQueue
    private var reader = Frame.Reader()
    private let lock = NSLock()
    private var _serverCertificate: [UInt8]?

    /// O certificado da TV (DER), conhecido depois de abrir.
    var serverCertificate: [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        return _serverCertificate
    }

    init(host: String, port: UInt16, identity: SecIdentity) {
        let queue = DispatchQueue(label: "cc.slokker.goatremote.tv")
        self.queue = queue
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        if let id = sec_identity_create(identity) { sec_protocol_options_set_local_identity(sec, id) }
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        let box = CertificateBox()
        sec_protocol_options_set_verify_block(sec, { _, trust, complete in
            let ref = sec_trust_copy_ref(trust).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(ref) as? [SecCertificate], let first = chain.first {
                box.der = Array(SecCertificateCopyData(first) as Data)
            }
            complete(true)
        }, queue)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 6
        tcp.enableKeepalive = true
        let params = NWParameters(tls: tls, tcp: tcp)
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
        self.box = box
    }

    private let box: CertificateBox

    private final class CertificateBox: @unchecked Sendable {
        var der: [UInt8]?
    }

    func open() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { [weak self] state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    if let self {
                        self.lock.lock()
                        self._serverCertificate = self.box.der
                        self.lock.unlock()
                    }
                    cont.resume()
                case .failed(let error):
                    resumed = true
                    cont.resume(throwing: Self.classify(error))
                case .waiting(let error):
                    resumed = true
                    self?.connection.cancel()
                    cont.resume(throwing: Self.classify(error))
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

    /// Recusas de TLS contam como "fechou" (a TV não aceita este certificado); o resto como "não chegou".
    private static func classify(_ error: NWError) -> Error {
        if case .tls = error { return Failure.closed }
        if case .posix(let code) = error, code == .ECONNRESET || code == .EPIPE { return Failure.closed }
        return Failure.unreachable(error.localizedDescription)
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: Self.classify(error)) } else { cont.resume() }
            })
        }
    }

    /// A próxima mensagem inteira da TV.
    func receive() async throws -> [UInt8] {
        while true {
            if let frame = try reader.next() { return frame }
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, complete, error in
                    if let error { cont.resume(throwing: Self.classify(error)) }
                    else if let data, !data.isEmpty { cont.resume(returning: data) }
                    else if complete { cont.resume(throwing: Failure.closed) }
                    else { cont.resume(returning: Data()) }
                }
            }
            reader.append(chunk)
        }
    }

    func close() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}
