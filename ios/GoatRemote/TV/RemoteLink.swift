import Foundation
import RemoteCore

extension TVKind {
    var symbol: String { self == .apple ? "appletv.fill" : "tv" }
}

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

/// O comando ligado a uma TV (porta 6466): negocia, responde aos pings e conta o estado da TV.
final class RemoteLink: @unchecked Sendable {
    enum Failure: Error {
        /// A TV recusou este iPhone: é preciso emparelhar (outra vez).
        case notPaired
        case unreachable(String)
    }

    let tv: SavedTV
    /// Mudanças de estado e o fim da ligação (na fila principal).
    var onState: (@MainActor (TVState) -> Void)?
    var onClose: (@MainActor () -> Void)?

    private var connection: TVConnection?
    private var proto: RemoteProtocol
    private let lock = NSLock()
    private var loop: Task<Void, Never>?
    /// Depois de close() esta ligação não faz mais nada, mesmo que ainda estivesse a abrir.
    private var closed = false

    init(tv: SavedTV) {
        self.tv = tv
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        proto = RemoteProtocol(model: "iPhone", appVersion: version)
    }

    var state: TVState {
        lock.lock()
        defer { lock.unlock() }
        return proto.state
    }

    /// Liga e espera que a TV aceite teclas.
    func connect() async throws {
        let identity = try Identity.load()
        let connection = TVConnection(host: tv.host, port: RemoteProtocol.port, identity: identity.identity)
        do {
            try await connection.open()
        } catch TVConnection.Failure.closed {
            DebugLog.add("Android TV: TLS closed by the TV (not paired?)")
            throw Failure.notPaired
        } catch TVConnection.Failure.unreachable(let why) {
            throw Failure.unreachable(why)
        }
        // Tem de ser a TV emparelhada, antes de ler ou mandar o que quer que seja.
        let seen = connection.serverCertificate.map(Certificate.fingerprint)
        let pinned = TVStore.certificate(of: tv.id)
        guard Certificate.matches(pinned: pinned, seen: seen) else {
            DebugLog.add("Android TV: not the certificate saved for this TV")
            connection.close()
            throw Failure.notPaired
        }
        guard attach(connection) else {
            connection.close()
            throw Failure.unreachable("closed")
        }
        // Até a TV mandar set_active (com um limite: se fechar antes, não estamos emparelhados).
        let ready: Bool = await withTaskGroup(of: Bool.self) { group in
            group.addTask { [self] in
                do {
                    while !isReady, !isClosed { try await handle(try await connection.receive()) }
                    return !isClosed
                } catch {
                    return false
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            // A leitura à espera só acaba com a ligação fechada, e o grupo espera por ela.
            if !first { connection.close() }
            return first
        }
        guard ready else {
            DebugLog.add("Android TV: no set_active from the TV (not paired?)")
            connection.close()
            throw Failure.notPaired
        }
        if pinned == nil, let seen { TVStore.pinCertificate(tv.id, seen) }
        loop = Task { [weak self] in
            while let self, !Task.isCancelled {
                do {
                    try await self.handle(try await connection.receive())
                } catch {
                    if !Task.isCancelled { DebugLog.add("Android TV: connection ended: \(error)") }
                    break
                }
            }
            connection.close()
            if !Task.isCancelled, let onClose = self?.onClose { await onClose() }
        }
    }

    private var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return proto.ready
    }

    private var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    /// Fica com a ligação aberta; false se close() já foi chamado.
    private func attach(_ connection: TVConnection) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if closed { return false }
        self.connection = connection
        return true
    }

    private func handle(_ frame: [UInt8]) async throws {
        guard !isClosed else { return }
        if let refused = RemoteProtocol.reportedError(frame) { DebugLog.add("Android TV: the TV reported an error about \(refused)") }
        lock.lock()
        let before = proto.state
        let replies: [Data]
        do {
            replies = try proto.handle(frame)
        } catch {
            lock.unlock()
            // Uma mensagem que não se percebe não é razão para largar a TV.
            DebugLog.add("Android TV: unreadable message: \(error)")
            return
        }
        let after = proto.state
        lock.unlock()
        for reply in replies { try await connection?.send(reply) }
        if after != before, !isClosed, let onState { await onState(after) }
    }

    private func send(_ build: (RemoteProtocol) -> Data) {
        lock.lock()
        let data = build(proto)
        lock.unlock()
        Task { try? await connection?.send(data) }
    }

    func key(_ key: Key, _ direction: KeyDirection = .short) { send { $0.key(key, direction) } }

    func text(_ text: String) {
        // Os Apagar e o texto vão juntos, para chegarem por ordem.
        lock.lock()
        let data = proto.text(text)
        lock.unlock()
        guard !data.isEmpty else { return }
        Task { try? await connection?.send(data) }
    }

    func openApp(_ link: String) { send { $0.appLink(link) } }

    func close() {
        lock.lock()
        closed = true
        let connection = self.connection
        self.connection = nil
        lock.unlock()
        loop?.cancel()
        connection?.close()
    }

    /// Para os Atalhos e a Siri: uma tecla, e o volume pelo mesmo caminho que no comando (ver LauncherMemory).
    @MainActor
    static func press(_ key: Key) async throws {
        if let what = LauncherVolume.path(key), let tv = TVStore.current, tv.kind == .android, LauncherMemory.known(tv.id) != false {
            let (status, refused) = await LauncherApi(host: tv.host).volume(what)
            switch LauncherVolume.outcome(known: LauncherMemory.known(tv.id), status: status, refused: refused) {
            case .done:
                LauncherMemory.set(tv.id, true)
                return
            case .noLauncher:
                DebugLog.add("Volume: no launcher on \(tv.name) (\(refused ? "refused" : "404")), using keys")
                LauncherMemory.set(tv.id, false)
            case .didntAnswer:
                DebugLog.add("Volume: launcher on \(tv.name) didn't answer (HTTP \(status)), not sending the key")
                throw Failure.unreachable(L("The TV's launcher didn't answer", "O launcher da TV não respondeu"))
            }
        }
        try await once { $0.key(key) }
    }

    /// Para os Atalhos: liga, manda e desliga.
    @MainActor
    static func once(_ action: (TVControl) -> Void) async throws {
        guard let tv = TVStore.current else { throw Failure.unreachable(L("No TV paired yet. Open GoatRemote and add one", "Ainda não há TV emparelhada. Abre o GoatRemote e junta uma")) }
        let link = makeTVLink(tv)
        try await link.connect()
        action(link)
        try? await Task.sleep(nanoseconds: 400_000_000)
        link.close()
    }
}

/// A ligação certa para o tipo de TV.
func makeTVLink(_ tv: SavedTV) -> TVControl {
    tv.kind == .apple ? AppleTVLink(tv: tv) : RemoteLink(tv: tv)
}
