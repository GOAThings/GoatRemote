package cc.slokker.goatremote.tv

import android.annotation.SuppressLint
import cc.slokker.goatremote.DebugLog
import java.io.EOFException
import java.io.IOException
import java.net.ConnectException
import java.net.InetSocketAddress
import java.net.NoRouteToHostException
import java.net.Socket
import java.net.SocketTimeoutException
import java.security.Principal
import java.security.PrivateKey
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLException
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509TrustManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** O que o comando faz a qualquer TV (Android TV ou Apple TV). */
interface TvControl {
    val state: StateFlow<TvState>
    /** A ligação caiu (não é chamado depois de [close]). */
    var onClose: (() -> Unit)?
    suspend fun connect()
    fun key(key: Key, direction: KeyDirection = KeyDirection.SHORT)
    fun text(text: String)
    /** Abre uma app: o link (Android) ou o bundle id (Apple TV). */
    fun openApp(id: String)
    fun close()
}

/** A TV recusou este telemóvel: é preciso emparelhar (outra vez). */
class NotPairedException : Exception("not paired")

/** Não se chegou à TV (desligada da rede, IP errado). */
class UnreachableException(message: String) : Exception(message)

/**
 * Uma ligação TLS a uma porta da TV (6467 emparelhar, 6466 comando), às mensagens inteiras. A TV tem um certificado
 * auto-assinado: aceita-se qualquer um, porque o que dá segurança é o emparelhamento.
 */
class TvSocket private constructor(private val socket: SSLSocket) {
    private val input = socket.inputStream.buffered()
    private val output = socket.outputStream
    private val writeLock = Mutex()

    /** O certificado da TV. */
    val serverCertificate: X509Certificate? = socket.session.peerCertificates.firstOrNull() as? X509Certificate

    suspend fun send(frame: ByteArray) = withContext(Dispatchers.IO) {
        writeLock.withLock { output.writeFrame(frame) }
    }

    /** A próxima mensagem inteira (bloqueia; chamar fora da thread principal). */
    fun receive(): ByteArray = input.readFrame()

    fun setTimeout(millis: Int) {
        socket.soTimeout = millis
    }

    fun close() {
        runCatching { socket.close() }
    }

    companion object {
        /** Liga (fora da thread principal). Recusas de TLS contam como "não emparelhado". */
        suspend fun open(host: String, port: Int, identity: Identity): TvSocket = withContext(Dispatchers.IO) {
            val context = SSLContext.getInstance("TLS").apply { init(arrayOf(OwnKey(identity)), arrayOf(TrustAll), null) }
            val plain = Socket()
            try {
                plain.connect(InetSocketAddress(host, port), 6000)
            } catch (e: IOException) {
                DebugLog.add("Can't connect to $host:$port: $e")
                plain.close()
                throw UnreachableException(e.message ?: e.javaClass.simpleName)
            }
            val socket = context.socketFactory.createSocket(plain, host, port, true) as SSLSocket
            try {
                socket.soTimeout = 8000
                socket.startHandshake()
            } catch (e: IOException) {
                DebugLog.add("TLS $host:$port failed: $e")
                socket.close()
                throw if (e is SSLException || e is EOFException) NotPairedException() else UnreachableException(e.message ?: "")
            }
            TvSocket(socket)
        }
    }

    /** Manda sempre o certificado deste telemóvel, peça a TV os emissores que pedir. */
    private class OwnKey(private val identity: Identity) : X509ExtendedKeyManager() {
        override fun chooseClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, socket: Socket?) = ALIAS
        override fun chooseEngineClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, engine: SSLEngine?) = ALIAS
        override fun getCertificateChain(alias: String?) = arrayOf(identity.certificate)
        override fun getPrivateKey(alias: String?): PrivateKey = identity.privateKey
        override fun getClientAliases(keyType: String?, issuers: Array<out Principal>?) = arrayOf(ALIAS)
        override fun getServerAliases(keyType: String?, issuers: Array<out Principal>?) = null
        override fun chooseServerAlias(keyType: String?, issuers: Array<out Principal>?, socket: Socket?) = null

        companion object {
            const val ALIAS = "me"
        }
    }

    @SuppressLint("CustomX509TrustManager", "TrustAllX509TrustManager")
    private object TrustAll : X509TrustManager {
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }
}

/** O comando ligado a uma Android TV (porta 6466): negocia, responde aos pings e conta o estado da TV. */
class AndroidTvLink(private val host: String, private val identity: () -> Identity, appVersion: String, model: String) : TvControl {
    private val proto = RemoteProtocol(model, appVersion)
    private val _state = MutableStateFlow(TvState())
    override val state: StateFlow<TvState> = _state
    override var onClose: (() -> Unit)? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var socket: TvSocket? = null
    @Volatile private var closed = false

    override suspend fun connect() {
        val socket = TvSocket.open(host, RemoteProtocol.PORT, identity())
        this.socket = socket
        // Até a TV mandar set_active (se fechar antes, não estamos emparelhados).
        try {
            withContext(Dispatchers.IO) {
                socket.setTimeout(6000)
                while (!proto.ready) handle(socket, socket.receive())
                // A TV manda um ping a cada 5 s: sem nada em 15 s, a ligação caiu.
                socket.setTimeout(15_000)
            }
        } catch (e: Exception) {
            DebugLog.add("Android TV: no set_active from the TV: $e")
            socket.close()
            throw if (e is SocketTimeoutException || e is EOFException || e is SSLException) NotPairedException() else e
        }
        scope.launch {
            try {
                while (true) handle(socket, socket.receive())
            } catch (_: Exception) {
            }
            socket.close()
            if (!closed) onClose?.invoke()
        }
    }

    private suspend fun handle(socket: TvSocket, frame: ByteArray) {
        val replies = synchronized(proto) { proto.handle(frame) }
        replies.forEach { socket.send(it) }
        _state.value = proto.state
    }

    private fun send(build: (RemoteProtocol) -> ByteArray) {
        val socket = socket ?: return
        val data = synchronized(proto) { build(proto) }
        scope.launch { runCatching { socket.send(data) } }
    }

    override fun key(key: Key, direction: KeyDirection) = send { it.key(key, direction) }

    override fun text(text: String) {
        val socket = socket ?: return
        val frames = synchronized(proto) { proto.text(text) }
        // Uma só tarefa, para os Apagar chegarem antes do texto.
        scope.launch { runCatching { frames.forEach { socket.send(it) } } }
    }

    override fun openApp(id: String) = send { it.appLink(id) }

    override fun close() {
        closed = true
        socket?.close()
        socket = null
        scope.cancel()
    }

    companion object {
        fun isUnreachable(e: Throwable) = e is UnreachableException || e is ConnectException || e is NoRouteToHostException
    }
}
