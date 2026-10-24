import Foundation
import RemoteCore

/// Uma TV guardada (emparelhada). [id] é o nome com que se anuncia na rede, ou o IP se foi juntada à mão.
struct SavedTV: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var host: String
}

/// As TVs guardadas e a escolhida (partilhadas pela app e pelos Atalhos).
enum TVStore {
    private static let key = "tvs"
    private static let currentKey = "current"

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
            throw Failure.notPaired
        } catch TVConnection.Failure.unreachable(let why) {
            throw Failure.unreachable(why)
        }
        self.connection = connection
        // Até a TV mandar set_active (com um limite: se fechar antes, não estamos emparelhados).
        let ready: Bool = await withTaskGroup(of: Bool.self) { group in
            group.addTask { [self] in
                do {
                    while !isReady { try await handle(try await connection.receive()) }
                    return true
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
            return first
        }
        guard ready else {
            connection.close()
            throw Failure.notPaired
        }
        loop = Task { [weak self] in
            while let self, !Task.isCancelled {
                do {
                    try await self.handle(try await connection.receive())
                } catch {
                    break
                }
            }
            if !Task.isCancelled, let onClose = self?.onClose { await onClose() }
        }
    }

    private var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return proto.ready
    }

    private func handle(_ frame: [UInt8]) async throws {
        lock.lock()
        let before = proto.state
        let replies: [Data]
        do {
            replies = try proto.handle(frame)
        } catch {
            lock.unlock()
            throw error
        }
        let after = proto.state
        lock.unlock()
        for reply in replies { try await connection?.send(reply) }
        if after != before, let onState { await onState(after) }
    }

    private func send(_ build: (RemoteProtocol) -> Data) {
        lock.lock()
        let data = build(proto)
        lock.unlock()
        Task { try? await connection?.send(data) }
    }

    func key(_ key: Key, _ direction: KeyDirection = .short) { send { $0.key(key, direction) } }

    func text(_ text: String) { send { $0.text(text) } }

    func openApp(_ link: String) { send { $0.appLink(link) } }

    func close() {
        loop?.cancel()
        connection?.close()
        connection = nil
    }

    /// Para os Atalhos: liga, manda e desliga.
    static func once(_ action: (RemoteLink) -> Void) async throws {
        guard let tv = TVStore.current else { throw Failure.unreachable("sem TV") }
        let link = RemoteLink(tv: tv)
        try await link.connect()
        action(link)
        try? await Task.sleep(nanoseconds: 400_000_000)
        link.close()
    }
}
