import Foundation
import Network
import Observation
import RemoteCore
import UIKit

/// O estado da app: as TVs, a ligação à escolhida e o emparelhamento.
@MainActor
@Observable
final class RemoteModel {
    enum Status: Equatable {
        case noTV
        case connecting
        case connected
        /// A TV não aceita este iPhone: emparelhar (outra vez).
        case notPaired
        case unreachable(String)
    }

    private(set) var tvs: [SavedTV] = []
    private(set) var current: SavedTV?
    private(set) var status: Status = .noTV
    private(set) var state = TVState()
    /// As apps que se viu abertas nesta TV (as mais recentes primeiro), para as abrir com um toque.
    private(set) var recentApps: [String] = []

    /// O emparelhamento em curso (a folha mostra-o).
    var pairing: PairingModel?

    @ObservationIgnored private var link: RemoteLink?
    @ObservationIgnored private let haptics = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private let heavyHaptics = UIImpactFeedbackGenerator(style: .medium)

    init() {
        #if DEBUG
        // Testes de interface: começa sem TVs.
        if CommandLine.arguments.contains("-UITestReset"), let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        #endif
        tvs = TVStore.all
        current = TVStore.current
        recentApps = Self.loadRecents(current?.id)
    }

    // MARK: Ligação

    func connect() {
        guard let tv = current else {
            status = .noTV
            return
        }
        if link != nil, status == .connected || status == .connecting { return }
        link?.close()
        status = .connecting
        let link = RemoteLink(tv: tv)
        link.onState = { [weak self] state in self?.update(state) }
        link.onClose = { [weak self, weak link] in
            guard let self, let link, self.link === link else { return }
            self.link = nil
            self.status = .unreachable(L("The TV closed the connection", "A TV fechou a ligação"))
        }
        self.link = link
        Task {
            do {
                try await link.connect()
                guard self.link === link else { return }
                self.status = .connected
                self.update(link.state)
            } catch RemoteLink.Failure.notPaired {
                guard self.link === link else { return }
                self.link = nil
                self.status = .notPaired
            } catch {
                guard self.link === link else { return }
                self.link = nil
                self.status = .unreachable(Self.describe(error))
            }
        }
    }

    func disconnect() {
        link?.close()
        link = nil
        if current != nil { status = .connecting }
    }

    func reconnect() {
        link?.close()
        link = nil
        connect()
    }

    private func update(_ new: TVState) {
        state = new
        if let app = new.currentApp, !AppCatalog.isLauncher(app) {
            recentApps.removeAll { $0 == app }
            recentApps.insert(app, at: 0)
            recentApps = Array(recentApps.prefix(12))
            if let id = current?.id { UserDefaults.standard.set(recentApps, forKey: "recents.\(id)") }
        }
    }

    private static func loadRecents(_ id: String?) -> [String] {
        guard let id else { return [] }
        return UserDefaults.standard.stringArray(forKey: "recents.\(id)") ?? []
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case RemoteLink.Failure.unreachable(let why): return why
        case Identity.Failure.keychain(let status): return "Keychain \(status)"
        case Identity.Failure.keyGeneration(let why): return why
        default: return error.localizedDescription
        }
    }

    // MARK: TVs

    func select(_ tv: SavedTV) {
        guard tv.id != current?.id else { return }
        link?.close()
        link = nil
        current = tv
        TVStore.currentID = tv.id
        state = TVState()
        recentApps = Self.loadRecents(tv.id)
        connect()
    }

    func forget(_ tv: SavedTV) {
        TVStore.remove(tv.id)
        tvs = TVStore.all
        if current?.id == tv.id {
            link?.close()
            link = nil
            current = TVStore.current
            state = TVState()
            recentApps = Self.loadRecents(current?.id)
            status = current == nil ? .noTV : .connecting
            connect()
        }
    }

    /// Emparelhar uma TV encontrada na rede ou escrita à mão (IP).
    func startPairing(name: String, id: String, host: String?, endpoint: NWEndpoint?) {
        pairing?.cancel()
        let model = PairingModel(name: name, id: id, host: host, endpoint: endpoint) { [weak self] tv in
            self?.paired(tv)
        }
        pairing = model
        model.start()
    }

    /// Emparelhar outra vez a TV escolhida (a TV esqueceu este iPhone).
    func repairCurrent() {
        guard let tv = current else { return }
        startPairing(name: tv.name, id: tv.id, host: tv.host, endpoint: nil)
    }

    private func paired(_ tv: SavedTV) {
        TVStore.save(tv)
        TVStore.currentID = tv.id
        tvs = TVStore.all
        link?.close()
        link = nil
        current = tv
        state = TVState()
        recentApps = Self.loadRecents(tv.id)
        status = .connecting
        connect()
    }

    // MARK: Comando

    func press(_ key: Key) {
        haptics.impactOccurred()
        guard let link, status == .connected else { return reconnectIfNeeded() }
        link.key(key)
    }

    /// Carregar e manter: início e fim.
    func hold(_ key: Key, down: Bool) {
        if down { heavyHaptics.impactOccurred() }
        guard let link, status == .connected else { return reconnectIfNeeded() }
        link.key(key, down ? .startLong : .endLong)
    }

    func type(_ text: String) {
        guard let link, status == .connected, !text.isEmpty else { return }
        link.text(text)
    }

    func open(_ link: String) {
        haptics.impactOccurred()
        guard let remote = self.link, status == .connected else { return reconnectIfNeeded() }
        remote.openApp(link)
    }

    private func reconnectIfNeeded() {
        if case .unreachable = status { connect() }
    }
}

/// Um emparelhamento: liga à porta 6467, a TV mostra o código e espera-se que a pessoa o escreva.
@MainActor
@Observable
final class PairingModel: Identifiable {
    enum Phase: Equatable {
        case connecting
        case waitingCode(retry: Bool)
        case checking
        case done
        case failed(String)
    }

    let id = UUID()
    let name: String
    private(set) var phase: Phase = .connecting

    @ObservationIgnored private let tvID: String
    @ObservationIgnored private var host: String?
    @ObservationIgnored private let endpoint: NWEndpoint?
    @ObservationIgnored private let onPaired: (SavedTV) -> Void
    @ObservationIgnored private var codeContinuation: CheckedContinuation<String, Error>?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var connection: TVConnection?

    init(name: String, id: String, host: String?, endpoint: NWEndpoint?, onPaired: @escaping (SavedTV) -> Void) {
        self.name = name
        self.tvID = id
        self.host = host
        self.endpoint = endpoint
        self.onPaired = onPaired
    }

    func start() {
        task = Task { await run() }
    }

    private func run() async {
        var opened: TVConnection?
        do {
            if host == nil, let endpoint { host = await TVFinder.resolve(endpoint) }
            guard let host else { throw RemoteLink.Failure.unreachable(L("Couldn't find the TV on the network", "Não deu para encontrar a TV na rede")) }
            let identity = try Identity.load()
            let connection = TVConnection(host: host, port: Pairing.port, identity: identity.identity)
            self.connection = connection
            opened = connection
            try await connection.open()
            guard let der = connection.serverCertificate, let server = RSAKey(certificate: der) else {
                throw RemoteLink.Failure.unreachable(L("The TV's certificate is unreadable", "O certificado da TV não se lê"))
            }
            try await Pairing.run(
                clientName: UIDevice.current.name,
                client: identity.key,
                server: server,
                send: { try await connection.send($0) },
                receive: { try await connection.receive() },
                askCode: { [weak self] retry in
                    guard let self else { throw CancellationError() }
                    return try await self.askCode(retry: retry)
                }
            )
            connection.close()
            phase = .done
            onPaired(SavedTV(id: tvID, name: name, host: host))
        } catch is CancellationError {
            opened?.close()
        } catch {
            opened?.close()
            // Um "tentar outra vez" já começou outro: este não mexe no ecrã.
            if !Task.isCancelled { phase = .failed(Self.explain(error)) }
        }
    }

    private func askCode(retry: Bool) async throws -> String {
        phase = .waitingCode(retry: retry)
        return try await withCheckedThrowingContinuation { codeContinuation = $0 }
    }

    /// O código que a pessoa escreveu (6 caracteres).
    func submit(_ code: String) {
        guard let cont = codeContinuation else { return }
        codeContinuation = nil
        phase = .checking
        cont.resume(returning: code)
    }

    /// Recomeça (a TV volta a mostrar um código novo).
    func retry() {
        cancel()
        phase = .connecting
        start()
    }

    func cancel() {
        codeContinuation?.resume(throwing: CancellationError())
        codeContinuation = nil
        task?.cancel()
        connection?.close()
    }

    private static func explain(_ error: Error) -> String {
        switch error {
        case Pairing.Failure.rejected(let status):
            return L("The TV refused (\(status)). Try again.", "A TV recusou (\(status)). Tenta outra vez.")
        case TVConnection.Failure.closed:
            return L("The TV closed the connection. Try again.", "A TV fechou a ligação. Tenta outra vez.")
        default:
            return RemoteModel.describe(error)
        }
    }
}
