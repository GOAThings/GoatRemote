import Foundation
import RemoteCore

/// Uma resposta do GoatTV já lida: o estado, se a ligação foi recusada, e o que veio (nil se não veio ou não se leu).
struct Fetched<T> {
    var status = 0
    var refused = false
    var value: T?
    var error: Error?
}

/// O GoatTV de uma TV (porta 6471; contracts/goattv-6471): os pedidos, sem decidir nada. O que fazer com cada resposta
/// fica com quem chama.
struct GoatTvApi {
    let host: String

    private func url(_ what: String, key: String? = nil) -> URL? { URL(string: GoatTVChannels.url(host: host, what, key: key)) }

    /// GET /channels: até 8 MiB de JSON, lido fora da thread principal. nil se o endereço não dá um URL.
    func channels() async -> Fetched<ChannelList>? {
        guard let url = url("channels") else { return nil }
        let r = await LanHttp.get(url, timeout: 8, limit: GoatTVChannels.maxBytes)
        guard let body = r.body else { return Fetched(status: r.status, refused: r.refused, error: r.error) }
        do {
            return Fetched(status: r.status, value: try await Task.detached(priority: .userInitiated) { try GoatTVChannels.parse(body) }.value)
        } catch {
            return Fetched(status: r.status, error: error)
        }
    }

    /// GET /now (pequeno). nil se o endereço não dá um URL.
    func now() async -> Fetched<NowInfo>? {
        guard let url = url("now") else { return nil }
        let r = await LanHttp.get(url, timeout: 3, limit: GoatTVChannels.maxNowBytes)
        guard let body = r.body else { return Fetched(status: r.status, refused: r.refused, error: r.error) }
        do {
            return Fetched(status: r.status, value: try GoatTVChannels.parseNow(body))
        } catch {
            return Fetched(status: r.status, error: error)
        }
    }

    /// POST /play/<chave>: o estado HTTP e se a ligação foi recusada.
    func play(_ key: String) async -> (status: Int, refused: Bool) {
        guard let url = url("play", key: key) else { return (0, false) }
        let r = await LanHttp.post(url, timeout: 4)
        if let error = r.error { DebugLog.add("Play failed: \(error)") }
        return (r.status, r.refused)
    }

    func logoURL(_ key: String) -> URL? { url("logo", key: key) }
}
