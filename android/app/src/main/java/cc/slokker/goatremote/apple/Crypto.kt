package cc.slokker.goatremote.apple

import cc.slokker.goatremote.tv.unsignedBytes
import java.math.BigInteger
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.bouncycastle.crypto.agreement.X25519Agreement
import org.bouncycastle.crypto.modes.ChaCha20Poly1305
import org.bouncycastle.crypto.params.AEADParameters
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.params.KeyParameter
import org.bouncycastle.crypto.params.X25519PrivateKeyParameters
import org.bouncycastle.crypto.params.X25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer

/** A criptografia do emparelhamento com a Apple TV (Ed25519, X25519 e ChaCha20-Poly1305 do Bouncy Castle). */
object Crypto {
    val random = SecureRandom()

    fun randomBytes(n: Int) = ByteArray(n).also(random::nextBytes)

    fun sha512(vararg parts: ByteArray): ByteArray = MessageDigest.getInstance("SHA-512").run {
        parts.forEach(::update)
        digest()
    }

    private fun hmac(key: ByteArray, data: ByteArray): ByteArray = Mac.getInstance("HmacSHA512").run {
        // Uma chave vazia não é aceite pelo SecretKeySpec; para o HMAC é o mesmo que um zero.
        init(SecretKeySpec(if (key.isEmpty()) ByteArray(1) else key, "HmacSHA512"))
        doFinal(data)
    }

    /** HKDF-SHA512 (RFC 5869). */
    fun hkdf(salt: String, info: String, key: ByteArray, length: Int = 32): ByteArray {
        val prk = hmac(salt.toByteArray(), key)
        val out = java.io.ByteArrayOutputStream()
        var t = ByteArray(0)
        var i = 1
        while (out.size() < length) {
            t = hmac(prk, t + info.toByteArray() + byteArrayOf(i.toByte()))
            out.write(t)
            i++
        }
        return out.toByteArray().copyOf(length)
    }

    /** Cifra com ChaCha20-Poly1305: o texto cifrado com a etiqueta de 16 bytes no fim. */
    fun seal(key: ByteArray, nonce: ByteArray, plain: ByteArray, aad: ByteArray? = null): ByteArray =
        aead(true, key, nonce, plain, aad)

    /** Decifra; falha (exceção) se a etiqueta não bater certo. */
    fun open(key: ByteArray, nonce: ByteArray, sealed: ByteArray, aad: ByteArray? = null): ByteArray =
        aead(false, key, nonce, sealed, aad)

    private fun aead(encrypt: Boolean, key: ByteArray, nonce: ByteArray, input: ByteArray, aad: ByteArray?): ByteArray {
        val cipher = ChaCha20Poly1305()
        cipher.init(encrypt, AEADParameters(KeyParameter(key), 128, nonce, aad))
        val out = ByteArray(cipher.getOutputSize(input.size))
        val n = cipher.processBytes(input, 0, input.size, out, 0)
        cipher.doFinal(out, n)
        return out
    }

    /** Os nonces do emparelhamento: 4 zeros e 8 letras ("PS-Msg05", "PV-Msg02", …). */
    fun pairingNonce(label: String) = ByteArray(4) + label.toByteArray()

    class SigningKey(val raw: ByteArray) {
        private val key = Ed25519PrivateKeyParameters(raw, 0)
        val publicKey: ByteArray get() = key.generatePublicKey().encoded

        fun sign(data: ByteArray): ByteArray = Ed25519Signer().run {
            init(true, key)
            update(data, 0, data.size)
            generateSignature()
        }

        companion object {
            fun generate() = SigningKey(randomBytes(32))
        }
    }

    fun verify(publicKey: ByteArray, signature: ByteArray, data: ByteArray): Boolean = runCatching {
        Ed25519Signer().run {
            init(false, Ed25519PublicKeyParameters(publicKey, 0))
            update(data, 0, data.size)
            verifySignature(signature)
        }
    }.getOrDefault(false)

    class AgreementKey {
        private val key = X25519PrivateKeyParameters(random)
        val publicKey: ByteArray get() = key.generatePublicKey().encoded

        fun shared(other: ByteArray): ByteArray = ByteArray(32).also {
            X25519Agreement().run {
                init(key)
                calculateAgreement(X25519PublicKeyParameters(other, 0), it, 0)
            }
        }
    }
}

/**
 * SRP-6a do emparelhamento HomeKit/Companion (Apple TV): grupo de 3072 bits do RFC 5054, g = 5, SHA-512, utilizador
 * "Pair-Setup" e o PIN como palavra-passe. As conversões de bytes são as do srptools (o que a Apple TV aceita): k e
 * u com valores alinhados a 384 bytes; K = H(S) e a prova com S, A e B no tamanho mínimo.
 */
class SrpClient(privateKey: ByteArray) {
    private val a = BigInteger(1, privateKey)

    /** A, a enviar na M3 (tamanho mínimo). */
    val publicKey: ByteArray = G.modPow(a, N).unsignedBytes()

    class Result(
        /** M1: a prova deste lado. */
        val proof: ByteArray,
        /** M2: a prova que a TV tem de mandar. */
        val expectedServerProof: ByteArray,
        /** K: a chave de sessão (64 bytes). */
        val sessionKey: ByteArray,
    )

    /** Com o sal e o B da TV (M2) e o PIN; null se B não servir (B mod N = 0). */
    fun process(salt: ByteArray, serverPublicKey: ByteArray, pin: String): Result? {
        val b = BigInteger(1, serverPublicKey)
        if (b.mod(N).signum() == 0) return null
        val bigA = BigInteger(1, publicKey)
        val k = BigInteger(1, Crypto.sha512(N.unsignedBytes(), padded(G)))
        val x = BigInteger(1, Crypto.sha512(salt, Crypto.sha512("Pair-Setup:$pin".toByteArray())))
        val u = BigInteger(1, Crypto.sha512(padded(bigA), padded(b)))
        val base = b.subtract(k.multiply(G.modPow(x, N))).mod(N)
        val s = base.modPow(a.add(u.multiply(x)), N)
        val sessionKey = Crypto.sha512(s.unsignedBytes())
        val hN = Crypto.sha512(N.unsignedBytes())
        val hG = Crypto.sha512(G.unsignedBytes())
        val xor = BigInteger(1, ByteArray(hN.size) { (hN[it].toInt() xor hG[it].toInt()).toByte() }).unsignedBytes()
        val hI = BigInteger(1, Crypto.sha512("Pair-Setup".toByteArray())).unsignedBytes()
        val m1 = Crypto.sha512(xor, hI, salt, bigA.unsignedBytes(), b.unsignedBytes(), sessionKey)
        val m2 = Crypto.sha512(bigA.unsignedBytes(), m1, sessionKey)
        return Result(m1, m2, sessionKey)
    }

    companion object {
        val N = BigInteger(
            "ffffffffffffffffc90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74020bbea63b139b22514a08798e3404dd" +
                "ef9519b3cd3a431b302b0a6df25f14374fe1356d6d51c245e485b576625e7ec6f44c42e9a637ed6b0bff5cb6f406b7ed" +
                "ee386bfb5a899fa5ae9f24117c4b1fe649286651ece45b3dc2007cb8a163bf0598da48361c55d39a69163fa8fd24cf5f" +
                "83655d23dca3ad961c62f356208552bb9ed529077096966d670c354e4abc9804f1746c08ca18217c32905e462e36ce3b" +
                "e39e772c180e86039b2783a2ec07a28fb5c55df06f4c52c9de2bcbf6955817183995497cea956ae515d2261898fa0510" +
                "15728e5a8aaac42dad33170d04507a33a85521abdf1cba64ecfb850458dbef0a8aea71575d060c7db3970f85a6e1e4c7" +
                "abf5ae8cdb0933d71e8c94e04a25619dcee3d2261ad2ee6bf12ffa06d98a0864d87602733ec86a64521f2b18177b200c" +
                "bbe117577a615d6c770988c0bad946e208e24fa074e5ab3143db5bfce0fd108e4b82d120a93ad2caffffffffffffffff",
            16,
        )
        val G: BigInteger = BigInteger.valueOf(5)

        fun padded(v: BigInteger, size: Int = 384): ByteArray {
            val b = v.unsignedBytes()
            return ByteArray(maxOf(0, size - b.size)) + b
        }
    }
}
