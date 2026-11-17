import Foundation

/// O registo de diagnóstico antes de sair do iPhone (enviar, copiar ou partilhar): as regras do GoatTV
/// (BugReportRules, no itv-shared) e do GoatLauncher, mais os emails e o IPv6. O mesmo que o Android faz
/// (data/LogRedaction.kt), conferido dos dois lados por contracts/redaction.json.
///
/// Aqui o registo é quase todo sobre achar as TVs na rede, por isso os IPs e os MACs não passam a `***`: cada um leva
/// um nome que se mantém no relatório inteiro (o primeiro IP é `ip1`, o seguinte `ip2`…; os MACs `mac1`…), para se
/// perceber qual é qual sem se ver o endereço. As portas ficam. Os nomes das TVs também (foi a pessoa que os deu).
public enum LogRedaction {
    /// Troca por `***` os [secrets] e o que tem cara de credencial ou de servidor; os IPs e os MACs por `ipN`/`macN`.
    public static func redact(_ text: String, secrets: [String] = []) -> String {
        let p = Patterns()
        var out = text
        var done = Set<String>()
        for secret in secrets.filter({ $0.utf16.count >= 3 }).sorted(by: { $0.utf16.count > $1.utf16.count }) {
            guard done.insert(secret).inserted else { continue }
            out = out.replacingOccurrences(of: secret, with: "***")
        }
        // Os links podem ter credenciais em qualquer parte do caminho ou do servidor: sai o URL inteiro, menos o IP e a
        // porta de uma TV (que levam o nome no fim, como os outros IPs).
        out = replace(p.url, in: out) { g in
            let scheme = g[1] ?? ""
            guard let lan = groups(p.lanURL, in: g[0] ?? "") else { return "\(scheme)://***" }
            let ip = lan[1] ?? ""
            let port = lan[2] ?? ""
            let rest = (lan[3] ?? "").isEmpty ? "" : "/***"
            return scheme + "://" + ip + port + rest
        }
        out = replace(p.query, in: out) { g in "\(g[1] ?? "")=***" }
        out = replace(p.xtreamPath, in: out) { g in "/\(g[1] ?? "")/***/***/" }
        out = replace(p.stalkerPath, in: out) { _ in "/stalker/***/***/" }
        out = replace(p.userInfo, in: out) { g in "\(g[1] ?? "")***@" }
        out = replace(p.auth, in: out) { g in "\(g[1] ?? "") ***" }
        // O email antes dos servidores, senão ficava `nome@***`.
        out = replace(p.email, in: out) { _ in "***" }
        out = replace(p.host, in: out) { g in
            let name = g[0] ?? ""
            return looksLikeCode(name) ? name : "***"
        }
        // Por fim os MACs e os IPs, numa só passagem, para os nomes irem pela ordem em que aparecem.
        var names: [String: String] = [:]
        var ips = 0
        var macs = 0
        out = replace(p.address, in: out) { g in
            let value = g[0] ?? ""
            if let mac = g[1] {
                let key = "mac " + mac.lowercased().replacingOccurrences(of: "%3a", with: ":")
                if let name = names[key] { return name }
                macs += 1
                names[key] = "mac\(macs)"
                return "mac\(macs)"
            }
            // Um `::` sozinho (Swift, C++) não é endereço.
            if !value.contains(where: { $0.isLetter || $0.isNumber }) { return value }
            // O mesmo IPv6 com ou sem a interface (`fe80::1%en0`) é o mesmo aparelho.
            let address = value.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).first.map { String($0) } ?? value
            let key = "ip " + address.lowercased()
            if let name = names[key] { return name }
            ips += 1
            names[key] = "ip\(ips)"
            return "ip\(ips)"
        }
        return out
    }

    /// Um nome com pontos que é código, um ficheiro ou um pacote (fica, para o relatório servir) e não um servidor. Na
    /// dúvida, é servidor. Os tipos de serviço da procura (`_androidtvremote2._tcp.local`) também ficam.
    private static func looksLikeCode(_ name: String) -> Bool {
        let labels = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let last = (labels.last ?? "").lowercased()
        if fileEndings.contains(last) { return true }
        if labels.count >= 3 && packageRoots.contains(labels[0]) { return true }
        if labels.contains(where: { $0.hasPrefix("_") }) { return true }
        if last.utf16.count == 2 || commonTLDs.contains(last) || name.contains("-") { return false }
        return name.contains(where: { $0.isUppercase }) || codeRoots.contains(labels[0])
            || (labels.count > 1 && codeRoots.contains("\(labels[0]).\(labels[1])"))
    }

    /// Troca cada ocorrência de [pattern] pelo que [replacement] dá com os grupos (o 0 é tudo; nil se não entrou).
    private static func replace(_ pattern: NSRegularExpression, in text: String, _ replacement: ([String?]) -> String) -> String {
        let ns = NSString(string: text)
        var out = ""
        var last = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            out += replacement(captures(match, ns))
            last = match.range.location + match.range.length
        }
        return out + ns.substring(from: last)
    }

    /// Os grupos de [pattern] se apanhar [text] inteiro.
    private static func groups(_ pattern: NSRegularExpression, in text: String) -> [String?]? {
        let ns = NSString(string: text)
        guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.range.location == 0, match.range.length == ns.length else { return nil }
        return captures(match, ns)
    }

    private static func captures(_ match: NSTextCheckingResult, _ ns: NSString) -> [String?] {
        (0..<match.numberOfRanges).map { i in
            let r = match.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    private static let h = "[0-9A-Fa-f]{1,4}"
    private static let v4 = #"\d{1,3}(?:\.\d{1,3}){3}"#
    /// Os IPv6 inteiros (8 grupos) ou com `::`, também com um IPv4 no fim (`::ffff:1.2.3.4`) e com a interface
    /// (`fe80::1%en0`). Uma hora (`01:12:03`) não tem `::` nem 8 grupos, por isso fica.
    private static let ipv6 = "(?<![A-Za-z0-9_:.%])(?:"
        + "(?:(?:\(h):){6}|(?:\(h)(?::\(h)){0,5})?::(?:\(h):){0,5})\(v4)" + #"(?![A-Za-z0-9_]|\.\d)"#
        + "|(?:(?:\(h):){7}\(h)|(?:\(h)(?::\(h)){0,6})?::(?:\(h)(?::\(h)){0,6})?)" + #"(?:%[A-Za-z0-9_.-]+|(?![A-Za-z0-9_:%]|\.\d))"#
        + ")"
    private static let ipv4 = "(?<![A-Za-z0-9_.])\(v4)(?![A-Za-z0-9_.])"

    /// Compilados a cada relatório (são poucos e o registo é curto), para não haver estado partilhado entre threads.
    private struct Patterns {
        let url = redactionPattern(#"\b([a-zA-Z][a-zA-Z0-9+.-]*)://[^\s"'<>]+"#)
        /// Um URL para um IP (o de uma TV): o IP (com os parênteses retos do IPv6), a porta e o resto (caminho, `)`…).
        let lanURL = redactionPattern(#"^[a-zA-Z][a-zA-Z0-9+.-]*://(?:[^/\s@]*@)?("# + LogRedaction.v4 + #"|\[[0-9A-Fa-f:.]+(?:%[A-Za-z0-9_.-]+)?\])(:\d{1,5})?((?:[^A-Za-z0-9.:%-]).*)?$"#)
        let query = redactionPattern(#"(?i)\b(password|passwd|pass|pwd|username|user|token|access_token|auth|key|api_key|apikey|secret|mac|sn|device_id|device_id2|signature|play_token)=([^&\s"']+)"#)
        let xtreamPath = redactionPattern(#"/(live|movie|series|timeshift)/[^/\s]+/[^/\s]+/"#)
        let stalkerPath = redactionPattern(#"/stalker/[^/\s]+/[^/\s]+/"#)
        let userInfo = redactionPattern(#"([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s@]+@"#)
        let auth = redactionPattern(#"(?i)(authorization:?|bearer)\s+(?:(?:bearer|basic|token)\s+)?[^\s,]+"#)
        let email = redactionPattern(#"(?<![A-Za-z0-9_.+-])[A-Za-z0-9_.+-]+@(?:[A-Za-z0-9-]+\.)+[A-Za-z][A-Za-z0-9-]+"#)
        let host = redactionPattern(#"(?<![A-Za-z0-9_.-])(?:[A-Za-z0-9_-]+\.)+[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9](?![A-Za-z0-9_-])"#)
        /// Um MAC (no grupo 1), um IPv6 ou um IPv4.
        let address = redactionPattern(#"(?<![A-Za-z0-9_])((?i:[0-9a-f]{2}(?:(?::|%3A)[0-9a-f]{2}){5}))(?![A-Za-z0-9_])|"# + LogRedaction.ipv6 + "|" + LogRedaction.ipv4)
    }

    private static let fileEndings: Set<String> = ["kt", "java", "swift", "cpp", "dex", "jar", "apk", "ipa", "dylib", "xml", "json", "png", "jpg", "webp", "gz", "ts", "m3u", "m3u8", "mp4", "mkv", "php", "html", "js", "css", "txt", "log"]
    private static let commonTLDs: Set<String> = ["com", "net", "org", "info", "biz", "xyz", "top", "site", "online", "club", "live", "pro", "stream", "app", "dev", "tech", "store", "shop", "cloud", "link", "icu", "vip", "fun", "space", "website", "one", "world", "today", "media", "example", "invalid", "test", "local", "lan"]
    private static let codeRoots: Set<String> = ["java", "javax", "kotlin", "kotlinx", "android", "androidx", "dalvik", "libcore", "sun", "okhttp3", "okio", "retrofit2", "coil", "coil3", "com.android", "com.google", "com.squareup", "com.apple", "org.videolan", "org.json", "cc.slokker"]
    /// Os começos dos pacotes das apps (`com.netflix.ninja`), que um servidor quase nunca tem.
    private static let packageRoots: Set<String> = ["com", "org", "net", "io"]
}

/// Os padrões são fixos: se um não compilar, é erro de quem o escreveu (os testes apanham-no logo).
private func redactionPattern(_ pattern: String) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern)
}
