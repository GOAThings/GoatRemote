package cc.slokker.goatremote.data

import cc.slokker.goatremote.tv.readLimited
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Os pedidos HTTP na rede de casa (o GoatLauncher em 6470, o GoatTV em 6471): sem cabeçalhos além dos do sistema
 * (o launcher recusa pedidos com Origin), com tempos por pedido e respostas com limite de bytes.
 *
 * "Recusado" é só a ligação recusada (ConnectException): a porta está fechada, a app não está a correr. É o que o
 * [cc.slokker.goatremote.tv.LauncherVolume.outcome] usa para decidir se pode mandar a tecla de volume, por isso não
 * se alarga: um tempo esgotado, um endereço que não dá um URL ou uma resposta estragada não são recusas. (No iPhone é o
 * URLError.cannotConnectToHost, e um endereço que não dá URL conta como recusa no volume: ver o LanHttp de lá.)
 */
object LanHttp {
    /** O estado HTTP (0 sem resposta), se a ligação foi recusada, o corpo (só num 200 com [limit]) e o erro, se houve. */
    class Result(val status: Int, val refused: Boolean, val body: ByteArray? = null, val error: Exception? = null)

    /** http://<host>:<porta>/<caminho>; um IPv6 vai entre parênteses retos (sem eles o URL não se lê). */
    fun url(host: String, port: Int, path: String): String {
        val h = if (host.contains(':') && !host.startsWith("[")) "[$host]" else host
        return "http://$h:$port/$path"
    }

    /** Um pedido; com [limit], lê o corpo de um 200 (mais do que isso é erro). Nunca lança, a não ser cancelado. */
    suspend fun request(url: String, method: String = "GET", connectMs: Int, readMs: Int, limit: Int? = null): Result =
        withContext(Dispatchers.IO) {
            var status = 0
            try {
                val c = URL(url).openConnection() as HttpURLConnection
                if (method != "GET") c.requestMethod = method
                c.connectTimeout = connectMs
                c.readTimeout = readMs
                try {
                    status = c.responseCode
                    val body = if (limit != null && status == 200) c.inputStream.readLimited(limit) else null
                    Result(status, false, body)
                } finally {
                    c.disconnect()
                }
            } catch (e: java.net.ConnectException) {
                Result(0, true)
            } catch (e: Exception) {
                // O corpo que não se leu (grande demais, cortado) não conta como resposta.
                Result(0, false, error = e)
            }
        }
}
