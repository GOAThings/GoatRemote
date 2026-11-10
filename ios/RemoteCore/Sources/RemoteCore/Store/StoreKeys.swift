import Foundation

/// Os nomes de tudo o que fica guardado em UserDefaults (contracts/persisted/options-keys.json). Quem já tem a app
/// guarda isto: um nome que mude é uma opção, uma TV ou um emparelhamento que se perde.
public enum StoreKeys {
    public static let tvs = "tvs"
    public static let current = "current"
    public static let haptics = "haptics"
    public static let volumeButtons = "volumeButtons"
    public static let layout = "layout"
    /// As "setas nas bordas" de antes: só se lê sem `layout`, e sai na próxima mudança.
    public static let dpadTaps = "dpadTaps"
    /// O _i estável que a Apple TV vê.
    public static let companionID = "companion.id"

    public static let recents = "recents"
    public static let launcher = "launcher"
    public static let volumeUnknown = "volumeUnknown"
    public static let goatTV = "goattv"

    /// O que é de uma TV guarda-se como "<prefixo>.<id da TV>"; esquecê-la apaga todos.
    public static let perTV = [recents, launcher, volumeUnknown, goatTV]

    public static func perTV(_ prefix: String, _ tvID: String) -> String { "\(prefix).\(tvID)" }

    /// Todas as chaves de uma TV (para a esquecer).
    public static func perTVKeys(_ tvID: String) -> [String] { perTV.map { perTV($0, tvID) } }

    /// O Keychain das credenciais da Apple TV (a conta é o id da TV).
    public static let appleTVService = "cc.slokker.goatremote.appletv"
}

/// O meio do comando: a superfície de toque (deslizar) ou as setas com o OK, como num comando físico.
public enum RemoteLayout: String, CaseIterable, Sendable {
    case touch, dpad

    /// O guardado ("touch" ou "dpad"); sem ele, quem tinha as "setas nas bordas" ligadas começa nas setas.
    public static func saved(_ value: String?, dpadTaps: Bool) -> RemoteLayout {
        value.flatMap(RemoteLayout.init(rawValue:)) ?? (dpadTaps ? .dpad : .touch)
    }
}
