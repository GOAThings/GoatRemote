package cc.slokker.goatremote

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import cc.slokker.goatremote.apple.AirPlayPairing
import cc.slokker.goatremote.apple.AppleTvLink
import cc.slokker.goatremote.apple.AppleTvPairing
import cc.slokker.goatremote.apple.CompanionConnection
import cc.slokker.goatremote.apple.CompanionCredentials
import cc.slokker.goatremote.apple.RawHttp
import cc.slokker.goatremote.data.SavedTv
import cc.slokker.goatremote.data.TvKind
import cc.slokker.goatremote.tv.IdentityStore
import cc.slokker.goatremote.tv.NotPairedException
import cc.slokker.goatremote.tv.Pairing
import cc.slokker.goatremote.tv.RsaKey
import cc.slokker.goatremote.tv.TvSocket
import cc.slokker.goatremote.tv.UnreachableException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Em que passo vai um emparelhamento. */
sealed interface Phase {
    data object Connecting : Phase
    data class WaitingCode(val retry: Boolean) : Phase
    data object Checking : Phase
    data object Done : Phase
    data class Failed(val why: String) : Phase
}

/** Um emparelhamento: liga à TV, a TV mostra o código e espera-se que a pessoa o escreva. */
class PairingModel(
    val name: String,
    private val tvId: String,
    private var host: String?,
    val kind: TvKind,
    private var port: Int?,
    /** Onde corre (o do view model: sobrevive às folhas). */
    private val scope: CoroutineScope,
    /** Para as credenciais da Apple TV. */
    private val context: Context,
    private val identities: IdentityStore,
    private val deviceName: () -> String,
    /** O _i estável que a Apple TV vê. */
    private val stableId: () -> String,
    /** Emparelhada: guardar e ligar. */
    private val onPaired: (SavedTv) -> Unit,
    /** O diálogo fecha-se (0,7 s depois de emparelhar, para se ver o "feito"). */
    private val onDone: (PairingModel) -> Unit,
) {
    private var phaseValue by mutableStateOf<Phase>(Phase.Connecting)
    var phase: Phase
        get() = phaseValue
        private set(value) {
            if (value != phaseValue) DebugLog.add("Pairing $name: $value")
            phaseValue = value
        }

    /** O código que a TV mostra: 6 caracteres hexadecimais (Android TV) ou um PIN de 4 algarismos (Apple TV). */
    val codeLength: Int get() = if (kind == TvKind.APPLE) 4 else Pairing.CODE_LENGTH

    /** A emparelhar pelo AirPlay (depois de "Não aparece o PIN?"). */
    var usingAirPlay by mutableStateOf(false)
        private set

    private var code: CompletableDeferred<String>? = null
    private var job: Job? = null
    private var socket: TvSocket? = null
    private var airPlay: RawHttp? = null

    fun start() {
        DebugLog.add("Pairing $name ($kind) started")
        job = scope.launch { if (kind == TvKind.APPLE) runApple() else runAndroid() }
    }

    private suspend fun runAndroid() {
        try {
            val host = host ?: throw UnreachableException(Strings.couldntFindTheTvOnThe)
            DebugLog.add("Pairing: TV at $host:${Pairing.PORT}")
            val identity = withContext(Dispatchers.IO) { identities.get() }
            val socket = TvSocket.open(host, Pairing.PORT, identity)
            DebugLog.add("Pairing: TLS open")
            this.socket = socket
            val server = socket.serverCertificate?.let(RsaKey::of)
                ?: throw UnreachableException(Strings.theTvsCertificateIsUnreadable)
            val client = RsaKey.of(identity.certificate)!!
            Pairing.run(
                clientName = deviceName(),
                client = client,
                server = server,
                send = { socket.send(it) },
                receive = { withContext(Dispatchers.IO) { socket.receive() } },
                askCode = { retry -> askCode(retry) },
            )
            socket.close()
            phase = Phase.Done
            onPaired(SavedTv(tvId, name, host))
            delay(DONE_SHOWN_MS)
            onDone(this)
        } catch (e: kotlinx.coroutines.CancellationException) {
            socket?.close()
        } catch (e: Exception) {
            DebugLog.add("Pairing failed: $e")
            socket?.close()
            if (currentCoroutineContext().isActive) phase = Phase.Failed(explain(e))
        }
    }

    /** Apple TV: SRP com o PIN, e as credenciais ficam guardadas. */
    private suspend fun runApple() {
        try {
            val host = host
            val port = port
            if (host == null || port == null) {
                throw UnreachableException(Strings.couldntFindTheTvOnThe)
            }
            DebugLog.add("Pairing: Apple TV at $host:$port${if (usingAirPlay) " (via AirPlay)" else ""}")
            if (usingAirPlay) {
                val previous = CompanionCredentials.load(context, tvId)
                val http = RawHttp(host, AirPlayPairing.PORT).also { airPlay = it }
                val creds = AirPlayPairing.pair(http, deviceName()) { askCode(false) }
                CompanionCredentials.save(context, tvId, creds)
                // A experiência: a chave do AirPlay serve no Companion (o comando)? Liga-se já para saber.
                phase = Phase.Checking
                val link = AppleTvLink(host, port, { CompanionCredentials.load(context, tvId) },
                    { CompanionCredentials.save(context, tvId, it) }, deviceName(), stableId())
                try {
                    link.connect()
                    link.close()
                    DebugLog.add("AirPlay pairing: the Apple TV accepts the AirPlay key for the remote")
                } catch (e: Exception) {
                    link.close()
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    // Uma tentativa falhada não estraga um emparelhamento que já funcionava.
                    if (previous != null) CompanionCredentials.save(context, tvId, previous)
                    else CompanionCredentials.delete(context, tvId)
                    DebugLog.add("AirPlay pairing: the Apple TV doesn't accept the AirPlay key for the remote: $e")
                    throw AirPlayPairing.NotForRemote()
                }
            } else {
                val creds = AppleTvPairing.pair(host, port, deviceName()) { askCode(false) }
                CompanionCredentials.save(context, tvId, creds)
            }
            phase = Phase.Done
            onPaired(SavedTv(tvId, name, host, TvKind.APPLE, port))
            delay(DONE_SHOWN_MS)
            onDone(this)
        } catch (e: kotlinx.coroutines.CancellationException) {
            DebugLog.add("Pairing cancelled")
            return
        } catch (e: Exception) {
            DebugLog.add("Pairing failed: $e")
            // Um "tentar outra vez" (ou o AirPlay) já começou outro: este não mexe no ecrã.
            if (currentCoroutineContext().isActive) phase = Phase.Failed(explain(e))
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

    /** "Não aparece o PIN?": emparelhar pelo AirPlay (ver [AirPlayPairing]). */
    fun useAirPlay() {
        DebugLog.add("Pairing: switching to AirPlay")
        cancel()
        usingAirPlay = true
        phase = Phase.Connecting
        start()
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
        airPlay?.close()
    }

    private companion object {
        /** O "feito" fica à vista um bocado antes de o diálogo fechar (o mesmo que no iPhone). */
        const val DONE_SHOWN_MS = 700L
    }

    private fun explain(e: Exception): String = when (e) {
        is Pairing.Rejected -> L("The TV refused (${e.status}). Try again.", "A TV recusou (${e.status}). Tenta outra vez.")
        is NotPairedException, is java.io.EOFException ->
            Strings.theTvClosedTheConnectionTry
        is AppleTvPairing.WrongPin -> Strings.wrongPinTryAgainTheTv
        is AppleTvPairing.Refused -> appleRefusal(e.code, e.retryAfter)
        is AirPlayPairing.NotForRemote ->
            Strings.thePinWorkedOverAirplayBut
        is CompanionConnection.TvError -> L("The TV refused: ${e.message}", "A TV recusou: ${e.message}")
        else -> describe(e)
    }
}

/** O que quer dizer cada recusa da Apple TV (códigos de erro do emparelhamento HomeKit). */
private fun appleRefusal(code: Int, retryAfter: Int?): String = when (code) {
    3 -> {
        val wait = retryAfter?.let { if (it >= 90) L("${(it + 59) / 60} minutes", "${(it + 59) / 60} minutos") else L("$it seconds", "$it segundos") }
            ?: Strings.aFewMinutes
        L("After several tries, the Apple TV is blocking pairing for a while. Wait $wait (or restart the Apple TV) and try again with the Apple TV awake and on screen.",
            "Depois de várias tentativas, a Apple TV bloqueou o emparelhamento por um bocado. Espera $wait (ou reinicia a Apple TV) e tenta outra vez com a Apple TV ligada e no ecrã.")
    }
    4 -> Strings.theAppleTvHasTooMany
    5 -> Strings.tooManyWrongPinsRestartThe
    6 -> Strings.theAppleTvIsntAcceptingNew
    7 -> Strings.theAppleTvIsBusyPairing
    else -> L("The Apple TV refused (code $code). Try again.", "A Apple TV recusou (código $code). Tenta outra vez.")
}
