import Foundation

/// Os ícones das apps da Apple TV, da App Store (pelo bundle id).
enum AppStoreArtwork {
    static func lookup(_ bundleID: String) async -> URL? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let art = (first["artworkUrl512"] ?? first["artworkUrl100"]) as? String else { return nil }
        return URL(string: art)
    }
}
