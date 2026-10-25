package cc.slokker.goatremote

import android.accessibilityservice.AccessibilityService
import android.graphics.Bitmap
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.click
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.swipeRight
import androidx.compose.ui.test.swipeUp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Emparelha com a TV falsa (tools/AtvTool.java, a correr no computador: 10.0.2.2 visto do emulador) pelo IP e usa o
 * comando, com um screenshot a cada passo. No fim confere no registo da TV falsa (porta 7000) que as teclas, o texto
 * e a app chegaram. O mesmo percurso do teste do iPhone.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class RemoteUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<MainActivity>()

    private var step = 0

    @Test
    fun pairAndControl() {
        // Juntar a TV pelo IP e emparelhar com o código que ela mostra.
        rule.waitUntilExactlyOneExists(hasTestTag("manual-ip"), 10_000)
        shot("start")
        rule.onNodeWithTag("manual-ip").performTextInput(HOST)
        rule.onNodeWithTag("pair-ip").performClick()
        rule.waitUntilExactlyOneExists(hasTestTag("code-field"), 20_000)
        shot("code")
        val code = waitFor("code")
        assertEquals("A TV falsa não mostrou código", 6, code.length)
        rule.onNodeWithTag("code-field").performTextInput(code)

        // O comando.
        rule.waitUntilExactlyOneExists(hasTestTag("status"), 20_000)
        pause(1.0)
        shot("remote")

        // A superfície: tocar, deslizar nos quatro sentidos, manter.
        val pad = rule.onNodeWithTag("touchpad")
        pad.performClick()
        pause(0.4)
        pad.performTouchInput { swipeUp() }
        pad.performTouchInput { swipeDown() }
        pad.performTouchInput { swipeLeft() }
        pad.performTouchInput { swipeRight() }
        pad.performTouchInput { longClick(durationMillis = 1200) }
        pause(0.4)

        // Os botões.
        for (tag in listOf("key:playPause", "key:back", "key:home", "key:mute")) {
            rule.onNodeWithTag(tag).performClick()
            pause(0.35)
        }
        shot("volume")

        // Mais: volume e pesquisa (a TV pede o teclado sozinha).
        rule.onNodeWithTag("more").performClick()
        rule.waitUntilExactlyOneExists(hasTestTag("key:VOLUME_UP"), 5_000)
        rule.onNodeWithTag("key:VOLUME_UP").performClick()
        pause(0.5)
        shot("more")
        rule.onNodeWithTag("key:SEARCH").performClick()
        rule.waitUntilExactlyOneExists(hasTestTag("keyboard-field"), 8_000)
        pause(0.6)
        rule.onNodeWithTag("keyboard-field").performTextInput("hello")
        pause(0.5)
        shot("keyboard")
        rule.onNodeWithTag("send-text").performClick()
        pause(0.8)

        // Ligar as setas nas bordas (em Mais) e fechar a folha.
        rule.onNodeWithTag("more").performClick()
        rule.waitUntilExactlyOneExists(hasTestTag("more-grid"), 5_000)
        rule.onNodeWithTag("more-grid").performScrollToNode(hasTestTag("opt:dpad"))
        rule.onNodeWithTag("opt:dpad").performClick()
        pause(0.4)
        shot("options")
        // O "voltar" do sistema (o do Espresso espera pelo foco da janela, que uma janela do sistema pode roubar).
        InstrumentationRegistry.getInstrumentation().uiAutomation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
        pause(0.8)

        // Setas nas bordas: tocar em cima e à direita.
        rule.onNodeWithTag("touchpad").performTouchInput {
            click(Offset(width / 2f, 12f))
            click(Offset(width - 12f, height / 2f))
        }
        pause(0.4)
        shot("dpad")

        // A lista vem do "GoatLauncher" da TV falsa (porta 6470): também tem apps que o comando nunca viu abertas.
        rule.onNodeWithTag("apps").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("app:YouTube"), 8_000)
        rule.waitUntilAtLeastOneExists(hasTestTag("app:Kodi"), 5_000)
        // Os banners (dentro do botão de cada app, por isso na árvore não fundida).
        rule.waitUntil(8_000) { rule.onAllNodesWithTag("image", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        pause(0.5)
        shot("apps")
        rule.onAllNodesWithTag("app:YouTube")[0].performClick()
        pause(1.5)
        shot("after-app")

        // O que a TV falsa recebeu.
        val log = fetch("log") ?: ""
        File(shotsDir, "fake-tv-log.txt").writeText(log)
        val expected = listOf(
            "emparelhado", "tecla DPAD_CENTER", "tecla DPAD_UP", "tecla DPAD_DOWN", "tecla DPAD_LEFT", "tecla DPAD_RIGHT",
            "tecla DPAD_CENTER (início)", "tecla DPAD_CENTER (fim)", "tecla MEDIA_PLAY_PAUSE", "tecla BACK", "tecla HOME",
            "launcher /volume/mute", "launcher /volume/up", "tecla SEARCH", "texto hello", "tecla ENTER",
            "abrir market://launch?id=com.google.android.youtube.tv", "launcher /apps", "launcher /icon/cc.slokker.itv",
        )
        val missing = expected.filterNot { log.contains(it) }
        assertTrue("Falta no registo da TV: $missing", missing.isEmpty())
    }

    // ---- Ajudas ----

    private fun pause(seconds: Double) {
        rule.waitForIdle()
        Thread.sleep((seconds * 1000).toLong())
    }

    /** O ecrã inteiro (com as folhas e o diálogo, que são janelas à parte). */
    private fun shot(name: String) {
        rule.waitForIdle()
        step++
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: return
        File(shotsDir, "%02d-%s.png".format(step, name)).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun fetch(path: String): String? = runCatching {
        val c = URL("http://$HOST:7000/$path").openConnection() as HttpURLConnection
        c.connectTimeout = 3000
        c.readTimeout = 3000
        try {
            c.inputStream.bufferedReader().readText()
        } finally {
            c.disconnect()
        }
    }.getOrNull()

    private fun waitFor(path: String, timeoutMs: Long = 15_000): String {
        val until = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < until) {
            fetch(path)?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
            Thread.sleep(500)
        }
        return ""
    }

    companion object {
        /** O computador visto do emulador. */
        const val HOST = "10.0.2.2"

        val shotsDir: File by lazy {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            File(context.getExternalFilesDir(null), "shots").apply { mkdirs() }
        }

        /** Começa sem TVs (como uma instalação nova). */
        @BeforeClass
        @JvmStatic
        fun reset() {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            for (name in listOf("tvs", "options", "companion")) context.getSharedPreferences(name, 0).edit().clear().commit()
        }
    }
}
