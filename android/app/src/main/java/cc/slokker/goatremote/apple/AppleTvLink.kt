package cc.slokker.goatremote.apple

import android.content.Context
import android.util.Base64
import cc.slokker.goatremote.DebugLog
import cc.slokker.goatremote.tv.Key
import cc.slokker.goatremote.tv.KeyDirection
import cc.slokker.goatremote.tv.NotPairedException
import cc.slokker.goatremote.tv.TvControl
import cc.slokker.goatremote.tv.TvState
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

/** O que fica guardado depois de emparelhar com uma Apple TV (num ficheiro privado da app, por TV). */
class CompanionCredentials(
    /** A chave pública Ed25519 da TV. */
    val tvPublicKey: ByteArray,
    /** A nossa chave privada Ed25519 (32 bytes). */
    val privateKey: ByteArray,
    /** O identificador da TV (da M6). */
    val tvId: ByteArray,
    /** O nosso identificador (UUID em texto, 36 bytes ASCII). */
    val clientId: ByteArray,
) {
    companion object {
        private fun prefs(context: Context) = context.getSharedPreferences("companion", Context.MODE_PRIVATE)
        private fun b64(b: ByteArray) = Base64.encodeToString(b, Base64.NO_WRAP)
        private fun bytes(s: String) = Base64.decode(s, Base64.NO_WRAP)

        fun load(context: Context, tvId: String): CompanionCredentials? = runCatching {
            val json = JSONObject(prefs(context).getString(tvId, null) ?: return null)
            CompanionCredentials(bytes(json.getString("tvPublicKey")), bytes(json.getString("privateKey")),
                bytes(json.getString("tvID")), bytes(json.getString("clientID")))
        }.getOrNull()

        fun save(context: Context, tvId: String, c: CompanionCredentials) {
            val json = JSONObject()
                .put("tvPublicKey", b64(c.tvPublicKey)).put("privateKey", b64(c.privateKey))
                .put("tvID", b64(c.tvId)).put("clientID", b64(c.clientId))
            prefs(context).edit().putString(tvId, json.toString()).apply()
        }

        fun delete(context: Context, tvId: String) {
            prefs(context).edit().remove(tvId).apply()
        }
    }
}

/** Emparelhar com uma Apple TV (a TV mostra um PIN de 4 algarismos). */
object AppleTvPairing {
    class WrongPin : Exception("wrong PIN")

    /**
     * A TV recusou com um código de erro do emparelhamento HomeKit (3 = espera, 4 = demasiados aparelhos,
     * 5 = demasiadas tentativas, 6 = indisponível, 7 = ocupada) e, às vezes, quantos segundos esperar.
     */
    class Refused(val code: Int, val retryAfter: Int?) : Exception("refused $code")

    suspend fun pair(host: String, port: Int, name: String, askPin: suspend () -> String): CompanionCredentials {
        val conn = CompanionConnection(host, port)
        conn.open()
        DebugLog.add("Apple pairing: connected to $host:$port")
        try {
            fun pd(message: Opack): Map<Int, ByteArray> {
                val tlv = Tlv8.decode(message["_pd"]?.data ?: ByteArray(0))
                // Só os tipos e tamanhos: os valores são o sal, as chaves e as provas.
                DebugLog.add("Apple pairing: got ${AppleTvLink.keys(message)} TLV ${tlv.keys.sorted().map { "$it:${tlv[it]!!.size}" }}")
                tlv[7]?.firstOrNull()?.let { error ->
                    if (error.toInt() == 2) throw WrongPin()
                    // RetryDelay (tipo 8): segundos, little-endian.
                    val delay = tlv[8]?.foldRight(0) { b, acc -> acc shl 8 or (b.toInt() and 0xFF) }
                    DebugLog.add("Apple pairing: refused, code ${error.toInt() and 0xFF}, retry after ${delay ?: "-"}")
                    throw Refused(error.toInt() and 0xFF, delay)
                }
                return tlv
            }
            suspend fun send(frame: CompanionConnection.Frame, vararg tlv: Pair<Int, ByteArray>) =
                conn.send(frame, Opack.dict("_pd" to Opack.Data(Tlv8.encode(*tlv)), "_pwTy" to Opack.Int(1), "_x" to Opack.Int(conn.nextXid())))
            suspend fun receive() = kotlinx.coroutines.withContext(Dispatchers.IO) { conn.receive().second }

            // M1 → M2: o sal e o B; a TV mostra o PIN.
            send(CompanionConnection.Frame.PAIR_SETUP_START, 0 to byteArrayOf(0), 6 to byteArrayOf(1))
            DebugLog.add("Apple pairing: M1 sent, waiting for the TV to show the PIN")
            val m2 = pd(receive())
            val salt = m2[2] ?: throw CompanionConnection.TvError("M2 sem sal")
            val serverKey = m2[3] ?: throw CompanionConnection.TvError("M2 sem B")
            val pin = askPin()
            DebugLog.add("Apple pairing: PIN entered, sending M3")
            // M3 → M4: as provas do SRP.
            val srp = SrpClient(Crypto.randomBytes(32))
            val result = srp.process(salt, serverKey, pin) ?: throw CompanionConnection.TvError("B inválido")
            send(CompanionConnection.Frame.PAIR_SETUP_NEXT, 6 to byteArrayOf(3), 3 to srp.publicKey, 4 to result.proof)
            val m4 = pd(receive())
            if (!(m4[4] ?: ByteArray(0)).contentEquals(result.expectedServerProof)) throw WrongPin()
            DebugLog.add("Apple pairing: PIN accepted, sending M5")
            // M5 → M6: trocam-se as identidades (Ed25519), cifradas com a chave do SRP.
            val k = result.sessionKey
            val encKey = Crypto.hkdf("Pair-Setup-Encrypt-Salt", "Pair-Setup-Encrypt-Info", k)
            val signing = Crypto.SigningKey.generate()
            val ltpk = signing.publicKey
            val clientId = UUID.randomUUID().toString().lowercase().toByteArray()
            val deviceX = Crypto.hkdf("Pair-Setup-Controller-Sign-Salt", "Pair-Setup-Controller-Sign-Info", k)
            val signature = signing.sign(deviceX + clientId + ltpk)
            val sub = Tlv8.encode(1 to clientId, 3 to ltpk, 10 to signature, 0x11 to Opack.dict("name" to Opack.Str(name)).encoded)
            send(CompanionConnection.Frame.PAIR_SETUP_NEXT, 6 to byteArrayOf(5), 5 to Crypto.seal(encKey, Crypto.pairingNonce("PS-Msg05"), sub))
            val m6 = pd(receive())
            val encrypted = m6[5]?.takeIf { it.size > 16 } ?: throw CompanionConnection.TvError("M6 sem dados")
            val tv = Tlv8.decode(Crypto.open(encKey, Crypto.pairingNonce("PS-Msg06"), encrypted))
            val tvId = tv[1]
            val tvKey = tv[3]
            val tvSignature = tv[10]
            if (tvId == null || tvKey == null || tvSignature == null) throw CompanionConnection.TvError("M6 incompleta")
            val accessoryX = Crypto.hkdf("Pair-Setup-Accessory-Sign-Salt", "Pair-Setup-Accessory-Sign-Info", k)
            if (!Crypto.verify(tvKey, tvSignature, accessoryX + tvId + tvKey)) {
                throw CompanionConnection.TvError("a assinatura da TV não bate certo")
            }
            DebugLog.add("Apple pairing: done")
            return CompanionCredentials(tvKey, signing.raw, tvId, clientId)
        } finally {
            conn.close()
        }
    }
}

/** O comando ligado a uma Apple TV: verifica (com as credenciais guardadas), abre a sessão e manda teclas. */
class AppleTvLink(
    private val host: String,
    private val port: Int,
    private val credentials: () -> CompanionCredentials?,
    private val deviceName: String,
    /** Um id estável por instalação (sem ele a TV não manda os eventos de ligada/desligada). */
    private val stableId: String,
) : TvControl {
    private val _state = MutableStateFlow(TvState())
    override val state: StateFlow<TvState> = _state
    override var onClose: (() -> Unit)? = null
    /** A lista de apps da TV (bundle id → nome), quando chega. */
    var onApps: ((Map<String, String>) -> Unit)? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var conn: CompanionConnection? = null
    private val pending = ConcurrentHashMap<Long, CompletableDeferred<Opack>>()
    @Volatile private var closed = false
    /** A sessão de texto aberta na TV (do _tiStart ou do _tiStarted), para onde vai o que se escreve. */
    @Volatile private var textSession: ByteArray? = null
    private var typing: Job? = null

    override suspend fun connect() {
        val creds = credentials() ?: throw NotPairedException()
        val conn = CompanionConnection(host, port)
        try {
            conn.open()
        } catch (e: Exception) {
            DebugLog.add("Apple TV: can't connect to $host:$port: $e")
            throw e
        }
        this.conn = conn
        try {
            verify(conn, creds)
            DebugLog.add("Apple TV: verified")
        } catch (e: Exception) {
            DebugLog.add("Apple TV: verify failed: $e")
            conn.close()
            throw NotPairedException()
        }
        scope.launch {
            try {
                while (true) dispatch(conn.receive().second)
            } catch (_: Exception) {
            }
            pending.values.forEach { it.completeExceptionally(CompanionConnection.TvError("closed")) }
            pending.clear()
            conn.close()
            if (!closed) onClose?.invoke()
        }
        startSession(creds)
    }

    /** Verificação (X25519 + as assinaturas Ed25519 do emparelhamento) e chaves da sessão. */
    private suspend fun verify(conn: CompanionConnection, creds: CompanionCredentials) {
        suspend fun receive() = kotlinx.coroutines.withContext(Dispatchers.IO) { conn.receive().second }
        val ephemeral = Crypto.AgreementKey()
        val epk = ephemeral.publicKey
        conn.send(CompanionConnection.Frame.PAIR_VERIFY_START,
            Opack.dict("_pd" to Opack.Data(Tlv8.encode(6 to byteArrayOf(1), 3 to epk)), "_auTy" to Opack.Int(4), "_x" to Opack.Int(conn.nextXid())))
        val m2 = Tlv8.decode(receive()["_pd"]?.data ?: ByteArray(0))
        m2[7]?.firstOrNull()?.let { DebugLog.add("Apple TV: verify refused, code ${it.toInt() and 0xFF}") }
        val tvEph = m2[3]
        val encrypted = m2[5]
        if (m2[7] != null || tvEph == null || encrypted == null || encrypted.size <= 16) throw NotPairedException()
        val secret = ephemeral.shared(tvEph)
        val pvKey = Crypto.hkdf("Pair-Verify-Encrypt-Salt", "Pair-Verify-Encrypt-Info", secret)
        val inner = Tlv8.decode(Crypto.open(pvKey, Crypto.pairingNonce("PV-Msg02"), encrypted))
        val id = inner[1]
        val signature = inner[10]
        if (id == null || !id.contentEquals(creds.tvId) || signature == null ||
            !Crypto.verify(creds.tvPublicKey, signature, tvEph + id + epk)
        ) throw NotPairedException()
        val mySignature = Crypto.SigningKey(creds.privateKey).sign(epk + creds.clientId + tvEph)
        val box = Crypto.seal(pvKey, Crypto.pairingNonce("PV-Msg03"), Tlv8.encode(1 to creds.clientId, 10 to mySignature))
        conn.send(CompanionConnection.Frame.PAIR_VERIFY_NEXT,
            Opack.dict("_pd" to Opack.Data(Tlv8.encode(6 to byteArrayOf(3), 5 to box)), "_x" to Opack.Int(conn.nextXid())))
        val m4 = Tlv8.decode(receive()["_pd"]?.data ?: ByteArray(0))
        m4[7]?.firstOrNull()?.let { DebugLog.add("Apple TV: verify M4 refused, code ${it.toInt() and 0xFF}") }
        if (m4[7] != null) throw NotPairedException()
        conn.encrypt(Crypto.hkdf("", "ClientEncrypt-main", secret), Crypto.hkdf("", "ServerEncrypt-main", secret))
    }

    /** A sequência de arranque (como o pyatv): sistema, toque, sessão, texto e eventos. */
    private suspend fun startSession(creds: CompanionCredentials) {
        request("_systemInfo", mapOf(
            "_bf" to Opack.Int(0), "_cf" to Opack.Int(512), "_clFl" to Opack.Int(128), "_i" to Opack.Str(stableId),
            "_idsID" to Opack.Data(creds.clientId), "_pubID" to Opack.Str("AA:BB:CC:DD:EE:FF"), "_sf" to Opack.Int(256),
            "_sv" to Opack.Str("170.18"), "model" to Opack.Str("iPhone"), "name" to Opack.Str(deviceName),
        ))
        request("_touchStart", mapOf("_height" to Opack.Double(1000.0), "_tFl" to Opack.Int(0), "_width" to Opack.Double(1000.0)))
        request("_sessionStart", mapOf("_srvT" to Opack.Str("com.apple.tvremoteservices"), "_sid" to Opack.Int((1L..0xFFFF_FFFFL).random())))
        runCatching { request("TVRCSessionStart", mapOf("ProtocolVersionKey" to Opack.Str("1.2"))) }
        runCatching { request("_tiStart", emptyMap())["_tiD"]?.data?.let(::textStarted) }
        // Até a TV dizer o contrário (no _iMC), não há volume.
        _state.update { it.copy(volumeControl = false) }
        for (name in listOf("_iMC", "SystemStatus", "TVSystemStatus")) {
            runCatching { event("_interest", mapOf("_regEvents" to Opack.Arr(listOf(Opack.Str(name))))) }
        }
        val attention = runCatching { request("FetchAttentionState", emptyMap())["state"]?.int }.getOrNull()
        _state.update { it.copy(isOn = attention?.let { s -> s != 1L } ?: true, model = "Apple TV", vendor = "Apple") }
        scope.launch {
            val apps = runCatching { request("FetchLaunchableApplicationsEvent", emptyMap()).dict }.getOrNull() ?: return@launch
            onApps?.invoke(apps.mapNotNull { (k, v) -> v.string?.let { k to it } }.toMap())
        }
    }

    // ---- Mensagens ----

    suspend fun request(id: String, content: Map<String, Opack>, timeoutMs: Long = 5000): Opack {
        val conn = conn ?: throw CompanionConnection.TvError("closed")
        val x = conn.nextXid()
        val reply = CompletableDeferred<Opack>()
        pending[x] = reply
        try {
            conn.send(CompanionConnection.Frame.OPACK,
                Opack.dict("_i" to Opack.Str(id), "_t" to Opack.Int(2), "_c" to Opack.Dict(content), "_x" to Opack.Int(x)))
            return withTimeout(timeoutMs) { reply.await() }
        } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
            throw CompanionConnection.Timeout(id)
        } finally {
            pending.remove(x)
        }
    }

    suspend fun event(id: String, content: Map<String, Opack>) {
        val conn = conn ?: throw CompanionConnection.TvError("closed")
        conn.send(CompanionConnection.Frame.OPACK,
            Opack.dict("_i" to Opack.Str(id), "_t" to Opack.Int(1), "_c" to Opack.Dict(content), "_x" to Opack.Int(conn.nextXid())))
    }

    private fun dispatch(message: Opack) {
        when (message["_t"]?.int) {
            3L -> {
                val x = message["_x"]?.int ?: return
                val reply = pending.remove(x) ?: return
                val error = message["_em"]?.string
                if (error != null) DebugLog.add("Apple TV: request $x failed: $error")
                if (error != null) reply.completeExceptionally(CompanionConnection.TvError(error))
                else reply.complete(message["_c"] ?: Opack.Dict(emptyMap()))
            }
            1L -> handleEvent(message["_i"]?.string ?: "", message["_c"] ?: Opack.Dict(emptyMap()))
        }
    }

    private fun handleEvent(id: String, content: Opack) {
        when (id) {
            "SystemStatus", "TVSystemStatus" -> content["state"]?.int?.let { s -> _state.update { it.copy(isOn = s != 1L) } }
            "_tiStarted" -> content["_tiD"]?.data?.let(::textStarted)
            "_tiStopped" -> textSession = null
            "_iMC" -> {
                // Com controlo de volume (0x100), pergunta-se o volume.
                val volume = ((content["_mcF"]?.int ?: 0L) and 0x100L) != 0L
                _state.update { it.copy(volumeControl = volume) }
                if (volume) scope.launch {
                    val v = runCatching { request("_mcc", mapOf("_mcc" to Opack.Int(5)))["_vol"] }.getOrNull()
                    if (v is Opack.Double) _state.update { it.copy(volume = Math.round(v.value * 100).toInt(), maxVolume = 100, muted = false) }
                }
            }
        }
    }

    /** A TV abriu um campo de texto: guarda a sessão e o texto que já lá está, e abre o teclado no telemóvel. */
    private fun textStarted(tiD: ByteArray) {
        val ti = Rti.state(tiD) ?: return
        textSession = ti.session
        _state.update { it.copy(textValue = ti.text, keyboardRequests = it.keyboardRequests + 1) }
    }

    // ---- Comandos ----

    override fun key(key: Key, direction: KeyDirection) {
        if (key == Key.ENTER) return submit()
        scope.launch {
            when (key) {
                Key.POWER -> {
                    // Ligar e desligar mandam só o largar (Wake 13, Sleep 12).
                    val on = state.value.isOn != false
                    runCatching { request("_hidC", mapOf("_hBtS" to Opack.Int(2), "_hidC" to Opack.Int(if (on) 12 else 13))) }
                    _state.update { it.copy(isOn = !on) }
                }
                Key.REWIND, Key.FAST_FORWARD -> runCatching {
                    request("_mcc", mapOf("_mcc" to Opack.Int(7), "_skpS" to Opack.Double(if (key == Key.REWIND) -10.0 else 10.0)))
                }
                Key.PREVIOUS, Key.NEXT -> runCatching { request("_mcc", mapOf("_mcc" to Opack.Int(if (key == Key.NEXT) 3 else 4))) }
                Key.SETTINGS -> runCatching { request("_launchApp", mapOf("_bundleID" to Opack.Str("com.apple.TVSettings"))) }
                Key.SEARCH -> runCatching { request("_launchApp", mapOf("_bundleID" to Opack.Str("com.apple.TVSearch"))) }
                else -> {
                    val code = hid(key) ?: return@launch
                    suspend fun hidC(state: Int) = runCatching {
                        request("_hidC", mapOf("_hBtS" to Opack.of(state), "_hidC" to Opack.of(code)))
                    }
                    when (direction) {
                        KeyDirection.START_LONG -> hidC(1)
                        KeyDirection.END_LONG -> hidC(2)
                        KeyDirection.SHORT -> { hidC(1); hidC(2) }
                    }
                }
            }
        }
    }

    /** Substitui o texto do campo aberto na TV: apaga e escreve tudo outra vez. */
    override fun text(text: String) = typeOnTv { session ->
        listOf(Rti.clear(session)) + if (text.isEmpty()) emptyList() else listOf(Rti.insert(text, session))
    }

    /** O Enter do teclado: uma mudança de linha no campo é o "return" do tvOS (pesquisar, entrar, seguinte). */
    private fun submit() = typeOnTv { session -> listOf(Rti.insert("\n", session)) }

    /** Manda operações de texto para o campo aberto, uma de cada vez e pela ordem em que se escreveu. */
    @Synchronized
    private fun typeOnTv(operations: (ByteArray) -> List<ByteArray>) {
        val session = textSession ?: return
        val previous = typing
        typing = scope.launch {
            previous?.join()
            for (payload in operations(session)) {
                runCatching { event("_tiC", mapOf("_tiV" to Opack.Int(1), "_tiD" to Opack.Data(payload))) }
            }
        }
    }

    override fun openApp(id: String) {
        scope.launch {
            val key = if (id.contains("://")) "_urlS" else "_bundleID"
            runCatching { request("_launchApp", mapOf(key to Opack.Str(id))) }
        }
    }

    override fun close() {
        closed = true
        val conn = conn ?: return scope.cancel()
        this.conn = null
        CoroutineScope(Dispatchers.IO).launch {
            // Larga os eventos e o texto (senão a próxima ligação pode ficar sem resposta ao _tiStart).
            runCatching {
                conn.send(CompanionConnection.Frame.OPACK, Opack.dict("_i" to Opack.Str("_interest"), "_t" to Opack.Int(1),
                    "_x" to Opack.Int(conn.nextXid()),
                    "_c" to Opack.dict("_deregEvents" to Opack.Arr(listOf(Opack.Str("_iMC"), Opack.Str("SystemStatus"), Opack.Str("TVSystemStatus"))))))
                conn.send(CompanionConnection.Frame.OPACK, Opack.dict("_i" to Opack.Str("_tiStop"), "_t" to Opack.Int(2),
                    "_c" to Opack.Dict(emptyMap()), "_x" to Opack.Int(conn.nextXid())))
            }
            kotlinx.coroutines.delay(300)
            conn.close()
            scope.cancel()
        }
    }

    companion object {
        const val SERVICE = "_companion-link._tcp"
        const val DEFAULT_PORT = 49_153

        /** As chaves de uma mensagem, e o erro se a TV mandar um (para o registo de diagnóstico). */
        fun keys(message: Opack): String {
            val keys = message.dict?.keys?.sorted()?.joinToString(",") ?: "?"
            return message["_em"]?.string?.let { "[$keys] error $it" } ?: "[$keys]"
        }

        /** As teclas da Apple TV (códigos HID do _hidC). */
        private fun hid(key: Key): Int? = when (key) {
            Key.UP -> 1
            Key.DOWN -> 2
            Key.LEFT -> 3
            Key.RIGHT -> 4
            Key.BACK -> 5
            Key.CENTER -> 6
            Key.HOME -> 7
            Key.VOLUME_UP -> 8
            Key.VOLUME_DOWN -> 9
            Key.PLAY_PAUSE -> 14
            Key.CHANNEL_UP -> 15
            Key.CHANNEL_DOWN -> 16
            Key.GUIDE -> 17
            else -> null
        }
    }
}
