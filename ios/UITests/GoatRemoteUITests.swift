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
        for id in ["key:up", "key:down", "key:left", "key:right", "key:center", "key:volumeUp", "key:mute", "key:back", "key:home", "key:playPause"] {
            app.buttons[id].tap()
            pause(0.35)
        }
        app.buttons["key:center"].press(forDuration: 1.2)
        pause(0.5)
        shot("after-keys")

        app.buttons["mode"].tap()
        let pad = app.descendants(matching: .any)["touchpad"]
        XCTAssertTrue(pad.waitForExistence(timeout: 5))
        pad.swipeUp()
        pad.tap()
        pause(0.5)
        shot("touchpad")
        app.buttons["mode"].tap()

        app.buttons["keyboard"].tap()
        let keyboard = app.textFields["keyboard-field"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        keyboard.typeText("hello")
        pause(0.5)
        shot("keyboard")
        app.buttons["Send"].tap()
        pause(0.5)

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
        for expected in ["emparelhado", "tecla DPAD_UP", "tecla DPAD_CENTER (início)", "tecla DPAD_CENTER (fim)", "tecla VOLUME_UP",
                         "tecla MEDIA_PLAY_PAUSE", "texto hello", "tecla 66", "abrir market://launch?id=com.google.android.youtube.tv"] {
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
