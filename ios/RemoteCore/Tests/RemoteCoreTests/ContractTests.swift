import Foundation
@testable import RemoteCore

/// Os contratos de contracts/: o protocolo, o GoatLauncher (6470), o GoatTV (6471) e o que fica guardado. Os mesmos
/// ficheiros que o ContractsTest do Android lê.
extension CoreTests {
    static let contracts: [(String, () throws -> Void)] = [
        ("pairingFrames", pairingFrames),
        ("remoteFrames", remoteFrames),
        ("companionCrypto", companionCrypto),
        ("goatTVChannelCases", goatTVChannelCases),
        ("goatTVNowCases", goatTVNowCases),
        ("goatTVKeysAndOutcomes", goatTVKeysAndOutcomes),
        ("lanURLs", lanURLs),
        ("launcherApps", launcherApps),
        ("launcherVolumeTable", launcherVolumeTable),
        ("savedTVs", savedTVs),
        ("companionCredentials", companionCredentials),
        ("optionKeys", optionKeys),
        ("layoutMigration", layoutMigration),
        ("themeTokens", themeTokens),
    ]

    /// As mensagens de um bloco de tramas, sem o tamanho à frente.
    static func payloads(_ data: Data) throws -> [String] {
        var reader = Frame.Reader()
        reader.append(data)
        var out: [String] = []
        while let frame = try reader.next() { out.append(SHA.hex(frame)) }
        return out
    }

    // MARK: Protocolo da Android TV

    static func pairingFrames() throws {
        try expect(try payloads(Pairing.request(clientName: "Phone")), [try Contracts.vectorHex("pairing.request")])
        try expect(try payloads(Pairing.options), [try Contracts.vectorHex("pairing.options")])
        try expect(try payloads(Pairing.configuration), [try Contracts.vectorHex("pairing.configuration")])
        try expect(try payloads(Pairing.secretMessage((0..<32).map { UInt8($0) })), [try Contracts.vectorHex("pairing.secretMessage_0to31")])
        let client = RSAKey(modulus: try Contracts.vector("secret.clientModulus"), exponent: try Contracts.vector("secret.clientExponent"))
        let server = RSAKey(modulus: try Contracts.vector("secret.serverModulus"), exponent: try Contracts.vector("secret.serverExponent"))
        let secret = Pairing.secret(code: try Contracts.vectorHex("secret.code"), client: client, server: server)
        try expect(secret.map(SHA.hex), try Contracts.vectorHex("secret.secret"))
    }

    static func remoteFrames() throws {
        var r = RemoteProtocol(model: "Phone", appVersion: "1.0")
        func reply(_ vector: String) throws -> [String] { try r.handle(try Contracts.vector(vector)).flatMap(payloads) }
        try expect(try reply("remote.configure"), [try Contracts.vectorHex("remote.configureReply_ios")])
        try expect(try reply("remote.setActive"), [try Contracts.vectorHex("remote.setActiveReply")])
        try expect(try reply("remote.ping"), [try Contracts.vectorHex("remote.pong")])
        try expect(try payloads(r.key(.center)), [try Contracts.vectorHex("remote.keyCenter")])
        try expect(try payloads(r.key(.home, .startLong)), [try Contracts.vectorHex("remote.keyHomeStartLong")])
        try expect(try payloads(r.key(.home, .endLong)), [try Contracts.vectorHex("remote.keyHomeEndLong")])
        _ = try reply("remote.imeShow_abc_Search")
        _ = try reply("remote.imeBatchEdit_7_3")
        try expect(try payloads(r.text("abcolá")), [try Contracts.vectorHex("remote.text_abcola")])
        let delete = try Contracts.vectorHex("remote.text_abcd_delete")
        try expect(try payloads(r.text("abcd")), [delete, delete, delete, try Contracts.vectorHex("remote.text_abcd_insert")])
        try expect(try payloads(r.appLink("market://launch?id=com.netflix.ninja")), [try Contracts.vectorHex("remote.appLink_netflix")])
    }

    static func companionCrypto() throws {
        let ikm = (0..<32).map { UInt8($0) }
        try expect(SHA.hex(SHA512.hkdf(salt: "Pair-Verify-Encrypt-Salt", info: "Pair-Verify-Encrypt-Info", key: ikm)), try Contracts.vectorHex("hkdf.pairVerify"))
        try expect(SHA.hex(SHA512.hkdf(salt: "", info: "ClientEncrypt-main", key: ikm)), try Contracts.vectorHex("hkdf.clientEncrypt"))
        try expect(SHA.hex(SHA512.hash(Array("abc".utf8))), try Contracts.vectorHex("sha512.abc"))
    }

    // MARK: GoatTV (6471)

    static func payload(_ dir: String, _ value: String) throws -> Data {
        value.hasPrefix("@") ? try Contracts.data("\(dir)/\(value.dropFirst())") : Data(value.utf8)
    }

    static func goatTVChannelCases() throws {
        for c in Contracts.list(try Contracts.object("goattv-6471/channels.expected.json")["cases"]) {
            let data = try payload("goattv-6471", c["payload"] as? String ?? "")
            if c["expected"] as? String == "error" {
                if (try? GoatTVChannels.parse(data)) != nil { throw Failed(description: "devia ter dado erro: \(c["payload"] ?? "")") }
                continue
            }
            guard let want = c["expected"] as? [String: Any] else { throw Failed(description: "sem expected") }
            let list = try GoatTVChannels.parse(data)
            try expect(list.playlist, Contracts.string(want["playlist"]))
            try expect(list.current, Contracts.string(want["current"]))
            try expect(list.groups.map { "\($0.id)=\($0.name)" }, Contracts.list(want["groups"]).map { "\($0["id"] ?? "")=\($0["name"] ?? "")" })
            let channels = Contracts.list(want["channels"])
            try expect(list.channels.map(\.key), channels.map { $0["key"] as? String ?? "" })
            for (w, ch) in zip(channels, list.channels) {
                try expect(ch.num, Contracts.int(w["num"]))
                try expect(ch.name, w["name"] as? String ?? "")
                try expect(ch.group, Contracts.string(w["group"]))
                try expect(ch.logo, w["logo"] as? Bool ?? true)
                try expect(ch.favorite, w["favorite"] as? Bool ?? true)
            }
            try expect(list.truncated, want["truncated"] as? Bool ?? false)
        }
    }

    static func goatTVNowCases() throws {
        func programme(_ v: Any?) -> Programme? {
            guard let o = v as? [String: Any], let title = o["title"] as? String, let start = o["start"] as? Int, let end = o["end"] as? Int else { return nil }
            return Programme(title: title, startMs: Int64(start), endMs: Int64(end))
        }
        for c in Contracts.list(try Contracts.object("goattv-6471/now.json")["cases"]) {
            let data = Data((c["payload"] as? String ?? "").utf8)
            if c["expected"] as? String == "error" {
                if (try? GoatTVChannels.parseNow(data)) != nil { throw Failed(description: "devia ter dado erro") }
                continue
            }
            guard let want = c["expected"] as? [String: Any] else { throw Failed(description: "sem expected") }
            try expect(try GoatTVChannels.parseNow(data), NowInfo(current: Contracts.string(want["current"]), now: programme(want["now"]), next: programme(want["next"])))
        }
    }

    static func goatTVKeysAndOutcomes() throws {
        let keys = try Contracts.object("goattv-6471/encode-key.json")
        for pair in keys["keys"] as? [[String]] ?? [] { try expect(GoatTVChannels.encodeKey(pair[0]), pair[1]) }
        for u in Contracts.list(keys["urls"]) {
            try expect(GoatTVChannels.url(host: u["host"] as? String ?? "", u["what"] as? String ?? "", key: Contracts.string(u["key"])), u["url"] as? String ?? "")
        }
        for row in Contracts.list(try Contracts.object("goattv-6471/play-outcome.json")["rows"]) {
            let got = GoatTVChannels.playOutcome(status: row["status"] as? Int ?? -1, refused: row["refused"] as? Bool ?? false)
            try expect("\(got)", row["outcome"] as? String ?? "")
        }
        for row in Contracts.list(try Contracts.object("goattv-6471/apple-app.json")["rows"]) {
            try expect(GoatTVChannels.appleApp(row["apps"] as? [String: String] ?? [:]), Contracts.string(row["expected"]))
        }
    }

    // MARK: A rede de casa

    /// B6: os IPv6 vão entre parênteses retos, senão o URL não se lê.
    static func lanURLs() throws {
        for row in Contracts.list(try Contracts.object("lan-url.json")["rows"]) {
            let url = LanURL.string(host: row["host"] as? String ?? "", port: row["port"] as? Int ?? 0, path: row["path"] as? String ?? "")
            try expect(url, row["url"] as? String ?? "")
            try expect(URL(string: url) != nil, true)
        }
        try expect(GoatTVChannels.url(host: "fe80::1", "play", key: "a/b"), "http://[fe80::1]:6471/play/a%2Fb")
    }

    // MARK: GoatLauncher (6470)

    static func launcherApps() throws {
        let expected = try Contracts.object("launcher-6470/apps.expected.json")
        let apps = try LauncherApps.parse(try Contracts.data("launcher-6470/" + (expected["input"] as? String ?? "")))
        let want = Contracts.list(expected["expected"])
        try expect(apps.map(\.package), want.map { $0["package"] as? String ?? "" })
        for (w, app) in zip(want, apps) {
            try expect(app.label, w["label"] as? String ?? "")
            try expect(app.banner, w["banner"] as? Bool ?? false)
            try expect(app.color, Contracts.string(w["color"]))
        }
        for bad in expected["notAList"] as? [String] ?? [] {
            if (try? LauncherApps.parse(Data(bad.utf8))) != nil { throw Failed(description: "devia ter dado erro: \(bad)") }
        }
        for row in Contracts.list(try Contracts.object("launcher-6470/open-fallback.json")["rows"]) {
            try expect(LauncherApps.openFallsBack(status: row["status"] as? Int ?? -1), row["fallback"] as? Bool ?? false)
        }
    }

    /// A regra que impede a SHIELD de reiniciar: tecla de volume só com a certeza de que não há launcher.
    static func launcherVolumeTable() throws {
        let rows = Contracts.list(try Contracts.object("launcher-6470/volume-outcome.json")["rows"])
        try expect(rows.count, 24)
        for row in rows {
            let got = LauncherVolume.outcome(known: Contracts.bool(row["known"]), status: row["status"] as? Int ?? -1, refused: row["refused"] as? Bool ?? false)
            try expect("\(got)", row["outcome"] as? String ?? "")
        }
    }

    // MARK: O que fica guardado

    static func savedTVs() throws {
        let sample = try Contracts.object("persisted/ios/tvs.json")
        let stored = try JSONSerialization.data(withJSONObject: sample["stored"] ?? [])
        let tvs = try JSONDecoder().decode([SavedTV].self, from: stored)
        try expect(tvs, [SavedTV(id: "SHIELD", name: "SHIELD", host: "192.168.1.10"),
                         SavedTV(id: "Sala", name: "Sala", host: "192.168.1.11", certificate: "ab12cd"),
                         SavedTV(id: "apple:Quarto", name: "Quarto", host: "192.168.1.20", kind: .apple, port: 49153)])
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tvs))
        if !Contracts.same(written, sample["written"]) { throw Failed(description: "SavedTV escreve \(written)") }
    }

    static func companionCredentials() throws {
        let sample = try Contracts.object("persisted/ios/companion.json")
        for name in ["plain", "airPlay"] {
            let json = try JSONSerialization.data(withJSONObject: sample[name] ?? [:])
            let creds = try JSONDecoder().decode(CompanionCredentials.self, from: json)
            try expect([UInt8](creds.tvPublicKey), (1...32).map { UInt8($0) })
            try expect([UInt8](creds.privateKey), (100..<132).map { UInt8($0) })
            try expect(String(decoding: creds.clientID, as: UTF8.self), "0B1C2D3E-4F50-6172-8394-A5B6C7D8E9F0")
            try expect(creds.viaAirPlay, name == "airPlay" ? true : nil)
            try expect(creds.companionID.map { String(decoding: $0, as: UTF8.self) }, name == "airPlay" ? "companion-id" : nil)
            let again = try JSONSerialization.jsonObject(with: JSONEncoder().encode(creds))
            if !Contracts.same(again, sample[name]) { throw Failed(description: "CompanionCredentials escreve \(again)") }
        }
    }

    static func optionKeys() throws {
        guard let ios = try Contracts.object("persisted/options-keys.json")["ios"] as? [String: Any],
              let defaults = ios["userDefaults"] as? [String: Any], let perTV = ios["perTv"] as? [String: Any] else {
            throw Failed(description: "options-keys.json sem ios")
        }
        try expect(Set(defaults.keys), [StoreKeys.tvs, StoreKeys.current, StoreKeys.haptics, StoreKeys.volumeButtons, StoreKeys.layout,
                                        StoreKeys.dpadTaps, StoreKeys.companionID])
        try expect(Set(perTV.keys), Set(StoreKeys.perTV))
        try expect(StoreKeys.perTVKeys("x"), ["recents.x", "launcher.x", "volumeUnknown.x", "goattv.x"])
        try expect(ios["layoutValues"] as? [String] ?? [], RemoteLayout.allCases.map(\.rawValue))
        guard let keychain = ios["keychain"] as? [String: String], keychain["appletv"]?.contains(StoreKeys.appleTVService) == true else {
            throw Failed(description: "o serviço do Keychain mudou")
        }
    }

    /// Quem tinha as "setas nas bordas" (dpadTaps) começa nas setas; um layout guardado ganha sempre.
    static func layoutMigration() throws {
        try expect(RemoteLayout.saved(nil, dpadTaps: false), .touch)
        try expect(RemoteLayout.saved(nil, dpadTaps: true), .dpad)
        try expect(RemoteLayout.saved("touch", dpadTaps: true), .touch)
        try expect(RemoteLayout.saved("dpad", dpadTaps: false), .dpad)
        // Um valor desconhecido (ou o do Android, em maiúsculas) não é um layout: vale o dpadTaps.
        try expect(RemoteLayout.saved("DPAD", dpadTaps: false), .touch)
    }

    static func themeTokens() throws {
        let theme = try Contracts.object("theme.json")
        guard let tokens = theme["tokens"] as? [String: String], let alpha = theme["alpha"] as? [String: Double] else {
            throw Failed(description: "theme.json")
        }
        func hex(_ v: UInt32) -> String {
            let s = String(v, radix: 16, uppercase: true)
            return String(repeating: "0", count: max(0, 6 - s.count)) + s
        }
        let mine: [String: UInt32] = [
            "background": ThemeTokens.background, "surface": ThemeTokens.surface, "card": ThemeTokens.card,
            "surfaceHigh": ThemeTokens.surfaceHigh, "surfacePressed": ThemeTokens.surfacePressed, "accent": ThemeTokens.accent,
            "accent2": ThemeTokens.accent2, "power": ThemeTokens.power, "green": ThemeTokens.green, "text": ThemeTokens.text,
            "dim": ThemeTokens.dim, "faint": ThemeTokens.dim, "heroTop": ThemeTokens.heroTop, "heroBottom": ThemeTokens.heroBottom,
            "favorite": ThemeTokens.favorite,
        ]
        try expect(Set(mine.keys), Set(tokens.keys))
        for (name, value) in mine { try expect("\(name)=\(hex(value))", "\(name)=\(tokens[name] ?? "")") }
        try expect(alpha["dim"], ThemeTokens.dimAlpha)
        try expect(alpha["faint"], ThemeTokens.faintAlpha)
        try expect(alpha["line"], ThemeTokens.lineAlpha)
    }
}
