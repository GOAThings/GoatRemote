import Foundation

/// Uma app instalada na TV, como o GoatLauncher a dá.
public struct TVApp: Decodable, Identifiable, Hashable, Sendable {
    public let package: String
    public let label: String
    /// Tem banner de TV (16:9); senão é um ícone sobre a [color].
    public let banner: Bool
    public let color: String?

    public init(package: String, label: String, banner: Bool, color: String?) {
        self.package = package
        self.label = label
        self.banner = banner
        self.color = color
    }

    public var id: String { package }
    public var link: String { "market://launch?id=\(package)" }
}

/// Um elemento de uma lista que, se não se ler, fica nil em vez de estragar a lista toda.
public struct Lenient<T: Decodable>: Decodable {
    public let value: T?

    public init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// O que o GoatLauncher da TV dá na porta 6470 (GoatLauncher data/PhoneRoutes.kt; contracts/launcher-6470). O mesmo
/// que o Android faz (data/LauncherApps.kt).
public enum LauncherApps {
    public static let port = 6470
    /// GET /apps: mais do que isto não é o GoatLauncher.
    public static let maxBytes = 2 << 20

    /// Lê a resposta de /apps. O que não for uma lista dá erro; uma app mal descrita fica de fora e as outras contam.
    public static func parse(_ data: Data) throws -> [TVApp] {
        let list = try JSONDecoder().decode([Lenient<TVApp>].self, from: data)
        var seen = Set<String>()
        return list.compactMap(\.value).filter { seen.insert($0.package).inserted }
    }

    /// POST /open/<pacote>: tudo menos 200 (o 409 é o launcher sem o serviço de acessibilidade) abre pelo link do comando.
    public static func openFallsBack(status: Int) -> Bool { status != 200 }
}
