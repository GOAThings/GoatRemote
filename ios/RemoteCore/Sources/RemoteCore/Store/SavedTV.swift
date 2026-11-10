import Foundation

/// Android TV / Google TV (protocolo da app Google TV) ou Apple TV (protocolo Companion).
public enum TVKind: String, Codable, CaseIterable, Sendable {
    case android, apple
}

/// Uma TV guardada (emparelhada). [id] é o nome com que se anuncia na rede ("apple:" + nome nas Apple TV), ou o IP
/// se foi juntada à mão. Fica em UserDefaults "tvs" (contracts/persisted/ios/tvs.json): os nomes dos campos não mudam.
public struct SavedTV: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var host: String
    public var kind: TVKind = .android
    /// A porta do comando, se não for a de sempre (a Apple TV escolhe uma).
    public var port: UInt16?
    /// O SHA-256 do certificado do comando da TV (Android TV), guardado na primeira ligação depois de emparelhar.
    public var certificate: String?

    public init(id: String, name: String, host: String, kind: TVKind = .android, port: UInt16? = nil, certificate: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.kind = kind
        self.port = port
        self.certificate = certificate
    }

    // As TVs guardadas antes de haver Apple TV não têm "kind".
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        kind = try c.decodeIfPresent(TVKind.self, forKey: .kind) ?? .android
        port = try c.decodeIfPresent(UInt16.self, forKey: .port)
        certificate = try c.decodeIfPresent(String.self, forKey: .certificate)
    }

    /// A mesma TV num endereço novo (visto na procura), ou nil se não mudou. Só a Apple TV guarda a porta: a da Android
    /// TV é sempre a mesma. O certificado fica: continua a ser a mesma TV.
    public static func moved(_ tv: SavedTV, host: String, port: UInt16?) -> SavedTV? {
        let newPort = tv.kind == .apple ? port ?? tv.port : tv.port
        guard !host.isEmpty, host != tv.host || newPort != tv.port else { return nil }
        var moved = tv
        moved.host = host
        moved.port = newPort
        return moved
    }
}
