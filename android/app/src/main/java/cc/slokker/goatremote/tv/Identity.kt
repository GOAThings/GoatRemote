package cc.slokker.goatremote.tv

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.Signature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * A identidade deste telemóvel perante as TVs: uma chave RSA e um certificado auto-assinado. A TV guarda o
 * certificado quando se emparelha e daí em diante só aceita ligações com ele.
 */
class Identity(val privateKey: PrivateKey, val certificate: X509Certificate) {
    companion object {
        /** Cria uma identidade nova (chave RSA de 2048 bits, certificado válido por 20 anos). */
        fun generate(commonName: String = "GoatRemote"): Identity {
            val keys = KeyPairGenerator.getInstance("RSA").apply { initialize(2048, SecureRandom()) }.generateKeyPair()
            val now = System.currentTimeMillis()
            val name = der(0x30, der(0x31, der(0x30, oid(OID_COMMON_NAME) + der(0x0C, commonName.toByteArray()))))
            val tbs = der(
                0x30,
                der(0xA0, derInt(BigInteger.valueOf(2))) + // v3
                    derInt(BigInteger(63, SecureRandom()).add(BigInteger.ONE)) +
                    SHA256_WITH_RSA +
                    name +
                    der(0x30, derTime(now - DAY_MS) + derTime(now + 20L * 365 * DAY_MS)) +
                    name +
                    keys.public.encoded,
            )
            val signature = Signature.getInstance("SHA256withRSA").run {
                initSign(keys.private)
                update(tbs)
                sign()
            }
            val cert = der(0x30, tbs + SHA256_WITH_RSA + der(0x03, byteArrayOf(0) + signature))
            return Identity(keys.private, parseCertificate(cert))
        }

        fun parseCertificate(der: ByteArray): X509Certificate =
            CertificateFactory.getInstance("X.509").generateCertificate(ByteArrayInputStream(der)) as X509Certificate

        private val SHA256_WITH_RSA = der(0x30, oid(intArrayOf(1, 2, 840, 113549, 1, 1, 11)) + byteArrayOf(0x05, 0x00))
        private val OID_COMMON_NAME = intArrayOf(2, 5, 4, 3)
        private const val DAY_MS = 24L * 60 * 60 * 1000
    }
}

/** Guarda a identidade num ficheiro privado da app; cria-a na primeira vez. */
class IdentityStore(private val file: File) {
    @Volatile private var cached: Identity? = null

    @Synchronized
    fun get(): Identity {
        cached?.let { return it }
        val identity = runCatching { load() }.getOrNull() ?: Identity.generate().also(::save)
        cached = identity
        return identity
    }

    private fun load(): Identity? {
        if (!file.exists()) return null
        DataInputStream(file.inputStream().buffered()).use { input ->
            val key = ByteArray(input.readInt()).also(input::readFully)
            val cert = ByteArray(input.readInt()).also(input::readFully)
            val privateKey = KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(key))
            return Identity(privateKey, Identity.parseCertificate(cert))
        }
    }

    private fun save(identity: Identity) {
        val tmp = File(file.parentFile, file.name + ".tmp")
        DataOutputStream(tmp.outputStream().buffered()).use { out ->
            val key = identity.privateKey.encoded
            val cert = identity.certificate.encoded
            out.writeInt(key.size); out.write(key)
            out.writeInt(cert.size); out.write(cert)
        }
        tmp.renameTo(file)
    }
}

/** Impressão digital SHA-256 de um certificado, em hexadecimal: serve para reconhecer a mesma TV mais tarde. */
fun X509Certificate.sha256(): String =
    MessageDigest.getInstance("SHA-256").digest(encoded).joinToString("") { "%02x".format(it) }

// ---- DER mínimo: só o que um certificado auto-assinado precisa ----

private fun der(tag: Int, content: ByteArray): ByteArray {
    val out = ByteArrayOutputStream()
    out.write(tag)
    val len = content.size
    when {
        len < 0x80 -> out.write(len)
        len < 0x100 -> { out.write(0x81); out.write(len) }
        len < 0x10000 -> { out.write(0x82); out.write(len shr 8); out.write(len and 0xFF) }
        else -> { out.write(0x83); out.write(len shr 16); out.write((len shr 8) and 0xFF); out.write(len and 0xFF) }
    }
    out.write(content)
    return out.toByteArray()
}

private fun derInt(value: BigInteger) = der(0x02, value.toByteArray())

private fun oid(parts: IntArray): ByteArray {
    val out = ByteArrayOutputStream()
    out.write(parts[0] * 40 + parts[1])
    for (part in parts.drop(2)) {
        val chunks = mutableListOf<Int>()
        var v = part
        do { chunks.add(v and 0x7F); v = v ushr 7 } while (v != 0)
        for (i in chunks.indices.reversed()) out.write(chunks[i] or if (i > 0) 0x80 else 0)
    }
    return der(0x06, out.toByteArray())
}

/** UTCTime até 2049, GeneralizedTime depois (regra do X.509). */
private fun derTime(millis: Long): ByteArray {
    val utc = TimeZone.getTimeZone("UTC")
    val year = java.util.Calendar.getInstance(utc).apply { timeInMillis = millis }.get(java.util.Calendar.YEAR)
    val (tag, pattern) = if (year < 2050) 0x17 to "yyMMddHHmmss'Z'" else 0x18 to "yyyyMMddHHmmss'Z'"
    val text = SimpleDateFormat(pattern, Locale.US).apply { timeZone = utc }.format(Date(millis))
    return der(tag, text.toByteArray(Charsets.US_ASCII))
}
