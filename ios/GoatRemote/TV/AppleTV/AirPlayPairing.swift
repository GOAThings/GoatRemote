import Foundation
import Network
import RemoteCore

/// Plano B do emparelhamento com a Apple TV: pelo AirPlay (HTTP na porta 7000). No tvOS 26/27, a Apple TV 4K de
/// 3.ª geração entra em modo de PIN no Companion mas não o mostra (pyatv #2837); no AirPlay, o PIN aparece com o
/// pedido `/pair-pin-start` e o nome do cliente no cabeçalho `X-Apple-Client-Name` (Home Assistant #173352).
/// O emparelhamento é o mesmo (SRP com o PIN e as identidades Ed25519): a chave que fica usa-se no Companion, se a
/// TV a aceitar lá (ver AppleTVLink.verify).
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
        try await send(Array(head.utf8) + body)
        // Cabeçalhos até à linha vazia; depois o Content-Length.
        while true {
            if let end = find([13, 10, 13, 10]) {
                let text = String(decoding: buffer[..<end], as: UTF8.self)
                let lines = text.components(separatedBy: "\r\n")
                let status = lines.first.flatMap { Int($0.split(separator: " ").dropFirst().first ?? "") } ?? 0
                let length = lines.dropFirst().compactMap { line -> Int? in
                    let parts = line.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
                    return Int(parts[1].trimmingCharacters(in: .whitespaces))
                }.first ?? 0
                while buffer.count < end + 4 + length { try await receiveMore() }
                let bodyBytes = Array(buffer[(end + 4)..<(end + 4 + length)])
                buffer.removeFirst(end + 4 + length)
                return Response(status: status, body: bodyBytes)
            }
            try await receiveMore()
        }
    }

    private func find(_ pattern: [UInt8]) -> Int? {
        guard buffer.count >= pattern.count else { return nil }
        for i in 0...(buffer.count - pattern.count) where Array(buffer[i..<(i + pattern.count)]) == pattern { return i }
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
