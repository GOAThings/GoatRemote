import Foundation

/// Um canal do GoatTV, como ele o dá na rede de casa (porta 6471).
public struct TVChannel: Equatable, Identifiable, Sendable {
    public let key: String
    public let num: Int?
    public let name: String
    public let group: String?
    public let logo: Bool
    public let favorite: Bool

    public var id: String { key }

    public init(key: String, num: Int?, name: String, group: String?, logo: Bool, favorite: Bool) {
        self.key = key
        self.num = num
        self.name = name
        self.group = group
        self.logo = logo
        self.favorite = favorite
    }
}

public struct ChannelGroup: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
}

/// A lista ativa do GoatTV: grupos e canais pela ordem dele, e o canal que está a dar.
public struct ChannelList: Equatable, Sendable {
    public var playlist: String?
    public var current: String?
    public var groups: [ChannelGroup]
    public var channels: [TVChannel]
    /// A lista não veio toda (cortada pelo GoatTV, ou aqui, acima do limite de canais).
    public var truncated: Bool
}

/// Um programa do guia do GoatTV (horas em ms).
public struct Programme: Equatable, Sendable {
    public let title: String
    public let startMs: Int64
    public let endMs: Int64

    public init(title: String, startMs: Int64, endMs: Int64) {
        self.title = title
        self.startMs = startMs
        self.endMs = endMs
    }

    public func progress(now: Int64) -> Double { min(max(Double(now - startMs) / Double(endMs - startMs), 0), 1) }
}

/// O que o GoatTV está a dar (GET /now): o canal e, se ele tiver guia, o programa e o seguinte.
public struct NowInfo: Equatable, Sendable {
    public let current: String?
    public let now: Programme?
    public let next: Programme?

    public init(current: String?, now: Programme?, next: Programme?) {
        self.current = current
        self.now = now
        self.next = next
    }
}

/// Os canais do GoatTV na TV (GET /channels, GET /now, GET /logo/<key>, POST /play/<key>). O mesmo que o Android faz.
public enum GoatTVChannels {
    public static let port = 6471
    /// O GoatTV numa Android TV (abre-se pelo GoatLauncher).
    public static let androidPackage = "cc.slokker.itv"
    /// O GoatTV na Apple TV; quem assina a IPA pode mudar o bundle id, por isso também se procura pelo nome.
    public static let appleBundle = "cc.slokker.goattv"
    public static let maxBytes = 8 << 20
    public static let maxLogoBytes = 1 << 20
    /// Os logótipos mostram-se pequenos: reduzem-se mais do que os banners.
    public static let logoSide = 256
    public static let maxChannels = 50_000
    public static let maxGroups = 5_000
    public static let maxKey = 1024
    public static let maxName = 200
    public static let maxNum = 999_999
    /// O /now é pequeno: mais do que isto não é o GoatTV.
    public static let maxNowBytes = 64 << 10
    public static let maxTitle = 300

    public enum Play: Equatable, Sendable {
        case done
        /// Canal desconhecido, escondido ou bloqueado.
        case notFound
        /// O GoatTV não está à frente (ou ainda não carregou): abre-se e tenta-se outra vez.
        case retry
        case failed
    }

    public static func playOutcome(status: Int, refused: Bool) -> Play {
        if status == 200 { return .done }
        if status == 404 { return .notFound }
        if status == 409 || status == 503 || refused { return .retry }
        return .failed
    }

    /// O caminho de um pedido: a chave vai codificada (tudo menos letras e algarismos ASCII, "-", "_" e "~").
    public static func url(host: String, _ what: String, key: String? = nil) -> String {
        LanURL.string(host: host, port: port, path: what + (key.map { "/" + encodeKey($0) } ?? ""))
    }

    public static func encodeKey(_ key: String) -> String {
        let hex = Array("0123456789ABCDEF")
        var out = ""
        for byte in key.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "~"):
                out.unicodeScalars.append(Unicode.Scalar(byte))
            default:
                out.append("%")
                out.append(hex[Int(byte >> 4)])
                out.append(hex[Int(byte & 0x0F)])
            }
        }
        return out
    }

    /// O GoatTV na lista de apps da Apple TV (bundle id → nome): pelo bundle id, ou pelo nome se a IPA foi assinada
    /// com outro. nil se não estiver lá.
    public static func appleApp(_ apps: [String: String]) -> String? {
        if apps[appleBundle] != nil { return appleBundle }
        // Por ordem, para que a escolha não dependa da ordem do dicionário.
        return apps.filter { $0.value.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("GoatTV") == .orderedSame }
            .keys.sorted().first
    }

    /// Lê a resposta de /channels. O que não for um objeto dá erro; um canal ou grupo estragado só fica de fora. Chaves
    /// repetidas ficam só a primeira vez (a lista usa-as como identificador).
    public static func parse(_ data: Data) throws -> ChannelList {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        var groups: [ChannelGroup] = []
        var groupIDs = Set<String>()
        for item in raw.groups ?? [] {
            guard groups.count < maxGroups else { break }
            guard let g = item.value, !g.id.isEmpty, g.id.count <= maxKey, groupIDs.insert(g.id).inserted else { continue }
            groups.append(ChannelGroup(id: g.id, name: String(g.name.prefix(maxName))))
        }
        var channels: [TVChannel] = []
        var keys = Set<String>()
        var truncated = raw.truncated ?? false
        for item in raw.channels ?? [] {
            guard let c = item.value, !c.key.isEmpty, c.key.count <= maxKey, !keys.contains(c.key) else { continue }
            guard channels.count < maxChannels else {
                truncated = true
                break
            }
            keys.insert(c.key)
            let num = c.num.flatMap { $0 >= 0 && $0 <= Double(maxNum) && $0 == $0.rounded(.down) ? Int($0) : nil }
            let group = c.group.flatMap { !$0.isEmpty && $0.count <= maxKey ? $0 : nil }
            channels.append(TVChannel(key: c.key, num: num, name: String(c.name.prefix(maxName)), group: group,
                                      logo: c.logo, favorite: c.favorite))
        }
        return ChannelList(playlist: raw.playlist?.name.map { String($0.prefix(maxName)) },
                           current: raw.current.flatMap { keys.contains($0) ? $0 : nil },
                           groups: groups, channels: channels, truncated: truncated)
    }

    /// Lê a resposta de /now. O que não for um objeto dá erro; um programa estragado (sem título, horas trocadas) fica nil.
    public static func parseNow(_ data: Data) throws -> NowInfo {
        let raw = try JSONDecoder().decode(RawNow.self, from: data)
        func programme(_ p: RawProgramme?) -> Programme? {
            guard let p, let title = p.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let start = p.start, let end = p.end, end > start else { return nil }
            return Programme(title: String(title.prefix(maxTitle)), startMs: Int64(start), endMs: Int64(end))
        }
        let current = raw.current.flatMap { !$0.isEmpty && $0.count <= maxKey ? $0 : nil }
        return NowInfo(current: current, now: programme(raw.now), next: programme(raw.next))
    }

    private struct RawNow: Decodable {
        let current: String?
        let now: RawProgramme?
        let next: RawProgramme?

        enum CodingKeys: String, CodingKey { case current, now, next }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            current = try? c.decodeIfPresent(String.self, forKey: .current)
            now = try? c.decodeIfPresent(RawProgramme.self, forKey: .now)
            next = try? c.decodeIfPresent(RawProgramme.self, forKey: .next)
        }
    }

    private struct RawProgramme: Decodable {
        let title: String?
        let start: Double?
        let end: Double?

        enum CodingKeys: String, CodingKey { case title, start, end }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try? c.decodeIfPresent(String.self, forKey: .title)
            // Fora do que um Int64 guarda não é uma hora.
            start = (try? c.decodeIfPresent(Double.self, forKey: .start)).flatMap { abs($0) < 9e15 ? $0 : nil }
            end = (try? c.decodeIfPresent(Double.self, forKey: .end)).flatMap { abs($0) < 9e15 ? $0 : nil }
        }
    }

    // O JSON tal como vem: os campos com o tipo errado ficam como se não viessem.
    private struct Raw: Decodable {
        let playlist: RawPlaylist?
        let current: String?
        let groups: [Lossy<RawGroup>]?
        let channels: [Lossy<RawChannel>]?
        let truncated: Bool?

        enum CodingKeys: String, CodingKey { case playlist, current, groups, channels, truncated }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            playlist = try? c.decodeIfPresent(RawPlaylist.self, forKey: .playlist)
            current = try? c.decodeIfPresent(String.self, forKey: .current)
            groups = try? c.decodeIfPresent([Lossy<RawGroup>].self, forKey: .groups)
            channels = try? c.decodeIfPresent([Lossy<RawChannel>].self, forKey: .channels)
            truncated = try? c.decodeIfPresent(Bool.self, forKey: .truncated)
        }
    }

    private struct RawPlaylist: Decodable {
        let name: String?

        enum CodingKeys: String, CodingKey { case name }

        init(from decoder: Decoder) throws {
            name = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .name)
        }
    }

    private struct RawGroup: Decodable {
        let id: String
        let name: String
    }

    private struct RawChannel: Decodable {
        let key: String
        let name: String
        let num: Double?
        let group: String?
        let logo: Bool
        let favorite: Bool

        enum CodingKeys: String, CodingKey { case key, name, num, group, logo, favorite }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decode(String.self, forKey: .key)
            name = try c.decode(String.self, forKey: .name)
            num = try? c.decodeIfPresent(Double.self, forKey: .num)
            group = try? c.decodeIfPresent(String.self, forKey: .group)
            logo = (try? c.decodeIfPresent(Bool.self, forKey: .logo)) == true
            favorite = (try? c.decodeIfPresent(Bool.self, forKey: .favorite)) == true
        }
    }

    /// Um elemento que não se lê fica nil, em vez de estragar a lista inteira.
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?

        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }
}
