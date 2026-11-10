package cc.slokker.goatremote.data

/**
 * O GoatLauncher de uma TV (porta 6470; contracts/launcher-6470): os pedidos, sem decidir nada. O que fazer com cada
 * resposta fica com quem chama (o volume, por exemplo, decide-se em [cc.slokker.goatremote.tv.LauncherVolume]).
 */
class LauncherApi(private val host: String) {
    private fun url(path: String) = LanHttp.url(host, LauncherApps.PORT, path)

    /** GET /apps: a lista, ou null se não respondeu com uma (sem launcher, ou ainda a arrancar). */
    suspend fun apps(): List<TvApp>? {
        val r = LanHttp.request(url("apps"), connectMs = 4000, readMs = 4000, limit = LauncherApps.MAX_BYTES)
        val body = r.body ?: return null
        return runCatching { LauncherApps.parse(String(body, Charsets.UTF_8)) }.getOrNull()
    }

    /** POST /open/<pacote>: o estado HTTP (0 sem resposta). */
    suspend fun open(pkg: String): Int = LanHttp.request(url("open/$pkg"), "POST", 3000, 3000).status

    /** POST /volume/up|down|mute. */
    suspend fun volume(what: String): LanHttp.Result = LanHttp.request(url("volume/$what"), "POST", 3000, 3000)

    /** O banner (ou ícone) de uma app. */
    fun iconUrl(pkg: String) = url("icon/$pkg")
}
