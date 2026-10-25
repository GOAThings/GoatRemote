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
import cc.slokker.goatremote.data.FoundTv
import cc.slokker.goatremote.data.SavedTv
import cc.slokker.goatremote.data.TvApp
import cc.slokker.goatremote.data.TvFinder
import cc.slokker.goatremote.data.TvKind
import cc.slokker.goatremote.data.TvStore
import cc.slokker.goatremote.tv.AndroidTvLink
import cc.slokker.goatremote.tv.IdentityStore
import cc.slokker.goatremote.tv.Key
import cc.slokker.goatremote.tv.KeyDirection
import cc.slokker.goatremote.tv.NotPairedException
import cc.slokker.goatremote.tv.Pairing
import cc.slokker.goatremote.tv.RsaKey
import cc.slokker.goatremote.tv.TvControl
import cc.slokker.goatremote.tv.TvSocket
import cc.slokker.goatremote.tv.TvState
import cc.slokker.goatremote.tv.UnreachableException
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

    private val context: Context get() = getApplication()
    private val store = TvStore(app)
    private val prefs = app.getSharedPreferences("options", Context.MODE_PRIVATE)
    private val identities = IdentityStore(File(app.filesDir, "identity"))
    val finder = TvFinder(app)

    var tvs by mutableStateOf(store.all)
        private set
    var current by mutableStateOf(store.current)
        private set
    var status by mutableStateOf<Status>(if (store.current == null) Status.NoTv else Status.Connecting)
        private set
    var state by mutableStateOf(TvState())
        private set
    /** As apps que se viu abertas nesta TV (as mais recentes primeiro), para as abrir com um toque. */
    var recentApps by mutableStateOf(loadRecents(store.current?.id))
        private set
    /** As apps instaladas na TV, se ela tiver o GoatLauncher (que as dá na rede de casa); vazio sem ele. */
    var installedApps by mutableStateOf<List<TvApp>>(emptyList())
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
    /** Touchpad: só deslizar e tocar, ou também tocar nas bordas para as setas. */
    var dpadTaps by mutableStateOf(prefs.getBoolean("dpadTaps", false))
        private set

    fun changeHaptics(on: Boolean) { haptics = on; prefs.edit().putBoolean("haptics", on).apply() }
    fun changeVolumeButtons(on: Boolean) { volumeButtons = on; prefs.edit().putBoolean("volumeButtons", on).apply() }
    fun changeDpadTaps(on: Boolean) { dpadTaps = on; prefs.edit().putBoolean("dpadTaps", on).apply() }

    private var link: TvControl? = null
    private var stateJob: Job? = null
    /** Ícones das apps da Apple TV (da App Store, por bundle id). */
    private val appleArtwork = mutableStateMapOf<String, String>()
    private val vibrator = app.getSystemService(Vibrator::class.java)

    val deviceName: String
        get() = Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) ?: Build.MODEL

    // ---- Ligação ----

    /**
     * Liga à TV escolhida. Uma falha que não seja "não emparelhado" tenta mais uma vez daí a pouco: a SHIELD, por
     * exemplo, recusa a primeira ligação logo a seguir a emparelhar.
     */
    fun connect(retry: Boolean = true) {
        val tv = current ?: run { status = Status.NoTv; return }
        if (link != null && (status == Status.Connected || status == Status.Connecting)) return
        link?.close()
        status = Status.Connecting
        val link = makeLink(tv)
        this.link = link
        (link as? AppleTvLink)?.onApps = { apps -> viewModelScope.launch { appleApps(apps, tv) } }
        link.onClose = {
            viewModelScope.launch {
                if (this@RemoteViewModel.link === link) {
                    this@RemoteViewModel.link = null
                    status = Status.Unreachable(L("The TV closed the connection", "A TV fechou a ligação"))
                }
            }
        }
        stateJob?.cancel()
        stateJob = viewModelScope.launch { link.state.collect { if (this@RemoteViewModel.link === link) update(it) } }
        viewModelScope.launch {
            try {
                link.connect()
                if (this@RemoteViewModel.link !== link) return@launch
                status = Status.Connected
                update(link.state.value)
                refreshApps()
            } catch (e: NotPairedException) {
                if (this@RemoteViewModel.link !== link) return@launch
                this@RemoteViewModel.link = null
                status = Status.NotPaired
            } catch (e: Exception) {
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
        if (old.volume != null && (new.volume != old.volume || new.muted != old.muted)) volumeChanged++
        val app = new.currentApp
        if (app != null && app != old.currentApp && !AppCatalog.isLauncher(app)) {
            recentApps = (listOf(app) + recentApps.filterNot { it == app }).take(12)
            current?.id?.let { prefs.edit().putString("recents.$it", JSONArray(recentApps).toString()).apply() }
        }
    }

    private fun loadRecents(id: String?): List<String> {
        id ?: return emptyList()
        val array = runCatching { JSONArray(context.getSharedPreferences("options", Context.MODE_PRIVATE).getString("recents.$id", "[]")) }
            .getOrNull() ?: return emptyList()
        return (0 until array.length()).map { array.getString(it) }
    }

    /** A ligação certa para o tipo de TV. */
    private fun makeLink(tv: SavedTv): TvControl = when (tv.kind) {
        TvKind.APPLE -> AppleTvLink(tv.host, tv.port ?: AppleTvLink.DEFAULT_PORT, { CompanionCredentials.load(context, tv.id) },
            deviceName, stableId())
        TvKind.ANDROID -> AndroidTvLink(tv.host, identities::get, BuildConfig.VERSION_NAME, Build.MODEL)
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
    fun launch(app: TvApp) = open(if (current?.kind == TvKind.APPLE) app.pkg else app.link)

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
                        val array = JSONArray(c.inputStream.bufferedReader().readText())
                        (0 until array.length()).map { i ->
                            val o = array.getJSONObject(i)
                            TvApp(o.getString("package"), o.getString("label"), o.optBoolean("banner"), o.optString("color").ifEmpty { null })
                        }
                    } finally {
                        c.disconnect()
                    }
                }.getOrNull()
            }
            if (apps != null && current?.id == tv.id) installedApps = apps
        }
    }

    /** O banner (ou ícone) de uma app, dado pelo GoatLauncher (ou, na Apple TV, o da App Store). */
    fun iconUrl(pkg: String): String? {
        val tv = current ?: return null
        return if (tv.kind == TvKind.APPLE) appleArtwork[pkg] else "http://${tv.host}:$LAUNCHER_PORT/icon/$pkg"
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
        launcherVolume = null
        state = TvState()
        recentApps = loadRecents(tv?.id)
        installedApps = emptyList()
    }

    fun forget(tv: SavedTv) {
        if (tv.kind == TvKind.APPLE) CompanionCredentials.delete(context, tv.id)
        store.remove(tv.id)
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
        val model = PairingModel(name, id, host, kind, port)
        if (tvs.isNotEmpty()) closeSheets++
        pairing = model
        model.start()
    }

    /** Emparelhar outra vez a TV escolhida (a TV esqueceu este telemóvel). */
    fun repairCurrent() {
        val tv = current ?: return
        startPairing(tv.name, tv.id, tv.host, tv.kind, tv.port)
    }

    private fun paired(tv: SavedTv) {
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

    fun press(key: Key) {
        if (haptics) vibrate(false)
        val link = link
        if (link == null || status != Status.Connected) return reconnectIfNeeded()
        if (noVolume(key) || volumeViaLauncher(key)) return
        link.key(key)
    }

    /** O GoatLauncher da TV sabe mudar o volume (null: ainda não se sabe; false: é uma versão sem isso). */
    private var launcherVolume: Boolean? = null

    /**
     * Com o GoatLauncher na TV, o volume vai por ele (POST /volume/…) em vez de tecla: as teclas de volume do
     * protocolo rebentam o Android 11 da SHIELD quando o GoatLauncher vê as teclas (botões a abrir apps). Um
     * GoatLauncher antigo responde 404 e volta-se às teclas.
     */
    private fun volumeViaLauncher(key: Key): Boolean {
        val tv = current ?: return false
        val what = when (key) {
            Key.VOLUME_UP -> "up"
            Key.VOLUME_DOWN -> "down"
            Key.MUTE -> "mute"
            else -> return false
        }
        if (tv.kind != TvKind.ANDROID || installedApps.isEmpty() || launcherVolume == false) return false
        viewModelScope.launch {
            val status = withContext(Dispatchers.IO) {
                runCatching {
                    val c = URL("http://${tv.host}:$LAUNCHER_PORT/volume/$what").openConnection() as HttpURLConnection
                    c.requestMethod = "POST"
                    c.connectTimeout = 2000
                    c.readTimeout = 2000
                    try {
                        c.responseCode
                    } finally {
                        c.disconnect()
                    }
                }.getOrDefault(0)
            }
            if (status == 200) {
                launcherVolume = true
            } else if (current?.id == tv.id) {
                if (status == 404) launcherVolume = false
                link?.key(key)
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
        if (down && haptics) vibrate(true)
        val link = link
        if (link == null || status != Status.Connected) return reconnectIfNeeded()
        if (down && noVolume(key)) return
        if (key in listOf(Key.VOLUME_UP, Key.VOLUME_DOWN, Key.MUTE) && current?.kind == TvKind.ANDROID && installedApps.isNotEmpty() &&
            launcherVolume != false
        ) {
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

    fun open(target: String) {
        if (haptics) vibrate(false)
        val link = link
        if (link == null || status != Status.Connected) return reconnectIfNeeded()
        link.openApp(target)
    }

    private fun reconnectIfNeeded() {
        if (status is Status.Unreachable) connect()
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

    private fun describe(e: Throwable): String = e.message?.takeIf { it.isNotBlank() } ?: e.javaClass.simpleName

    /** Um emparelhamento: liga à TV, a TV mostra o código e espera-se que a pessoa o escreva. */
    inner class PairingModel(val name: String, private val tvId: String, private var host: String?, val kind: TvKind, private var port: Int?) {
        var phase by mutableStateOf<Phase>(Phase.Connecting)
            private set

        /** O código que a TV mostra: 6 caracteres hexadecimais (Android TV) ou um PIN de 4 algarismos (Apple TV). */
        val codeLength: Int get() = if (kind == TvKind.APPLE) 4 else Pairing.CODE_LENGTH

        private var code: CompletableDeferred<String>? = null
        private var job: Job? = null
        private var socket: TvSocket? = null

        fun start() {
            job = viewModelScope.launch { if (kind == TvKind.APPLE) runApple() else runAndroid() }
        }

        private suspend fun runAndroid() {
            try {
                val host = host ?: throw UnreachableException(L("Couldn't find the TV on the network", "Não deu para encontrar a TV na rede"))
                val identity = withContext(Dispatchers.IO) { identities.get() }
                val socket = TvSocket.open(host, Pairing.PORT, identity)
                this.socket = socket
                val server = socket.serverCertificate?.let(RsaKey::of)
                    ?: throw UnreachableException(L("The TV's certificate is unreadable", "O certificado da TV não se lê"))
                val client = RsaKey.of(identity.certificate)!!
                Pairing.run(
                    clientName = deviceName,
                    client = client,
                    server = server,
                    send = { socket.send(it) },
                    receive = { withContext(Dispatchers.IO) { socket.receive() } },
                    askCode = { retry -> askCode(retry) },
                )
                socket.close()
                phase = Phase.Done
                paired(SavedTv(tvId, name, host))
                delay(700)
                if (pairing === this) pairing = null
            } catch (e: kotlinx.coroutines.CancellationException) {
                socket?.close()
            } catch (e: Exception) {
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
                val creds = AppleTvPairing.pair(host, port, deviceName) { askCode(false) }
                CompanionCredentials.save(context, tvId, creds)
                phase = Phase.Done
                paired(SavedTv(tvId, name, host, TvKind.APPLE, port))
                delay(700)
                if (pairing === this) pairing = null
            } catch (e: kotlinx.coroutines.CancellationException) {
                return
            } catch (e: Exception) {
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
            is CompanionConnection.TvError -> L("The TV refused: ${e.message}", "A TV recusou: ${e.message}")
            else -> describe(e)
        }
    }

    companion object {
        const val LAUNCHER_PORT = 6470
    }
}
