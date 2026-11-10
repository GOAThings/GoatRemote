package cc.slokker.goatremote.data

/** Uma resposta do GoatTV já lida: o estado, se a ligação foi recusada, e o que veio (null se não veio ou não se leu). */
class Fetched<T>(val status: Int, val refused: Boolean, val value: T?, val error: Exception? = null)

/**
 * O GoatTV de uma TV (porta 6471; contracts/goattv-6471): os pedidos, sem decidir nada. O que fazer com cada resposta
 * fica com quem chama.
 */
class GoatTvApi(private val host: String) {
    /** GET /channels (até 8 MiB, lido fora da thread principal). */
    suspend fun channels(): Fetched<ChannelList> =
        fetch(LanHttp.request(GoatTvChannels.url(host, "channels"), connectMs = 4000, readMs = 8000, limit = GoatTvChannels.MAX_BYTES)) {
            GoatTvChannels.parse(it)
        }

    /** GET /now (pequeno). */
    suspend fun now(): Fetched<NowInfo> =
        fetch(LanHttp.request(GoatTvChannels.url(host, "now"), connectMs = 2000, readMs = 3000, limit = GoatTvChannels.MAX_NOW_BYTES)) {
            GoatTvChannels.parseNow(it)
        }

    /** POST /play/<chave>. */
    suspend fun play(key: String): LanHttp.Result = LanHttp.request(GoatTvChannels.url(host, "play", key), "POST", 3000, 4000)

    fun logoUrl(key: String) = GoatTvChannels.url(host, "logo", key)

    private suspend fun <T> fetch(r: LanHttp.Result, parse: (String) -> T): Fetched<T> {
        val body = r.body ?: return Fetched(r.status, r.refused, null, r.error)
        return try {
            Fetched(r.status, false, kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { parse(String(body, Charsets.UTF_8)) })
        } catch (e: Exception) {
            Fetched(r.status, false, null, e)
        }
    }
}
