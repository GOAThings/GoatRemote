import Foundation
import RemoteCore

/// As TVs guardadas e a escolhida (partilhadas pela app e pelos Atalhos).
enum TVStore {
    private static let key = StoreKeys.tvs
    private static let currentKey = StoreKeys.current

    static var all: [SavedTV] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([SavedTV].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    static var currentID: String? {
        get { UserDefaults.standard.string(forKey: currentKey) }
        set { UserDefaults.standard.set(newValue, forKey: currentKey) }
    }

    static var current: SavedTV? {
        let tvs = all
        return tvs.first { $0.id == currentID } ?? tvs.first
    }

    static func save(_ tv: SavedTV) {
        var tvs = all
        if let i = tvs.firstIndex(where: { $0.id == tv.id }) { tvs[i] = tv } else { tvs.append(tv) }
        all = tvs
    }

    /// O certificado guardado de uma TV (sempre o do que está guardado, não o de uma cópia em memória).
    static func certificate(of id: String) -> String? {
        all.first { $0.id == id }?.certificate
    }

    /// Ainda sem certificado (acabada de emparelhar, ou de antes de se guardar): fica o da primeira ligação bem sucedida.
    static func pinCertificate(_ id: String, _ certificate: String) {
        var tvs = all
        guard let i = tvs.firstIndex(where: { $0.id == id }), tvs[i].certificate == nil else { return }
        tvs[i].certificate = certificate
        all = tvs
    }

    static func remove(_ id: String) {
        all = all.filter { $0.id != id }
        if currentID == id { currentID = all.first?.id }
    }
}
