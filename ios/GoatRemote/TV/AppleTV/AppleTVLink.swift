import CryptoKit
import Foundation
import RemoteCore
import UIKit

/// O que o comando faz a qualquer TV (Android TV ou Apple TV).
protocol TVControl: AnyObject {
    var onState: (@MainActor (TVState) -> Void)? { get set }
    var onClose: (@MainActor () -> Void)? { get set }
    var state: TVState { get }
    func connect() async throws
    func key(_ key: Key, _ direction: KeyDirection)
    func text(_ text: String)
    /// Abre uma app: o pacote (Android) ou o bundle id (Apple TV).
    func openApp(_ id: String)
    func close()
}

extension TVControl {
    func key(_ key: Key) { self.key(key, .short) }
}

extension RemoteLink: TVControl {}

/// Emparelhar com uma Apple TV (a TV mostra um PIN de 4 algarismos).
enum AppleTVPairing {
    enum Failure: Error {
        case wrongPIN
        case tv(String)
        /// A TV recusou com um código de erro do emparelhamento HomeKit (3 = espera, 4 = demasiados aparelhos,
        /// 5 = demasiadas tentativas, 6 = indisponível, 7 = ocupada), e às vezes quantos segundos esperar.
        case refused(code: Int, retryAfter: Int?)
    }

    static func pair(host: String, port: UInt16, name: String, askPIN: () async throws -> String) async throws -> CompanionCredentials {
        let conn = CompanionConnection(host: host, port: port)
        try await conn.open()
        DebugLog.add("Apple pairing: connected to \(host):\(port)")
        defer { conn.close() }
        func pd(_ message: OPACK) throws -> [UInt8: [UInt8]] {
            let tlv = TLV8.decode(message["_pd"]?.data ?? [])
            // Só os tipos e tamanhos: os valores são o sal, as chaves e as provas.
            DebugLog.add("Apple pairing: got \(AppleTVLink.keys(message)) TLV \(tlv.keys.sorted().map { "\($0):\(tlv[$0]!.count)" })")
            if let error = tlv[7]?.first {
                if error == 2 { throw Failure.wrongPIN }
                // RetryDelay (tipo 8): segundos, little-endian.
                let delay = tlv[8].map { $0.reversed().reduce(0) { $0 << 8 | Int($1) } }
                DebugLog.add("Apple pairing: refused, code \(error), retry after \(delay.map(String.init) ?? "-")")
                throw Failure.refused(code: Int(error), retryAfter: delay)
            }
            return tlv
        }
        func send(_ frame: CompanionConnection.Frame, _ tlv: [(UInt8, [UInt8])]) async throws {
            try await conn.send(frame, .dict(["_pd": .data(TLV8.encode(tlv)), "_pwTy": .int(1), "_x": .int(conn.nextXID())]))
        }
        // M1 → M2: o sal e o B; a TV mostra o PIN.
        try await send(.pairSetupStart, [(0, [0]), (6, [1])])
        DebugLog.add("Apple pairing: M1 sent, waiting for the TV to show the PIN")
        let m2 = try pd(try await conn.receive().1)
        guard let salt = m2[2], let serverKey = m2[3] else { throw Failure.tv("M2 sem sal") }
        let pin = try await askPIN()
        DebugLog.add("Apple pairing: PIN entered, sending M3")
        // M3 → M4: as provas do SRP.
        let srp = SRPClient(privateKey: (0..<32).map { _ in UInt8.random(in: 0...255) })
        guard let result = srp.process(salt: salt, serverPublicKey: serverKey, pin: pin) else { throw Failure.tv("B inválido") }
        try await send(.pairSetupNext, [(6, [3]), (3, srp.publicKey), (4, result.proof)])
        let m4 = try pd(try await conn.receive().1)
        guard m4[4] == result.expectedServerProof else { throw Failure.wrongPIN }
        DebugLog.add("Apple pairing: PIN accepted, sending M5")
        // M5 → M6: trocam-se as identidades (Ed25519), cifradas com a chave do SRP.
        let k = result.sessionKey
        let encKey = SymmetricKey(data: SHA512.hkdf(salt: "Pair-Setup-Encrypt-Salt", info: "Pair-Setup-Encrypt-Info", key: k))
        let signing = Curve25519.Signing.PrivateKey()
        let ltpk = Array(signing.publicKey.rawRepresentation)
        let clientID = Array(UUID().uuidString.lowercased().utf8)
        let deviceX = SHA512.hkdf(salt: "Pair-Setup-Controller-Sign-Salt", info: "Pair-Setup-Controller-Sign-Info", key: k)
        let signature = Array(try signing.signature(for: deviceX + clientID + ltpk))
        let sub = TLV8.encode([(1, clientID), (3, ltpk), (10, signature), (0x11, OPACK.dict(["name": .string(name)]).encoded)])
        let box = try ChaChaPoly.seal(sub, using: encKey, nonce: CompanionConnection.pairingNonce("PS-Msg05"))
        try await send(.pairSetupNext, [(6, [5]), (5, Array(box.ciphertext) + Array(box.tag))])
        let m6 = try pd(try await conn.receive().1)
        guard let encrypted = m6[5], encrypted.count > 16 else { throw Failure.tv("M6 sem dados") }
        let opened = try ChaChaPoly.open(ChaChaPoly.SealedBox(nonce: CompanionConnection.pairingNonce("PS-Msg06"),
                                                              ciphertext: encrypted.dropLast(16), tag: encrypted.suffix(16)), using: encKey)
        let tv = TLV8.decode(Array(opened))
        guard let tvID = tv[1], let tvKey = tv[3], let tvSignature = tv[10] else { throw Failure.tv("M6 incompleta") }
        let accessoryX = SHA512.hkdf(salt: "Pair-Setup-Accessory-Sign-Salt", info: "Pair-Setup-Accessory-Sign-Info", key: k)
        guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: tvKey),
              publicKey.isValidSignature(tvSignature, for: accessoryX + tvID + tvKey) else { throw Failure.tv("a assinatura da TV não bate certo") }
        DebugLog.add("Apple pairing: done")
        return CompanionCredentials(tvPublicKey: Data(tvKey), privateKey: signing.rawRepresentation, tvID: Data(tvID), clientID: Data(clientID))
    }
}

/// O comando ligado a uma Apple TV: verifica (com as credenciais guardadas), abre a sessão e manda teclas.
final class AppleTVLink: TVControl, @unchecked Sendable {
    enum Failure: Error {
        case notPaired
    }

    let tv: SavedTV
    var onState: (@MainActor (TVState) -> Void)?
    var onClose: (@MainActor () -> Void)?
    /// A lista de apps da TV (bundle id → nome), quando chega.
    var onApps: (@MainActor ([String: String]) -> Void)?

    private var conn: CompanionConnection?
    private var loop: Task<Void, Never>?
    private let lock = NSLock()
    private var _state = TVState()
    private var pending: [UInt64: CheckedContinuation<OPACK, Error>] = [:]
    /// A sessão de texto aberta na TV (do _tiStart ou do _tiStarted), para onde vai o que se escreve.
    private var textSession: [UInt8]?
    private var typing: Task<Void, Never>?

    init(tv: SavedTV) {
        self.tv = tv
    }

    var state: TVState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    private func update(_ change: (inout TVState) -> Void) {
        lock.lock()
        change(&_state)
        let new = _state
        lock.unlock()
        if let onState { Task { @MainActor in onState(new) } }
    }

    // MARK: Ligar

    func connect() async throws {
        guard let creds = CompanionCredentials.load(tv.id) else { throw Failure.notPaired }
        let conn = CompanionConnection(host: tv.host, port: tv.port ?? 49_153)
        do {
            try await conn.open()
        } catch CompanionConnection.Failure.unreachable(let why) {
            DebugLog.add("Apple TV: can't connect to \(tv.host):\(tv.port ?? 49_153): \(why)")
            throw RemoteLink.Failure.unreachable(why)
        }
        self.conn = conn
        do {
            try await verify(conn, creds)
            DebugLog.add("Apple TV: verified")
        } catch {
            DebugLog.add("Apple TV: verify failed: \(error)")
            conn.close()
            throw Failure.notPaired
        }
        loop = Task { [weak self] in
            while let self, !Task.isCancelled {
                do {
                    let (_, message) = try await conn.receive()
                    self.dispatch(message)
                } catch {
                    break
                }
            }
            self?.failPending()
            if !Task.isCancelled, let onClose = self?.onClose { await onClose() }
        }
        try await startSession(creds)
    }

    /// Verificação (X25519 + as assinaturas Ed25519 do emparelhamento) e chaves da sessão.
    private func verify(_ conn: CompanionConnection, _ creds: CompanionCredentials) async throws {
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let epk = Array(ephemeral.publicKey.rawRepresentation)
        try await conn.send(.pairVerifyStart, .dict(["_pd": .data(TLV8.encode([(6, [1]), (3, epk)])), "_auTy": .int(4), "_x": .int(conn.nextXID())]))
        let m2 = TLV8.decode(try await conn.receive().1["_pd"]?.data ?? [])
        if let error = m2[7]?.first { DebugLog.add("Apple TV: verify refused, code \(error)") }
        guard m2[7] == nil, let tvEph = m2[3], let encrypted = m2[5], encrypted.count > 16 else { throw Failure.notPaired }
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: tvEph))
        let secret = shared.withUnsafeBytes { Array($0) }
        let pvKey = SymmetricKey(data: SHA512.hkdf(salt: "Pair-Verify-Encrypt-Salt", info: "Pair-Verify-Encrypt-Info", key: secret))
        let inner = TLV8.decode(Array(try ChaChaPoly.open(ChaChaPoly.SealedBox(nonce: CompanionConnection.pairingNonce("PV-Msg02"),
                                                                              ciphertext: encrypted.dropLast(16), tag: encrypted.suffix(16)), using: pvKey)))
        guard let id = inner[1], Data(id) == creds.tvID, let signature = inner[10],
              let tvKey = try? Curve25519.Signing.PublicKey(rawRepresentation: creds.tvPublicKey),
              tvKey.isValidSignature(signature, for: tvEph + id + epk) else { throw Failure.notPaired }
        let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: creds.privateKey)
        let clientID = Array(creds.clientID)
        let mySignature = Array(try signing.signature(for: epk + clientID + tvEph))
        let box = try ChaChaPoly.seal(TLV8.encode([(1, clientID), (10, mySignature)]), using: pvKey, nonce: CompanionConnection.pairingNonce("PV-Msg03"))
        try await conn.send(.pairVerifyNext, .dict(["_pd": .data(TLV8.encode([(6, [3]), (5, Array(box.ciphertext) + Array(box.tag))])), "_x": .int(conn.nextXID())]))
        let m4 = TLV8.decode(try await conn.receive().1["_pd"]?.data ?? [])
        if let error = m4[7]?.first { DebugLog.add("Apple TV: verify M4 refused, code \(error)") }
        guard m4[7] == nil else { throw Failure.notPaired }
        conn.encrypt(out: SymmetricKey(data: SHA512.hkdf(salt: "", info: "ClientEncrypt-main", key: secret)),
                     in: SymmetricKey(data: SHA512.hkdf(salt: "", info: "ServerEncrypt-main", key: secret)))
    }

    /// A sequência de arranque (como o pyatv): sistema, toque, sessão, texto e eventos.
    private func startSession(_ creds: CompanionCredentials) async throws {
        _ = try await request("_systemInfo", [
            "_bf": .int(0), "_cf": .int(512), "_clFl": .int(128), "_i": .string(Self.stableID), "_idsID": .data(Array(creds.clientID)),
            "_pubID": .string("AA:BB:CC:DD:EE:FF"), "_sf": .int(256), "_sv": .string("170.18"),
            "model": .string("iPhone"), "name": .string(UIDevice.current.name),
        ])
        _ = try await request("_touchStart", ["_height": .double(1000), "_tFl": .int(0), "_width": .double(1000)])
        _ = try await request("_sessionStart", ["_srvT": .string("com.apple.tvremoteservices"), "_sid": .int(UInt64(UInt32.random(in: 1...UInt32.max)))])
        _ = try? await request("TVRCSessionStart", ["ProtocolVersionKey": .string("1.2")])
        if let ti = try? await request("_tiStart", [:]), let tiD = ti["_tiD"]?.data {
            textStarted(tiD)
        }
        // Até a TV dizer o contrário (no _iMC), não há volume.
        update { $0.volumeControl = false }
        for name in ["_iMC", "SystemStatus", "TVSystemStatus"] {
            try? await event("_interest", ["_regEvents": .array([.string(name)])])
        }
        if let attention = try? await request("FetchAttentionState", [:]), let s = attention["state"]?.int {
            update { $0.isOn = s != 1 }
        } else {
            update { $0.isOn = true }
        }
        update { $0.model = "Apple TV"; $0.vendor = "Apple" }
        Task { [weak self] in
            guard let self, let apps = try? await self.request("FetchLaunchableApplicationsEvent", [:]).dict else { return }
            let list = apps.compactMapValues { $0.string }
            if let onApps = self.onApps { await onApps(list) }
        }
    }

    /// As chaves de uma mensagem, e o erro se a TV mandar um (para o registo de diagnóstico).
    static func keys(_ message: OPACK) -> String {
        let keys = message.dict.map { $0.keys.sorted().joined(separator: ",") } ?? "?"
        return message["_em"]?.string.map { "[\(keys)] error \($0)" } ?? "[\(keys)]"
    }

    /// Um id estável por instalação (sem ele a TV não manda os eventos de ligada/desligada).
    private static var stableID: String {
        if let id = UserDefaults.standard.string(forKey: "companion.id") { return id }
        let id = (0..<6).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        UserDefaults.standard.set(id, forKey: "companion.id")
        return id
    }

    // MARK: Mensagens

    func request(_ id: String, _ content: [String: OPACK], timeout: Double = 5) async throws -> OPACK {
        guard let conn else { throw CompanionConnection.Failure.closed }
        let x = conn.nextXID()
        let message = OPACK.dict(["_i": .string(id), "_t": .int(2), "_c": .dict(content), "_x": .int(x)])
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<OPACK, Error>) in
            lock.lock()
            pending[x] = cont
            lock.unlock()
            Task {
                do {
                    try await conn.send(.opack, message)
                } catch {
                    self.finish(x, .failure(error))
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.finish(x, .failure(CompanionConnection.Failure.timeout(id)))
            }
        }
    }

    func event(_ id: String, _ content: [String: OPACK]) async throws {
        guard let conn else { throw CompanionConnection.Failure.closed }
        try await conn.send(.opack, .dict(["_i": .string(id), "_t": .int(1), "_c": .dict(content), "_x": .int(conn.nextXID())]))
    }

    private func finish(_ x: UInt64, _ result: Result<OPACK, Error>) {
        lock.lock()
        let cont = pending.removeValue(forKey: x)
        lock.unlock()
        cont?.resume(with: result)
    }

    private func failPending() {
        lock.lock()
        let all = pending
        pending = [:]
        lock.unlock()
        for cont in all.values { cont.resume(throwing: CompanionConnection.Failure.closed) }
    }

    private func dispatch(_ message: OPACK) {
        switch message["_t"]?.int {
        case 3:
            guard let x = message["_x"]?.int else { return }
            if let error = message["_em"]?.string {
                DebugLog.add("Apple TV: request \(x) failed: \(error)")
                finish(UInt64(x), .failure(CompanionConnection.Failure.tv(error)))
            } else {
                finish(UInt64(x), .success(message["_c"] ?? .dict([:])))
            }
        case 1:
            handleEvent(message["_i"]?.string ?? "", message["_c"] ?? .dict([:]))
        default:
            break
        }
    }

    private func handleEvent(_ id: String, _ content: OPACK) {
        switch id {
        case "SystemStatus", "TVSystemStatus":
            if let s = content["state"]?.int { update { $0.isOn = s != 1 } }
        case "_tiStarted":
            if let tiD = content["_tiD"]?.data { textStarted(tiD) }
        case "_tiStopped":
            lock.lock()
            textSession = nil
            lock.unlock()
        case "_iMC":
            // Com controlo de volume (0x100), pergunta-se o volume.
            let volume = (content["_mcF"]?.int ?? 0) & 0x100 != 0
            update { $0.volumeControl = volume }
            if volume {
                Task { [weak self] in
                    if let volume = try? await self?.request("_mcc", ["_mcc": .int(5)])["_vol"], case .double(let v) = volume {
                        self?.update { $0.volume = Int((v * 100).rounded()); $0.maxVolume = 100; $0.muted = false }
                    }
                }
            }
        default:
            break
        }
    }

    /// A TV abriu um campo de texto: guarda a sessão e o texto que já lá está, e abre o teclado no telefone.
    private func textStarted(_ tiD: [UInt8]) {
        guard let ti = RTI.state(tiD) else { return }
        lock.lock()
        textSession = ti.session
        lock.unlock()
        update {
            $0.textValue = ti.text
            $0.keyboardRequests += 1
        }
    }

    // MARK: Comandos

    /// As teclas da Apple TV (códigos HID do _hidC).
    private static func hid(_ key: Key) -> Int? {
        switch key {
        case .up: return 1
        case .down: return 2
        case .left: return 3
        case .right: return 4
        case .back: return 5
        case .center: return 6
        case .home: return 7
        case .volumeUp: return 8
        case .volumeDown: return 9
        case .playPause: return 14
        case .channelUp: return 15
        case .channelDown: return 16
        case .guide: return 17
        default: return nil
        }
    }

    func key(_ key: Key, _ direction: KeyDirection) {
        if key == .enter { return submit() }
        Task { [weak self] in
            guard let self else { return }
            switch key {
            case .power:
                // Ligar e desligar mandam só o largar (Wake 13, Sleep 12).
                let on = self.state.isOn != false
                _ = try? await self.request("_hidC", ["_hBtS": .int(2), "_hidC": .int(on ? 12 : 13)])
                self.update { $0.isOn = !on }
            case .rewind, .fastForward:
                _ = try? await self.request("_mcc", ["_mcc": .int(7), "_skpS": .double(key == .rewind ? -10 : 10)])
            case .previous, .next:
                _ = try? await self.request("_mcc", ["_mcc": .int(key == .next ? 3 : 4)])
            case .settings:
                _ = try? await self.request("_launchApp", ["_bundleID": .string("com.apple.TVSettings")])
            case .search:
                _ = try? await self.request("_launchApp", ["_bundleID": .string("com.apple.TVSearch")])
            default:
                guard let code = Self.hid(key) else { return }
                switch direction {
                case .startLong:
                    _ = try? await self.request("_hidC", ["_hBtS": .int(1), "_hidC": .int(UInt64(code))])
                case .endLong:
                    _ = try? await self.request("_hidC", ["_hBtS": .int(2), "_hidC": .int(UInt64(code))])
                case .short:
                    _ = try? await self.request("_hidC", ["_hBtS": .int(1), "_hidC": .int(UInt64(code))])
                    _ = try? await self.request("_hidC", ["_hBtS": .int(2), "_hidC": .int(UInt64(code))])
                }
            }
        }
    }

    /// Substitui o texto do campo aberto na TV: apaga e escreve tudo outra vez.
    func text(_ text: String) {
        typeOnTV { session in
            [RTI.clear(session: session)] + (text.isEmpty ? [] : [RTI.insert(text, session: session)])
        }
    }

    /// O Enter do teclado: uma mudança de linha no campo é o "return" do tvOS (pesquisar, entrar, seguinte).
    private func submit() {
        typeOnTV { session in [RTI.insert("\n", session: session)] }
    }

    /// Manda operações de texto para o campo aberto, uma de cada vez e pela ordem em que se escreveu.
    private func typeOnTV(_ operations: @escaping @Sendable ([UInt8]) -> [[UInt8]]) {
        lock.lock()
        let session = textSession
        lock.unlock()
        guard let session else { return }
        let previous = typing
        typing = Task { [weak self] in
            await previous?.value
            for payload in operations(session) {
                try? await self?.event("_tiC", ["_tiV": .int(1), "_tiD": .data(payload)])
            }
        }
    }

    func openApp(_ id: String) {
        Task { [weak self] in
            let key = id.contains("://") ? "_urlS" : "_bundleID"
            _ = try? await self?.request("_launchApp", [key: .string(id)])
        }
    }

    func close() {
        loop?.cancel()
        guard let conn = self.conn else { return }
        self.conn = nil
        failPending()
        Task {
            // Larga os eventos e o texto (senão a próxima ligação pode ficar sem resposta ao _tiStart).
            try? await conn.send(.opack, .dict(["_i": .string("_interest"), "_t": .int(1), "_x": .int(conn.nextXID()),
                                                "_c": .dict(["_deregEvents": .array([.string("_iMC"), .string("SystemStatus"), .string("TVSystemStatus")])])]))
            try? await conn.send(.opack, .dict(["_i": .string("_tiStop"), "_t": .int(2), "_c": .dict([:]), "_x": .int(conn.nextXID())]))
            try? await Task.sleep(nanoseconds: 300_000_000)
            conn.close()
        }
    }
}
