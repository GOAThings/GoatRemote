import Foundation
import Network
import SwiftUI
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
    private(set) var status: Status = .noTV {
        didSet { if status != oldValue { DebugLog.add("Status: \(status)" + (current.map { " (\($0.name), \($0.kind))" } ?? "")) } }
    }
    private(set) var state = TVState()
    /// As apps que se viu abertas nesta TV (as mais recentes primeiro), para as abrir com um toque.
    private(set) var recentApps: [String] = []
    /// As apps instaladas na TV, se ela tiver o GoatLauncher (que as dá na rede de casa); vazio sem ele.
    private(set) var installedApps: [TVApp] = []

    /// O emparelhamento em curso (a folha mostra-o).
    var pairing: PairingModel?
    /// A TV abriu uma caixa de texto: mostra-se o teclado.
    var showKeyboard = false
    /// Pede ao comando que feche as folhas abertas (as TVs, as apps, …): o emparelhamento abre por cima de tudo, e
    /// com outra folha aberta o iOS só o mostrava depois de a fechar, já com o código na TV cancelado.
    var closeSheets = 0
    /// Muda quando o volume da TV muda (o indicador aparece um bocado).
    private(set) var volumeChanged = 0

    // Opções (Mais → Opções).
    var haptics: Bool = UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true {
        didSet { UserDefaults.standard.set(haptics, forKey: "haptics") }
    }
    /// Os botões de volume do iPhone mexem no volume da TV (com a app aberta).
    var volumeButtons: Bool = UserDefaults.standard.object(forKey: "volumeButtons") as? Bool ?? true {
        didSet { UserDefaults.standard.set(volumeButtons, forKey: "volumeButtons") }
    }
    /// Touchpad: só deslizar e tocar (como o da Apple TV), ou também tocar nas bordas para as setas.
    var dpadTaps: Bool = UserDefaults.standard.bool(forKey: "dpadTaps") {
        didSet { UserDefaults.standard.set(dpadTaps, forKey: "dpadTaps") }
    }

    @ObservationIgnored private var link: TVControl?
    /// Ícones das apps da Apple TV (da App Store, por bundle id).
    private var appleArtwork: [String: URL] = [:]
    @ObservationIgnored private let lightHaptics = UIImpactFeedbackGenerator(style: .light)
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
        DebugLog.add("Connecting to \(tv.name) (\(tv.kind), \(tv.host)\(tv.port.map { ":\($0)" } ?? ""))")
        status = .connecting
        let link = Self.makeLink(tv)
        link.onState = { [weak self] state in self?.update(state) }
        (link as? AppleTVLink)?.onApps = { [weak self] apps in self?.appleApps(apps, for: tv) }
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
                self.refreshApps()
            } catch let error where Self.isNotPaired(error) {
                DebugLog.add("Connect: not paired (\(error))")
                guard self.link === link else { return }
                self.link = nil
                self.status = .notPaired
            } catch {
                DebugLog.add("Connect failed: \(error)")
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
        let old = state
        state = new
        if new.keyboardRequests > old.keyboardRequests { showKeyboard = true }
        if old.volume != nil, new.volume != old.volume || new.muted != old.muted { volumeChanged += 1 }
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

    /// A ligação certa para o tipo de TV.
    static func makeLink(_ tv: SavedTV) -> TVControl {
        tv.kind == .apple ? AppleTVLink(tv: tv) : RemoteLink(tv: tv)
    }

    static func isNotPaired(_ error: Error) -> Bool {
        if case RemoteLink.Failure.notPaired = error { return true }
        if case AppleTVLink.Failure.notPaired = error { return true }
        return false
    }

    // MARK: Apps da TV (GoatLauncher; na Apple TV, a própria TV)

    /// A lista que a Apple TV dá (sem ícones): os ícones vêm da App Store, pelo bundle id.
    private func appleApps(_ apps: [String: String], for tv: SavedTV) {
        guard current?.id == tv.id else { return }
        installedApps = apps.map { TVApp(package: $0.key, label: $0.value.replacingOccurrences(of: "\u{00A0}", with: " "), banner: false, color: nil) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        for app in installedApps where appleArtwork[app.package] == nil && !app.package.hasPrefix("com.apple.") {
            Task {
                guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(app.package)"),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let first = (json["results"] as? [[String: Any]])?.first,
                      let art = (first["artworkUrl512"] ?? first["artworkUrl100"]) as? String,
                      let artURL = URL(string: art) else { return }
                appleArtwork[app.package] = artURL
            }
        }
    }

    /// Abre uma app da lista (Android: pelo pacote; Apple TV: pelo bundle id).
    func launch(_ app: TVApp) {
        open(current?.kind == .apple ? app.package : app.link)
    }

    /// Pede a lista de apps ao GoatLauncher da TV (porta 6470). Sem ele, fica vazia e usam-se as apps vistas.
    func refreshApps() {
        guard current?.kind != .apple else { return }
        guard let tv = current, let url = URL(string: "http://\(tv.host):\(Self.launcherPort)/apps") else { return }
        Task {
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let apps = try? JSONDecoder().decode([TVApp].self, from: data) else { return }
            Self.setLauncher(tv.id, true)
            guard current?.id == tv.id else { return }
            installedApps = apps
        }
    }

    /// O banner (ou ícone) de uma app, dado pelo GoatLauncher (ou, na Apple TV, o da App Store).
    func iconURL(_ package: String) -> URL? {
        guard let tv = current else { return nil }
        if tv.kind == .apple { return appleArtwork[package] }
        return URL(string: "http://\(tv.host):\(Self.launcherPort)/icon/\(package)")
    }

    static let launcherPort = 6470

    // MARK: TVs

    func select(_ tv: SavedTV) {
        guard tv.id != current?.id else { return }
        link?.close()
        link = nil
        current = tv
        TVStore.currentID = tv.id
        state = TVState()
        recentApps = Self.loadRecents(tv.id)
        installedApps = []
        connect()
    }

    func forget(_ tv: SavedTV) {
        if tv.kind == .apple { CompanionCredentials.delete(tv.id) }
        TVStore.remove(tv.id)
        tvs = TVStore.all
        if current?.id == tv.id {
            link?.close()
            link = nil
            current = TVStore.current
            state = TVState()
            recentApps = Self.loadRecents(current?.id)
            installedApps = []
            status = current == nil ? .noTV : .connecting
            connect()
        }
    }

    /// A Apple TV (protocolo Companion) já emparelha.
    static let appleTVReady = true

    /// Emparelhar uma TV encontrada na rede.
    func startPairing(_ found: FoundTV) {
        startPairing(name: found.name, id: found.id, host: nil, endpoint: found.endpoint, kind: found.kind)
    }

    /// Emparelhar uma TV encontrada na rede ou escrita à mão (IP).
    func startPairing(name: String, id: String, host: String?, endpoint: NWEndpoint?, kind: TVKind = .android, port: UInt16? = nil) {
        pairing?.cancel()
        pairing = nil
        let model = PairingModel(name: name, id: id, host: host, endpoint: endpoint, kind: kind, port: port) { [weak self] tv in
            self?.paired(tv)
        }
        // Sem TVs, o ecrã de juntar é o principal e não há folhas por cima.
        guard !tvs.isEmpty else {
            pairing = model
            return model.start()
        }
        closeSheets += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            self?.pairing = model
            model.start()
        }
    }

    /// Emparelhar outra vez a TV escolhida (a TV esqueceu este iPhone).
    func repairCurrent() {
        guard let tv = current else { return }
        startPairing(name: tv.name, id: tv.id, host: tv.host, endpoint: nil, kind: tv.kind, port: tv.port)
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
        installedApps = []
        status = .connecting
        connect()
    }

    // MARK: Comando

    func press(_ key: Key) {
        if haptics { lightHaptics.impactOccurred() }
        guard let link, status == .connected else { return reconnectIfNeeded() }
        if noVolume(key) || volumeViaLauncher(key) { return }
        link.key(key)
    }

    /// Se a TV tem o GoatLauncher (fica guardado por TV: nil enquanto não se sabe). Com ele, ou sem se saber, o
    /// volume nunca vai como tecla: as teclas de volume do protocolo rebentam o Android 11 da SHIELD quando o
    /// GoatLauncher vê as teclas (botões a abrir apps). Só se manda tecla quando se tem a certeza de que não há
    /// launcher (404, ou ligação recusada na porta dele).
    static func hasLauncher(_ tvID: String) -> Bool? {
        UserDefaults.standard.object(forKey: "launcher.\(tvID)") as? Bool
    }

    static func setLauncher(_ tvID: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: "launcher.\(tvID)")
    }

    /// Mostrado no indicador de volume quando o launcher não respondeu (nil: nada a dizer).
    private(set) var volumeProblem: String?

    /// O volume pelo GoatLauncher (POST /volume/…) em vez de tecla; false se esta TV não tem launcher (tecla).
    private func volumeViaLauncher(_ key: Key) -> Bool {
        let what: String
        switch key {
        case .volumeUp: what = "up"
        case .volumeDown: what = "down"
        case .mute: what = "mute"
        default: return false
        }
        guard let tv = current, tv.kind == .android, Self.hasLauncher(tv.id) != false,
              let url = URL(string: "http://\(tv.host):\(Self.launcherPort)/volume/\(what)") else { return false }
        Task {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 3
            var status = 0
            var refused = false
            do {
                status = ((try await URLSession.shared.data(for: request)).1 as? HTTPURLResponse)?.statusCode ?? 0
            } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
                refused = true
            } catch {
                DebugLog.add("Volume via launcher failed: \(error)")
            }
            if status == 200 {
                Self.setLauncher(tv.id, true)
                volumeProblem = nil
            } else if status == 404 || refused {
                // Não há launcher nesta TV: a tecla é segura.
                DebugLog.add("Volume: no launcher on \(tv.name) (\(refused ? "refused" : "404")), using keys")
                Self.setLauncher(tv.id, false)
                if current?.id == tv.id { link?.key(key) }
            } else if current?.id == tv.id {
                // Pode haver launcher e ele não respondeu (TV ocupada): nunca a tecla, que podia reiniciar a TV.
                DebugLog.add("Volume: launcher on \(tv.name) didn't answer (HTTP \(status)), not sending the key")
                volumeProblem = L("The TV's launcher didn't answer. Try again", "O launcher da TV não respondeu. Tenta outra vez")
                volumeChanged += 1
            }
        }
        return true
    }

    /// Volume numa TV que não o controla: em vez de não fazer nada, o indicador explica porquê.
    private func noVolume(_ key: Key) -> Bool {
        guard [.volumeUp, .volumeDown, .mute].contains(key), !state.volumeControl else { return false }
        volumeChanged += 1
        return true
    }

    /// Carregar e manter: início e fim.
    func hold(_ key: Key, down: Bool) {
        if down, haptics { heavyHaptics.impactOccurred() }
        guard let link, status == .connected else { return reconnectIfNeeded() }
        if down, noVolume(key) { return }
        if [.volumeUp, .volumeDown, .mute].contains(key), let tv = current, tv.kind == .android, Self.hasLauncher(tv.id) != false {
            // Pelo GoatLauncher não há "manter": cada toque é um passo.
            if down { _ = volumeViaLauncher(key) }
            return
        }
        link.key(key, down ? .startLong : .endLong)
    }

    func type(_ text: String) {
        guard let link, status == .connected else { return }
        link.text(text)
    }

    func open(_ link: String) {
        if haptics { lightHaptics.impactOccurred() }
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
    @ObservationIgnored private var codeContinuation: CheckedContinuation<String, Error>?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var connection: TVConnection?

    init(name: String, id: String, host: String?, endpoint: NWEndpoint?, kind: TVKind = .android, port: UInt16? = nil,
         onPaired: @escaping (SavedTV) -> Void) {
        self.name = name
        self.kind = kind
        self.port = port
        self.tvID = id
        self.host = host
        self.endpoint = endpoint
        self.onPaired = onPaired
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
            guard let host else { throw RemoteLink.Failure.unreachable(L("Couldn't find the TV on the network", "Não deu para encontrar a TV na rede")) }
            DebugLog.add("Pairing: TV at \(host):\(Pairing.port)")
            let identity = try Identity.load()
            let connection = TVConnection(host: host, port: Pairing.port, identity: identity.identity)
            self.connection = connection
            opened = connection
            try await connection.open()
            DebugLog.add("Pairing: TLS open")
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
                throw RemoteLink.Failure.unreachable(L("Couldn't find the TV on the network", "Não deu para encontrar a TV na rede"))
            }
            DebugLog.add("Pairing: Apple TV at \(host):\(port)\(usingAirPlay ? " (via AirPlay)" : "")")
            let askPIN: () async throws -> String = { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.askCode(retry: false)
            }
            if usingAirPlay {
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
                    CompanionCredentials.delete(tvID)
                    DebugLog.add("AirPlay pairing: the Apple TV doesn't accept the AirPlay key for the remote: \(error)")
                    throw AirPlayPairing.NotForRemote()
                }
            } else {
                let creds = try await AppleTVPairing.pair(host: host, port: port, name: UIDevice.current.name, askPIN: askPIN)
                creds.save(tvID)
            }
            phase = .done
            onPaired(SavedTV(id: tvID, name: name, host: host, kind: .apple, port: port))
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
                ?? L("a few minutes", "uns minutos")
            return L("After several tries, the Apple TV is blocking pairing for a while. Wait \(wait) (or restart the Apple TV) and try again with the Apple TV awake and on screen.",
                     "Depois de várias tentativas, a Apple TV bloqueou o emparelhamento por um bocado. Espera \(wait) (ou reinicia a Apple TV) e tenta outra vez com a Apple TV ligada e no ecrã.")
        case 4:
            return L("The Apple TV has too many paired devices. Remove one in Settings → Remotes and Devices → Remote App and Devices.",
                     "A Apple TV tem demasiados aparelhos emparelhados. Remove um em Definições → Comandos e dispositivos → App Remote e dispositivos.")
        case 5:
            return L("Too many wrong PINs. Restart the Apple TV and try again.", "Demasiados PINs errados. Reinicia a Apple TV e tenta outra vez.")
        case 6:
            return L("The Apple TV isn't accepting new devices. On the Apple TV, set Settings → AirPlay and HomeKit → Allow Access to “Everyone on the Same Network” and try again.",
                     "A Apple TV não está a aceitar aparelhos novos. Na Apple TV, põe Definições → AirPlay e HomeKit → Permitir acesso em “Todos na mesma rede” e tenta outra vez.")
        case 7:
            return L("The Apple TV is busy pairing with another device. Try again in a moment.", "A Apple TV está a emparelhar com outro aparelho. Tenta outra vez daqui a pouco.")
        default:
            return L("The Apple TV refused (code \(code)). Try again.", "A Apple TV recusou (código \(code)). Tenta outra vez.")
        }
    }

    private static func explain(_ error: Error) -> String {
        switch error {
        case Pairing.Failure.rejected(let status):
            return L("The TV refused (\(status)). Try again.", "A TV recusou (\(status)). Tenta outra vez.")
        case TVConnection.Failure.closed, CompanionConnection.Failure.closed:
            return L("The TV closed the connection. Try again.", "A TV fechou a ligação. Tenta outra vez.")
        case AppleTVPairing.Failure.wrongPIN:
            return L("Wrong PIN. Try again: the TV will show a new one.", "PIN errado. Tenta outra vez: a TV mostra um novo.")
        case AppleTVPairing.Failure.refused(let code, let retryAfter):
            return appleRefusal(code, retryAfter)
        case is AirPlayPairing.NotForRemote:
            return L("The PIN worked over AirPlay, but this Apple TV doesn't accept it for the remote. Send a report so we can look into it.",
                     "O PIN funcionou pelo AirPlay, mas esta Apple TV não o aceita para o comando. Envia um relatório para vermos.")
        case AppleTVPairing.Failure.tv(let why):
            return L("The TV refused: \(why)", "A TV recusou: \(why)")
        case CompanionConnection.Failure.unreachable(let why):
            return why
        default:
            return RemoteModel.describe(error)
        }
    }
}

/// Uma app instalada na TV, como o GoatLauncher a dá.
struct TVApp: Decodable, Identifiable, Hashable {
    let package: String
    let label: String
    /// Tem banner de TV (16:9); senão é um ícone sobre a [color].
    let banner: Bool
    let color: String?

    var id: String { package }
    var link: String { "market://launch?id=\(package)" }

    var tint: Color {
        guard let color, color.hasPrefix("#"), let value = UInt32(color.dropFirst(), radix: 16) else { return Theme.surfaceHigh }
        return Color(hex: value)
    }
}
