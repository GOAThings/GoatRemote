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
    /// A sessão da TV escolhida: tudo o que é dela (ver TVSession).
    private var session = TVSession(tvID: nil, status: .noTV, recents: [], hasChannels: false)

    private(set) var status: Status {
        get { session.status }
        set {
            if newValue != session.status { DebugLog.add("Status: \(newValue)" + (current.map { " (\($0.name), \($0.kind))" } ?? "")) }
            session.status = newValue
        }
    }
    private(set) var state: TVState {
        get { session.state }
        set { session.state = newValue }
    }
    /// As apps que se viu abertas nesta TV (as mais recentes primeiro), para as abrir com um toque.
    private(set) var recentApps: [String] {
        get { session.recentApps }
        set { session.recentApps = newValue }
    }
    /// As apps instaladas na TV, se ela tiver o GoatLauncher (que as dá na rede de casa); vazio sem ele.
    private(set) var installedApps: [TVApp] {
        get { session.installedApps }
        set { session.installedApps = newValue }
    }

    /// A TV tem o GoatTV com os canais para o telemóvel (já respondeu a /channels): mostra-se o botão Canais.
    private(set) var hasChannels: Bool {
        get { session.hasChannels }
        set { session.hasChannels = newValue }
    }
    /// A lista de canais do GoatTV (nil enquanto não veio, ou com o GoatTV fechado).
    private(set) var channels: ChannelList? {
        get { session.channels }
        set { session.channels = newValue }
    }
    private(set) var channelsStatus: ChannelsStatus {
        get { session.channelsStatus }
        set { session.channelsStatus = newValue }
    }
    /// A abrir o GoatTV na TV, à espera de que dê os canais.
    private(set) var openingGoatTV: Bool {
        get { session.openingGoatTV }
        set { session.openingGoatTV = newValue }
    }
    /// Porque é que o último canal não mudou (nil: nada a dizer).
    private(set) var playProblem: String? {
        get { session.playProblem }
        set { session.playProblem = newValue }
    }
    /// O programa do canal que o GoatTV está a dar (nil sem guia, ou num GoatTV antigo, sem o /now).
    private(set) var nowInfo: NowInfo? {
        get { session.nowInfo }
        set { session.nowInfo = newValue }
    }

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
    @ObservationIgnored private let options = Options()
    var haptics: Bool {
        get { options.haptics }
        set { options.haptics = newValue }
    }
    /// Os botões de volume do iPhone mexem no volume da TV (com a app aberta).
    var volumeButtons: Bool {
        get { options.volumeButtons }
        set { options.volumeButtons = newValue }
    }
    /// Superfície de toque ou setas (D-pad).
    var layout: RemoteLayout {
        get { options.layout }
        set { options.layout = newValue }
    }

    private var link: TVControl? {
        get { session.link }
        set {
            // A ligação mudou: o teclado fecha-se e o que lá estava escrito não passa para a próxima.
            guard newValue !== session.link else { return }
            session.link = newValue
            showKeyboard = false
            state.textValue = ""
            state.textLabel = nil
            state.keyboardRequests = 0
        }
    }
    /// As teclas mantidas da TV escolhida: os controlos do ecrã chamam keyHold.end() quando saem.
    var keyHold: KeyHold { session.keyHold }
    /// Ícones das apps da Apple TV (da App Store, por bundle id).
    private var appleArtwork: [String: URL] {
        get { session.appleArtwork }
        set { session.appleArtwork = newValue }
    }
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
        session = TVSession(tvID: current?.id, status: .noTV, recents: Self.loadRecents(current?.id), hasChannels: Self.hasGoatTV(current?.id))
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
        session.autoReconnect?.cancel()
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
            let since = Int(Date().timeIntervalSince(session.lastAutoReconnect) * 1000)
            if case .retry(let delay, let retry) = ConnectPolicy.next(.closed, notPairedRetries: session.notPairedRetries, retry: true,
                                                                      kind: tv.kind, sinceAutoReconnectMs: since) {
                session.lastAutoReconnect = Date()
                DebugLog.add("Reconnecting to \(tv.name)")
                self.status = .connecting
                self.retryLater(tv, delayMs: delay, retry: retry)
                return
            }
            self.status = .unreachable(L("The TV closed the connection", "A TV fechou a ligação"))
        }
        self.link = link
        Task {
            do {
                try await link.connect()
                guard self.link === link else { return }
                session.notPairedRetries = 0
                self.status = .connected
                self.session.withoutNow = false
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
                if case .retry(let delay, let again) = ConnectPolicy.next(.notPaired, notPairedRetries: session.notPairedRetries, retry: retry,
                                                                           kind: tv.kind, sinceAutoReconnectMs: 0) {
                    session.notPairedRetries += 1
                    DebugLog.add("Not paired: trying again (\(session.notPairedRetries))")
                    self.retryLater(tv, delayMs: delay, retry: again)
                    return
                }
                session.notPairedRetries = 0
                self.status = .notPaired
            } catch {
                DebugLog.add("Connect failed\(retry ? " (will retry)" : ""): \(error)")
                guard self.link === link else { return }
                self.link = nil
                link.close()
                switch ConnectPolicy.next(.failed, notPairedRetries: session.notPairedRetries, retry: retry, kind: tv.kind, sinceAutoReconnectMs: 0) {
                case .retry(let delay, let again): self.retryLater(tv, delayMs: delay, retry: again)
                case .give: self.status = .unreachable(Self.describe(error))
                }
            }
        }
    }

    /// No autoReconnect: ir para segundo plano (disconnect) ou mudar de TV cancela esta tentativa.
    private func retryLater(_ tv: SavedTV, delayMs: Int, retry: Bool) {
        session.autoReconnect = Task {
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            guard !Task.isCancelled, self.link == nil, self.current?.id == tv.id else { return }
            self.connect(retry: retry)
        }
    }

    func disconnect() {
        session.autoReconnect?.cancel()
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
        // Ao ligar, a TV manda vários valores seguidos (na SHIELD, com HDMI-CEC, acaba em 0): isso não é mudar o volume.
        if old.volume == nil, new.volume != nil { session.volumeSettlesAt = Date().addingTimeInterval(Double(VolumeRoute.settleMs) / 1000) }
        if VolumeRoute.changed(old: (old.volume, old.muted), new: (new.volume, new.muted), unknown: volumeUnknown,
                               settled: Date() >= session.volumeSettlesAt) { volumeChanged += 1 }
        // O GoatTV veio para a frente: o canal que está a dar pode ter mudado.
        if new.currentApp == GoatTVChannels.androidPackage, old.currentApp != new.currentApp, hasChannels { refreshChannels() }
        // Só muda (e só se escreve) se a app não for já a primeira: antes reescrevia a cada volume ou tecla (D3).
        if let recents = RecentApps.push(recentApps, new.currentApp) {
            recentApps = recents
            if let id = current?.id { UserDefaults.standard.set(recents, forKey: StoreKeys.perTV(StoreKeys.recents, id)) }
        }
    }

    private static func loadRecents(_ id: String?) -> [String] {
        guard let id else { return [] }
        let saved = UserDefaults.standard.stringArray(forKey: StoreKeys.perTV(StoreKeys.recents, id)) ?? []
        // O que não for um nome de pacote não volta a ler-se.
        let recents = RecentApps.sanitize(saved)
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

    private static func hasGoatTV(_ tvID: String?) -> Bool {
        tvID.map { UserDefaults.standard.bool(forKey: StoreKeys.perTV(StoreKeys.goatTV, $0)) } ?? false
    }

    /// Pede a lista ao GoatTV da TV. Ao ligar e ao abrir a folha.
    func refreshChannels() {
        guard let tv = current else { return }
        let session = session
        if session.channelsTask != nil { return }
        let id = UUID()
        let task = Task {
            await loadChannels(tv)
            if session.channelsTask?.id == id { session.channelsTask = nil }
        }
        session.channelsTask = (id, task)
    }

    /// true se veio a lista.
    @discardableResult
    private func loadChannels(_ tv: SavedTV) async -> Bool {
        guard let fetched = await GoatTvApi(host: tv.host).channels() else { return false }
        if let error = fetched.error { DebugLog.add("Channels: \(error)") }
        let list = fetched.value
        guard current?.id == tv.id else { return false }
        switch ChannelsOutcome.of(status: fetched.status, refused: fetched.refused, parsed: list != nil, hadList: channels != nil) {
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
        case .keep:
            // Outra resposta (ou nenhuma): fica a lista que já havia.
            break
        case .failed:
            channelsStatus = .failed
        }
        return list != nil
    }

    /// Pergunta ao GoatTV o que está a dar (GET /now, pequeno). Se o canal mudou (pelo comando da TV, por exemplo), o
    /// cartão muda; um canal que a lista não tem pede a lista outra vez. Fechado (Apple TV em segundo plano), o cartão sai.
    private func pollNow(_ tv: SavedTV) async {
        guard !session.withoutNow, let fetched = await GoatTvApi(host: tv.host).now() else { return }
        let info = fetched.value
        let status = fetched.status
        let refused = fetched.refused
        guard current?.id == tv.id else { return }
        switch NowOutcome.of(status: status, refused: refused, parsed: info != nil) {
        case .update:
            nowInfo = info
            guard let info, let list = channels else { return }
            switch NowOutcome.list(nowCurrent: info.current, listCurrent: list.current, inList: list.channels.contains(where: { $0.key == info.current })) {
            case .same: break
            case .setCurrent: channels?.current = info.current
            case .refetch: refreshChannels()
            }
        case .noNow:
            DebugLog.add("GoatTV on \(tv.name) has no /now")
            session.withoutNow = true
        case .close:
            channels = nil
            channelsStatus = .closed
            nowInfo = nil
        case .nothing:
            break
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
        session.playTask?.cancel()
        session.playTask = Task {
            var deadline: Date?
            while !Task.isCancelled {
                let (status, refused) = await Self.postPlay(tv, channel.key)
                guard !Task.isCancelled, current?.id == tv.id else { return }
                let app = goatTVApp ?? (tv.kind == .android ? Self.androidGoatTV : nil)
                let inFront = tv.kind == .android && state.currentApp == GoatTVChannels.androidPackage
                switch PlayStep.of(GoatTVChannels.playOutcome(status: status, refused: refused), waiting: deadline != nil,
                                   timedOut: deadline.map { Date() >= $0 } ?? false, inFront: inFront, canOpen: app != nil) {
                case .done:
                    channels?.current = channel.key
                    try? await Task.sleep(nanoseconds: UInt64(PlayStep.nowAfterMs) * 1_000_000)
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
                case .startWaiting:
                    // Já está à frente, só ainda não pode (a meio de mudar de canal): abri-lo outra vez não ajuda,
                    // e o link pelo comando faz a SHIELD fechar a ligação.
                    DebugLog.add("Play: GoatTV is in front but answered \(refused ? "refused" : "HTTP \(status)"), waiting")
                    deadline = Date().addingTimeInterval(Double(PlayStep.waitMs) / 1000)
                case .openAndWait:
                    guard let app else { return }
                    DebugLog.add("Play: GoatTV isn't in front (\(refused ? "refused" : "HTTP \(status)")), opening it")
                    launch(app, haptic: false)
                    deadline = Date().addingTimeInterval(Double(PlayStep.waitMs) / 1000)
                case .cannotOpen:
                    playProblem = goatTVClosedLine
                    return
                case .timedOut:
                    playProblem = L("GoatTV didn't switch channels. Check the TV and try again",
                                    "O GoatTV não mudou de canal. Vê a TV e tenta outra vez")
                    return
                case .keepWaiting:
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(PlayStep.retryEveryMs) * 1_000_000)
            }
        }
    }

    /// POST /play/<key> no GoatTV da TV: o estado HTTP e se a ligação foi recusada.
    static func postPlay(_ tv: SavedTV, _ key: String) async -> (status: Int, refused: Bool) {
        await GoatTvApi(host: tv.host).play(key)
    }

    /// Fecha a sessão da TV que estava e começa a de `tv`: nada passa de uma TV para a outra.
    private func startSession(_ tv: SavedTV?, status: Status) {
        session.close()
        showKeyboard = false
        session = TVSession(tvID: tv?.id, status: status, recents: Self.loadRecents(tv?.id), hasChannels: Self.hasGoatTV(tv?.id))
    }

    // MARK: TVs

    func select(_ tv: SavedTV) {
        guard tv.id != current?.id else { return }
        current = tv
        TVStore.currentID = tv.id
        startSession(tv, status: status)
        connect()
    }

    func forget(_ tv: SavedTV) {
        if tv.kind == .apple { CompanionCredentials.delete(tv.id) }
        TVStore.remove(tv.id)
        for key in StoreKeys.perTVKeys(tv.id) { UserDefaults.standard.removeObject(forKey: key) }
        tvs = TVStore.all
        if current?.id == tv.id {
            current = TVStore.current
            startSession(current, status: current == nil ? .noTV : .connecting)
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
        let model = PairingModel(name: name, id: id, host: host, endpoint: endpoint, kind: kind, port: port,
                                 onPaired: { [weak self] tv in self?.paired(tv) },
                                 onDone: { [weak self] done in if self?.pairing === done { self?.pairing = nil } })
        // Sem TVs, o ecrã de juntar é o principal e não há folhas por cima.
        guard !tvs.isEmpty else {
            pairing = model
            return model.start()
        }
        closeSheets += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: SheetHandoff.nanoseconds)
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
        current = tv
        startSession(tv, status: .connecting)
        connect()
    }

    // MARK: Comando

    /// [haptic] false nas repetições de uma tecla mantida: vibrava a cada passo, mais do que a TV avançava.
    func press(_ key: Key, haptic: Bool = true) {
        if haptic, haptics { lightHaptics.impactOccurred() }
        guard let link, status == .connected else { return reconnectIfNeeded() }
        switch VolumeRouter.route(current, key, .tap, volumeControl: state.volumeControl) {
        case .key: link.key(key)
        case .launcher: if let tv = current { volumeViaLauncher(tv, key) }
        case .explain: volumeChanged += 1
        case .nothing: break
        }
    }

    /// Se a TV tem o GoatLauncher (fica guardado por TV: nil enquanto não se sabe). Com ele, ou sem se saber, o
    /// volume nunca vai como tecla: as teclas de volume do protocolo rebentam o Android 11 da SHIELD quando o
    /// GoatLauncher vê as teclas (botões a abrir apps). Só se manda tecla quando se tem a certeza de que não há
    /// launcher: 404, ou ligação recusada na porta dele, numa TV onde nunca se viu nenhum. Onde já se viu, isso é só não
    /// ter respondido; esquecer a TV limpa o que se sabe, se o launcher saiu mesmo de lá. A regra está em VolumeRoute e
    /// no VolumeRouter, por onde passa todo o volume.
    static func hasLauncher(_ tvID: String) -> Bool? { LauncherMemory.known(tvID) }

    static func setLauncher(_ tvID: String, _ value: Bool) { LauncherMemory.set(tvID, value) }

    /// Com HDMI-CEC, o volume está na TV e a box não sabe o valor: o que reporta não diz nada. Descobre-se ao
    /// carregar: o launcher mudou o volume e o valor não mexeu. Fica guardado por TV.
    private var volumeUnknown: Bool {
        current.map { UserDefaults.standard.bool(forKey: StoreKeys.perTV(StoreKeys.volumeUnknown, $0.id)) } ?? false
    }

    /// A última tecla, para o indicador numa TV sem valor de volume (nil: mostra-se a barra).
    private(set) var volumePressed: Key? {
        get { session.volumePressed }
        set { session.volumePressed = newValue }
    }

    /// Mostrado no indicador de volume quando o launcher não respondeu (nil: nada a dizer).
    private(set) var volumeProblem: String? {
        get { session.volumeProblem }
        set { session.volumeProblem = newValue }
    }

    /// O volume pelo GoatLauncher (POST /volume/…) em vez de tecla. A tecla só vai se ele disser que não há launcher.
    private func volumeViaLauncher(_ tv: SavedTV, _ key: Key) {
        let before = (volume: state.volume, muted: state.muted)
        Task {
            guard let sent = await VolumeRouter.viaLauncher(tv, key) else { return }
            switch sent.outcome {
            case .done:
                volumeProblem = nil
                try? await Task.sleep(for: .milliseconds(VolumeRoute.learnAfterMs))
                guard current?.id == tv.id else { return }
                let unknown = VolumeRoute.learnUnknown(before: before, after: (state.volume, state.muted))
                UserDefaults.standard.set(unknown, forKey: StoreKeys.perTV(StoreKeys.volumeUnknown, tv.id))
                volumePressed = unknown ? key : nil
                if unknown { volumeChanged += 1 }
            case .noLauncher:
                if current?.id == tv.id { link?.key(key) }
            case .didntAnswer:
                guard current?.id == tv.id else { return }
                if sent.status == 404 {
                    volumeProblem = L("Update GoatLauncher on the TV to change the volume from here", "Atualiza o GoatLauncher na TV para mudares o volume daqui")
                } else if sent.refused {
                    volumeProblem = L("GoatLauncher isn't running on the TV. Open it. If you removed it, forget this TV and pair it again",
                                      "O GoatLauncher não está a correr na TV. Abre-o. Se o tiraste, esquece esta TV e emparelha-a outra vez")
                } else {
                    volumeProblem = L("The TV's launcher didn't answer. Try again", "O launcher da TV não respondeu. Tenta outra vez")
                }
                volumeChanged += 1
            }
        }
    }

    /// Carregar e manter: início e fim. Pelo GoatLauncher não há "manter": cada toque é um passo.
    func hold(_ key: Key, down: Bool) {
        if down { repeatStarted() }
        guard let link, status == .connected else { return reconnectIfNeeded() }
        switch VolumeRouter.route(current, key, down ? .holdDown : .holdUp, volumeControl: state.volumeControl) {
        case .key: link.key(key, down ? .startLong : .endLong)
        case .launcher: if let tv = current { volumeViaLauncher(tv, key) }
        case .explain: volumeChanged += 1
        case .nothing: break
        }
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

extension TVApp {
    var tint: Color {
        guard let color, color.hasPrefix("#"), let value = UInt32(color.dropFirst(), radix: 16) else { return Theme.surfaceHigh }
        return Color(hex: value)
    }
}
