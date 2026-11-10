package cc.slokker.goatremote.apple

import cc.slokker.goatremote.DebugLog
import cc.slokker.goatremote.tv.ProtocolException
import cc.slokker.goatremote.tv.UnreachableException
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Plano B do emparelhamento com a Apple TV: pelo AirPlay (HTTP na porta 7000). No tvOS 26/27, a Apple TV 4K de
 * 3.ª geração entra em modo de PIN no Companion mas não o mostra (pyatv #2837); no AirPlay, o PIN aparece com o
 * pedido `/pair-pin-start` e o nome do cliente no cabeçalho `X-Apple-Client-Name` (Home Assistant #173352).
 * O emparelhamento é o mesmo (SRP com o PIN e as identidades Ed25519): a chave que fica usa-se no Companion, se a
 * TV a aceitar lá. A identidade da TV guardada aqui é a do AirPlay: no Companion pode ser outra (ver AppleTvLink.verify).
 */
object AirPlayPairing {
    const val PORT = 7000

    /** O AirPlay emparelhou, mas a TV não aceita essa chave no Companion. */
    class NotForRemote : Exception("AirPlay key not accepted for the remote")

    /** [http] é de quem chama: fechá-lo cancela o emparelhamento a meio de um pedido. */
    suspend fun pair(http: RawHttp, name: String, askPin: suspend () -> String): CompanionCredentials {
        http.open()
        try {
            val headers = mapOf(
                "User-Agent" to "AirPlay/320.20", "Connection" to "keep-alive", "X-Apple-HKP" to "3",
                "Content-Type" to "application/octet-stream", "X-Apple-Client-Name" to name,
            )
            DebugLog.add("AirPlay pairing: ${http.host}:${http.port}, asking the TV to show the PIN as \"$name\"")
            val start = http.post("/pair-pin-start", ByteArray(0), headers)
            DebugLog.add("AirPlay pairing: pair-pin-start HTTP ${start.status}")
            if (start.status !in 200..299) throw CompanionConnection.TvError("pair-pin-start HTTP ${start.status}")
            val pin = askPin()
            DebugLog.add("AirPlay pairing: PIN entered, sending M1")
            val exchange = AppleTvPairing.Exchange { tlv ->
                val response = http.post("/pair-setup", Tlv8.encode(*tlv.toTypedArray()), headers)
                val reply = Tlv8.decode(response.body)
                DebugLog.add("AirPlay pairing: HTTP ${response.status} TLV ${AppleTvPairing.describe(reply)}")
                if (response.status !in 200..299) throw CompanionConnection.TvError("pair-setup HTTP ${response.status}")
                AppleTvPairing.check(reply)
            }
            // No AirPlay o PIN vem antes do M1: o pair-pin-start já o pôs no ecrã.
            val m2 = exchange.send(listOf(0 to byteArrayOf(0), 6 to byteArrayOf(1)))
            return AppleTvPairing.finish(m2, pin, name, exchange).copy(viaAirPlay = true)
        } finally {
            http.close()
        }
    }
}

/** HTTP/1.1 mínimo sobre uma só ligação TCP: o emparelhamento do AirPlay tem de ir todo na mesma ligação. */
class RawHttp(val host: String, val port: Int) {
    class Response(val status: Int, val body: ByteArray)

    private val socket = Socket()
    private lateinit var input: InputStream
    private var buffer = ByteArray(0)

    suspend fun open() = withContext(Dispatchers.IO) {
        try {
            socket.connect(InetSocketAddress(host, port), 6000)
            socket.tcpNoDelay = true
            // Cada pedido tem um limite de tempo.
            socket.soTimeout = 30_000
            input = socket.inputStream
        } catch (e: IOException) {
            DebugLog.add("AirPlay $host:$port: $e")
            socket.close()
            throw UnreachableException(e.message ?: e.javaClass.simpleName)
        }
    }

    fun close() {
        runCatching { socket.close() }
    }

    suspend fun post(path: String, body: ByteArray, headers: Map<String, String>): Response = withContext(Dispatchers.IO) {
        val head = StringBuilder("POST $path HTTP/1.1\r\nHost: $host:$port\r\nContent-Length: ${body.size}\r\n")
        for ((name, value) in headers.toSortedMap()) head.append("$name: $value\r\n")
        head.append("\r\n")
        try {
            socket.outputStream.run {
                write(head.toString().toByteArray() + body)
                flush()
            }
            // Cabeçalhos até à linha vazia; depois o Content-Length. A cabeça e o corpo têm tamanho máximo.
            var scanned = 0
            while (true) {
                val end = find(CRLFCRLF, scanned)
                if (end >= 0) {
                    if (end > AirPlayHead.MAX_HEAD) throw CompanionConnection.TvError("resposta HTTP demasiado grande")
                    val (status, length) = AirPlayHead.parse(buffer.copyOfRange(0, end))
                    val total = end + 4 + length
                    while (buffer.size < total) receiveMore()
                    val response = Response(status, buffer.copyOfRange(end + 4, total))
                    buffer = buffer.copyOfRange(total, buffer.size)
                    return@withContext response
                }
                if (buffer.size > AirPlayHead.MAX_HEAD) throw CompanionConnection.TvError("resposta HTTP demasiado grande")
                scanned = maxOf(buffer.size - 3, 0)
                receiveMore()
            }
            @Suppress("UNREACHABLE_CODE")
            throw IllegalStateException()
        } catch (e: IOException) {
            throw UnreachableException(e.message ?: e.javaClass.simpleName)
        }
    }

    private fun find(pattern: ByteArray, from: Int): Int {
        for (i in from..buffer.size - pattern.size) {
            if ((pattern.indices).all { buffer[i + it] == pattern[it] }) return i
        }
        return -1
    }

    private fun receiveMore() {
        val chunk = ByteArray(65_536)
        val n = input.read(chunk)
        if (n < 0) throw IOException("closed")
        buffer += chunk.copyOf(n)
    }

    private companion object {
        val CRLFCRLF = byteArrayOf(13, 10, 13, 10)
    }
}

/** A cabeça de uma resposta HTTP do emparelhamento pelo AirPlay (as respostas são TLV pequenos). */
object AirPlayHead {
    const val MAX_HEAD = 64 * 1024
    const val MAX_BODY = 1 shl 20

    /** O estado e o tamanho do corpo; um Content-Length que não seja um número até [MAX_BODY] é erro. */
    fun parse(head: ByteArray): Pair<Int, Int> {
        val lines = String(head, Charsets.UTF_8).split("\r\n")
        val status = lines.firstOrNull()?.split(" ")?.getOrNull(1)?.toIntOrNull() ?: 0
        for (line in lines.drop(1)) {
            val parts = line.split(":", limit = 2)
            if (parts.size != 2 || parts[0].lowercase() != "content-length") continue
            val length = parts[1].trim().toIntOrNull()
            if (length == null || length < 0 || length > MAX_BODY) throw ProtocolException("Content-Length")
            return status to length
        }
        return status to 0
    }
}

/** A identidade que uma TV mostra na verificação do Companion (M2), contra o que está guardado. */
object CompanionIdentity {
    enum class Verdict {
        /** O id e a chave guardados: a TV provou quem é. */
        VERIFIED,
        /** Emparelhada pelo AirPlay e ainda sem identidade no Companion: a primeira verificação guarda o id. */
        FIRST_SEEN,
        /** Emparelhada pelo AirPlay, com o mesmo id da primeira verificação. */
        PINNED,
        REJECTED,
    }

    /**
     * [provenByKey]: o id é o guardado e a assinatura bate com a chave guardada. Só o emparelhamento pelo AirPlay
     * pode ter outra identidade no Companion, e depois de vista essa identidade não muda.
     */
    fun check(id: ByteArray, provenByKey: Boolean, viaAirPlay: Boolean, pinned: ByteArray?): Verdict = when {
        provenByKey -> Verdict.VERIFIED
        !viaAirPlay -> Verdict.REJECTED
        pinned == null -> Verdict.FIRST_SEEN
        id.contentEquals(pinned) -> Verdict.PINNED
        else -> Verdict.REJECTED
    }
}
