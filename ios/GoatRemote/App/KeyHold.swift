import Foundation
import RemoteCore

/// As teclas mantidas (o OK longo, uma seta a repetir) de uma sessão: os temporizadores correm aqui, não na vista. Um
/// controlo que sai do ecrã a meio (a TV desligou-se, mudou o layout) chama end(): a repetição pára e um OK longo
/// acaba com o fim do toque longo (B5: uma Task em @State sobrevivia à vista e continuava a mandar a seta à TV).
@MainActor
final class KeyHold {
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var long: Key?
    private var endLong: ((Key) -> Void)?

    /// Um temporizador ou repetição desta tecla mantida.
    @discardableResult
    func later(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await operation()
            self?.tasks[id] = nil
        }
        tasks[id] = task
        return task
    }

    /// O início do toque longo já foi para a TV; end() manda o fim se o controlo sair antes.
    func longStarted(_ key: Key, end: @escaping (Key) -> Void) {
        long = key
        endLong = end
    }

    /// O fim do toque longo já foi (o dedo saiu).
    func longEnded() {
        long = nil
        endLong = nil
    }

    /// O controlo saiu do ecrã: pára tudo e acaba o toque longo, se havia.
    func end() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        guard let key = long else { return }
        let end = endLong
        longEnded()
        end?(key)
    }
}
