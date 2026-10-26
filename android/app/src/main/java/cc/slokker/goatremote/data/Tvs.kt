package cc.slokker.goatremote.data

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import cc.slokker.goatremote.DebugLog
import cc.slokker.goatremote.apple.AppleTvLink
import cc.slokker.goatremote.tv.RemoteProtocol
import java.net.Inet4Address
import java.util.concurrent.Executors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject

/** Android TV / Google TV (protocolo da app Google TV) ou Apple TV (protocolo Companion). */
enum class TvKind { ANDROID, APPLE }

/**
 * Uma TV guardada (emparelhada). [id] é o nome com que se anuncia na rede ("apple:" + nome nas Apple TV), ou o IP
 * se foi juntada à mão.
 */
data class SavedTv(
    val id: String,
    val name: String,
    val host: String,
    val kind: TvKind = TvKind.ANDROID,
    /** A porta do comando, se não for a de sempre (a Apple TV escolhe uma). */
    val port: Int? = null,
) {
    fun toJson(): JSONObject = JSONObject().put("id", id).put("name", name).put("host", host)
        .put("kind", kind.name.lowercase()).apply { port?.let { put("port", it) } }

    companion object {
        fun fromJson(o: JSONObject) = SavedTv(
            id = o.getString("id"),
            name = o.getString("name"),
            host = o.getString("host"),
            kind = if (o.optString("kind") == "apple") TvKind.APPLE else TvKind.ANDROID,
            port = if (o.has("port")) o.getInt("port") else null,
        )
    }
}

/** As TVs guardadas e a escolhida. */
class TvStore(context: Context) {
    private val prefs = context.getSharedPreferences("tvs", Context.MODE_PRIVATE)

    var all: List<SavedTv>
        get() = runCatching {
            val array = JSONArray(prefs.getString("tvs", "[]"))
            (0 until array.length()).map { SavedTv.fromJson(array.getJSONObject(it)) }
        }.getOrDefault(emptyList())
        set(value) {
            prefs.edit().putString("tvs", JSONArray(value.map { it.toJson() }).toString()).apply()
        }

    var currentId: String?
        get() = prefs.getString("current", null)
        set(value) {
            prefs.edit().putString("current", value).apply()
        }

    val current: SavedTv?
        get() = all.let { tvs -> tvs.firstOrNull { it.id == currentId } ?: tvs.firstOrNull() }

    fun save(tv: SavedTv) {
        all = all.filterNot { it.id == tv.id } + tv
    }

    fun remove(id: String) {
        all = all.filterNot { it.id == id }
        if (currentId == id) currentId = all.firstOrNull()?.id
    }
}

/** Uma TV que se anuncia na rede: Android TV (_androidtvremote2._tcp) ou Apple TV (_companion-link._tcp). */
data class FoundTv(
    val name: String,
    val kind: TvKind,
    val host: String?,
    val port: Int?,
    /** O modelo, quando a TV o diz (Apple TV: "AppleTV11,1"). */
    val model: String? = null,
) {
    /** O mesmo id com que fica guardada depois de emparelhada. */
    val id: String get() = if (kind == TvKind.APPLE) "apple:$name" else name
}

/**
 * Procura TVs na rede de casa enquanto está ligado. O _companion-link também é anunciado por iPhones, iPads, Macs e
 * HomePods: só contam as Apple TV (o "rpMd" do anúncio começa por "AppleTV"), por isso cada um é resolvido.
 */
class TvFinder(context: Context) {
    private val nsd = context.getSystemService(NsdManager::class.java)
    private val _found = MutableStateFlow<List<FoundTv>>(emptyList())
    val found: StateFlow<List<FoundTv>> = _found
    private val listeners = mutableListOf<NsdManager.DiscoveryListener>()
    private val tvs = LinkedHashMap<String, FoundTv>()
    /** Antes do Android 14 só se resolve um serviço de cada vez. */
    private val resolver = Executors.newSingleThreadExecutor()

    @Synchronized
    fun start() {
        if (listeners.isNotEmpty()) return
        for ((type, kind) in listOf(RemoteProtocol.SERVICE to TvKind.ANDROID, AppleTvLink.SERVICE to TvKind.APPLE)) {
            val listener = object : NsdManager.DiscoveryListener {
                override fun onServiceFound(info: NsdServiceInfo) = resolve(info, kind)
                override fun onServiceLost(info: NsdServiceInfo) = lost(info.serviceName, kind)
                override fun onDiscoveryStarted(serviceType: String) = Unit
                override fun onDiscoveryStopped(serviceType: String) = Unit
                override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) = DebugLog.add("Discovery $serviceType failed: $errorCode")
                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
            }
            runCatching { nsd.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener) }
                .onSuccess { listeners.add(listener) }
                .onFailure { DebugLog.add("Discovery $type: $it") }
        }
    }

    @Synchronized
    fun stop() {
        listeners.forEach { runCatching { nsd.stopServiceDiscovery(it) } }
        listeners.clear()
    }

    private fun resolve(info: NsdServiceInfo, kind: TvKind) {
        resolver.execute {
            val done = java.util.concurrent.CountDownLatch(1)
            @Suppress("DEPRECATION")
            val ok = runCatching {
                nsd.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                        DebugLog.add("Resolve ${info.serviceName} ($kind) failed: $errorCode")
                        done.countDown()
                    }
                    override fun onServiceResolved(info: NsdServiceInfo) {
                        found(info, kind)
                        done.countDown()
                    }
                })
            }.isSuccess
            if (ok) done.await(6, java.util.concurrent.TimeUnit.SECONDS)
        }
    }

    private fun found(info: NsdServiceInfo, kind: TvKind) {
        val model = info.attributes["rpMd"]?.toString(Charsets.UTF_8)
        // Os outros aparelhos Apple só pelo modelo, para ver se a Apple TV aparece com outro rpMd.
        if (kind == TvKind.APPLE && model?.startsWith("AppleTV") != true) return DebugLog.add("Ignored Apple device ($model)")
        val host = hostOf(info)
        DebugLog.add("Found ${info.serviceName} ($kind${model?.let { ", $it" } ?: ""}) at $host:${info.port}")
        val tv = FoundTv(info.serviceName, kind, host, info.port, model)
        synchronized(tvs) {
            tvs[tv.id] = tv
            _found.value = tvs.values.sortedBy { it.name.lowercase() }
        }
    }

    private fun lost(name: String, kind: TvKind) {
        val id = if (kind == TvKind.APPLE) "apple:$name" else name
        synchronized(tvs) {
            tvs.remove(id)
            _found.value = tvs.values.sortedBy { it.name.lowercase() }
        }
    }

    /** O IP (IPv4 de preferência). */
    private fun hostOf(info: NsdServiceInfo): String? {
        val addresses = if (Build.VERSION.SDK_INT >= 34) info.hostAddresses else listOfNotNull(@Suppress("DEPRECATION") info.host)
        val best = addresses.firstOrNull { it is Inet4Address } ?: addresses.firstOrNull()
        return best?.hostAddress?.substringBefore('%')
    }
}

/** Apps conhecidas: nome e cor, para os atalhos. Abrem-se pelo pacote (market://launch?id=…). */
data class KnownApp(val pkg: String, val name: String, val color: Long)

object AppCatalog {
    val apps = listOf(
        KnownApp("com.google.android.youtube.tv", "YouTube", 0xFF0033),
        KnownApp("com.netflix.ninja", "Netflix", 0xE50914),
        KnownApp("com.amazon.amazonvideo.livingroom", "Prime Video", 0x00A8E1),
        KnownApp("com.disney.disneyplus", "Disney+", 0x113CCF),
        KnownApp("com.wbd.stream", "Max", 0x002BE7),
        KnownApp("com.apple.atve.androidtv.appletv", "Apple TV", 0x555555),
        KnownApp("com.spotify.tv.android", "Spotify", 0x1DB954),
        KnownApp("com.plexapp.android", "Plex", 0xE5A00D),
        KnownApp("org.xbmc.kodi", "Kodi", 0x17B2E7),
        KnownApp("tv.twitch.android.app", "Twitch", 0x9146FF),
        KnownApp("cc.slokker.itv", "GoatTV", 0x38BDF8),
        KnownApp("com.android.tv.settings", "Settings", 0x6B7280),
    )

    fun app(pkg: String) = apps.firstOrNull { it.pkg == pkg }

    /** O nome a mostrar de um pacote (o conhecido, ou a última parte do pacote). */
    fun name(pkg: String): String = app(pkg)?.name ?: pkg.substringAfterLast('.').replaceFirstChar { it.uppercase() }

    /** O ecrã inicial da TV não conta como app aberta. */
    fun isLauncher(pkg: String) = pkg.lowercase().contains("launcher") || pkg == "com.google.android.apps.tv.launcherx"
}

/** Uma app instalada na TV, como o GoatLauncher a dá (ou a Apple TV, sem banner nem cor). */
data class TvApp(
    val pkg: String,
    val label: String,
    /** Tem banner de TV (16:9); senão é um ícone sobre a [color]. */
    val banner: Boolean = false,
    val color: String? = null,
) {
    val link: String get() = "market://launch?id=$pkg"

    val tint: Long?
        get() = color?.takeIf { it.startsWith("#") }?.drop(1)?.toLongOrNull(16)
}
