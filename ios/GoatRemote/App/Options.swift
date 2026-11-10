import Foundation
import Observation
import RemoteCore

/// As opções (Mais → Opções), guardadas em UserDefaults com os nomes de sempre.
@MainActor
@Observable
final class Options {
    var haptics: Bool = UserDefaults.standard.object(forKey: StoreKeys.haptics) as? Bool ?? true {
        didSet { UserDefaults.standard.set(haptics, forKey: StoreKeys.haptics) }
    }
    /// Os botões de volume do iPhone mexem no volume da TV (com a app aberta).
    var volumeButtons: Bool = UserDefaults.standard.object(forKey: StoreKeys.volumeButtons) as? Bool ?? true {
        didSet { UserDefaults.standard.set(volumeButtons, forKey: StoreKeys.volumeButtons) }
    }
    /// Superfície de toque ou setas (D-pad). Quem tinha as "setas nas bordas" ligadas começa nas setas.
    var layout: RemoteLayout = RemoteLayout.saved(UserDefaults.standard.string(forKey: StoreKeys.layout),
                                                  dpadTaps: UserDefaults.standard.bool(forKey: StoreKeys.dpadTaps)) {
        didSet {
            UserDefaults.standard.set(layout.rawValue, forKey: StoreKeys.layout)
            UserDefaults.standard.removeObject(forKey: StoreKeys.dpadTaps)
        }
    }
}
