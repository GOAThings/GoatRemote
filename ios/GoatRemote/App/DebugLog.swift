import Foundation
import OSLog
import UIKit

/// Registo de diagnóstico: os passos da procura, da ligação e do emparelhamento (nunca PINs, códigos, chaves ou
/// certificados). Fica em memória (as últimas [limit] linhas) e no registo do sistema; em Mais → Diagnóstico
/// pode copiar-se ou partilhar-se, para perceber o que falhou na TV de outra pessoa.
enum DebugLog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lines: [String] = []
    private static let logger = Logger(subsystem: "cc.slokker.goatremote", category: "debug")
    private static let limit = 500

    static func add(_ message: String) {
        let line = Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()) + "  " + message
        lock.lock()
        lines.append(line)
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        lock.unlock()
        logger.info("\(message, privacy: .public)")
    }

    /// O registo com uma linha de cabeçalho (versão da app e do sistema), pronto a partilhar.
    @MainActor
    static var text: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let device = UIDevice.current
        let header = "GoatRemote \(version) · \(device.systemName) \(device.systemVersion) · \(device.model)"
        lock.lock()
        defer { lock.unlock() }
        return ([header] + lines).joined(separator: "\n")
    }

    static func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
    }
}
