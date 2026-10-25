package cc.slokker.goatremote.tv

import java.math.BigInteger
import java.security.MessageDigest
import java.security.cert.X509Certificate
import java.security.interfaces.RSAPublicKey

/**
 * O emparelhamento (porta 6467): o telemóvel pede, a TV mostra um código de 6 caracteres hexadecimais e o telemóvel
 * manda um segredo feito com o código e as chaves dos dois certificados. Daí em diante a TV aceita este certificado
 * no comando (porta 6466).
 *
 * PairingMessage: protocol_version 1, status 2 (200 = OK), e um destes: pairing_request 10 {service_name 1,
 * client_name 2}, pairing_request_ack 11, pairing_option 20 {input_encodings 1, output_encodings 2, preferred_role 3},
 * pairing_configuration 30 {encoding 1, client_role 2}, pairing_configuration_ack 31, pairing_secret 40 {secret 1},
 * pairing_secret_ack 41. Encoding {type 1 (3 = hexadecimal), symbol_length 2}; role 1 = quem escreve o código.
 */
object Pairing {
    const val PORT = 6467
    const val CODE_LENGTH = 6

    /** A TV recusou (estado diferente de 200). */
    class Rejected(val status: Int) : Exception("a TV recusou ($status)")

    private fun message(field: Int, body: ProtoWriter.() -> Unit): ByteArray =
        ProtoWriter().varint(1, 2).varint(2, 200).message(field, body).toByteArray()

    private val hexEncoding: ProtoWriter.() -> Unit = { varint(1, 3); varint(2, CODE_LENGTH) }

    fun request(clientName: String) = message(10) { string(1, "atvremote"); string(2, clientName) }

    val options = message(20) { message(1, hexEncoding); varint(3, 1) }

    val configuration = message(30) { message(1, hexEncoding); varint(2, 1) }

    fun secretMessage(secret: ByteArray) = message(40) { bytes(1, secret) }

    /** Confere uma resposta da TV: estado 200 e o campo esperado. */
    fun check(frame: ByteArray, expecting: Int) {
        val m = ProtoMessage.parse(frame)
        val status = m.int(2)
        if (status != 200) throw Rejected(status)
        if (!m.has(expecting)) throw ProtocolException("esperava $expecting")
    }

    /** O código como a TV o mostra (6 caracteres hexadecimais, maiúsculas), ou null. */
    fun normalize(code: String): String? {
        val clean = code.uppercase().filterNot { it.isWhitespace() }
        return clean.takeIf { it.length == CODE_LENGTH && it.all { c -> c in '0'..'9' || c in 'A'..'F' } }
    }

    /**
     * O segredo: SHA-256 de módulo e expoente do telemóvel, módulo e expoente da TV e dos 2 últimos bytes do código.
     * O primeiro byte do código é o primeiro do segredo: se não bater, o código está errado (null).
     */
    fun secret(code: String, client: RsaKey, server: RsaKey): ByteArray? {
        val clean = normalize(code) ?: return null
        val bytes = clean.chunked(2).map { it.toInt(16).toByte() }
        val digest = MessageDigest.getInstance("SHA-256").run {
            update(client.modulus); update(client.exponent); update(server.modulus); update(server.exponent)
            update(bytes.drop(1).toByteArray())
            digest()
        }
        return digest.takeIf { it[0] == bytes[0] }
    }

    /**
     * Os passos todos, com a ligação dada pelo chamador. [askCode] espera pelo código que a pessoa lê na TV (com true
     * quando o anterior estava errado: a TV continua à espera, não é preciso recomeçar).
     */
    suspend fun run(
        clientName: String,
        client: RsaKey,
        server: RsaKey,
        send: suspend (ByteArray) -> Unit,
        receive: suspend () -> ByteArray,
        askCode: suspend (retry: Boolean) -> String,
    ) {
        send(request(clientName))
        check(receive(), 11)
        send(options)
        check(receive(), 20)
        send(configuration)
        check(receive(), 31)
        // A TV mostra agora o código.
        var retry = false
        var secret: ByteArray? = null
        while (secret == null) {
            secret = secret(askCode(retry), client, server)
            retry = true
        }
        send(secretMessage(secret))
        check(receive(), 41)
    }
}

/** Módulo e expoente de uma chave RSA, sem zeros à esquerda (como entram no segredo). */
class RsaKey(modulus: BigInteger, exponent: BigInteger) {
    val modulus: ByteArray = modulus.unsignedBytes()
    val exponent: ByteArray = exponent.unsignedBytes()

    companion object {
        fun of(cert: X509Certificate): RsaKey? = (cert.publicKey as? RSAPublicKey)?.let { RsaKey(it.modulus, it.publicExponent) }
    }
}

/** Os bytes de um inteiro positivo, sem o zero de sinal à esquerda. */
fun BigInteger.unsignedBytes(): ByteArray {
    val b = toByteArray()
    return if (b.size > 1 && b[0] == 0.toByte()) b.copyOfRange(1, b.size) else b
}
