import Foundation

/// As teclas que se mandam (os códigos do Android, KeyEvent.KEYCODE_*).
public enum Key: Int, CaseIterable, Sendable {
    case home = 3, back = 4
    case num0 = 7, num1, num2, num3, num4, num5, num6, num7, num8, num9
    case up = 19, down = 20, left = 21, right = 22, center = 23
    case volumeUp = 24, volumeDown = 25, power = 26
    case enter = 66, delete = 67
    case menu = 82, search = 84
    case playPause = 85, stop = 86, next = 87, previous = 88, rewind = 89, fastForward = 90
    case mute = 164, info = 165, channelUp = 166, channelDown = 167, guide = 172
    case captions = 175, settings = 176, input = 178
    case audioTrack = 222, lastChannel = 229
}

/// Carregar e largar, ou carregar e manter (início e fim do toque longo).
public enum KeyDirection: Int, Sendable {
    case startLong = 1, endLong = 2, short = 3
}

/// O que a TV conta: ligada ou não, volume, app aberta.
public struct TVState: Equatable, Sendable {
    public var isOn: Bool?
    public var volume: Int?
    public var maxVolume: Int?
    public var muted: Bool?
    /// Se dá para mudar o volume (a Apple TV só consegue com HDMI-CEC ou colunas dela; por infravermelhos é o
    /// comando físico que fala com a TV).
    public var volumeControl = true
    public var currentApp: String?
    public var model: String?
    public var vendor: String?
    /// Sobe cada vez que a TV abre uma caixa de texto (o iPhone mostra o teclado).
    public var keyboardRequests = 0
    /// O que a caixa de texto já tem e o nome dela (ex.: "Pesquisar").
    public var textValue = ""
    public var textLabel: String?

    public init() {}
}

/// O comando (porta 6466), sem a ligação: recebe as mensagens da TV, devolve as respostas e guarda o estado.
///
/// RemoteMessage: remote_configure 1 {code1 1, device_info 2 {model 1, vendor 2, unknown1 3, unknown2 4,
/// package_name 5, app_version 6}}, remote_set_active 2 {active 1}, remote_error 3, remote_ping_request 8 {val1 1},
/// remote_ping_response 9 {val1 1}, remote_key_inject 10 {key_code 1, direction 2}, remote_ime_key_inject 20
/// {app_info 1 {app_package 12}}, remote_ime_show_request 22 {remote_text_field_status 2 {value 2, label 6}},
/// remote_ime_batch_edit 21 {ime_counter 1, field_counter 2, edit_info 3 {insert 1,
/// text_field_status 2 {start 1, end 2, value 3}}}, remote_start 40 {started 1}, remote_set_volume_level 50
/// {player_model 3, volume_max 6, volume_level 7, volume_muted 8}, remote_app_link_launch_request 90 {app_link 1}.
public struct RemoteProtocol: Sendable {
    public static let port: UInt16 = 6466
    /// PING, KEY, IME, POWER, VOLUME, APP_LINK.
    public static let features = 1 | 2 | 4 | 32 | 64 | 512

    public private(set) var state = TVState()
    /// Já se pode mandar teclas (a TV mandou set_active e respondemos).
    public private(set) var ready = false
    private var imeCounter = 0
    /// As funções que a TV aceita e nós também (a resposta ao configure e ao set_active).
    private var active = RemoteProtocol.features
    private var fieldCounter = 0
    /// O que a caixa de texto da TV tem, segundo nós (o que lá estava mais o que já escrevemos).
    private var typed = ""
    private let model: String
    private let appVersion: String

    public init(model: String, appVersion: String) {
        self.model = model
        self.appVersion = appVersion
    }

    /// Trata uma mensagem da TV; devolve o que há a responder.
    public mutating func handle(_ frame: [UInt8]) throws -> [Data] {
        let m = try ProtoMessage(frame)
        if m.has(1) {
            let configure = m.message(1)
            let info = configure.message(2)
            state.model = info.string(1).isEmpty ? nil : info.string(1)
            state.vendor = info.string(2).isEmpty ? nil : info.string(2)
            active = Self.features & configure.int(1)
            let device = Proto().string(1, model).string(2, "Apple").varint(3, 1).string(4, "1")
                .string(5, "cc.slokker.goatremote").string(6, appVersion)
            return [Frame.encode(Proto().message(1, Proto().varint(1, active).message(2, device)))]
        }
        if m.has(2) {
            ready = true
            return [Frame.encode(Proto().message(2, Proto().varint(1, active)))]
        }
        if m.has(8) {
            return [Frame.encode(Proto().message(9, Proto().varint(1, m.message(8).int(1))))]
        }
        if m.has(40) {
            state.isOn = m.message(40).bool(1)
        } else if m.has(50) {
            let v = m.message(50)
            state.maxVolume = v.int(6)
            state.volume = v.int(7)
            state.muted = v.bool(8)
        } else if m.has(20) {
            let app = m.message(20).message(1).string(12)
            if !app.isEmpty { state.currentApp = app }
        } else if m.has(21) {
            let edit = m.message(21)
            imeCounter = edit.int(1)
            fieldCounter = edit.int(2)
        } else if m.has(22) {
            let field = m.message(22).message(2)
            state.textValue = field.string(2)
            typed = state.textValue
            state.textLabel = field.string(6).isEmpty ? nil : field.string(6)
            state.keyboardRequests += 1
        } else if m.has(3) {
            throw ProtocolError.unexpected("a TV mandou um erro")
        }
        return []
    }

    public func key(_ key: Key, _ direction: KeyDirection = .short) -> Data {
        keyCode(key.rawValue, direction)
    }

    public func keyCode(_ code: Int, _ direction: KeyDirection = .short) -> Data {
        Frame.encode(Proto().message(10, Proto().varint(1, code).varint(2, direction.rawValue)))
    }

    /// Põe [text] no campo de texto aberto na TV. A TV não substitui o campo: insere o que recebe no cursor.
    /// Por isso manda-se só a diferença para o que já lá está: Apagar por cada letra a menos, e o texto novo.
    public mutating func text(_ text: String) -> Data {
        let old = Array(typed.unicodeScalars), new = Array(text.unicodeScalars)
        var same = 0
        while same < old.count, same < new.count, old[same] == new[same] { same += 1 }
        typed = text
        var frames = Data()
        for _ in same..<old.count { frames += key(.delete) }
        if same < new.count { frames += insert(String(String.UnicodeScalarView(new[same...]))) }
        return frames
    }

    private func insert(_ text: String) -> Data {
        // O cursor no fim (em caracteres Unicode, como o cliente de referência).
        let end = max(text.unicodeScalars.count - 1, 0)
        let status = Proto().varint(1, end).varint(2, end).string(3, text)
        let edit = Proto().varint(1, imeCounter).varint(2, fieldCounter).message(3, Proto().varint(1, 1).message(2, status))
        return Frame.encode(Proto().message(21, edit))
    }

    /// Abre uma app por link (ex.: https://www.youtube.com, market://launch?id=…).
    public func appLink(_ link: String) -> Data {
        Frame.encode(Proto().message(90, Proto().string(1, link)))
    }
}

/// Como as TVs se anunciam na rede (Bonjour).
public enum Discovery {
    public static let serviceType = "_androidtvremote2._tcp"
}
