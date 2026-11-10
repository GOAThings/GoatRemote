package cc.slokker.goatremote.data

import org.json.JSONArray

/**
 * O que o GoatLauncher da TV dá na porta 6470 (GoatLauncher data/PhoneRoutes.kt; contracts/launcher-6470). O mesmo
 * que o iPhone faz (RemoteCore LauncherApps).
 */
object LauncherApps {
    const val PORT = 6470
    /** GET /apps: mais do que isto não é o GoatLauncher. */
    const val MAX_BYTES = 2 shl 20

    /** Lê a resposta de /apps. O que não for uma lista dá erro; uma app mal descrita fica de fora e as outras contam. */
    fun parse(text: String): List<TvApp> {
        val array = JSONArray(text)
        return (0 until array.length()).mapNotNull { i ->
            runCatching {
                val o = array.getJSONObject(i)
                TvApp(o.getString("package"), o.getString("label"), o.optBoolean("banner"), o.optString("color").ifEmpty { null })
            }.getOrNull()
        }.distinctBy { it.pkg }
    }

    /** POST /open/<pacote>: tudo menos 200 (o 409 é o launcher sem o serviço de acessibilidade) abre pelo link do comando. */
    fun openFallsBack(status: Int) = status != 200
}
