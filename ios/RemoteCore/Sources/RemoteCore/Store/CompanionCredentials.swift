import Foundation

/// O que fica guardado depois de emparelhar com uma Apple TV (no Keychain, por TV; ver contracts/persisted/ios/
/// companion.json). O JSON é o do Codable: os nomes dos campos não mudam.
public struct CompanionCredentials: Codable, Equatable, Sendable {
    /// A chave pública Ed25519 da TV.
    public var tvPublicKey: Data
    /// A nossa chave privada Ed25519 (32 bytes).
    public var privateKey: Data
    /// O identificador da TV (da M6).
    public var tvID: Data
    /// O nosso identificador (UUID em texto, 36 bytes ASCII).
    public var clientID: Data
    /// Emparelhada pelo AirPlay (ver AirPlayPairing): a identidade da TV no Companion pode ser outra.
    public var viaAirPlay: Bool?
    /// O id que a TV mostrou no Companion na primeira verificação, se não for a identidade do AirPlay.
    public var companionID: Data?

    public init(tvPublicKey: Data, privateKey: Data, tvID: Data, clientID: Data, viaAirPlay: Bool? = nil, companionID: Data? = nil) {
        self.tvPublicKey = tvPublicKey
        self.privateKey = privateKey
        self.tvID = tvID
        self.clientID = clientID
        self.viaAirPlay = viaAirPlay
        self.companionID = companionID
    }
}
