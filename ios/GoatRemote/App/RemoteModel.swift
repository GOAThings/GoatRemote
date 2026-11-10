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

    /// A TV tem o GoatTV com os canais para o telemóvel (já respondeu a /channels): mostra-se o botão Canais.
    private(set) var hasChannels = false
    /// A lista de canais do GoatTV (nil enquanto não veio, ou com o GoatTV fechado).
    private(set) var channels: ChannelList?
    private(set) var channelsStatus: ChannelsStatus = .unknown
    /// A abrir o GoatTV na TV, à espera de que dê os canais.
    private(set) var openingGoatTV = false
    /// Porque é que o último canal não mudou (nil: nada a dizer).
    private(set) var playProblem: String?
    /// O programa do canal que o GoatTV está a dar (nil sem guia, ou num GoatTV antigo, sem o /now).
    private(set) var nowInfo: NowInfo?
    /// TVs cujo GoatTV não tem o /now (responde 404): até voltar a ligar, não se pergunta.
    @ObservationIgnored private var withoutNow = Set<String>()

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
    var haptics: Bool = UserDefaults.standard.object(forKey: StoreKeys.haptics) as? Bool ?? true {
        didSet { UserDefaults.standard.set(haptics, forKey: StoreKeys.haptics) }
    }
    /// Os botões de volume do iPhone mexem no volume da TV (com a app aberta).
    var volumeButtons: Bool = UserDefaults.standard.object(forKey: StoreKeys.volumeButtons) as? Bool ?? true {
        didSet { UserDefaults.standard.set(volumeButtons, forKey: StoreKeys.volumeButtons) }
    }
    /// Superfície de toque ou setas (D-pad). Quem tinha as "setas nas bordas" ligadas começa nas setas.
    var layout: RemoteLayout = RemoteLayout.saved(UserDefaults.standard.string(forKey: StoreKeys.layout),
                                                  dpadTaps: UserDefaults.standard.bool(forKey: StoreKeys.dpadTaps)) {
        didSet {
            UserDefaults.standard.set(layout.rawValue, forKey: StoreKeys.layout)
            UserDefaults.standard.removeObject(forKey: StoreKeys.dpadTaps)
        }
    }

    @ObservationIgnored private var link: TVControl? {
        didSet {
            // A ligação mudou: o teclado fecha-se e o que lá estava escrito não passa para a próxima.
            guard link !== oldValue else { return }
            showKeyboard = false
            state.textValue = ""
            state.textLabel = nil
            state.keyboardRequests = 0
        }
    }
    @ObservationIgnored private var autoReconnect: Task<Void, Never>?
    @ObservationIgnored private var lastAutoReconnect = Date.distantPast
    /// Recusas seguidas desta TV que ainda não se mostraram (ver connect()).
    @ObservationIgnored private var notPairedRetries = 0
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
        hasChannels = Self.hasGoatTV(current?.id)
        watchNow()
    }

    // MARK: Ligação

    /// Liga à TV escolhida. Uma falha que não seja "não emparelhado" tenta mais uma vez daí a 1,5 s: a SHIELD, por
    /// exemplo, recusa a primeira ligação logo a seguir a emparelhar.
    func connect(retry: Bool = true) {
        guard let tv = current else {
            status = .noTV
            return
        }
        if link != nil, status == .connected || status == .connecting { return }
        autoReconnect?.cancel()
        link?.close()
        DebugLog.add("Connecting to \(tv.name) (\(tv.kind), \(tv.host)\(tv.port.map { ":\($0)" } ?? ""))")
        status = .connecting
        let link = Self.makeLink(tv)
        // Só a ligação atual conta: uma antiga que ainda fale não mexe no estado da TV escolhida agora.
        link.onState = { [weak self, weak link] state in
            guard let self, let link, self.link === link else { return }
            self.update(state)
        }
        (link as? AppleTVLink)?.onApps = { [weak self] apps in self?.appleApps(apps, for: tv) }
        link.onClose = { [weak self, weak link] in
            guard let self, let link, self.link === link else { return }
            self.link = nil
            // Liga outra vez sem incomodar; se voltar a fechar logo a seguir, aí sim mostra-se o aviso.
            if tv.kind == .android, Date().timeIntervalSince(self.lastAutoReconnect) > 10 {
                self.lastAutoReconnect = Date()
                DebugLog.add("Reconnecting to \(tv.name)")
                self.status = .connecting
                self.autoReconnect = Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled, self.link == nil, self.current?.id == tv.id else { return }
                    self.connect()
                }
                return
            }
            self.status = .unreachable(L("The TV closed the connection", "A TV fechou a ligação"))
        }
        self.link = link
        Task {
            do {
                try await link.connect()
                guard self.link === link else { return }
                self.notPairedRetries = 0
                self.status = .connected
                self.withoutNow.remove(tv.id)
                self.update(link.state)
                self.refreshApps()
                self.refreshChannels()
            } catch let error where Self.isNotPaired(error) {
                DebugLog.add("Connect: not paired (\(error))")
                guard self.link === link else { return }
                self.link = nil
                // A TV às vezes recusa uma ligação de um iPhone que conhece: a SHIELD, logo a seguir a mudar de canal,
                // fecha a ligação e recusa as seguintes durante uns segundos. Só se pede para emparelhar se ainda
                // recusar passados uns 12 s (três tentativas).
                if self.notPairedRetries < 3 {
                    self.notPairedRetries += 1
                    let attempt = self.notPairedRetries
                    DebugLog.add("Not paired: trying again (\(attempt))")
                    self.autoReconnect = Task {
                        try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                        guard !Task.isCancelled, self.link == nil, self.current?.id == tv.id else { return }
                        self.connect()
                    }
                    return
                }
                self.notPairedRetries = 0
                self.status = .notPaired
            } catch {
                DebugLog.add("Connect failed\(retry ? " (will retry)" : ""): \(error)")
                guard self.link === link else { return }
                self.link = nil
                link.close()
                guard retry else {
                    self.status = .unreachable(Self.describe(error))
                    return
                }
                self.autoReconnect = Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled, self.link == nil, self.current?.id == tv.id else { return }
                    self.connect(retry: false)
                }
            }
        }
    }

    func disconnect() {
        autoReconnect?.cancel()
        link?.close()
        link = nil
        if current != nil { status = .connecting }
    }

    func reconnect() {
        link?.close()
        link = nil
        connect()
    }

    private var volumeSettlesAt = Date.distantPast

    private func update(_ new: TVState) {
        let old = state
        state = new
        if new.keyboardRequests > old.keyboardRequests { showKeyboard = true }
        // Ao ligar, a TV manda vários valores seguidos (na SHIELD, com HDMI-CEC, acaba em 0): isso não é mudar o volume.
        if old.volume == nil, new.volume != nil { volumeSettlesAt = Date().addingTimeInterval(5) }
        if old.volume != nil, new.volume != old.volume || new.muted != old.muted, !volumeUnknown, Date() >= volumeSettlesAt { volumeChanged += 1 }
        // O GoatTV veio para a frente: o canal que está a dar pode ter mudado.
        if new.currentApp == GoatTVChannels.androidPackage, old.currentApp != new.currentApp, hasChannels { refreshChannels() }
        if let app = new.currentApp, !AppCatalog.isLauncher(app) {
            recentApps.removeAll { $0 == app }
            recentApps.insert(app, at: 0)
            recentApps = Array(recentApps.prefix(12))
            if let id = current?.id { UserDefaults.standard.set(recentApps, forKey: StoreKeys.perTV(StoreKeys.recents, id)) }
        }
    }

    private static func loadRecents(_ id: String?) -> [String] {
        guard let id else { return [] }
        let saved = UserDefaults.standard.stringArray(forKey: StoreKeys.perTV(StoreKeys.recents, id)) ?? []
        // O que não for um nome de pacote não volta a ler-se.
        var seen = Set<String>()
        let recents = Array(saved.filter { RemoteProtocol.isPackageName($0) && seen.insert($0).inserted }.prefix(12))
        if recents != saved { UserDefaults.standard.set(recents, forKey: StoreKeys.perTV(StoreKeys.recents, id)) }
        return recents
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
    static func makeLink(_ tv: SavedTV) -> TVControl { makeTVLink(tv) }

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
                guard let artURL = await AppStoreArtwork.lookup(app.package) else { return }
                appleArtwork[app.package] = artURL
            }
        }
    }

    /// Abre uma app da lista (Android: pelo pacote; Apple TV: pelo bundle id).
    func launch(_ app: TVApp, haptic: Bool = true) {
        guard let tv = current, tv.kind == .android, Self.hasLauncher(tv.id) != false,
              LanHttp.url(tv.host, LauncherApps.port, "open/\(app.package)") != nil else {
            return open(current?.kind == .apple ? app.package : app.link, haptic: haptic)
        }
        // Pelo GoatLauncher: a SHIELD recusa o link do comando e fecha a ligação.
        if haptic, haptics { lightHaptics.impactOccurred() }
        DebugLog.add("Open app via launcher: \(app.package)")
        Task {
            let status = await LauncherApi(host: tv.host).open(app.package) ?? 0
            if !LauncherApps.openFallsBack(status: status) { return }
            DebugLog.add("Launcher didn't open it (HTTP \(status)), using the remote's link")
            if current?.id == tv.id { open(app.link, haptic: false) }
        }
    }

    /// Pede a lista de apps ao GoatLauncher da TV (porta 6470). Sem ele, fica vazia e usam-se as apps vistas.
    func refreshApps() {
        guard current?.kind != .apple else { return }
        guard let tv = current, LanHttp.url(tv.host, LauncherApps.port, "apps") != nil else { return }
        Task {
            guard let apps = await LauncherApi(host: tv.host).apps() else { return }
            Self.setLauncher(tv.id, true)
            guard current?.id == tv.id else { return }
            installedApps = apps
        }
    }

    /// O banner (ou ícone) de uma app, dado pelo GoatLauncher (ou, na Apple TV, o da App Store).
    func iconURL(_ package: String) -> URL? {
        guard let tv = current else { return nil }
        if tv.kind == .apple { return appleArtwork[package] }
        return LauncherApi(host: tv.host).iconURL(package)
    }

    // MARK: Canais do GoatTV (porta 6471)

    enum ChannelsStatus: Equatable {
        case unknown
        case ready
        /// Ligação recusada ou 503: o GoatTV não está aberto (ou ainda não carregou a lista).
        case closed
        case failed
    }

    /// O pedido da lista em curso, e de que TV: trocar de TV substitui-o em vez de esperar por ele.
    @ObservationIgnored private var channelsTask: (tv: String, id: UUID, task: Task<Void, Never>)?
    @ObservationIgnored private var playTask: Task<Void, Never>?

    private static func hasGoatTV(_ tvID: String?) -> Bool {
        tvID.map { UserDefaults.standard.bool(forKey: StoreKeys.perTV(StoreKeys.goatTV, $0)) } ?? false
    }

    /// Pede a lista ao GoatTV da TV. Ao ligar e ao abrir a folha.
    func refreshChannels() {
        guard let tv = current else { return }
        if let running = channelsTask, running.tv == tv.id { return }
        channelsTask?.task.cancel()
        let id = UUID()
        let task = Task {
            await loadChannels(tv)
            if channelsTask?.id == id { channelsTask = nil }
        }
        channelsTask = (tv.id, id, task)
    }

    /// true se veio a lista.
    @discardableResult
    private func loadChannels(_ tv: SavedTV) async -> Bool {
        guard let fetched = await GoatTvApi(host: tv.host).channels() else { return false }
        if let error = fetched.error { DebugLog.add("Channels: \(error)") }
        let list = fetched.value
        var outcome = ChannelsStatus.failed
        if list != nil {
            outcome = .ready
        } else if fetched.refused || fetched.status == 503 {
            outcome = .closed
        }
        guard current?.id == tv.id else { return false }
        switch outcome {
        case .ready:
            if let list {
                if !hasChannels { DebugLog.add("GoatTV channels on \(tv.name): \(list.channels.count)") }
                channels = list
            }
            channelsStatus = .ready
            hasChannels = true
            UserDefaults.standard.set(true, forKey: StoreKeys.perTV(StoreKeys.goatTV, tv.id))
        case .closed:
            channels = nil
            channelsStatus = .closed
        case .failed, .unknown:
            // Outra resposta (ou nenhuma): fica a lista que já havia.
            if channels == nil { channelsStatus = .failed }
        }
        return outcome == .ready
    }

    /// Pergunta ao GoatTV o que está a dar (GET /now, pequeno). Se o canal mudou (pelo comando da TV, por exemplo), o
    /// cartão muda; um canal que a lista não tem pede a lista outra vez. Fechado (Apple TV em segundo plano), o cartão sai.
    private func pollNow(_ tv: SavedTV) async {
        guard !withoutNow.contains(tv.id), let fetched = await GoatTvApi(host: tv.host).now() else { return }
        let info = fetched.value
        let status = fetched.status
        let refused = fetched.refused
        guard current?.id == tv.id else { return }
        if let info {
            nowInfo = info
            guard let list = channels, info.current != list.current else { return }
            if info.current == nil || list.channels.contains(where: { $0.key == info.current }) {
                channels?.current = info.current
            } else {
                refreshChannels()
            }
        } else if status == 404 {
            DebugLog.add("GoatTV on \(tv.name) has no /now")
            withoutNow.insert(tv.id)
        } else if refused || status == 503 {
            channels = nil
            channelsStatus = .closed
            nowInfo = nil
        }
    }

    /// Com o GoatTV à frente e a lista dele, a cada 3 s: o canal pode mudar pelo comando da TV.
    private func watchNow() {
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self else { return }
                guard let tv = current, status == .connected, channels != nil,
                      tv.kind == .apple || state.currentApp == GoatTVChannels.androidPackage else { continue }
                await pollNow(tv)
            }
        }
    }

    /// Como abrir o GoatTV nesta TV: na Android TV pelo GoatLauncher (só se se sabe que o tem); na Apple TV pela
    /// própria ligação, se ele estiver na lista de apps dela. nil: só se pode pedir para o abrirem na TV.
    var goatTVApp: TVApp? {
        guard let tv = current else { return nil }
        switch tv.kind {
        case .android:
            return Self.hasLauncher(tv.id) == true ? Self.androidGoatTV : nil
        case .apple:
            let apps = Dictionary(installedApps.map { ($0.package, $0.label) }, uniquingKeysWith: { a, _ in a })
            return GoatTVChannels.appleApp(apps).map { TVApp(package: $0, label: "GoatTV", banner: false, color: nil) }
        }
    }

    private static let androidGoatTV = TVApp(package: GoatTVChannels.androidPackage, label: "GoatTV", banner: false, color: nil)

    /// O canal que o GoatTV está a dar, se ele estiver à frente (na Android TV pela app aberta; a Apple TV não diz qual
    /// é, por isso vale a última lista que veio).
    var nowPlaying: TVChannel? {
        guard let list = channels else { return nil }
        if current?.kind == .android, state.currentApp != GoatTVChannels.androidPackage { return nil }
        return list.channels.first { $0.key == list.current }
    }

    /// Canal seguinte ou anterior, no grupo do que está a dar (como o zapping na TV).
    func zap(_ delta: Int) {
        guard let list = channels, let now = nowPlaying else { return }
        let inGroup = list.channels.filter { $0.group == now.group }
        let group = inGroup.isEmpty ? list.channels : inGroup
        guard let i = group.firstIndex(where: { $0.key == now.key }) else { return }
        let n = group.count
        play(group[((i + delta) % n + n) % n])
    }

    var goatTVClosedLine: String { L("GoatTV has to be open on the TV", "O GoatTV tem de estar aberto na TV") }

    /// "Abrir o GoatTV" na folha dos canais: abre-o e espera (até 10 s) que dê a lista.
    func openGoatTV() {
        guard let tv = current, let app = goatTVApp else { return }
        DebugLog.add("Opening GoatTV for the channels")
        launch(app)
        openingGoatTV = true
        Task {
            defer { if current?.id == tv.id { openingGoatTV = false } }
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard current?.id == tv.id else { return }
                if await loadChannels(tv) { return }
            }
        }
    }

    func channelLogoURL(_ channel: TVChannel) -> URL? {
        guard let tv = current, channel.logo else { return nil }
        return GoatTvApi(host: tv.host).logoURL(channel.key)
    }

    /// Muda de canal no GoatTV. Se ele não estiver à frente (409, 503 ou ligação recusada), abre-se e tenta-se outra
    /// vez a cada segundo, até 10 s. Um toque novo cancela o anterior (para fazer zapping).
    func play(_ channel: TVChannel) {
        guard let tv = current else { return }
        if haptics { lightHaptics.impactOccurred() }
        playProblem = nil
        let number = channel.num.map { String($0) } ?? "-"
        DebugLog.add("Play channel \(number) via GoatTV")
        playTask?.cancel()
        playTask = Task {
            var deadline: Date?
            while !Task.isCancelled {
                let (status, refused) = await Self.postPlay(tv, channel.key)
                guard !Task.isCancelled, current?.id == tv.id else { return }
                switch GoatTVChannels.playOutcome(status: status, refused: refused) {
                case .done:
                    channels?.current = channel.key
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    await pollNow(tv)
                    return
                case .notFound:
                    playProblem = L("This channel isn't available on the TV", "Este canal não está disponível na TV")
                    refreshChannels()
                    return
                case .failed:
                    DebugLog.add("Play: GoatTV answered HTTP \(status)")
                    playProblem = L("GoatTV didn't answer. Try again", "O GoatTV não respondeu. Tenta outra vez")
                    return
                case .retry:
                    if let deadline {
                        if Date() >= deadline {
                            playProblem = L("GoatTV didn't switch channels. Check the TV and try again",
                                            "O GoatTV não mudou de canal. Vê a TV e tenta outra vez")
                            return
                        }
                    } else if tv.kind == .android, state.currentApp == GoatTVChannels.androidPackage {
                        // Já está à frente, só ainda não pode (a meio de mudar de canal): abri-lo outra vez não ajuda,
                        // e o link pelo comando faz a SHIELD fechar a ligação.
                        DebugLog.add("Play: GoatTV is in front but answered \(refused ? "refused" : "HTTP \(status)"), waiting")
                        deadline = Date().addingTimeInterval(10)
                    } else {
                        guard let app = goatTVApp ?? (tv.kind == .android ? Self.androidGoatTV : nil) else {
                            playProblem = goatTVClosedLine
                            return
                        }
                        DebugLog.add("Play: GoatTV isn't in front (\(refused ? "refused" : "HTTP \(status)")), opening it")
                        launch(app, haptic: false)
                        deadline = Date().addingTimeInterval(10)
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    /// POST /play/<key> no GoatTV da TV: o estado HTTP e se a ligação foi recusada.
    static func postPlay(_ tv: SavedTV, _ key: String) async -> (status: Int, refused: Bool) {
        await GoatTvApi(host: tv.host).play(key)
    }

    /// O que é de uma TV (canais, volume, tentativas) volta ao início: outra TV, esta emparelhada outra vez, ou esquecida.
    private func resetChannels(_ tv: SavedTV?) {
        // O indicador do volume (e o ícone do HDMI-CEC), as tentativas e o que estava a dar eram da TV anterior.
        volumePressed = nil
        volumeProblem = nil
        volumeSettlesAt = .distantPast
        notPairedRetries = 0
        autoReconnect?.cancel()
        nowInfo = nil
        channelsTask?.task.cancel()
        channelsTask = nil
        playTask?.cancel()
        hasChannels = Self.hasGoatTV(tv?.id)
        channels = nil
        channelsStatus = .unknown
        openingGoatTV = false
        playProblem = nil
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
        installedApps = []
        resetChannels(tv)
        connect()
    }

    func forget(_ tv: SavedTV) {
        if tv.kind == .apple { CompanionCredentials.delete(tv.id) }
        TVStore.remove(tv.id)
        for key in StoreKeys.perTVKeys(tv.id) { UserDefaults.standard.removeObject(forKey: key) }
        tvs = TVStore.all
        if current?.id == tv.id {
            link?.close()
            link = nil
            current = TVStore.current
            state = TVState()
            recentApps = Self.loadRecents(current?.id)
            installedApps = []
            resetChannels(current)
            status = current == nil ? .noTV : .connecting
            connect()
        }
    }

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

    /// Quando se viu cada TV guardada na procura (para não perguntar o endereço a cada mudança da lista).
    @ObservationIgnored private var relocated: [String: Date] = [:]

    /// A procura encontrou TVs guardadas: se alguma mudou de IP (ou de porta, na Apple TV), o endereço guardado muda,
    /// para voltar a ligar e para "Emparelhar esta TV outra vez" irem ao sítio certo. Conta o id com que se guardou
    /// (o nome com que se anuncia), o mesmo que marca "Emparelhada".
    func relocate(_ found: [FoundTV]) {
        for tv in found {
            guard tvs.contains(where: { $0.id == tv.id }),
                  Date().timeIntervalSince(relocated[tv.id] ?? .distantPast) > 60 else { continue }
            relocated[tv.id] = Date()
            Task {
                guard let resolved = await TVFinder.resolveHostPort(tv.endpoint),
                      let saved = TVStore.all.first(where: { $0.id == tv.id }),
                      let moved = SavedTV.moved(saved, host: resolved.host, port: resolved.port) else { return }
                DebugLog.add("\(saved.name) moved to \(moved.host)\(moved.port.map { ":\($0)" } ?? "")")
                TVStore.save(moved)
                tvs = TVStore.all
                guard current?.id == moved.id else { return }
                current = moved
                if case .unreachable = status { connect() }
            }
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
        resetChannels(tv)
        status = .connecting
        connect()
    }

    // MARK: Comando

    /// [haptic] false nas repetições de uma tecla mantida: vibrava a cada passo, mais do que a TV avançava.
    func press(_ key: Key, haptic: Bool = true) {
        if haptic, haptics { lightHaptics.impactOccurred() }
        guard let link, status == .connected else { return reconnectIfNeeded() }
        if noVolume(key) || volumeViaLauncher(key) { return }
        link.key(key)
    }

    /// Se a TV tem o GoatLauncher (fica guardado por TV: nil enquanto não se sabe). Com ele, ou sem se saber, o
    /// volume nunca vai como tecla: as teclas de volume do protocolo rebentam o Android 11 da SHIELD quando o
    /// GoatLauncher vê as teclas (botões a abrir apps). Só se manda tecla quando se tem a certeza de que não há
    /// launcher: 404, ou ligação recusada na porta dele, numa TV onde nunca se viu nenhum. Onde já se viu, isso é só não
    /// ter respondido; esquecer a TV limpa o que se sabe, se o launcher saiu mesmo de lá.
    static func hasLauncher(_ tvID: String) -> Bool? { LauncherMemory.known(tvID) }

    static func setLauncher(_ tvID: String, _ value: Bool) { LauncherMemory.set(tvID, value) }

    /// Com HDMI-CEC, o volume está na TV e a box não sabe o valor: o que reporta não diz nada. Descobre-se ao
    /// carregar: o launcher mudou o volume e o valor não mexeu. Fica guardado por TV.
    private var volumeUnknown: Bool {
        current.map { UserDefaults.standard.bool(forKey: StoreKeys.perTV(StoreKeys.volumeUnknown, $0.id)) } ?? false
    }

    /// A última tecla, para o indicador numa TV sem valor de volume (nil: mostra-se a barra).
    private(set) var volumePressed: Key?

    /// Mostrado no indicador de volume quando o launcher não respondeu (nil: nada a dizer).
    private(set) var volumeProblem: String?

    /// O volume pelo GoatLauncher (POST /volume/…) em vez de tecla; false se esta TV não tem launcher (tecla).
    private func volumeViaLauncher(_ key: Key) -> Bool {
        guard let what = LauncherVolume.path(key), let tv = current, tv.kind == .android, Self.hasLauncher(tv.id) != false else { return false }
        let before = (state.volume, state.muted)
        Task {
            let (status, refused) = await LauncherApi(host: tv.host).volume(what)
            switch LauncherVolume.outcome(known: Self.hasLauncher(tv.id), status: status, refused: refused) {
            case .done:
                Self.setLauncher(tv.id, true)
                volumeProblem = nil
                try? await Task.sleep(for: .milliseconds(800))
                guard current?.id == tv.id else { return }
                let unknown = state.volume == before.0 && state.muted == before.1
                UserDefaults.standard.set(unknown, forKey: StoreKeys.perTV(StoreKeys.volumeUnknown, tv.id))
                volumePressed = unknown ? key : nil
                if unknown { volumeChanged += 1 }
            case .noLauncher:
                DebugLog.add("Volume: no launcher on \(tv.name) (\(refused ? "refused" : "404")), using keys")
                Self.setLauncher(tv.id, false)
                if current?.id == tv.id { link?.key(key) }
            case .didntAnswer:
                guard current?.id == tv.id else { return }
                DebugLog.add("Volume: launcher on \(tv.name) didn't answer (HTTP \(status)), not sending the key")
                if status == 404 {
                    volumeProblem = L("Update GoatLauncher on the TV to change the volume from here", "Atualiza o GoatLauncher na TV para mudares o volume daqui")
                } else if refused {
                    volumeProblem = L("GoatLauncher isn't running on the TV. Open it. If you removed it, forget this TV and pair it again",
                                      "O GoatLauncher não está a correr na TV. Abre-o. Se o tiraste, esquece esta TV e emparelha-a outra vez")
                } else {
                    volumeProblem = L("The TV's launcher didn't answer. Try again", "O launcher da TV não respondeu. Tenta outra vez")
                }
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
        if down { repeatStarted() }
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

    func open(_ link: String, haptic: Bool = true) {
        if haptic, haptics { lightHaptics.impactOccurred() }
        guard let remote = self.link, status == .connected else { return reconnectIfNeeded() }
        DebugLog.add("Open app: \(link)")
        remote.openApp(link)
    }

    /// Começou a manter uma tecla (o OK longo, ou uma seta a repetir): uma vibração forte, só esta.
    func repeatStarted() {
        if haptics { heavyHaptics.impactOccurred() }
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

extension TVApp {
    var tint: Color {
        guard let color, color.hasPrefix("#"), let value = UInt32(color.dropFirst(), radix: 16) else { return Theme.surfaceHigh }
        return Color(hex: value)
    }
}
