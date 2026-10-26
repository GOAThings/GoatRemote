import Foundation
import Network
import RemoteCore

/// Uma TV que se anuncia na rede: Android TV (_androidtvremote2._tcp) ou Apple TV (_companion-link._tcp).
struct FoundTV: Identifiable, Hashable {
    var name: String
    var endpoint: NWEndpoint
    var kind: TVKind
    /// O modelo, quando a TV o diz (Apple TV: "AppleTV11,1").
    var model: String?

    /// O mesmo id com que fica guardada depois de emparelhada.
    var id: String { kind == .apple ? "apple:" + name : name }
}

/// Procura TVs na rede de casa enquanto está ligado.
@MainActor
final class TVFinder: ObservableObject {
    @Published private(set) var found: [FoundTV] = []
    private var browsers: [NWBrowser] = []
    private var android: [FoundTV] = []
    private var apple: [FoundTV] = []

    func start() {
        guard browsers.isEmpty else { return }
        let params = NWParameters()
        params.includePeerToPeer = false
        let androidBrowser = NWBrowser(for: .bonjour(type: RemoteCore.Discovery.serviceType, domain: nil), using: params)
        androidBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            let tvs = results.compactMap { result -> FoundTV? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return FoundTV(name: name, endpoint: result.endpoint, kind: .android)
            }
            DebugLog.add("Found Android TVs: \(tvs.map(\.name))")
            Task { @MainActor in self?.android = tvs; self?.merge() }
        }
        // O _companion-link também é anunciado por iPhones, iPads, Macs e HomePods: só as Apple TV (rpMd).
        let appleBrowser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.appleService, domain: nil), using: params)
        appleBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            let tvs = results.compactMap { result -> FoundTV? in
                guard case .service(let name, _, _, _) = result.endpoint,
                      case .bonjour(let txt) = result.metadata,
                      let model = txt.dictionary["rpMd"], model.hasPrefix("AppleTV") else { return nil }
                return FoundTV(name: name, endpoint: result.endpoint, kind: .apple, model: model)
            }
            // Os outros aparelhos Apple só pelo modelo, para ver se a Apple TV aparece com outro rpMd.
            let others = results.compactMap { result -> String? in
                let model = result.metadata.txtDictionary?["rpMd"] ?? "?"
                return model.hasPrefix("AppleTV") ? nil : model
            }
            DebugLog.add("Found Apple TVs: \(tvs.map { "\($0.name) (\($0.model ?? "?"))" })" + (others.isEmpty ? "" : ", ignored \(others)"))
            Task { @MainActor in self?.apple = tvs; self?.merge() }
        }
        for browser in [androidBrowser, appleBrowser] {
            // Sem a autorização da rede local, o browser fica em "waiting" e nunca encontra nada.
            let what = "\(browser.descriptor)"
            browser.stateUpdateHandler = { state in DebugLog.add("Browser \(what): \(state)") }
            browser.start(queue: .main)
        }
        browsers = [androidBrowser, appleBrowser]
    }

    private func merge() {
        found = (android + apple).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers = []
    }

    static let appleService = "_companion-link._tcp"

    /// O IP de uma TV anunciada (liga-se ao serviço e vê para onde foi; IPv4 de preferência).
    nonisolated static func resolve(_ endpoint: NWEndpoint) async -> String? {
        await resolveHostPort(endpoint)?.host
    }

    /// O IP e a porta (a Apple TV não tem porta fixa).
    nonisolated static func resolveHostPort(_ endpoint: NWEndpoint) async -> (host: String, port: UInt16)? {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: endpoint, using: params)
        let hostPort: (host: String, port: UInt16)? = await withCheckedContinuation { cont in
            var done = false
            func finish(_ value: (host: String, port: UInt16)?) {
                guard !done else { return }
                done = true
                connection.cancel()
                cont.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint {
                        var text = "\(host)"
                        if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
                        finish((text, port.rawValue))
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 6) { connection.cancel() }
        }
        return hostPort
    }
}

private extension NWEndpoint.Metadata {
    var txtDictionary: [String: String]? {
        if case .bonjour(let txt) = self { return txt.dictionary }
        return nil
    }
}
