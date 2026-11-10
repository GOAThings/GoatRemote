import Foundation
import RemoteCore

/// Os pedidos HTTP na rede de casa (o GoatLauncher em 6470, o GoatTV em 6471): sem cabeçalhos além dos do sistema
/// (o launcher recusa pedidos com Origin), com tempos por pedido e respostas com limite de bytes.
///
/// "Recusado" é só URLError.cannotConnectToHost: a porta está fechada, a app não está a correr. É o que o
/// LauncherVolume.outcome usa para decidir se pode mandar a tecla de volume, por isso não se alarga. A única exceção
/// é o volume, onde um endereço que não dá um URL também conta como recusa (ver LauncherApi.volume). No Android é a
/// ConnectException, e um URL que não se lê nunca é recusa (data/LanHttp.kt).
enum LanHttp {
    /// O estado HTTP (0 sem resposta), se a ligação foi recusada, o corpo (só num GET 200) e o erro, se houve.
    struct Result {
        var status = 0
        var refused = false
        var body: Data?
        var error: Error?
    }

    static func url(_ host: String, _ port: Int, _ path: String) -> URL? {
        URL(string: LanURL.string(host: host, port: port, path: path))
    }

    /// Um GET com limite de bytes; nunca lança.
    static func get(_ url: URL, timeout: TimeInterval, limit: Int) async -> Result {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        do {
            let (data, status) = try await BoundedHTTP.get(request, limit: limit)
            return Result(status: status, body: status == 200 ? data : nil)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            return Result(refused: true)
        } catch {
            return Result(error: error)
        }
    }

    /// Um POST sem corpo; nunca lança.
    static func post(_ url: URL, timeout: TimeInterval) async -> Result {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        do {
            return Result(status: ((try await URLSession.shared.data(for: request)).1 as? HTTPURLResponse)?.statusCode ?? 0)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            return Result(refused: true)
        } catch {
            return Result(error: error)
        }
    }
}

/// Um GET com limites de bytes e de tempo: uma resposta que passe deles é erro, não fica em memória.
enum BoundedHTTP {
    static func get(_ request: URLRequest, limit: Int) async throws -> (data: Data, status: Int) {
        let (stream, response) = try await URLSession.shared.bytes(for: request)
        defer { stream.task.cancel() }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { return (Data(), status) }
        guard response.expectedContentLength <= Int64(limit) else { throw URLError(.dataLengthExceedsMaximum) }
        let deadline = Date().addingTimeInterval(20)
        var data = Data()
        for try await byte in stream {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            guard Date() < deadline else { throw URLError(.timedOut) }
            data.append(byte)
        }
        return (data, status)
    }
}
