import Foundation
@testable import RemoteCore

/// As regras de contracts/policies/: as mesmas tabelas que o Android testa.
extension CoreTests {
    static let policies: [(String, () throws -> Void)] = [
        ("connectPolicy", connectPolicy),
        ("channelsOutcome", channelsOutcome),
        ("nowOutcome", nowOutcome),
        ("playStep", playStep),
        ("volumeRoute", volumeRoute),
        ("recentApps", recentApps),
        ("onScreen", onScreen),
    ]

    static func rows(_ file: String, _ key: String = "rows") throws -> [[String: Any]] {
        Contracts.list(try Contracts.object("policies/\(file)")[key])
    }

    static func kind(_ v: Any?) -> TVKind { TVKind(rawValue: v as? String ?? "") ?? .android }

    static func connectPolicy() throws {
        let failures: [String: ConnectPolicy.Failure] = ["notPaired": .notPaired, "failed": .failed, "closed": .closed]
        let shows: [String: ConnectPolicy.Show] = ["notPaired": .notPaired, "unreachable": .unreachable, "closed": .closed]
        for row in try rows("connect.json") {
            guard let failure = failures[row["failure"] as? String ?? ""], let want = row["expected"] as? [String: Any] else { throw Failed(description: "\(row)") }
            let got = ConnectPolicy.next(failure, notPairedRetries: row["notPairedRetries"] as? Int ?? -1, retry: row["retry"] as? Bool ?? false,
                                         kind: kind(row["kind"]), sinceAutoReconnectMs: row["sinceAutoReconnectMs"] as? Int ?? -1)
            let expected: ConnectPolicy.Decision
            if let show = want["show"] as? String, let s = shows[show] {
                expected = .give(s)
            } else {
                expected = .retry(delayMs: want["retryMs"] as? Int ?? -1, retryOnFailure: want["retryOnFailure"] as? Bool ?? false)
            }
            try expect("\(row): \(got)", "\(row): \(expected)")
        }
    }

    static func channelsOutcome() throws {
        for row in try rows("channels.json") {
            let got = ChannelsOutcome.of(status: row["status"] as? Int ?? -1, refused: row["refused"] as? Bool ?? false,
                                         parsed: row["parsed"] as? Bool ?? false, hadList: row["hadList"] as? Bool ?? false)
            try expect("\(row): \(got)", "\(row): \(row["outcome"] as? String ?? "")")
        }
    }

    static func nowOutcome() throws {
        for row in try rows("now.json") {
            let got = NowOutcome.of(status: row["status"] as? Int ?? -1, refused: row["refused"] as? Bool ?? false, parsed: row["parsed"] as? Bool ?? false)
            try expect("\(row): \(got)", "\(row): \(row["outcome"] as? String ?? "")")
        }
        for row in try rows("now.json", "listRows") {
            let got = NowOutcome.list(nowCurrent: Contracts.string(row["nowCurrent"]), listCurrent: Contracts.string(row["listCurrent"]),
                                      inList: row["inList"] as? Bool ?? false)
            try expect("\(row): \(got)", "\(row): \(row["list"] as? String ?? "")")
        }
    }

    static func playStep() throws {
        let outcomes: [String: GoatTVChannels.Play] = ["done": .done, "notFound": .notFound, "failed": .failed, "retry": .retry]
        for row in try rows("play.json") {
            guard let outcome = outcomes[row["outcome"] as? String ?? ""] else { throw Failed(description: "\(row)") }
            let got = PlayStep.of(outcome, waiting: row["waiting"] as? Bool ?? false, timedOut: row["timedOut"] as? Bool ?? false,
                                  inFront: row["inFront"] as? Bool ?? false, canOpen: row["canOpen"] as? Bool ?? false)
            try expect("\(row): \(got)", "\(row): \(row["step"] as? String ?? "")")
        }
    }

    /// A regra que impede a SHIELD de reiniciar.
    static func volumeRoute() throws {
        let table = try Contracts.object("policies/volume-route.json")
        let keys: [String: Key] = ["volumeUp": .volumeUp, "volumeDown": .volumeDown, "mute": .mute, "home": .home]
        let presses: [String: VolumeRoute.Press] = ["tap": .tap, "holdDown": .holdDown, "holdUp": .holdUp]
        let rows = Contracts.list(table["rows"])
        try expect(rows.count, 144)
        for row in rows {
            guard let key = keys[row["key"] as? String ?? ""], let press = presses[row["press"] as? String ?? ""] else { throw Failed(description: "\(row)") }
            let got = VolumeRoute.of(key, press, kind: kind(row["kind"]), known: Contracts.bool(row["known"]), volumeControl: row["volumeControl"] as? Bool ?? false)
            try expect("\(row): \(got)", "\(row): \(row["route"] as? String ?? "")")
        }
        func pair(_ v: Any?) -> (volume: Int?, muted: Bool?) {
            let a = v as? [Any] ?? []
            return (a.first as? Int, a.count > 1 ? Contracts.bool(a[1]) : nil)
        }
        for row in Contracts.list(table["learn"]) {
            try expect(VolumeRoute.learnUnknown(before: pair(row["before"]), after: pair(row["after"])), row["unknown"] as? Bool ?? false)
        }
        for row in Contracts.list(table["changed"]) {
            try expect(VolumeRoute.changed(old: pair(row["old"]), new: pair(row["new"]), unknown: row["unknown"] as? Bool ?? false,
                                           settled: row["settled"] as? Bool ?? false), row["changed"] as? Bool ?? false)
        }
        for row in Contracts.list(table["problems"]) {
            let got = VolumeProblem.of(status: row["status"] as? Int ?? -1, refused: row["refused"] as? Bool ?? false)
            try expect("\(got)", row["problem"] as? String ?? "")
        }
        let timings = table["timings"] as? [String: Int] ?? [:]
        try expect(timings["learnAfterMs"], VolumeRoute.learnAfterMs)
        try expect(timings["settleMs"], VolumeRoute.settleMs)
    }

    static func onScreen() throws {
        for row in try rows("on-screen.json") {
            let got = OnScreen.of(isOn: Contracts.bool(row["isOn"]), currentApp: Contracts.string(row["currentApp"]), kind: kind(row["kind"]))
            try expect("\(row): \(got)", "\(row): \(row["onScreen"] as? String ?? "")")
        }
    }

    static func recentApps() throws {
        let table = try Contracts.object("policies/recents.json")
        for row in Contracts.list(table["push"]) {
            let got = RecentApps.push(row["list"] as? [String] ?? [], Contracts.string(row["app"]))
            try expect(got, row["result"] as? [String])
        }
        for row in Contracts.list(table["sanitize"]) {
            try expect(RecentApps.sanitize(row["saved"] as? [String] ?? []), row["result"] as? [String] ?? [])
        }
    }
}
