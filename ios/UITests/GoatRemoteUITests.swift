import XCTest

/// Emparelha com a TV falsa (tools/AtvTool.java, anunciada como "Living Room TV") e usa o comando, com um screenshot a cada
/// passo. No fim confere no registo da TV falsa (http://127.0.0.1:7000/log) que as teclas, o texto e a app chegaram, e
/// que o canal mudou.
final class GoatRemoteUITests: XCTestCase {
    private let app = XCUIApplication()
    private var step = 0

    override func setUp() {
        continueAfterFailure = true
        app.launchArguments = ["-UITestReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    func testPairAndControl() throws {
        addUIInterruptionMonitor(withDescription: "Rede local") { alert in
            for title in ["Allow", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        app.launch()

        // Encontrar e emparelhar.
        let tv = app.buttons["found:Living Room TV"]
        XCTAssertTrue(tv.waitForExistence(timeout: 30), "A TV falsa não apareceu na lista")
        shot("discover")
        tv.tap()
        app.swipeUp() // dá ao monitor do alerta da rede local a vez de atuar, se aparecer
        let field = app.textFields["code-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "Não chegou a pedir o código")
        shot("code")
        let code = waitFor("code", timeout: 15)
        XCTAssertEqual(code.count, 6, "A TV falsa não mostrou código")
        field.typeText(code)

        // O comando.
        let status = app.descendants(matching: .any)["status"]
        XCTAssertTrue(status.waitForExistence(timeout: 20), "Não ligou ao comando")
        pause(1)
        shot("remote")

        // A superfície: tocar, deslizar nos quatro sentidos, manter.
        let pad = app.descendants(matching: .any)["touchpad"]
        pad.tap()
        pause(0.4)
        pad.swipeUp()
        pad.swipeDown()
        pad.swipeLeft()
        pad.swipeRight()
        pad.press(forDuration: 1.2)
        pause(0.4)

        // Os botões.
        for id in ["key:playPause", "key:back", "key:home", "key:mute"] {
            app.buttons[id].tap()
            pause(0.35)
        }
        pause(0.3)
        shot("volume")

        // Mais: volume, setas nas bordas e pesquisa (a TV pede o teclado sozinha).
        app.buttons["more"].tap()
        let volumeUp = app.buttons["key:volumeUp"]
        XCTAssertTrue(volumeUp.waitForExistence(timeout: 5))
        volumeUp.tap()
        pause(0.5)
        shot("more")
        app.buttons["key:search"].tap()
        let keyboard = app.textFields["keyboard-field"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), "O teclado não apareceu quando a TV o pediu")
        keyboard.typeText("hello")
        pause(0.5)
        shot("keyboard")
        app.buttons["send-text"].tap()
        pause(0.8)

        // As setas: em cima e à direita, e de volta à superfície de toque.
        app.buttons["layout:dpad"].tap()
        let dpad = app.descendants(matching: .any)["dpad"]
        XCTAssertTrue(dpad.waitForExistence(timeout: 5), "As setas não apareceram")
        dpad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        dpad.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        pause(0.4)
        shot("dpad")
        app.buttons["layout:touch"].tap()
        pause(0.4)

        app.buttons["apps"].tap()
        // A lista vem do "GoatLauncher" da TV falsa (porta 6470): também tem apps que o comando nunca viu abertas.
        let youtube = app.buttons["app:YouTube"].firstMatch
        XCTAssertTrue(youtube.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["app:Kodi"].firstMatch.waitForExistence(timeout: 5), "A lista do GoatLauncher não apareceu")
        // Os banners: a TV falsa desenha-os na hora (o primeiro demora uns segundos).
        _ = app.images["banner"].firstMatch.waitForExistence(timeout: 10)
        pause(1)
        shot("apps")
        youtube.tap()
        pause(1.5)
        shot("after-app")

        // Os canais vêm do "GoatTV" da TV falsa (porta 6471). O primeiro /play dá 409: abre-se o GoatTV pelo launcher e
        // tenta-se outra vez. A chave do canal ("news 24/hd") vai codificada no caminho.
        let channelsKey = app.buttons["channels"]
        XCTAssertTrue(channelsKey.waitForExistence(timeout: 10), "O botão dos canais não apareceu")
        channelsKey.tap()
        XCTAssertTrue(app.buttons["channel:RTP 1"].firstMatch.waitForExistence(timeout: 8), "A lista do GoatTV não apareceu")
        app.swipeUp() // a folha abre a meio: assim cabe a lista toda
        pause(1)
        shot("channels")
        let news = app.buttons["group:News"]
        XCTAssertTrue(news.waitForExistence(timeout: 5))
        news.tap()
        let channel = app.buttons["channel:News 24"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 5))
        channel.tap()
        // Espera pela segunda tentativa (a seguir a abrir o GoatTV); a folha fica aberta.
        let until = Date().addingTimeInterval(15)
        while Date() < until, !(fetch("log") ?? "").components(separatedBy: "\n").contains("goattv /play/news 24/hd") { pause(0.5) }
        XCTAssertTrue(app.buttons["channel:News 24"].firstMatch.exists, "A folha dos canais fechou-se")
        pause(0.5)
        shot("channel-played")

        // Fechada a folha, o comando mostra o canal do GoatTV, com o programa do /now.
        app.swipeDown()
        pause(0.6)
        if app.buttons["channel:News 24"].firstMatch.exists { app.swipeDown() }
        XCTAssertTrue(app.descendants(matching: .any)["now-card"].waitForExistence(timeout: 10), "O cartão do canal não apareceu")
        pause(1.5)
        shot("now-card")

        // O que a TV falsa recebeu.
        let log = fetch("log") ?? ""
        let attachment = XCTAttachment(string: log)
        attachment.name = "fake-tv-log"
        attachment.lifetime = .keepAlways
        add(attachment)
        for expected in ["emparelhado", "tecla DPAD_CENTER", "tecla DPAD_UP", "tecla DPAD_DOWN", "tecla DPAD_LEFT", "tecla DPAD_RIGHT",
                         "tecla DPAD_CENTER (início)", "tecla DPAD_CENTER (fim)", "tecla MEDIA_PLAY_PAUSE", "tecla BACK", "tecla HOME",
                         "launcher /volume/mute", "launcher /volume/up", "tecla SEARCH", "tecla ENTER",
                         "launcher /open/com.google.android.youtube.tv", "launcher /apps", "launcher /icon/cc.slokker.itv"] {
            XCTAssertTrue(log.contains(expected), "Falta no registo da TV: \(expected)")
        }
        // O texto vai à medida que se escreve (o simulador escreve uma tecla de cada vez): juntas, as partes dão "hello".
        let typed = log.components(separatedBy: "\n").filter { $0.hasPrefix("texto ") }.map { String($0.dropFirst(6)) }.joined()
        XCTAssertEqual(typed, "hello", "O texto que chegou à TV")
        // Linhas inteiras: o primeiro /play deu 409, o launcher abriu o GoatTV e o segundo mudou de canal.
        let lines = log.components(separatedBy: "\n")
        for expected in ["goattv /channels", "goattv /logo/rtp1", "goattv /play/news 24/hd 409", "launcher /open/cc.slokker.itv",
                         "goattv /play/news 24/hd"] {
            XCTAssertTrue(lines.contains(expected), "Falta no registo da TV: \(expected)")
        }
        if let refused = lines.firstIndex(of: "goattv /play/news 24/hd 409"), let opened = lines.firstIndex(of: "launcher /open/cc.slokker.itv"),
           let played = lines.lastIndex(of: "goattv /play/news 24/hd") {
            XCTAssertTrue(refused < opened && opened < played, "O GoatTV não se abriu antes de tentar outra vez")
        }
    }

    // MARK: Ajudas

    private func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    private func shot(_ name: String) {
        step += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "%02d-%@", step, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// http://127.0.0.1:7000/<path> da TV falsa.
    private func fetch(_ path: String) -> String? {
        var result: String?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:7000/\(path)")!) { data, _, _ in
            result = data.map { String(decoding: $0, as: UTF8.self) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 5)
        return result
    }

    private func waitFor(_ path: String, timeout: TimeInterval) -> String {
        let until = Date().addingTimeInterval(timeout)
        while Date() < until {
            if let value = fetch(path)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
            pause(0.5)
        }
        return ""
    }
}
