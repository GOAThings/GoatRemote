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

    enum SendFailure: Error {
        case tooMany
        case http(Int)
    }

    /// Envia o registo para a zona admin do site (`POST /api/reports`, sem conta) e devolve o id do relatório.
    @MainActor
    static func send(message: String, contact: String) async throws -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let device = UIDevice.current
        // O servidor aceita até 64 KB de registo: ficam as linhas mais recentes.
        var log = text
        while log.utf8.count > 60_000, let cut = log.firstIndex(of: "\n") { log = String(log[log.index(after: cut)...]) }
        let body: [String: String] = [
            "app": "goatremote",
            "version": version,
            "platform": "ios",
            "device": "\(device.systemName) \(device.systemVersion) · \(device.model)",
            "message": String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000)),
            "contact": String(contact.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)),
            "log": log,
        ]
        var request = URLRequest(url: URL(string: "https://thegoat.systems/api/reports")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("goatremote/\(version) (ios)", forHTTPHeaderField: "X-Goat-Client")
        request.httpBody = try JSONSerialization.data(withJSONObject: body.filter { !$0.value.isEmpty })
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            add("Report failed: \(error)")
            throw error
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 201 || status == 200,
              let id = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String else {
            add("Report failed: HTTP \(status) \(String(decoding: data.prefix(300), as: UTF8.self))")
            throw status == 429 ? SendFailure.tooMany : SendFailure.http(status)
        }
        add("Report \(id) sent")
        return id
    }

    static func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
    }
}
