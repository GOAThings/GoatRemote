package cc.slokker.goatremote

import android.app.Application
import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import cc.slokker.goatremote.apple.AppleTvLink
import cc.slokker.goatremote.apple.AppleTvPairing
import cc.slokker.goatremote.apple.CompanionConnection
import cc.slokker.goatremote.apple.CompanionCredentials
import cc.slokker.goatremote.data.AppCatalog
import cc.slokker.goatremote.data.ChannelList
import cc.slokker.goatremote.data.FoundTv
import cc.slokker.goatremote.data.GoatTvChannels
import cc.slokker.goatremote.data.NowInfo
import cc.slokker.goatremote.data.SavedTv
import cc.slokker.goatremote.data.TvApp
import cc.slokker.goatremote.data.TvChannel
import cc.slokker.goatremote.data.TvFinder
import cc.slokker.goatremote.data.TvKind
import cc.slokker.goatremote.data.TvStore
import cc.slokker.goatremote.tv.AndroidTvLink
import cc.slokker.goatremote.tv.IdentityStore
import cc.slokker.goatremote.tv.Key
import cc.slokker.goatremote.tv.KeyDirection
import cc.slokker.goatremote.tv.LauncherVolume
import cc.slokker.goatremote.tv.NotPairedException
import cc.slokker.goatremote.tv.Pairing
import cc.slokker.goatremote.tv.RemoteProtocol
import cc.slokker.goatremote.tv.RsaKey
import cc.slokker.goatremote.tv.TvControl
import cc.slokker.goatremote.tv.TvSocket
import cc.slokker.goatremote.tv.TvState
import cc.slokker.goatremote.tv.UnreachableException
import cc.slokker.goatremote.tv.readLimited
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/** Em que passo vai um emparelhamento. */
sealed interface Phase {
    data object Connecting : Phase
    data class WaitingCode(val retry: Boolean) : Phase
    data object Checking : Phase
    data object Done : Phase
    data class Failed(val why: String) : Phase
}

/** Inglês ou português, conforme a língua do telemóvel (como na app do iPhone). */
fun L(en: String, pt: String) = if (Locale.getDefault().language == "pt") pt else en

/** O meio do comando: a superfície de toque (deslizar) ou as setas com o OK, como num comando físico. */
enum class RemoteLayout { TOUCH, DPAD }

/** O estado da app: as TVs, a ligação à escolhida e o emparelhamento. */
class RemoteViewModel(app: Application) : AndroidViewModel(app) {
    sealed interface Status {
        data object NoTv : Status
        data object Connecting : Status
        data object Connected : Status
        /** A TV não aceita este telemóvel: emparelhar (outra vez). */
        data object NotPaired : Status
        data class Unreachable(val why: String) : Status
    }

    internal val appContext: Context get() = getApplication()
    private val context: Context get() = appContext
    private val store = TvStore(app)
    private val prefs = app.getSharedPreferences("options", Context.MODE_PRIVATE)
    internal val identities = IdentityStore(File(app.filesDir, "identity"))
    val finder = TvFinder(app)

    var tvs by mutableStateOf(store.all)
        private set
    var current by mutableStateOf(store.current)
        private set
    private var statusValue by mutableStateOf<Status>(if (store.current == null) Status.NoTv else Status.Connecting)
    var status: Status
        get() = statusValue
        private set(value) {
            if (value != statusValue) DebugLog.add("Status: $value" + (current?.let { " (${it.name}, ${it.kind})" } ?: ""))
            statusValue = value
        }
    var state by mutableStateOf(TvState())
        private set
    /** As apps que se viu abertas nesta TV (as mais recentes primeiro), para as abrir com um toque. */
    var recentApps by mutableStateOf(loadRecents(store.current?.id))
        private set
    /** As apps instaladas na TV, se ela tiver o GoatLauncher (que as dá na rede de casa); vazio sem ele. */
    var installedApps by mutableStateOf<List<TvApp>>(emptyList())
        private set

    /** A TV tem o GoatTV com os canais para o telemóvel (já respondeu a /channels): mostra-se o botão Canais. */
    var hasChannels by mutableStateOf(store.current?.let { prefs.getBoolean("goattv.${it.id}", false) } ?: false)
        private set
    /** A lista de canais do GoatTV (null enquanto não veio, ou com o GoatTV fechado). */
    var channels by mutableStateOf<ChannelList?>(null)
        private set
    var channelsStatus by mutableStateOf(ChannelsStatus.UNKNOWN)
        private set
    /** A abrir o GoatTV na TV, à espera de que dê os canais. */
    var openingGoatTv by mutableStateOf(false)
        private set
    /** O programa do canal que o GoatTV está a dar (null sem guia, ou num GoatTV antigo, sem o /now). */
    var nowInfo by mutableStateOf<NowInfo?>(null)
        private set
    /** TVs cujo GoatTV não tem o /now (responde 404): até voltar a ligar, não se pergunta. */
    private val withoutNow = HashSet<String>()
    /** Porque é que o último canal não mudou (null: nada a dizer). */
    var playProblem by mutableStateOf<String?>(null)
        private set

    /** O emparelhamento em curso (o diálogo mostra-o). */
    var pairing by mutableStateOf<PairingModel?>(null)
    /** A TV abriu uma caixa de texto: mostra-se o teclado. */
    var showKeyboard by mutableStateOf(false)
    /** Pede ao comando que feche as folhas abertas antes de mostrar o emparelhamento. */
    var closeSheets by mutableIntStateOf(0)
        private set
    /** Muda quando o volume da TV muda (o indicador aparece um bocado). */
    var volumeChanged by mutableIntStateOf(0)
        private set

    // Opções (Mais → Opções).
    var haptics by mutableStateOf(prefs.getBoolean("haptics", true))
        private set
    /** Os botões de volume do telemóvel mexem no volume da TV (com a app aberta). */
    var volumeButtons by mutableStateOf(prefs.getBoolean("volumeButtons", true))
        private set
    /** Superfície de toque ou setas (D-pad). Quem tinha as "setas nas bordas" ligadas começa nas setas. */
    var layout by mutableStateOf(
        prefs.getString("layout", null)?.let { saved -> RemoteLayout.entries.firstOrNull { it.name == saved } }
            ?: if (prefs.getBoolean("dpadTaps", false)) RemoteLayout.DPAD else RemoteLayout.TOUCH,
    )
        private set

    fun changeHaptics(on: Boolean) { haptics = on; prefs.edit().putBoolean("haptics", on).apply() }
    fun changeVolumeButtons(on: Boolean) { volumeButtons = on; prefs.edit().putBoolean("volumeButtons", on).apply() }
    fun changeLayout(new: RemoteLayout) { layout = new; prefs.edit().putString("layout", new.name).remove("dpadTaps").apply() }

    private var link: TvControl? = null
        set(value) {
            // A ligação mudou: o teclado fecha-se e o que lá estava escrito não passa para a próxima.
            if (value !== field) {
                showKeyboard = false
                state = state.copy(textValue = "", textLabel = null, keyboardRequests = 0)
            }
            field = value
        }
    private var stateJob: Job? = null
    private var autoReconnect: Job? = null
    private var lastAutoReconnect = 0L
    /** Recusas seguidas desta TV que ainda não se mostraram (ver [connect]). */
    private var notPairedRetries = 0
    /** Ícones das apps da Apple TV (da App Store, por bundle id). */
    private val appleArtwork = mutableStateMapOf<String, String>()
    private val vibrator = app.getSystemService(Vibrator::class.java)

    val deviceName: String
        get() = Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) ?: Build.MODEL

    // ---- Ligação ----

    /**
     * Liga à TV escolhida. Uma falha que não seja "não emparelhado" tenta mais uma vez daí a pouco: a SHIELD, por
     * exemplo, recusa a primeira ligação logo a seguir a emparelhar. "Não emparelhado" tenta mais três vezes (uns 12 s)
     * antes de se mostrar: a TV às vezes recusa um telemóvel que conhece (a SHIELD, logo a seguir a mudar de canal,
     * fecha a ligação e recusa as seguintes durante uns segundos).
     */
    fun connect(retry: Boolean = true) {
        val tv = current ?: run { status = Status.NoTv; return }
        if (link != null && (status == Status.Connected || status == Status.Connecting)) return
        autoReconnect?.cancel()
        link?.close()
        DebugLog.add("Connecting to ${tv.name} (${tv.kind}, ${tv.host}${tv.port?.let { ":$it" } ?: ""})")
        status = Status.Connecting
        val link = makeLink(tv)
        this.link = link
        (link as? AppleTvLink)?.onApps = { apps -> viewModelScope.launch { appleApps(apps, tv) } }
        link.onClose = {
            viewModelScope.launch {
                if (this@RemoteViewModel.link === link) {
                    this@RemoteViewModel.link = null
                    // Liga outra vez sem incomodar; se voltar a fechar logo a seguir, aí sim mostra-se o aviso.
                    if (tv.kind == TvKind.ANDROID && System.currentTimeMillis() - lastAutoReconnect > 10_000) {
                        lastAutoReconnect = System.currentTimeMillis()
                        DebugLog.add("Reconnecting to ${tv.name}")
                        status = Status.Connecting
                        autoReconnect = viewModelScope.launch {
                            delay(1500)
                            if (this@RemoteViewModel.link == null && current?.id == tv.id) connect()
                        }
                    } else {
                        status = Status.Unreachable(L("The TV closed the connection", "A TV fechou a ligação"))
                    }
                }
            }
        }
        stateJob?.cancel()
        stateJob = viewModelScope.launch { link.state.collect { if (this@RemoteViewModel.link === link) update(it) } }
        viewModelScope.launch {
            try {
                link.connect()
                if (this@RemoteViewModel.link !== link) return@launch
                (link as? AndroidTvLink)?.certificate?.let { store.pinCertificate(tv.id, it) }
                notPairedRetries = 0
                status = Status.Connected
                withoutNow.remove(tv.id)
                update(link.state.value)
                refreshApps()
                refreshChannels()
            } catch (e: NotPairedException) {
                DebugLog.add("Connect: not paired ($e)")
                if (this@RemoteViewModel.link !== link) return@launch
                this@RemoteViewModel.link = null
                if (notPairedRetries < 3) {
                    notPairedRetries++
                    DebugLog.add("Not paired: trying again ($notPairedRetries)")
                    autoReconnect = viewModelScope.launch {
                        delay(2000L * notPairedRetries)
                        if (this@RemoteViewModel.link == null && current?.id == tv.id) connect()
                    }
                    return@launch
                }
                notPairedRetries = 0
                status = Status.NotPaired
            } catch (e: Exception) {
                DebugLog.add("Connect failed${if (retry) " (will retry)" else ""}: $e")
                if (this@RemoteViewModel.link !== link) return@launch
                this@RemoteViewModel.link = null
                link.close()
                if (retry) {
                    delay(1500)
                    if (this@RemoteViewModel.link == null && current?.id == tv.id) connect(retry = false)
                } else {
                    status = Status.Unreachable(describe(e))
                }
            }
        }
    }

    fun disconnect() {
        autoReconnect?.cancel()
        link?.close()
        link = null
        if (current != null) status = Status.Connecting
    }

    fun reconnect() {
        link?.close()
        link = null
        connect()
    }

    private fun update(new: TvState) {
        val old = state
        state = new
        if (new.keyboardRequests > old.keyboardRequests) showKeyboard = true
        // Ao ligar, a TV manda vários valores seguidos (na SHIELD, com HDMI-CEC, acaba em 0): isso não é mudar o volume.
        if (old.volume == null && new.volume != null) volumeSettlesAt = System.currentTimeMillis() + 5000
        if (old.volume != null && (new.volume != old.volume || new.muted != old.muted) && !volumeUnknown &&
            System.currentTimeMillis() >= volumeSettlesAt) volumeChanged++
        val app = new.currentApp
        // O GoatTV veio para a frente: o canal que está a dar pode ter mudado.
        if (app == GoatTvChannels.ANDROID_PACKAGE && app != old.currentApp && hasChannels) refreshChannels()
        if (app != null && app != old.currentApp && !AppCatalog.isLauncher(app)) {
            recentApps = (listOf(app) + recentApps.filterNot { it == app }).take(12)
            current?.id?.let { prefs.edit().putString("recents.$it", JSONArray(recentApps).toString()).apply() }
        }
    }

    private fun loadRecents(id: String?): List<String> {
        id ?: return emptyList()
        val saved = runCatching {
            val array = JSONArray(prefs.getString("recents.$id", "[]"))
            (0 until array.length()).map { array.getString(it) }
        }.getOrNull() ?: return emptyList()
        // O que não for um nome de pacote não volta a ler-se.
        val recents = saved.filter { RemoteProtocol.isPackageName(it) }.distinct().take(12)
        if (recents != saved) prefs.edit().putString("recents.$id", JSONArray(recents).toString()).apply()
        return recents
    }

    /** A ligação certa para o tipo de TV. */
    private fun makeLink(tv: SavedTv): TvControl = when (tv.kind) {
        TvKind.APPLE -> AppleTvLink(tv.host, tv.port ?: AppleTvLink.DEFAULT_PORT, { CompanionCredentials.load(context, tv.id) },
            deviceName, stableId())
        TvKind.ANDROID -> AndroidTvLink(tv.host, identities::get, BuildConfig.VERSION_NAME, Build.MODEL, store.certificate(tv.id))
    }

    private fun stableId(): String = prefs.getString("companion.id", null) ?: (0 until 6)
        .joinToString("") { "%02x".format((0..255).random()) }
        .also { prefs.edit().putString("companion.id", it).apply() }

    // ---- Apps da TV (GoatLauncher; na Apple TV, a própria TV) ----

    /** A lista que a Apple TV dá (sem ícones): os ícones vêm da App Store, pelo bundle id. */
    private fun appleApps(apps: Map<String, String>, tv: SavedTv) {
        if (current?.id != tv.id) return
        installedApps = apps.map { (id, name) -> TvApp(id, name.replace(' ', ' ')) }.sortedBy { it.label.lowercase() }
        for (app in installedApps) {
            if (appleArtwork.containsKey(app.pkg) || app.pkg.startsWith("com.apple.")) continue
            viewModelScope.launch {
                val art = withContext(Dispatchers.IO) {
                    runCatching {
                        val url = URL("https://itunes.apple.com/lookup?bundleId=" + URLEncoder.encode(app.pkg, "UTF-8"))
                        val json = JSONObject(url.readText())
                        json.getJSONArray("results").optJSONObject(0)?.let { it.optString("artworkUrl512").ifEmpty { it.optString("artworkUrl100") } }
                    }.getOrNull()
                }
                if (!art.isNullOrEmpty()) appleArtwork[app.pkg] = art
            }
        }
    }

    /** Abre uma app da lista (Android: pelo pacote; Apple TV: pelo bundle id). */
    fun launch(app: TvApp, haptic: Boolean = true) {
        val tv = current
        if (tv == null || tv.kind != TvKind.ANDROID || hasLauncher(tv.id) == false) {
            return open(if (tv?.kind == TvKind.APPLE) app.pkg else app.link, haptic)
        }
        // Pelo GoatLauncher: a SHIELD recusa o link do comando e fecha a ligação.
        if (haptic && haptics) vibrate(false)
        DebugLog.add("Open app via launcher: ${app.pkg}")
        viewModelScope.launch {
            val status = withContext(Dispatchers.IO) {
                runCatching {
                    val c = URL("http://${tv.host}:$LAUNCHER_PORT/open/${app.pkg}").openConnection() as HttpURLConnection
                    c.requestMethod = "POST"
                    c.connectTimeout = 3000
                    c.readTimeout = 3000
                    try {
                        c.responseCode
                    } finally {
                        c.disconnect()
                    }
                }.getOrDefault(0)
            }
            if (status != 200) {
                DebugLog.add("Launcher didn't open it (HTTP $status), using the remote's link")
                if (current?.id == tv.id) open(app.link, haptic = false)
            }
        }
    }

    /** Pede a lista de apps ao GoatLauncher da TV (porta 6470). Sem ele, fica vazia e usam-se as apps vistas. */
    fun refreshApps() {
        val tv = current ?: return
        if (tv.kind == TvKind.APPLE) return
        viewModelScope.launch {
            val apps = withContext(Dispatchers.IO) {
                runCatching {
                    val c = URL("http://${tv.host}:$LAUNCHER_PORT/apps").openConnection() as HttpURLConnection
                    c.connectTimeout = 4000
                    c.readTimeout = 4000
                    try {
                        if (c.responseCode != 200) return@runCatching null
                        val array = JSONArray(String(c.inputStream.readLimited(MAX_APPS_BYTES), Charsets.UTF_8))
                        (0 until array.length()).map { i ->
                            val o = array.getJSONObject(i)
                            TvApp(o.getString("package"), o.getString("label"), o.optBoolean("banner"), o.optString("color").ifEmpty { null })
                        }.distinctBy { it.pkg }
                    } finally {
                        c.disconnect()
                    }
                }.getOrNull()
            }
            if (apps != null) setLauncher(tv.id, true)
            if (apps != null && current?.id == tv.id) installedApps = apps
        }
    }

    /** O banner (ou ícone) de uma app, dado pelo GoatLauncher (ou, na Apple TV, o da App Store). */
    fun iconUrl(pkg: String): String? {
        val tv = current ?: return null
        return if (tv.kind == TvKind.APPLE) appleArtwork[pkg] else "http://${tv.host}:$LAUNCHER_PORT/icon/$pkg"
    }

    // ---- Canais do GoatTV (porta 6471) ----

    enum class ChannelsStatus {
        UNKNOWN,
        READY,
        /** Ligação recusada ou 503: o GoatTV não está aberto (ou ainda não carregou a lista). */
        CLOSED,
        FAILED,
    }

    private var channelsJob: Job? = null
    private var playJob: Job? = null

    /** Pede a lista ao GoatTV da TV. Ao ligar e ao abrir a folha. */
    fun refreshChannels() {
        val tv = current ?: return
        if (channelsJob?.isActive == true) return
        channelsJob = viewModelScope.launch { loadChannels(tv) }
    }

    /** true se veio a lista. */
    private suspend fun loadChannels(tv: SavedTv): Boolean {
        var refused = false
        var status = 0
        val list = withContext(Dispatchers.IO) {
            try {
                val c = URL(GoatTvChannels.url(tv.host, "channels")).openConnection() as HttpURLConnection
                c.connectTimeout = 4000
                c.readTimeout = 8000
                try {
                    status = c.responseCode
                    if (status != 200) null
                    else GoatTvChannels.parse(String(c.inputStream.readLimited(GoatTvChannels.MAX_BYTES), Charsets.UTF_8))
                } finally {
                    c.disconnect()
                }
            } catch (e: java.net.ConnectException) {
                refused = true
                null
            } catch (e: Exception) {
                DebugLog.add("Channels: $e")
                null
            }
        }
        if (current?.id != tv.id) return false
        when {
            list != null -> {
                channels = list
                channelsStatus = ChannelsStatus.READY
                if (!hasChannels) DebugLog.add("GoatTV channels on ${tv.name}: ${list.channels.size}")
                hasChannels = true
                prefs.edit().putBoolean("goattv.${tv.id}", true).apply()
            }
            refused || status == 503 -> {
                channels = null
                channelsStatus = ChannelsStatus.CLOSED
            }
            // Outra resposta (ou nenhuma): fica a lista que já havia.
            else -> if (channels == null) channelsStatus = ChannelsStatus.FAILED
        }
        return list != null
    }

    /**
     * Como abrir o GoatTV nesta TV: na Android TV pelo GoatLauncher (só se se sabe que o tem); na Apple TV pela
     * própria ligação, se ele estiver na lista de apps dela. null: só se pode pedir para o abrirem na TV.
     */
    val goatTvApp: TvApp?
        get() {
            val tv = current ?: return null
            return when (tv.kind) {
                TvKind.ANDROID -> if (hasLauncher(tv.id) == true) TvApp(GoatTvChannels.ANDROID_PACKAGE, "GoatTV") else null
                TvKind.APPLE -> GoatTvChannels.appleApp(installedApps.associate { it.pkg to it.label })?.let { TvApp(it, "GoatTV") }
            }
        }

    /** "Abrir o GoatTV" na folha dos canais: abre-o e espera (até 10 s) que dê a lista. */
    fun openGoatTv() {
        val tv = current ?: return
        val app = goatTvApp ?: return
        DebugLog.add("Opening GoatTV for the channels")
        launch(app)
        openingGoatTv = true
        viewModelScope.launch {
            try {
                repeat(10) {
                    delay(1000)
                    if (current?.id != tv.id || loadChannels(tv)) return@launch
                }
            } finally {
                if (current?.id == tv.id) openingGoatTv = false
            }
        }
    }

    /**
     * O canal que o GoatTV está a dar, se ele estiver à frente (na Android TV pela app aberta; a Apple TV não diz qual
     * é, por isso vale a última lista que veio).
     */
    val nowPlaying: TvChannel?
        get() {
            val list = channels ?: return null
            if (current?.kind == TvKind.ANDROID && state.currentApp != GoatTvChannels.ANDROID_PACKAGE) return null
            return list.channels.firstOrNull { it.key == list.current }
        }

    /**
     * Pergunta ao GoatTV o que está a dar (GET /now, pequeno). Se o canal mudou (pelo comando da TV, por exemplo), o
     * cartão muda; um canal que a lista não tem pede a lista outra vez. Fechado (Apple TV em segundo plano), o cartão sai.
     */
    private suspend fun pollNow(tv: SavedTv) {
        if (tv.id in withoutNow) return
        var status = 0
        var refused = false
        val info = withContext(Dispatchers.IO) {
            try {
                val c = URL(GoatTvChannels.url(tv.host, "now")).openConnection() as HttpURLConnection
                c.connectTimeout = 2000
                c.readTimeout = 3000
                try {
                    status = c.responseCode
                    if (status != 200) null
                    else GoatTvChannels.parseNow(String(c.inputStream.readLimited(GoatTvChannels.MAX_NOW_BYTES), Charsets.UTF_8))
                } finally {
                    c.disconnect()
                }
            } catch (e: java.net.ConnectException) {
                refused = true
                null
            } catch (e: Exception) {
                null
            }
        }
        if (current?.id != tv.id) return
        when {
            info != null -> {
                nowInfo = info
                val list = channels ?: return
                if (info.current == list.current) return
                if (info.current == null || list.channels.any { it.key == info.current }) channels = list.copy(current = info.current)
                else refreshChannels()
            }
            status == 404 -> {
                DebugLog.add("GoatTV on ${tv.name} has no /now")
                withoutNow.add(tv.id)
            }
            refused || status == 503 -> {
                channels = null
                channelsStatus = ChannelsStatus.CLOSED
                nowInfo = null
            }
        }
    }

    init {
        // Com o GoatTV à frente e a lista dele, a cada 3 s: o canal pode mudar pelo comando da TV.
        viewModelScope.launch {
            while (true) {
                delay(3000)
                val tv = current ?: continue
                val front = tv.kind == TvKind.APPLE || state.currentApp == GoatTvChannels.ANDROID_PACKAGE
                if (status == Status.Connected && channels != null && front) pollNow(tv)
            }
        }
    }

    /** Canal seguinte ou anterior, no grupo do que está a dar (como o zapping na TV). */
    fun zap(delta: Int) {
        val list = channels ?: return
        val now = nowPlaying ?: return
        val group = list.channels.filter { it.group == now.group }.ifEmpty { list.channels }
        val i = group.indexOfFirst { it.key == now.key }
        if (i < 0) return
        play(group[(i + delta).mod(group.size)])
    }

    fun goatTvClosedLine() = L("GoatTV has to be open on the TV", "O GoatTV tem de estar aberto na TV")

    fun channelLogoUrl(channel: TvChannel): String? {
        val tv = current ?: return null
        return if (channel.logo) GoatTvChannels.url(tv.host, "logo", channel.key) else null
    }

    /**
     * Muda de canal no GoatTV. Se ele não estiver à frente (409, 503 ou ligação recusada), abre-se e tenta-se outra vez
     * a cada segundo, até 10 s. Um toque novo cancela o anterior (para fazer zapping).
     */
    fun play(channel: TvChannel) {
        val tv = current ?: return
        if (haptics) vibrate(false)
        playProblem = null
        DebugLog.add("Play channel ${channel.num ?: "-"} via GoatTV")
        playJob?.cancel()
        playJob = viewModelScope.launch {
            var deadline = 0L
            while (true) {
                val (status, refused) = postPlay(tv, channel.key)
                if (current?.id != tv.id) return@launch
                when (GoatTvChannels.playOutcome(status, refused)) {
                    GoatTvChannels.Play.DONE -> {
                        channels = channels?.copy(current = channel.key)
                        delay(800)
                        pollNow(tv)
                        return@launch
                    }
                    GoatTvChannels.Play.NOT_FOUND -> {
                        playProblem = L("This channel isn't available on the TV", "Este canal não está disponível na TV")
                        refreshChannels()
                        return@launch
                    }
                    GoatTvChannels.Play.FAILED -> {
                        DebugLog.add("Play: GoatTV answered HTTP $status")
                        playProblem = L("GoatTV didn't answer. Try again", "O GoatTV não respondeu. Tenta outra vez")
                        return@launch
                    }
                    GoatTvChannels.Play.RETRY -> {
                        if (deadline == 0L && tv.kind == TvKind.ANDROID && state.currentApp == GoatTvChannels.ANDROID_PACKAGE) {
                            // Já está à frente, só ainda não pode (a meio de mudar de canal): abri-lo outra vez não
                            // ajuda, e o link pelo comando faz a SHIELD fechar a ligação.
                            DebugLog.add("Play: GoatTV is in front but answered ${if (refused) "refused" else "HTTP $status"}, waiting")
                            deadline = System.currentTimeMillis() + 10_000
                        } else if (deadline == 0L) {
                            val app = goatTvApp ?: if (tv.kind == TvKind.ANDROID) TvApp(GoatTvChannels.ANDROID_PACKAGE, "GoatTV") else null
                            if (app == null) {
                                playProblem = goatTvClosedLine()
                                return@launch
                            }
                            DebugLog.add("Play: GoatTV isn't in front (${if (refused) "refused" else "HTTP $status"}), opening it")
                            launch(app, haptic = false)
                            deadline = System.currentTimeMillis() + 10_000
                        } else if (System.currentTimeMillis() >= deadline) {
                            playProblem = L("GoatTV didn't switch channels. Check the TV and try again",
                                "O GoatTV não mudou de canal. Vê a TV e tenta outra vez")
                            return@launch
                        }
                        delay(1000)
                    }
                }
            }
        }
    }

    private suspend fun postPlay(tv: SavedTv, key: String): Pair<Int, Boolean> = withContext(Dispatchers.IO) {
        try {
            val c = URL(GoatTvChannels.url(tv.host, "play", key)).openConnection() as HttpURLConnection
            c.requestMethod = "POST"
            c.connectTimeout = 3000
            c.readTimeout = 4000
            try {
                c.responseCode to false
            } finally {
                c.disconnect()
            }
        } catch (e: java.net.ConnectException) {
            0 to true
        } catch (e: Exception) {
            DebugLog.add("Play failed: $e")
            0 to false
        }
    }

    // ---- TVs ----

    fun select(tv: SavedTv) {
        if (tv.id == current?.id) return
        link?.close()
        link = null
        current = tv
        store.currentId = tv.id
        resetFor(tv)
        connect()
    }

    private fun resetFor(tv: SavedTv?) {
        state = TvState()
        recentApps = loadRecents(tv?.id)
        installedApps = emptyList()
        playJob?.cancel()
        hasChannels = tv?.let { prefs.getBoolean("goattv.${it.id}", false) } ?: false
        channels = null
        channelsStatus = ChannelsStatus.UNKNOWN
        openingGoatTv = false
        playProblem = null
    }

    fun forget(tv: SavedTv) {
        if (tv.kind == TvKind.APPLE) CompanionCredentials.delete(context, tv.id)
        store.remove(tv.id)
        prefs.edit().remove("recents.${tv.id}").remove("launcher.${tv.id}").remove("volumeUnknown.${tv.id}").remove("goattv.${tv.id}").apply()
        tvs = store.all
        if (current?.id == tv.id) {
            link?.close()
            link = null
            current = store.current
            resetFor(current)
            status = if (current == null) Status.NoTv else Status.Connecting
            connect()
        }
    }

    fun startPairing(found: FoundTv) = startPairing(found.name, found.id, found.host, found.kind, found.port)

    /** Emparelhar uma TV encontrada na rede ou escrita à mão (IP). */
    fun startPairing(name: String, id: String, host: String?, kind: TvKind = TvKind.ANDROID, port: Int? = null) {
        pairing?.cancel()
        pairing = null
        val model = PairingModel(this, name, id, host, kind, port)
        if (tvs.isNotEmpty()) closeSheets++
        pairing = model
        model.start()
    }

    /** Emparelhar outra vez a TV escolhida (a TV esqueceu este telemóvel). */
    fun repairCurrent() {
        val tv = current ?: return
        startPairing(tv.name, tv.id, tv.host, tv.kind, tv.port)
    }

    internal fun paired(tv: SavedTv) {
        store.save(tv)
        store.currentId = tv.id
        tvs = store.all
        link?.close()
        link = null
        current = tv
        resetFor(tv)
        status = Status.Connecting
        connect()
    }

    // ---- Comando ----

    /** [haptic] false nas repetições de uma tecla mantida: vibrava a cada passo, mais do que a TV avançava. */
    fun press(key: Key, haptic: Boolean = true) {
        if (haptic && haptics) vibrate(false)
        val link = link
        if (link == null || status != Status.Connected) return reconnectIfNeeded()
        if (noVolume(key) || volumeViaLauncher(key)) return
        link.key(key)
    }

    /** O GoatLauncher da TV sabe mudar o volume (null: ainda não se sabe; false: é uma versão sem isso). */
    /**
     * Se a TV tem o GoatLauncher (fica guardado por TV: null enquanto não se sabe). Com ele, ou sem se saber, o
     * volume nunca vai como tecla: as teclas de volume do protocolo rebentam o Android 11 da SHIELD quando o
     * GoatLauncher vê as teclas (botões a abrir apps). Só se manda tecla quando se tem a certeza de que não há
     * launcher: 404, ou ligação recusada na porta dele, numa TV onde nunca se viu nenhum. Onde já se viu, isso é só não
     * ter respondido; esquecer a TV limpa o que se sabe, se o launcher saiu mesmo de lá.
     */
    private fun hasLauncher(tvId: String): Boolean? =
        if (prefs.contains("launcher.$tvId")) prefs.getBoolean("launcher.$tvId", false) else null

    private fun setLauncher(tvId: String, value: Boolean) = prefs.edit().putBoolean("launcher.$tvId", value).apply()

    /**
     * Com HDMI-CEC, o volume está na TV e a box não sabe o valor: o que reporta não diz nada. Descobre-se ao
     * carregar: o launcher mudou o volume e o valor não mexeu. Fica guardado por TV.
     */
    private val volumeUnknown: Boolean
        get() = current?.let { prefs.getBoolean("volumeUnknown.${it.id}", false) } ?: false

    private var volumeSettlesAt = 0L

    /** A última tecla, para o indicador numa TV sem valor de volume (null: mostra-se a barra). */
    var volumePressed by mutableStateOf<Key?>(null)
        private set

    /** Mostrado no indicador de volume quando o launcher não respondeu (null: nada a dizer). */
    var volumeProblem by mutableStateOf<String?>(null)
        private set

    /** O volume pelo GoatLauncher (POST /volume/…) em vez de tecla; false se esta TV não tem launcher (tecla). */
    private fun volumeViaLauncher(key: Key): Boolean {
        val tv = current ?: return false
        val what = LauncherVolume.path(key) ?: return false
        if (tv.kind != TvKind.ANDROID || hasLauncher(tv.id) == false) return false
        val beforeVolume = state.volume
        val beforeMuted = state.muted
        viewModelScope.launch {
            var refused = false
            val status = withContext(Dispatchers.IO) {
                try {
                    val c = URL("http://${tv.host}:$LAUNCHER_PORT/volume/$what").openConnection() as HttpURLConnection
                    c.requestMethod = "POST"
                    c.connectTimeout = 3000
                    c.readTimeout = 3000
                    try {
                        c.responseCode
                    } finally {
                        c.disconnect()
                    }
                } catch (e: java.net.ConnectException) {
                    refused = true
                    0
                } catch (e: Exception) {
                    DebugLog.add("Volume via launcher failed: $e")
                    0
                }
            }
            when (LauncherVolume.outcome(hasLauncher(tv.id), status, refused)) {
                LauncherVolume.Outcome.DONE -> {
                    setLauncher(tv.id, true)
                    volumeProblem = null
                    delay(800)
                    if (current?.id == tv.id) {
                        val unknown = state.volume == beforeVolume && state.muted == beforeMuted
                        prefs.edit().putBoolean("volumeUnknown.${tv.id}", unknown).apply()
                        volumePressed = if (unknown) key else null
                        if (unknown) volumeChanged++
                    }
                }
                LauncherVolume.Outcome.NO_LAUNCHER -> {
                    DebugLog.add("Volume: no launcher on ${tv.name} (${if (refused) "refused" else "404"}), using keys")
                    setLauncher(tv.id, false)
                    if (current?.id == tv.id) link?.key(key)
                }
                LauncherVolume.Outcome.DIDNT_ANSWER -> if (current?.id == tv.id) {
                    DebugLog.add("Volume: launcher on ${tv.name} didn't answer (HTTP $status), not sending the key")
                    volumeProblem = when {
                        status == 404 -> L("Update GoatLauncher on the TV to change the volume from here", "Atualiza o GoatLauncher na TV para mudares o volume daqui")
                        refused -> L("GoatLauncher isn't running on the TV. Open it. If you removed it, forget this TV and pair it again",
                            "O GoatLauncher não está a correr na TV. Abre-o. Se o tiraste, esquece esta TV e emparelha-a outra vez")
                        else -> L("The TV's launcher didn't answer. Try again", "O launcher da TV não respondeu. Tenta outra vez")
                    }
                    volumeChanged++
                }
            }
        }
        return true
    }

    /** Volume numa TV que não o controla: em vez de não fazer nada, o indicador explica porquê. */
    private fun noVolume(key: Key): Boolean {
        if (key !in listOf(Key.VOLUME_UP, Key.VOLUME_DOWN, Key.MUTE) || state.volumeControl) return false
        volumeChanged++
        return true
    }

    /** Carregar e manter: início e fim. */
    fun hold(key: Key, down: Boolean) {
        if (down) repeatStarted()
        val link = link
        if (link == null || status != Status.Connected) return reconnectIfNeeded()
        if (down && noVolume(key)) return
        val tv = current
        if (key in listOf(Key.VOLUME_UP, Key.VOLUME_DOWN, Key.MUTE) && tv?.kind == TvKind.ANDROID && hasLauncher(tv.id) != false) {
            // Pelo GoatLauncher não há "manter": cada toque é um passo.
            if (down) volumeViaLauncher(key)
            return
        }
        link.key(key, if (down) KeyDirection.START_LONG else KeyDirection.END_LONG)
    }

    fun type(text: String) {
        val link = link ?: return
        if (status == Status.Connected) link.text(text)
    }

    fun open(target: String, haptic: Boolean = true) {
        if (haptic && haptics) vibrate(false)
        val link = link
        if (link == null || status != Status.Connected) return reconnectIfNeeded()
        DebugLog.add("Open app: $target")
        link.openApp(target)
    }

    private fun reconnectIfNeeded() {
        if (status is Status.Unreachable) connect()
    }

    /** Começou a manter uma tecla (o OK longo, ou uma seta a repetir): uma vibração forte, só esta. */
    fun repeatStarted() {
        if (haptics) vibrate(true)
    }

    private fun vibrate(strong: Boolean) {
        val v = vibrator ?: return
        if (Build.VERSION.SDK_INT >= 29) {
            v.vibrate(VibrationEffect.createPredefined(if (strong) VibrationEffect.EFFECT_HEAVY_CLICK else VibrationEffect.EFFECT_TICK))
        } else {
            v.vibrate(VibrationEffect.createOneShot(if (strong) 30 else 12, VibrationEffect.DEFAULT_AMPLITUDE))
        }
    }

    override fun onCleared() {
        link?.close()
        pairing?.cancel()
        finder.stop()
    }

    internal fun describe(e: Throwable): String = e.message?.takeIf { it.isNotBlank() } ?: e.javaClass.simpleName

    companion object {
        const val LAUNCHER_PORT = 6470
        private const val MAX_APPS_BYTES = 2 shl 20
    }
}

/** Um emparelhamento: liga à TV, a TV mostra o código e espera-se que a pessoa o escreva. */
class PairingModel(private val vm: RemoteViewModel, val name: String, private val tvId: String, private var host: String?, val kind: TvKind, private var port: Int?) {
    private var phaseValue by mutableStateOf<Phase>(Phase.Connecting)
    var phase: Phase
        get() = phaseValue
        private set(value) {
            if (value != phaseValue) DebugLog.add("Pairing $name: $value")
            phaseValue = value
        }

    /** O código que a TV mostra: 6 caracteres hexadecimais (Android TV) ou um PIN de 4 algarismos (Apple TV). */
    val codeLength: Int get() = if (kind == TvKind.APPLE) 4 else Pairing.CODE_LENGTH

    private var code: CompletableDeferred<String>? = null
    private var job: Job? = null
    private var socket: TvSocket? = null

    fun start() {
        DebugLog.add("Pairing $name ($kind) started")
        job = vm.viewModelScope.launch { if (kind == TvKind.APPLE) runApple() else runAndroid() }
    }

    private suspend fun runAndroid() {
        try {
            val host = host ?: throw UnreachableException(L("Couldn't find the TV on the network", "Não deu para encontrar a TV na rede"))
            DebugLog.add("Pairing: TV at $host:${Pairing.PORT}")
            val identity = withContext(Dispatchers.IO) { vm.identities.get() }
            val socket = TvSocket.open(host, Pairing.PORT, identity)
            DebugLog.add("Pairing: TLS open")
            this.socket = socket
            val server = socket.serverCertificate?.let(RsaKey::of)
                ?: throw UnreachableException(L("The TV's certificate is unreadable", "O certificado da TV não se lê"))
            val client = RsaKey.of(identity.certificate)!!
            Pairing.run(
                clientName = vm.deviceName,
                client = client,
                server = server,
                send = { socket.send(it) },
                receive = { withContext(Dispatchers.IO) { socket.receive() } },
                askCode = { retry -> askCode(retry) },
            )
            socket.close()
            phase = Phase.Done
            vm.paired(SavedTv(tvId, name, host))
            delay(700)
            if (vm.pairing === this) vm.pairing = null
        } catch (e: kotlinx.coroutines.CancellationException) {
            socket?.close()
        } catch (e: Exception) {
            DebugLog.add("Pairing failed: $e")
            socket?.close()
            phase = Phase.Failed(explain(e))
        }
    }

    /** Apple TV: SRP com o PIN, e as credenciais ficam guardadas. */
    private suspend fun runApple() {
        try {
            val host = host
            val port = port
            if (host == null || port == null) {
                throw UnreachableException(L("Couldn't find the TV on the network", "Não deu para encontrar a TV na rede"))
            }
            DebugLog.add("Pairing: Apple TV at $host:$port")
            val creds = AppleTvPairing.pair(host, port, vm.deviceName) { askCode(false) }
            CompanionCredentials.save(vm.appContext, tvId, creds)
            phase = Phase.Done
            vm.paired(SavedTv(tvId, name, host, TvKind.APPLE, port))
            delay(700)
            if (vm.pairing === this) vm.pairing = null
        } catch (e: kotlinx.coroutines.CancellationException) {
            DebugLog.add("Pairing cancelled")
            return
        } catch (e: Exception) {
            DebugLog.add("Pairing failed: $e")
            phase = Phase.Failed(explain(e))
        }
    }

    private suspend fun askCode(retry: Boolean): String {
        val deferred = CompletableDeferred<String>()
        code = deferred
        phase = Phase.WaitingCode(retry)
        return deferred.await()
    }

    /** O código que a pessoa escreveu. */
    fun submit(value: String) {
        val deferred = code ?: return
        code = null
        phase = Phase.Checking
        deferred.complete(value)
    }

    /** Recomeça (a TV volta a mostrar um código novo). */
    fun retry() {
        cancel()
        phase = Phase.Connecting
        start()
    }

    fun cancel() {
        code?.cancel()
        code = null
        job?.cancel()
        socket?.close()
    }

    private fun explain(e: Exception): String = when (e) {
        is Pairing.Rejected -> L("The TV refused (${e.status}). Try again.", "A TV recusou (${e.status}). Tenta outra vez.")
        is NotPairedException, is java.io.EOFException ->
            L("The TV closed the connection. Try again.", "A TV fechou a ligação. Tenta outra vez.")
        is AppleTvPairing.WrongPin -> L("Wrong PIN. Try again: the TV will show a new one.", "PIN errado. Tenta outra vez: a TV mostra um novo.")
        is AppleTvPairing.Refused -> appleRefusal(e.code, e.retryAfter)
        is CompanionConnection.TvError -> L("The TV refused: ${e.message}", "A TV recusou: ${e.message}")
        else -> vm.describe(e)
    }
}

/** O que quer dizer cada recusa da Apple TV (códigos de erro do emparelhamento HomeKit). */
private fun appleRefusal(code: Int, retryAfter: Int?): String = when (code) {
    3 -> {
        val wait = retryAfter?.let { if (it >= 90) L("${(it + 59) / 60} minutes", "${(it + 59) / 60} minutos") else L("$it seconds", "$it segundos") }
            ?: L("a few minutes", "uns minutos")
        L("After several tries, the Apple TV is blocking pairing for a while. Wait $wait (or restart the Apple TV) and try again with the Apple TV awake and on screen.",
            "Depois de várias tentativas, a Apple TV bloqueou o emparelhamento por um bocado. Espera $wait (ou reinicia a Apple TV) e tenta outra vez com a Apple TV ligada e no ecrã.")
    }
    4 -> L("The Apple TV has too many paired devices. Remove one in Settings → Remotes and Devices → Remote App and Devices.",
        "A Apple TV tem demasiados aparelhos emparelhados. Remove um em Definições → Comandos e dispositivos → App Remote e dispositivos.")
    5 -> L("Too many wrong PINs. Restart the Apple TV and try again.", "Demasiados PINs errados. Reinicia a Apple TV e tenta outra vez.")
    6 -> L("The Apple TV isn't accepting new devices. On the Apple TV, set Settings → AirPlay and HomeKit → Allow Access to “Everyone on the Same Network” and try again.",
        "A Apple TV não está a aceitar aparelhos novos. Na Apple TV, põe Definições → AirPlay e HomeKit → Permitir acesso em “Todos na mesma rede” e tenta outra vez.")
    7 -> L("The Apple TV is busy pairing with another device. Try again in a moment.", "A Apple TV está a emparelhar com outro aparelho. Tenta outra vez daqui a pouco.")
    else -> L("The Apple TV refused (code $code). Try again.", "A Apple TV recusou (código $code). Tenta outra vez.")
}
