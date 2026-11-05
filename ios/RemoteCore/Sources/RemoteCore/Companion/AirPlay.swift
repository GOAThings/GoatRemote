import Foundation

/// A cabeça de uma resposta HTTP do emparelhamento pelo AirPlay (as respostas são TLV pequenos).
public enum AirPlayHead {
    public static let maxHead = 64 * 1024
    public static let maxBody = 1 << 20

    /// O estado e o tamanho do corpo; um Content-Length que não seja um número até [maxBody] é erro.
    public static func parse(_ head: [UInt8]) throws -> (status: Int, length: Int) {
        let lines = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n")
        let status = lines.first.flatMap { Int($0.split(separator: " ").dropFirst().first ?? "") } ?? 0
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased() == "content-length" else { continue }
            guard let length = Int(parts[1].trimmingCharacters(in: .whitespaces)), length >= 0, length <= maxBody else {
                throw ProtocolError.malformed("Content-Length")
            }
            return (status, length)
        }
        return (status, 0)
    }
}

/// A identidade que uma TV mostra na verificação do Companion (M2), contra o que está guardado.
public enum CompanionIdentity {
    public enum Verdict: Equatable, Sendable {
        /// O id e a chave guardados: a TV provou quem é.
        case verified
        /// Emparelhada pelo AirPlay e ainda sem identidade no Companion: a primeira verificação guarda o id.
        case firstSeen
        /// Emparelhada pelo AirPlay, com o mesmo id da primeira verificação.
        case pinned
        case rejected
    }

    /// [provenByKey]: o id é o guardado e a assinatura bate com a chave guardada. Só o emparelhamento pelo AirPlay
    /// pode ter outra identidade no Companion, e depois de vista essa identidade não muda.
    public static func check(id: [UInt8], provenByKey: Bool, viaAirPlay: Bool, pinned: [UInt8]?) -> Verdict {
        if provenByKey { return .verified }
        guard viaAirPlay else { return .rejected }
        guard let pinned else { return .firstSeen }
        return id == pinned ? .pinned : .rejected
    }
}
