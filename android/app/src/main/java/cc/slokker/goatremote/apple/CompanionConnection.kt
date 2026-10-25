package cc.slokker.goatremote.apple

import cc.slokker.goatremote.tv.UnreachableException
import java.io.DataInputStream
import java.io.EOFException
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * A ligação à Apple TV (protocolo Companion): TCP simples com tramas [tipo, tamanho de 3 bytes, conteúdo OPACK].
 * Depois da verificação, cada trama vai cifrada com ChaCha20-Poly1305 (cabeçalho como dados autenticados, nonce =
 * contador de 12 bytes little-endian por sentido).
 */
class CompanionConnection(private val host: String, private val port: Int) {
    enum class Frame(val code: Int) { PAIR_SETUP_START(3), PAIR_SETUP_NEXT(4), PAIR_VERIFY_START(5), PAIR_VERIFY_NEXT(6), OPACK(8) }

    class TvError(message: String) : Exception(message)
    class Timeout(what: String) : Exception("sem resposta: $what")

    private val socket = Socket()
    private lateinit var input: DataInputStream
    private var outKey: ByteArray? = null
    private var inKey: ByteArray? = null
    private var outCounter = 0L
    private var inCounter = 0L
    private var xid = (0 until 65_536).random().toLong()
    private val writeLock = Any()

    suspend fun open() = withContext(Dispatchers.IO) {
        try {
            socket.connect(InetSocketAddress(host, port), 6000)
            socket.tcpNoDelay = true
            socket.keepAlive = true
            input = DataInputStream(socket.inputStream.buffered())
        } catch (e: IOException) {
            socket.close()
            throw UnreachableException(e.message ?: e.javaClass.simpleName)
        }
    }

    fun close() {
        runCatching { socket.close() }
    }

    /** Passa a cifrar (depois da M4 da verificação). */
    fun encrypt(out: ByteArray, incoming: ByteArray) {
        synchronized(writeLock) {
            outKey = out
            inKey = incoming
            outCounter = 0
            inCounter = 0
        }
    }

    /** O próximo número de transação (_x). */
    @Synchronized
    fun nextXid(): Long = ++xid

    /** Cifrar e escrever juntos: a TV conta as tramas, por isso têm de sair pela ordem do contador. */
    suspend fun send(frame: Frame, message: Opack) = withContext(Dispatchers.IO) {
        synchronized(writeLock) {
            var body = message.encoded
            val key = outKey
            val header: ByteArray
            if (key != null && body.isNotEmpty()) {
                header = byteArrayOf(frame.code.toByte()) + length(body.size + 16)
                body = Crypto.seal(key, nonce(outCounter++), body, header)
            } else {
                header = byteArrayOf(frame.code.toByte()) + length(body.size)
            }
            socket.outputStream.run {
                write(header + body)
                flush()
            }
        }
    }

    /** A próxima trama inteira, já decifrada (bloqueia; chamar fora da thread principal). */
    fun receive(): Pair<Int, Opack> {
        val header = ByteArray(4)
        try {
            input.readFully(header)
        } catch (e: EOFException) {
            throw IOException("closed")
        }
        val n = (header[1].toInt() and 0xFF shl 16) or (header[2].toInt() and 0xFF shl 8) or (header[3].toInt() and 0xFF)
        var body = ByteArray(n).also(input::readFully)
        val key = inKey
        if (key != null && body.isNotEmpty()) {
            if (body.size < 16) throw TvError("trama cifrada curta")
            body = Crypto.open(key, nonce(inCounter++), body, header)
        }
        return header[0].toInt() to if (body.isEmpty()) Opack.Dict(emptyMap()) else Opack.decode(body)
    }

    private fun length(n: Int) = byteArrayOf((n shr 16).toByte(), (n shr 8).toByte(), n.toByte())

    private fun nonce(counter: Long) = ByteArray(12) { if (it < 8) (counter ushr (8 * it)).toByte() else 0 }
}
