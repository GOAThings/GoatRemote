import Foundation
import RemoteCore

/// O GoatLauncher de uma TV (porta 6470; contracts/launcher-6470): os pedidos, sem decidir nada. O que fazer com
/// cada resposta fica com quem chama (o volume, por exemplo, decide-se em LauncherVolume).
struct LauncherApi {
    let host: String

    private func url(_ path: String) -> URL? { LanHttp.url(host, LauncherApps.port, path) }

    /// GET /apps: a lista, ou nil se não respondeu com uma (sem launcher, ou ainda a arrancar).
    func apps() async -> [TVApp]? {
        guard let url = url("apps") else { return nil }
        guard let body = await LanHttp.get(url, timeout: 4, limit: LauncherApps.maxBytes).body else { return nil }
        return try? LauncherApps.parse(body)
    }

    /// POST /open/<pacote>: o estado HTTP (0 sem resposta, ou nil se o endereço não dá um URL).
    func open(_ package: String) async -> Int? {
        guard let url = url("open/\(package)") else { return nil }
        return await LanHttp.post(url, timeout: 3).status
    }

    /// POST /volume/…: o estado HTTP e se a ligação foi recusada. Um endereço que não dá um URL conta como recusa (o
    /// launcher não se alcança).
    func volume(_ what: String) async -> (status: Int, refused: Bool) {
        guard let url = url("volume/\(what)") else { return (0, true) }
        let r = await LanHttp.post(url, timeout: 3)
        if let error = r.error { DebugLog.add("Volume via launcher failed: \(error)") }
        return (r.status, r.refused)
    }

    /// O banner (ou ícone) de uma app.
    func iconURL(_ package: String) -> URL? { url("icon/\(package)") }
}

/// O que se sabe do GoatLauncher de cada TV ("launcher.<id>"): true se já respondeu, false se se viu que não há, nil
/// enquanto não se sabe. É disto que depende mandar ou não o volume como tecla (ver LauncherVolume.outcome).
enum LauncherMemory {
    static func known(_ tvID: String) -> Bool? {
        UserDefaults.standard.object(forKey: StoreKeys.perTV(StoreKeys.launcher, tvID)) as? Bool
    }

    static func set(_ tvID: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: StoreKeys.perTV(StoreKeys.launcher, tvID))
    }
}
