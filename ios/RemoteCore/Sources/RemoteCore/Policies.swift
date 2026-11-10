import Foundation

// As regras do comando, sem ligações nem estado: as mesmas (com os mesmos nomes) no Android (data/Policies.kt), e
// testadas dos dois lados pelas tabelas de contracts/policies/.

/// Ligar à TV: tentar outra vez daqui a pouco, ou mostrar o problema.
public enum ConnectPolicy {
    public enum Failure: Sendable {
        /// A TV não aceita este iPhone (pode ser só por uns segundos: a SHIELD, a meio de mudar de canal).
        case notPaired
        /// Não ligou (recusada, tempo esgotado, outro erro).
        case failed
        /// Estava ligada e a TV fechou a ligação.
        case closed
    }

    public enum Show: Sendable { case notPaired, unreachable, closed }

    public enum Decision: Equatable, Sendable {
        /// Tentar outra vez daqui a `delayMs`; `retryOnFailure` é o "retry" dessa tentativa.
        case retry(delayMs: Int, retryOnFailure: Bool)
        case give(Show)
    }

    public static let notPairedRetries = 3
    public static let notPairedStepMs = 2000
    public static let retryMs = 1500
    public static let autoReconnectMs = 1500
    /// Uma ligação que fecha outra vez antes disto já não se liga sozinha: mostra-se o aviso.
    public static let autoReconnectEveryMs = 10_000

    /// `notPairedRetries`: as recusas seguidas que já se tentaram de novo; `retry`: esta tentativa ainda pode tentar
    /// outra vez se falhar; `sinceAutoReconnectMs`: desde a última vez que uma ligação fechada se ligou sozinha.
    /// "Não emparelhado" tenta mais três vezes (2, 4 e 6 s, uns 12 s); outra falha tenta uma vez daí a 1,5 s; uma
    /// ligação fechada só se liga sozinha numa Android TV, no máximo uma vez a cada 10 s.
    public static func next(_ failure: Failure, notPairedRetries: Int, retry: Bool, kind: TVKind, sinceAutoReconnectMs: Int) -> Decision {
        switch failure {
        case .notPaired:
            return notPairedRetries < Self.notPairedRetries
                ? .retry(delayMs: notPairedStepMs * (notPairedRetries + 1), retryOnFailure: true) : .give(.notPaired)
        case .failed:
            return retry ? .retry(delayMs: retryMs, retryOnFailure: false) : .give(.unreachable)
        case .closed:
            return kind == .android && sinceAutoReconnectMs > autoReconnectEveryMs
                ? .retry(delayMs: autoReconnectMs, retryOnFailure: true) : .give(.closed)
        }
    }
}

/// A resposta de GET /channels: o que fica no ecrã.
public enum ChannelsOutcome: Sendable {
    case ready
    /// Ligação recusada ou 503: o GoatTV não está aberto (ou ainda não carregou a lista).
    case closed
    /// Outra resposta (ou nenhuma), com uma lista já mostrada: fica essa.
    case keep
    /// Outra resposta, e nenhuma lista: falhou.
    case failed

    public static func of(status: Int, refused: Bool, parsed: Bool, hadList: Bool) -> ChannelsOutcome {
        if parsed { return .ready }
        if refused || status == 503 { return .closed }
        return hadList ? .keep : .failed
    }
}

/// A resposta de GET /now: o que fazer ao cartão.
public enum NowOutcome: Sendable {
    /// Veio o que está a dar.
    case update
    /// 404: um GoatTV sem o /now; não se pergunta até voltar a ligar.
    case noNow
    /// Recusado ou 503: o GoatTV fechou, o cartão sai.
    case close
    /// Outra resposta: fica tudo como está.
    case nothing

    /// Com o que está a dar (`update`): o canal da lista muda, ou a lista vem outra vez (um canal que ela não tem).
    public enum List: Sendable { case same, setCurrent, refetch }

    public static func of(status: Int, refused: Bool, parsed: Bool) -> NowOutcome {
        if parsed { return .update }
        if status == 404 { return .noNow }
        if refused || status == 503 { return .close }
        return .nothing
    }

    public static func list(nowCurrent: String?, listCurrent: String?, inList: Bool) -> List {
        if nowCurrent == listCurrent { return .same }
        return nowCurrent == nil || inList ? .setCurrent : .refetch
    }
}

/// Mudar de canal (POST /play): um passo do ciclo que abre o GoatTV e tenta outra vez até 10 s.
public enum PlayStep: Sendable {
    case done
    case notFound
    case failed
    /// Já está à frente, só ainda não pode (a meio de mudar de canal): espera, sem o abrir outra vez.
    case startWaiting
    /// Não está à frente: abre-se e espera-se.
    case openAndWait
    /// Não se sabe abrir o GoatTV nesta TV.
    case cannotOpen
    case keepWaiting
    /// Passaram os 10 s.
    case timedOut

    public static let waitMs = 10_000
    public static let retryEveryMs = 1000
    /// Depois de mudar, espera-se isto antes de perguntar o que está a dar.
    public static let nowAfterMs = 800

    /// `waiting`: já se começou a esperar (o prazo existe); `timedOut`: o prazo passou; `inFront`: numa Android TV, o
    /// GoatTV é a app aberta; `canOpen`: há como o abrir.
    public static func of(_ outcome: GoatTVChannels.Play, waiting: Bool, timedOut: Bool, inFront: Bool, canOpen: Bool) -> PlayStep {
        switch outcome {
        case .done: return .done
        case .notFound: return .notFound
        case .failed: return .failed
        case .retry:
            if waiting { return timedOut ? .timedOut : .keepWaiting }
            if inFront { return .startWaiting }
            return canOpen ? .openAndWait : .cannotOpen
        }
    }
}

/// Por onde vai uma tecla de volume. A regra que impede a SHIELD de reiniciar: com o GoatLauncher, ou sem se saber se
/// ele lá está, o volume nunca vai como tecla (vai pelo launcher, POST /volume/…); a tecla só quando se tem a certeza
/// de que não há launcher (ver LauncherVolume.outcome). Vem dos incidentes c06672a, bcc9ca4 e b272212.
public enum VolumeRoute: Sendable {
    /// A tecla, pelo protocolo da TV.
    case key
    /// Pelo GoatLauncher.
    case launcher
    /// Esta TV não muda o volume: o indicador explica porquê.
    case explain
    /// Nada (largar uma tecla de volume que foi pelo launcher, que não tem "manter").
    case nothing

    public enum Press: Sendable { case tap, holdDown, holdUp }

    public static let volumeKeys: [Key] = [.volumeUp, .volumeDown, .mute]

    /// `known`: o que se sabe do launcher desta TV (nil: ainda não se sabe); `volumeControl`: a TV diz que o muda.
    public static func of(_ key: Key, _ press: Press, kind: TVKind, known: Bool?, volumeControl: Bool) -> VolumeRoute {
        guard volumeKeys.contains(key) else { return .key }
        if press != .holdUp, !volumeControl { return .explain }
        if kind == .android, known != false { return press == .holdUp ? .nothing : .launcher }
        return .key
    }

    /// HDMI-CEC: o launcher mudou o volume e o valor que a TV conta não mexeu (passados `learnAfterMs`).
    public static func learnUnknown(before: (volume: Int?, muted: Bool?), after: (volume: Int?, muted: Bool?)) -> Bool {
        before.volume == after.volume && before.muted == after.muted
    }

    public static let learnAfterMs = 800
    /// Ao ligar, a TV manda vários valores seguidos (na SHIELD, com HDMI-CEC, acaba em 0): isso não é mudar o volume.
    public static let settleMs = 5000

    /// O volume mudou (o indicador aparece): não ao ligar, nem numa TV que não sabe o valor.
    public static func changed(old: (volume: Int?, muted: Bool?), new: (volume: Int?, muted: Bool?), unknown: Bool, settled: Bool) -> Bool {
        old.volume != nil && (new.volume != old.volume || new.muted != old.muted) && !unknown && settled
    }
}

/// As apps que se viu abertas numa TV (as mais recentes primeiro), para as abrir com um toque.
public enum RecentApps {
    public static let max = 12

    /// O ecrã inicial da TV não conta como app aberta (o GoatLauncher também não, de propósito).
    public static func isLauncher(_ package: String) -> Bool {
        package.lowercased().contains("launcher") || package == "com.google.android.apps.tv.launcherx"
    }

    /// A lista com `app` à frente, ou nil se não muda (o ecrã inicial não conta, nem a que já está à frente).
    public static func push(_ list: [String], _ app: String?) -> [String]? {
        guard let app, !isLauncher(app), list.first != app else { return nil }
        return Array(([app] + list.filter { $0 != app }).prefix(max))
    }

    /// O que estava guardado: só nomes de pacote, sem repetidos, até `max`.
    public static func sanitize(_ saved: [String]) -> [String] {
        var seen = Set<String>()
        return Array(saved.filter { RemoteProtocol.isPackageName($0) && seen.insert($0).inserted }.prefix(max))
    }
}

/// O que está no ecrã da TV, para o subtítulo do cabeçalho e a marca-d'água da superfície (o mesmo nos dois).
public enum OnScreen: Sendable {
    case off
    /// Uma app (não o ecrã inicial): mostra-se o nome dela.
    case app
    /// A Apple TV não diz que app está aberta.
    case appleTV
    case home

    public static func of(isOn: Bool?, currentApp: String?, kind: TVKind?) -> OnScreen {
        if isOn == false { return .off }
        if let app = currentApp, !RecentApps.isLauncher(app) { return .app }
        return kind == .apple ? .appleTV : .home
    }
}

/// Porque é que o volume pelo GoatLauncher não foi (a vista diz o texto; aqui é só o motivo).
public enum VolumeProblem: Sendable {
    /// 404: um GoatLauncher antigo, sem o volume.
    case updateLauncher
    /// Ligação recusada: o GoatLauncher não está a correr.
    case launcherNotRunning
    case noAnswer

    public static func of(status: Int, refused: Bool) -> VolumeProblem {
        if status == 404 { return .updateLauncher }
        return refused ? .launcherNotRunning : .noAnswer
    }

    /// O que o indicador do volume mostra.
    public var text: String {
        switch self {
        case .updateLauncher: return Strings.updateGoatlauncherOnTheTvTo
        case .launcherNotRunning: return Strings.goatlauncherIsntRunningOnTheTv
        case .noAnswer: return Strings.theTvsLauncherDidntAnswerTry
        }
    }
}
