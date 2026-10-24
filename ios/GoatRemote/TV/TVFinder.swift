import Foundation
import Network
import RemoteCore

/// Uma TV que se anuncia na rede (Bonjour, _androidtvremote2._tcp).
struct FoundTV: Identifiable, Hashable {
    var name: String
    var endpoint: NWEndpoint

    var id: String { name }
}

/// Procura TVs na rede de casa enquanto está ligado.
@MainActor
final class TVFinder: ObservableObject {
    @Published private(set) var found: [FoundTV] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: RemoteCore.Discovery.serviceType, domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let tvs = results.compactMap { result -> FoundTV? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return FoundTV(name: name, endpoint: result.endpoint)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            Task { @MainActor in self?.found = tvs }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// O IP de uma TV anunciada (liga-se ao serviço e vê para onde foi; IPv4 de preferência).
    nonisolated static func resolve(_ endpoint: NWEndpoint) async -> String? {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: endpoint, using: params)
        let host: String? = await withCheckedContinuation { cont in
            var done = false
            func finish(_ value: String?) {
                guard !done else { return }
                done = true
                connection.cancel()
                cont.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, _)? = connection.currentPath?.remoteEndpoint {
                        var text = "\(host)"
                        if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
                        finish(text)
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
        return host
    }
}
