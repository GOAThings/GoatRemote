import Foundation
import Network
import RemoteCore

/// Plano B do emparelhamento com a Apple TV: pelo AirPlay (HTTP na porta 7000). No tvOS 26/27, a Apple TV 4K de
/// 3.ª geração entra em modo de PIN no Companion mas não o mostra (pyatv #2837); no AirPlay, o PIN aparece com o
/// pedido `/pair-pin-start` e o nome do cliente no cabeçalho `X-Apple-Client-Name` (Home Assistant #173352).
/// O emparelhamento é o mesmo (SRP com o PIN e as identidades Ed25519): a chave que fica usa-se no Companion, se a
/// TV a aceitar lá. A identidade da TV guardada aqui é a do AirPlay: no Companion pode ser outra (ver AppleTVLink.verify).
enum AirPlayPairing {
    static let port: UInt16 = 7000

    /// O AirPlay emparelhou, mas a TV não aceita essa chave no Companion.
    struct NotForRemote: Error {}

    static func pair(host: String, name: String, askPIN: () async throws -> String) async throws -> CompanionCredentials {
        let http = RawHTTP(host: host, port: port)
        try await http.open()
        defer { http.close() }
        let headers = [
            "User-Agent": "AirPlay/320.20", "Connection": "keep-alive", "X-Apple-HKP": "3",
            "Content-Type": "application/octet-stream", "X-Apple-Client-Name": name,
        ]
        DebugLog.add("AirPlay pairing: \(host):\(port), asking the TV to show the PIN as \"\(name)\"")
        let start = try await http.post("/pair-pin-start", body: [], headers: headers)
        DebugLog.add("AirPlay pairing: pair-pin-start HTTP \(start.status)")
        guard (200..<300).contains(start.status) else { throw AppleTVPairing.Failure.tv("pair-pin-start HTTP \(start.status)") }
        let pin = try await askPIN()
        DebugLog.add("AirPlay pairing: PIN entered, sending M1")
        let exchange: AppleTVPairing.Exchange = { tlv in
            let response = try await http.post("/pair-setup", body: TLV8.encode(tlv), headers: headers)
            let reply = TLV8.decode(response.body)
            DebugLog.add("AirPlay pairing: HTTP \(response.status) TLV \(AppleTVPairing.describe(reply))")
            guard (200..<300).contains(response.status) else { throw AppleTVPairing.Failure.tv("pair-setup HTTP \(response.status)") }
            return try AppleTVPairing.check(reply)
        }
        // No AirPlay o PIN vem antes do M1: o pair-pin-start já o pôs no ecrã.
        let m2 = try await exchange([(0, [0]), (6, [1])])
        var creds = try await AppleTVPairing.finish(m2: m2, pin: pin, name: name, exchange: exchange)
        creds.viaAirPlay = true
        return creds
    }
}

/// HTTP/1.1 mínimo sobre uma só ligação TCP: o emparelhamento do AirPlay tem de ir todo na mesma ligação.
final class RawHTTP: @unchecked Sendable {
    struct Response {
        let status: Int
        let body: [UInt8]
    }

    private let connection: NWConnection
    private let host: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "cc.slokker.goatremote.airplay")
    private var buffer: [UInt8] = []

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 6
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
                    DebugLog.add("AirPlay \(self.map { "\($0.host):\($0.port)" } ?? "?"): \(state)")
                    self?.connection.cancel()
                    cont.resume(throwing: CompanionConnection.Failure.unreachable(error.localizedDescription))
                case .cancelled:
                    resumed = true
                    cont.resume(throwing: CompanionConnection.Failure.closed)
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

    func post(_ path: String, body: [UInt8], headers: [String: String]) async throws -> Response {
        var head = "POST \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nContent-Length: \(body.count)\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        let request = Array(head.utf8) + body
        // Cada pedido tem um limite de tempo, e cancelar o emparelhamento fecha a ligação.
        let deadline = Task { [self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if !Task.isCancelled { connection.cancel() }
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try await exchange(request)
        } onCancel: { [self] in
            close()
        }
    }

    private func exchange(_ request: [UInt8]) async throws -> Response {
        try await send(request)
        // Cabeçalhos até à linha vazia; depois o Content-Length. A cabeça e o corpo têm tamanho máximo.
        var scanned = 0
        while true {
            if let end = find([13, 10, 13, 10], from: scanned) {
                guard end <= AirPlayHead.maxHead else { throw AppleTVPairing.Failure.tv("resposta HTTP demasiado grande") }
                let head = try AirPlayHead.parse(Array(buffer[..<end]))
                let total = end + 4 + head.length
                while buffer.count < total { try await receiveMore() }
                let bodyBytes = Array(buffer[(end + 4)..<total])
                buffer.removeFirst(total)
                return Response(status: head.status, body: bodyBytes)
            }
            guard buffer.count <= AirPlayHead.maxHead else { throw AppleTVPairing.Failure.tv("resposta HTTP demasiado grande") }
            scanned = max(buffer.count - 3, 0)
            try await receiveMore()
        }
    }

    private func find(_ pattern: [UInt8], from start: Int) -> Int? {
        guard buffer.count - pattern.count >= start else { return nil }
        for i in start...(buffer.count - pattern.count) where buffer[i..<(i + pattern.count)].elementsEqual(pattern) { return i }
        return nil
    }

    private func send(_ bytes: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: CompanionConnection.Failure.unreachable(error.localizedDescription)) } else { cont.resume() }
            })
        }
    }

    private func receiveMore() async throws {
        let chunk: [UInt8] = try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
                if let error { cont.resume(throwing: CompanionConnection.Failure.unreachable(error.localizedDescription)) }
                else if let data, !data.isEmpty { cont.resume(returning: Array(data)) }
                else if complete { cont.resume(throwing: CompanionConnection.Failure.closed) }
                else { cont.resume(returning: []) }
            }
        }
        buffer += chunk
    }
}
