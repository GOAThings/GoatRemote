package cc.slokker.goatremote

import android.os.Build
import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

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

    class TooManyReports : Exception("429")
    class ReportFailed(val status: Int) : Exception("HTTP $status")

    /** Envia o registo para a zona admin do site (`POST /api/reports`, sem conta) e devolve o id do relatório. */
    suspend fun send(message: String, contact: String): String = withContext(Dispatchers.IO) {
        // O servidor aceita até 64 KB de registo: ficam as linhas mais recentes.
        var log = text
        while (log.toByteArray().size > 60_000 && log.contains('\n')) log = log.substringAfter('\n')
        val body = JSONObject()
            .put("app", "goatremote")
            .put("version", BuildConfig.VERSION_NAME)
            .put("platform", "android")
            .put("device", "Android ${Build.VERSION.RELEASE} · ${Build.MANUFACTURER} ${Build.MODEL}".take(120))
            .put("log", log)
        message.trim().take(2000).takeIf { it.isNotEmpty() }?.let { body.put("message", it) }
        contact.trim().take(200).takeIf { it.isNotEmpty() }?.let { body.put("contact", it) }
        val conn = URL("https://thegoat.systems/api/reports").openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 10_000
            conn.readTimeout = 20_000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("X-Goat-Client", "goatremote/${BuildConfig.VERSION_NAME} (android)")
            val status = try {
                conn.outputStream.use { it.write(body.toString().toByteArray()) }
                conn.responseCode
            } catch (e: java.io.IOException) {
                add("Report failed: $e")
                throw e
            }
            if (status != 200 && status != 201) {
                val error = runCatching { conn.errorStream?.bufferedReader()?.use { it.readText().take(300) } }.getOrNull()
                add("Report failed: HTTP $status ${error.orEmpty()}")
                throw if (status == 429) TooManyReports() else ReportFailed(status)
            }
            val id = JSONObject(conn.inputStream.bufferedReader().use { it.readText() }).optString("id")
            if (id.isEmpty()) throw ReportFailed(status)
            add("Report $id sent")
            id
        } finally {
            conn.disconnect()
        }
    }
}
