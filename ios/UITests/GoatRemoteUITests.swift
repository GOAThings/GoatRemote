import XCTest

/// Emparelha com a TV falsa (tools/AtvTool.java, anunciada como "Fake TV") e usa o comando, com um screenshot a cada
/// passo. No fim confere no registo da TV falsa (http://127.0.0.1:7000/log) que as teclas, o texto e a app chegaram.
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
        let tv = app.buttons["found:Fake TV"]
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

        // Ligar as setas nas bordas (em Mais) e fechar a folha.
        app.buttons["more"].tap()
        let dpadSwitch = app.switches["opt:dpad"]
        XCTAssertTrue(dpadSwitch.waitForExistence(timeout: 5))
        dpadSwitch.switches.firstMatch.tap()
        pause(0.4)
        shot("options")
        app.swipeDown(velocity: .fast)
        pause(0.8)

        // Setas nas bordas: tocar em cima e à direita.
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        pause(0.4)
        shot("dpad")

        app.buttons["apps"].tap()
        let youtube = app.buttons["app:YouTube"]
        XCTAssertTrue(youtube.waitForExistence(timeout: 5))
        shot("apps")
        youtube.tap()
        pause(1.5)
        shot("after-app")

        // O que a TV falsa recebeu.
        let log = fetch("log") ?? ""
        let attachment = XCTAttachment(string: log)
        attachment.name = "fake-tv-log"
        attachment.lifetime = .keepAlways
        add(attachment)
        for expected in ["emparelhado", "tecla DPAD_CENTER", "tecla DPAD_UP", "tecla DPAD_DOWN", "tecla DPAD_LEFT", "tecla DPAD_RIGHT",
                         "tecla DPAD_CENTER (início)", "tecla DPAD_CENTER (fim)", "tecla MEDIA_PLAY_PAUSE", "tecla BACK", "tecla HOME",
                         "tecla MUTE", "tecla VOLUME_UP", "tecla SEARCH", "texto hello", "tecla 66",
                         "abrir market://launch?id=com.google.android.youtube.tv"] {
            XCTAssertTrue(log.contains(expected), "Falta no registo da TV: \(expected)")
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
