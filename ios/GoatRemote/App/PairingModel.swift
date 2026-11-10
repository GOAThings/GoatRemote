import Foundation
import Network
import Observation
import RemoteCore
import UIKit

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
    let kind: TVKind
    /// A emparelhar pelo AirPlay (depois de "Não aparece o PIN?").
    private(set) var usingAirPlay = false
    private(set) var phase: Phase = .connecting {
        didSet { if phase != oldValue { DebugLog.add("Pairing \(name): \(phase)") } }
    }

    /// O código que a TV mostra: 6 caracteres hexadecimais (Android TV) ou um PIN de 4 algarismos (Apple TV).
    var codeLength: Int { kind == .apple ? 4 : Pairing.codeLength }

    @ObservationIgnored private let tvID: String
    @ObservationIgnored private var host: String?
    @ObservationIgnored private var port: UInt16?
    @ObservationIgnored private let endpoint: NWEndpoint?
    @ObservationIgnored private let onPaired: (SavedTV) -> Void
    /// A folha fecha-se (0,7 s depois de emparelhar, para se ver o "feito"; o mesmo que no Android).
    @ObservationIgnored private let onDone: (PairingModel) -> Void
    @ObservationIgnored private var codeContinuation: CheckedContinuation<String, Error>?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var connection: TVConnection?

    init(name: String, id: String, host: String?, endpoint: NWEndpoint?, kind: TVKind = .android, port: UInt16? = nil,
         onPaired: @escaping (SavedTV) -> Void, onDone: @escaping (PairingModel) -> Void) {
        self.name = name
        self.kind = kind
        self.port = port
        self.tvID = id
        self.host = host
        self.endpoint = endpoint
        self.onPaired = onPaired
        self.onDone = onDone
    }

    /// O "feito" fica à vista um bocado antes de a folha fechar.
    static let doneShownMs = 700

    private func finished(_ tv: SavedTV) async {
        phase = .done
        onPaired(tv)
        try? await Task.sleep(nanoseconds: UInt64(Self.doneShownMs) * 1_000_000)
        onDone(self)
    }

    func start() {
        task = Task { await run() }
    }

    private func run() async {
        DebugLog.add("Pairing \(name) (\(kind)) started")
        if kind == .apple { return await runApple() }
        var opened: TVConnection?
        do {
            if host == nil, let endpoint { host = await TVFinder.resolve(endpoint) }
            guard let host else { throw RemoteLink.Failure.unreachable(Strings.couldntFindTheTvOnThe) }
            DebugLog.add("Pairing: TV at \(host):\(Pairing.port)")
            let identity = try Identity.load()
            let connection = TVConnection(host: host, port: Pairing.port, identity: identity.identity)
            self.connection = connection
            opened = connection
            try await connection.open()
            DebugLog.add("Pairing: TLS open")
            guard let der = connection.serverCertificate, let server = RSAKey(certificate: der) else {
                throw RemoteLink.Failure.unreachable(Strings.theTvsCertificateIsUnreadable)
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
            await finished(SavedTV(id: tvID, name: name, host: host))
        } catch is CancellationError {
            opened?.close()
        } catch {
            DebugLog.add("Pairing failed: \(error)")
            opened?.close()
            // Um "tentar outra vez" já começou outro: este não mexe no ecrã.
            if !Task.isCancelled { phase = .failed(Self.explain(error)) }
        }
    }

    /// Apple TV: SRP com o PIN, e as credenciais ficam no Keychain.
    private func runApple() async {
        do {
            if host == nil || port == nil, let endpoint, let resolved = await TVFinder.resolveHostPort(endpoint) {
                host = resolved.host
                port = resolved.port
            }
            guard let host, let port else {
                throw RemoteLink.Failure.unreachable(Strings.couldntFindTheTvOnThe)
            }
            DebugLog.add("Pairing: Apple TV at \(host):\(port)\(usingAirPlay ? " (via AirPlay)" : "")")
            let askPIN: () async throws -> String = { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.askCode(retry: false)
            }
            if usingAirPlay {
                let previous = CompanionCredentials.load(tvID)
                let creds = try await AirPlayPairing.pair(host: host, name: UIDevice.current.name, askPIN: askPIN)
                creds.save(tvID)
                // A experiência: a chave do AirPlay serve no Companion (o comando)? Liga-se já para saber.
                phase = .checking
                let link = AppleTVLink(tv: SavedTV(id: tvID, name: name, host: host, kind: .apple, port: port))
                do {
                    try await link.connect()
                    link.close()
                    DebugLog.add("AirPlay pairing: the Apple TV accepts the AirPlay key for the remote")
                } catch {
                    link.close()
                    // Uma tentativa falhada não estraga um emparelhamento que já funcionava.
                    if let previous { previous.save(tvID) } else { CompanionCredentials.delete(tvID) }
                    DebugLog.add("AirPlay pairing: the Apple TV doesn't accept the AirPlay key for the remote: \(error)")
                    throw AirPlayPairing.NotForRemote()
                }
            } else {
                let creds = try await AppleTVPairing.pair(host: host, port: port, name: UIDevice.current.name, askPIN: askPIN)
                creds.save(tvID)
            }
            await finished(SavedTV(id: tvID, name: name, host: host, kind: .apple, port: port))
        } catch is CancellationError {
            DebugLog.add("Pairing cancelled")
            return
        } catch {
            DebugLog.add("Pairing failed: \(error)")
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

    /// "Não aparece o PIN?": emparelhar pelo AirPlay (ver AirPlayPairing).
    func useAirPlay() {
        DebugLog.add("Pairing: switching to AirPlay")
        cancel()
        usingAirPlay = true
        phase = .connecting
        start()
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

    /// O que quer dizer cada recusa da Apple TV (códigos de erro do emparelhamento HomeKit).
    private static func appleRefusal(_ code: Int, _ retryAfter: Int?) -> String {
        switch code {
        case 3:
            let wait = retryAfter.map { $0 >= 90 ? L("\(($0 + 59) / 60) minutes", "\(($0 + 59) / 60) minutos") : L("\($0) seconds", "\($0) segundos") }
                ?? Strings.aFewMinutes
            return L("After several tries, the Apple TV is blocking pairing for a while. Wait \(wait) (or restart the Apple TV) and try again with the Apple TV awake and on screen.",
                     "Depois de várias tentativas, a Apple TV bloqueou o emparelhamento por um bocado. Espera \(wait) (ou reinicia a Apple TV) e tenta outra vez com a Apple TV ligada e no ecrã.")
        case 4:
            return Strings.theAppleTvHasTooMany
        case 5:
            return Strings.tooManyWrongPinsRestartThe
        case 6:
            return Strings.theAppleTvIsntAcceptingNew
        case 7:
            return Strings.theAppleTvIsBusyPairing
        default:
            return L("The Apple TV refused (code \(code)). Try again.", "A Apple TV recusou (código \(code)). Tenta outra vez.")
        }
    }

    private static func explain(_ error: Error) -> String {
        switch error {
        case Pairing.Failure.rejected(let status):
            return L("The TV refused (\(status)). Try again.", "A TV recusou (\(status)). Tenta outra vez.")
        case TVConnection.Failure.closed, CompanionConnection.Failure.closed:
            return Strings.theTvClosedTheConnectionTry
        case AppleTVPairing.Failure.wrongPIN:
            return Strings.wrongPinTryAgainTheTv
        case AppleTVPairing.Failure.refused(let code, let retryAfter):
            return appleRefusal(code, retryAfter)
        case is AirPlayPairing.NotForRemote:
            return Strings.thePinWorkedOverAirplayBut
        case AppleTVPairing.Failure.tv(let why):
            return L("The TV refused: \(why)", "A TV recusou: \(why)")
        case CompanionConnection.Failure.unreachable(let why):
            return why
        default:
            return RemoteModel.describe(error)
        }
    }
}
