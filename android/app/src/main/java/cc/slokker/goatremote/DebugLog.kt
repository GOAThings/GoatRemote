package cc.slokker.goatremote

import android.os.Build
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Registo de diagnóstico: os passos da procura, da ligação e do emparelhamento (nunca PINs, códigos, chaves ou
 * certificados). Fica em memória (as últimas [LIMIT] linhas) e no logcat; em Mais → Diagnóstico pode copiar-se ou
 * partilhar-se, para perceber o que falhou na TV de outra pessoa.
 */
object DebugLog {
    private const val LIMIT = 500
    private val lines = ArrayDeque<String>()
    private val time = SimpleDateFormat("HH:mm:ss", Locale.ROOT)

    fun add(message: String) {
        Log.i("GoatRemote", message)
        synchronized(this) {
            lines.addLast(time.format(Date()) + "  " + message)
            while (lines.size > LIMIT) lines.removeFirst()
        }
    }

    /** O registo com uma linha de cabeçalho (versão da app e do sistema), pronto a partilhar. */
    val text: String
        get() {
            val header = "GoatRemote ${BuildConfig.VERSION_NAME} · Android ${Build.VERSION.RELEASE} · ${Build.MANUFACTURER} ${Build.MODEL}"
            return synchronized(this) { (listOf(header) + lines).joinToString("\n") }
        }

    fun clear() = synchronized(this) { lines.clear() }
}
