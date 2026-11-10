package cc.slokker.goatremote.data

import org.json.JSONArray
import org.json.JSONObject

/** Um canal do GoatTV, como ele o dá na rede de casa (porta 6471). */
data class TvChannel(
    val key: String,
    val num: Int?,
    val name: String,
    val group: String?,
    val logo: Boolean,
    val favorite: Boolean,
)

data class ChannelGroup(val id: String, val name: String)

/** A lista ativa do GoatTV: grupos e canais pela ordem dele, e o canal que está a dar. */
/** Um programa do guia do GoatTV (horas em ms). */
data class Programme(val title: String, val startMs: Long, val endMs: Long) {
    fun progress(now: Long): Float = ((now - startMs).toFloat() / (endMs - startMs)).coerceIn(0f, 1f)
}

/** O que o GoatTV está a dar (GET /now): o canal e, se ele tiver guia, o programa e o seguinte. */
data class NowInfo(val current: String?, val now: Programme?, val next: Programme?)

data class ChannelList(
    val playlist: String?,
    val current: String?,
    val groups: List<ChannelGroup>,
    val channels: List<TvChannel>,
    /** A lista não veio toda (cortada pelo GoatTV, ou aqui, acima do limite de canais). */
    val truncated: Boolean,
)

/** Os canais do GoatTV na TV (GET /channels, GET /logo/<key>, POST /play/<key>). O mesmo que o iPhone faz. */
object GoatTvChannels {
    const val PORT = 6471
    /** O GoatTV numa Android TV (abre-se pelo GoatLauncher). */
    const val ANDROID_PACKAGE = "cc.slokker.itv"
    /** O GoatTV na Apple TV; quem assina a IPA pode mudar o bundle id, por isso também se procura pelo nome. */
    const val APPLE_BUNDLE = "cc.slokker.goattv"
    const val MAX_BYTES = 8 shl 20
    const val MAX_LOGO_BYTES = 1 shl 20
    /** Os logótipos mostram-se pequenos: reduzem-se mais do que os banners. */
    const val LOGO_SIDE = 256
    const val MAX_CHANNELS = 50_000
    const val MAX_GROUPS = 5_000
    const val MAX_KEY = 1024
    const val MAX_NAME = 200
    const val MAX_NUM = 999_999
    /** O /now é pequeno: mais do que isto não é o GoatTV. */
    const val MAX_NOW_BYTES = 64 shl 10
    const val MAX_TITLE = 300

    enum class Play {
        DONE,
        /** Canal desconhecido, escondido ou bloqueado. */
        NOT_FOUND,
        /** O GoatTV não está à frente (ou ainda não carregou): abre-se e tenta-se outra vez. */
        RETRY,
        FAILED,
    }

    fun playOutcome(status: Int, refused: Boolean): Play = when {
        status == 200 -> Play.DONE
        status == 404 -> Play.NOT_FOUND
        status == 409 || status == 503 || refused -> Play.RETRY
        else -> Play.FAILED
    }

    /** O caminho de um pedido: a chave vai codificada (tudo menos letras e algarismos ASCII, "-", "_" e "~"). */
    fun url(host: String, what: String, key: String? = null): String =
        LanHttp.url(host, PORT, what + (key?.let { "/" + encodeKey(it) } ?: ""))

    fun encodeKey(key: String): String {
        val out = StringBuilder()
        for (b in key.toByteArray(Charsets.UTF_8)) {
            val c = b.toInt() and 0xFF
            if (c in 'A'.code..'Z'.code || c in 'a'.code..'z'.code || c in '0'.code..'9'.code || c == '-'.code || c == '_'.code || c == '~'.code) {
                out.append(c.toChar())
            } else {
                out.append('%').append(HEX[c shr 4]).append(HEX[c and 0xF])
            }
        }
        return out.toString()
    }

    private const val HEX = "0123456789ABCDEF"

    /**
     * O GoatTV na lista de apps da Apple TV (bundle id → nome): pelo bundle id, ou pelo nome se a IPA foi assinada com
     * outro. null se não estiver lá.
     */
    fun appleApp(apps: Map<String, String>): String? =
        if (APPLE_BUNDLE in apps) APPLE_BUNDLE
        // Por ordem, para que a escolha não dependa da ordem da lista.
        else apps.filterValues { it.trim().equals("GoatTV", ignoreCase = true) }.keys.minOrNull()

    /**
     * Lê a resposta de /channels. O que não for um objeto dá erro; um canal ou grupo estragado só fica de fora. Chaves
     * repetidas ficam só a primeira vez (a lista usa-as como identificador).
     */
    fun parse(text: String): ChannelList {
        val json = JSONObject(text)
        val groups = mutableListOf<ChannelGroup>()
        val groupIds = HashSet<String>()
        (json.opt("groups") as? JSONArray)?.let { array ->
            for (i in 0 until array.length()) {
                if (groups.size >= MAX_GROUPS) break
                val o = array.opt(i) as? JSONObject ?: continue
                val id = o.opt("id") as? String ?: continue
                val name = o.opt("name") as? String ?: continue
                if (id.isEmpty() || id.length > MAX_KEY || !groupIds.add(id)) continue
                groups.add(ChannelGroup(id, name.take(MAX_NAME)))
            }
        }
        val channels = mutableListOf<TvChannel>()
        val keys = HashSet<String>()
        var truncated = json.opt("truncated") == true
        (json.opt("channels") as? JSONArray)?.let { array ->
            for (i in 0 until array.length()) {
                val o = array.opt(i) as? JSONObject ?: continue
                val key = o.opt("key") as? String ?: continue
                val name = o.opt("name") as? String ?: continue
                if (key.isEmpty() || key.length > MAX_KEY || key in keys) continue
                if (channels.size >= MAX_CHANNELS) {
                    truncated = true
                    break
                }
                keys.add(key)
                val num = (o.opt("num") as? Number)?.toDouble()?.takeIf { it >= 0 && it <= MAX_NUM && it == Math.floor(it) }?.toInt()
                val group = (o.opt("group") as? String)?.takeIf { it.isNotEmpty() && it.length <= MAX_KEY }
                channels.add(TvChannel(key, num, name.take(MAX_NAME), group, o.opt("logo") == true, o.opt("favorite") == true))
            }
        }
        val playlist = (json.opt("playlist") as? JSONObject)?.let { it.opt("name") as? String }?.take(MAX_NAME)
        val current = (json.opt("current") as? String)?.takeIf { it in keys }
        return ChannelList(playlist, current, groups, channels, truncated)
    }

    /** Lê a resposta de /now. O que não for um objeto dá erro; um programa estragado (sem título, horas trocadas) fica null. */
    fun parseNow(text: String): NowInfo {
        val json = JSONObject(text)
        fun programme(name: String): Programme? {
            val o = json.opt(name) as? JSONObject ?: return null
            val title = (o.opt("title") as? String)?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            val start = (o.opt("start") as? Number)?.toLong() ?: return null
            val end = (o.opt("end") as? Number)?.toLong() ?: return null
            return if (end > start) Programme(title.take(MAX_TITLE), start, end) else null
        }
        val current = (json.opt("current") as? String)?.takeIf { it.isNotEmpty() && it.length <= MAX_KEY }
        return NowInfo(current, programme("now"), programme("next"))
    }
}
