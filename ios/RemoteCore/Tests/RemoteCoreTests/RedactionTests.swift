import Foundation
@testable import RemoteCore

/// O registo de diagnóstico sem credenciais nem endereços: as mesmas linhas de contracts/redaction.json que o
/// LogRedactionTest do Android lê.
extension CoreTests {
    static let redaction: [(String, () throws -> Void)] = [
        ("redactionRows", redactionRows),
        ("redactionNames", redactionNames),
        ("redactionSecrets", redactionSecrets),
    ]

    static func redactionRows() throws {
        var wrong: [String] = []
        for row in Contracts.list(try Contracts.object("redaction.json")["rows"]) {
            let input = row["input"] as? String ?? ""
            let want = row["output"] as? String ?? ""
            let got = LogRedaction.redact(input)
            if got != want { wrong.append("\(input)\n  want \(want)\n  got  \(got)") }
        }
        if !wrong.isEmpty { throw Failed(description: wrong.joined(separator: "\n")) }
    }

    static func redactionNames() throws {
        let log = "Found Sala at 192.168.1.20:6466\nFound Quarto at 192.168.1.21:6466\nConnecting to Sala (192.168.1.20:6466)"
        try expect(LogRedaction.redact(log), "Found Sala at ip1:6466\nFound Quarto at ip2:6466\nConnecting to Sala (ip1:6466)")
    }

    static func redactionSecrets() throws {
        // Segredos de menos de 3 caracteres não se trocam (senão apagava letras soltas).
        try expect(LogRedaction.redact("Error with tok_live_999 and ab", secrets: ["tok_live_999", "ab"]), "Error with *** and ab")
    }
}
