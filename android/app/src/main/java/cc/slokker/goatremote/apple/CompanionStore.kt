package cc.slokker.goatremote.apple

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import cc.slokker.goatremote.DebugLog
import cc.slokker.goatremote.data.PrefKeys
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

/** Guardar texto por chave (as SharedPreferences na app; um mapa nos testes). */
interface KeyValue {
    fun get(key: String): String?
    fun put(key: String, value: String)
    fun remove(key: String)
    fun keys(): Set<String>
}

/** Cifrar e decifrar (AES-GCM com a chave no Android Keystore na app; outra chave nos testes). */
interface SecretBox {
    fun seal(plain: ByteArray): ByteArray
    fun open(sealed: ByteArray): ByteArray
}

/**
 * As credenciais da Apple TV (com a nossa chave privada Ed25519), cifradas com uma chave AES do Android Keystore que
 * nunca sai do aparelho (C6). O JSON é o mesmo de sempre (contracts/persisted/android/companion.json); o que fica nas
 * SharedPreferences [PrefKeys.COMPANION_KEYSTORE_PREFS] é Base64(IV de 12 bytes + texto cifrado com a etiqueta GCM).
 *
 * Migração (ler o antigo, escrever o novo): as que ainda estão em claro nas SharedPreferences [PrefKeys.COMPANION_PREFS]
 * passam para as novas, e a antiga só se apaga depois de a nova ter sido escrita e lida de volta igual. Se o Keystore
 * falhar, fica a antiga e continua a servir: nunca é preciso emparelhar outra vez por causa disto.
 */
class CompanionStore(
    private val old: KeyValue,
    private val new: KeyValue,
    private val box: SecretBox,
    private val log: (String) -> Unit = DebugLog::add,
) {
    fun load(tvId: String): CompanionCredentials? {
        new.get(tvId)?.let { sealed ->
            val creds = runCatching { decode(sealed) }.onFailure { log("Apple TV credentials: can't decrypt ($it)") }.getOrNull()
            if (creds != null) return creds
        }
        val plain = old.get(tvId) ?: return null
        val creds = runCatching { CompanionCredentials.fromJson(JSONObject(plain)) }.getOrNull() ?: return null
        migrate(tvId, plain)
        return creds
    }

    fun save(tvId: String, creds: CompanionCredentials) {
        val json = creds.toJson().toString()
        if (!writeVerified(tvId, json)) {
            // Sem o Keystore, fica como sempre esteve (em claro), para não perder o emparelhamento.
            old.put(tvId, json)
            return
        }
        old.remove(tvId)
    }

    fun delete(tvId: String) {
        new.remove(tvId)
        old.remove(tvId)
    }

    /** Passa todas as que ainda estão em claro (ao abrir a app). */
    fun migrateAll() {
        for (tvId in old.keys()) old.get(tvId)?.let { migrate(tvId, it) }
    }

    private fun migrate(tvId: String, plain: String) {
        if (runCatching { CompanionCredentials.fromJson(JSONObject(plain)) }.isFailure) return
        if (writeVerified(tvId, plain)) {
            old.remove(tvId)
            log("Apple TV credentials for $tvId moved to the Keystore")
        }
    }

    /** Escreve cifrado e lê de volta: true só se o que se lê é o mesmo JSON. */
    private fun writeVerified(tvId: String, json: String): Boolean = runCatching {
        val sealed = java.util.Base64.getEncoder().encodeToString(box.seal(json.toByteArray(Charsets.UTF_8)))
        new.put(tvId, sealed)
        val back = new.get(tvId)?.let { String(box.open(java.util.Base64.getDecoder().decode(it)), Charsets.UTF_8) }
        if (back != json) {
            new.remove(tvId)
            false
        } else {
            true
        }
    }.onFailure {
        log("Apple TV credentials: Keystore failed ($it)")
        runCatching { new.remove(tvId) }
    }.getOrDefault(false)

    private fun decode(sealed: String): CompanionCredentials {
        val json = String(box.open(java.util.Base64.getDecoder().decode(sealed)), Charsets.UTF_8)
        return CompanionCredentials.fromJson(JSONObject(json))
    }

    companion object {
        @Volatile private var instance: CompanionStore? = null

        fun of(context: Context): CompanionStore = instance ?: synchronized(this) {
            instance ?: CompanionStore(
                Prefs(context.getSharedPreferences(PrefKeys.COMPANION_PREFS, Context.MODE_PRIVATE)),
                Prefs(context.getSharedPreferences(PrefKeys.COMPANION_KEYSTORE_PREFS, Context.MODE_PRIVATE)),
                KeystoreBox(),
            ).also { instance = it }
        }
    }
}

/** As SharedPreferences como [KeyValue]. As escritas são síncronas: a leitura de volta tem de ver o que se escreveu. */
private class Prefs(private val prefs: SharedPreferences) : KeyValue {
    override fun get(key: String) = prefs.getString(key, null)
    override fun put(key: String, value: String) { prefs.edit().putString(key, value).commit() }
    override fun remove(key: String) { prefs.edit().remove(key).commit() }
    override fun keys(): Set<String> = prefs.all.keys.toSet()
}

/** AES-256-GCM com a chave no Android Keystore (criada na primeira vez; não se exporta). */
private class KeystoreBox : SecretBox {
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    override fun seal(plain: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        return cipher.iv + cipher.doFinal(plain)
    }

    override fun open(sealed: ByteArray): ByteArray {
        require(sealed.size > IV_BYTES) { "too short" }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 0, IV_BYTES))
        return cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES)
    }

    private companion object {
        const val ALIAS = "cc.slokker.goatremote.companion"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
    }
}
