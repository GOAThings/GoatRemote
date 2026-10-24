import Foundation

/// Apps conhecidas: nome, ícone (SF Symbol) e cor, para os atalhos. Abrem-se pelo pacote (market://launch?id=…),
/// que funciona com qualquer app instalada na TV.
struct KnownApp: Identifiable, Hashable {
    var package: String
    var name: String
    var symbol: String
    var color: UInt32

    var id: String { package }
    var link: String { "market://launch?id=\(package)" }
}

enum AppCatalog {
    static let apps: [KnownApp] = [
        KnownApp(package: "com.google.android.youtube.tv", name: "YouTube", symbol: "play.rectangle.fill", color: 0xFF0033),
        KnownApp(package: "com.netflix.ninja", name: "Netflix", symbol: "n.square.fill", color: 0xE50914),
        KnownApp(package: "com.amazon.amazonvideo.livingroom", name: "Prime Video", symbol: "play.tv.fill", color: 0x00A8E1),
        KnownApp(package: "com.disney.disneyplus", name: "Disney+", symbol: "sparkles.tv.fill", color: 0x113CCF),
        KnownApp(package: "com.wbd.stream", name: "Max", symbol: "m.square.fill", color: 0x002BE7),
        KnownApp(package: "com.apple.atve.androidtv.appletv", name: "Apple TV", symbol: "appletv.fill", color: 0x555555),
        KnownApp(package: "com.spotify.tv.android", name: "Spotify", symbol: "music.note", color: 0x1DB954),
        KnownApp(package: "com.plexapp.android", name: "Plex", symbol: "chevron.right.2", color: 0xE5A00D),
        KnownApp(package: "org.xbmc.kodi", name: "Kodi", symbol: "k.square.fill", color: 0x17B2E7),
        KnownApp(package: "tv.twitch.android.app", name: "Twitch", symbol: "bubble.left.fill", color: 0x9146FF),
        KnownApp(package: "cc.slokker.itv", name: "GoatTV", symbol: "tv.fill", color: 0x38BDF8),
        KnownApp(package: "com.android.tv.settings", name: "Settings", symbol: "gearshape.fill", color: 0x6B7280),
    ]

    static func app(_ package: String) -> KnownApp? { apps.first { $0.package == package } }

    /// O nome a mostrar de um pacote (o conhecido, ou a última parte do pacote).
    static func name(_ package: String) -> String {
        if let known = app(package) { return known.name }
        let last = package.split(separator: ".").last.map(String.init) ?? package
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    /// O ecrã inicial da TV não conta como app aberta.
    static func isLauncher(_ package: String) -> Bool {
        package.lowercased().contains("launcher") || package == "com.google.android.apps.tv.launcherx"
    }
}
