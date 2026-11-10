import Foundation
@testable import RemoteCore

/// Os textos do iPhone são os de contracts/strings.json, com os mesmos nomes que no Android (U8).
extension CoreTests {
    static func strings() throws {
        let json = try Contracts.object("strings.json")
        guard let strings = json["strings"] as? [String: [String: Any]],
              let phone = (json["phone"] as? [String: [String: String]])?["ios"] else { throw Failed(description: "strings.json") }
        let expected = Set(strings.filter { ($0.value["platforms"] as? [String] ?? []).contains("ios") }.keys)
        let mine = Dictionary(Strings.table, uniquingKeysWith: { a, _ in a })
        try expect(Set(mine.keys), expected)
        defer { Strings.language = nil }
        for lang in ["en", "pt"] {
            Strings.language = lang
            for (key, text) in mine {
                let entry = strings[key] ?? [:]
                let override = (entry["ios"] as? [String: String])?[lang]
                let want = (override ?? entry[lang] as? String ?? "").replacingOccurrences(of: "{phone}", with: phone[lang] ?? "")
                try expect("\(key) (\(lang)): \(text())", "\(key) (\(lang)): \(want)")
            }
        }
    }
}
