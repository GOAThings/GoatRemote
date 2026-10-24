import AppIntents
import RemoteCore

/// Teclas para os Atalhos e a Siri ("Ei Siri, desliga a TV"). Correm na própria app (sem extensão, que o
/// Signulous não assina): ligam à TV escolhida, mandam a tecla e desligam.
enum TVButton: String, AppEnum {
    case power, playPause, mute, volumeUp, volumeDown, home, back

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "TV button"

    static let caseDisplayRepresentations: [TVButton: DisplayRepresentation] = [
        .power: "Power",
        .playPause: "Play/Pause",
        .mute: "Mute",
        .volumeUp: "Volume up",
        .volumeDown: "Volume down",
        .home: "Home",
        .back: "Back",
    ]

    var key: Key {
        switch self {
        case .power: return .power
        case .playPause: return .playPause
        case .mute: return .mute
        case .volumeUp: return .volumeUp
        case .volumeDown: return .volumeDown
        case .home: return .home
        case .back: return .back
        }
    }
}

struct PressTVButton: AppIntent {
    static let title: LocalizedStringResource = "Press a TV button"
    static let description = IntentDescription("Presses a button on the TV chosen in GoatRemote.")

    @Parameter(title: "Button")
    var button: TVButton

    func perform() async throws -> some IntentResult {
        try await RemoteLink.once { $0.key(button.key) }
        return .result()
    }
}

struct TVPower: AppIntent {
    static let title: LocalizedStringResource = "Turn the TV on or off"

    func perform() async throws -> some IntentResult {
        try await RemoteLink.once { $0.key(.power) }
        return .result()
    }
}

struct TVPlayPause: AppIntent {
    static let title: LocalizedStringResource = "Play or pause the TV"

    func perform() async throws -> some IntentResult {
        try await RemoteLink.once { $0.key(.playPause) }
        return .result()
    }
}

struct GoatRemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TVPower(),
                    phrases: ["Turn the TV on or off with \(.applicationName)", "Liga ou desliga a TV com o \(.applicationName)", "\(.applicationName) power"],
                    shortTitle: "TV power", systemImageName: "power")
        AppShortcut(intent: TVPlayPause(),
                    phrases: ["Pause the TV with \(.applicationName)", "Pausa a TV com o \(.applicationName)"],
                    shortTitle: "Play/Pause", systemImageName: "playpause.fill")
        AppShortcut(intent: PressTVButton(),
                    phrases: ["Press \(\.$button) on \(.applicationName)", "Carrega em \(\.$button) no \(.applicationName)"],
                    shortTitle: "TV button", systemImageName: "av.remote")
    }
}
