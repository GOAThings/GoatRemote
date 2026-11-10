package cc.slokker.goatremote

import cc.slokker.goatremote.apple.CompanionCredentials
import cc.slokker.goatremote.apple.CompanionStore
import cc.slokker.goatremote.apple.KeyValue
import cc.slokker.goatremote.apple.SecretBox
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * C6: as credenciais da Apple TV passam das SharedPreferences em claro para cifradas (Keystore). Aqui com uma chave AES
 * de software no lugar do Keystore; a lógica (ler o antigo, escrever o novo, apagar o antigo só depois de ler o novo de
 * volta) é a mesma.
 */
class CompanionStoreTest {
    private class Map : KeyValue {
        val values = LinkedHashMap<String, String>()
        override fun get(key: String) = values[key]
        override fun put(key: String, value: String) { values[key] = value }
        override fun remove(key: String) { values.remove(key) }
        override fun keys() = values.keys.toSet()
    }

    private class Box(var broken: Boolean = false, var corruptOnRead: Boolean = false) : SecretBox {
        private val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        override fun seal(plain: ByteArray): ByteArray {
            check(!broken) { "keystore broken" }
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.ENCRYPT_MODE, key)
            return c.iv + c.doFinal(plain)
        }
        override fun open(sealed: ByteArray): ByteArray {
            check(!broken) { "keystore broken" }
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, sealed, 0, 12))
            val plain = c.doFinal(sealed, 12, sealed.size - 12)
            return if (corruptOnRead) plain + byteArrayOf(0) else plain
        }
    }

    private val sample = Contracts.obj("persisted/android/companion.json")
    private fun oldJson(name: String) = sample.getJSONObject(name).toString()

    @Test
    fun oldPrefsMigrateOnLoadAndStillWork() {
        val old = Map().apply { put("apple:Sala", oldJson("airPlay")) }
        val new = Map()
        val box = Box()
        val store = CompanionStore(old, new, box) {}
        val creds = store.load("apple:Sala")!!
        // A mesma chave privada de antes: não é preciso emparelhar outra vez.
        assertArrayEquals(ByteArray(32) { (it + 100).toByte() }, creds.privateKey)
        assertEquals(true, creds.viaAirPlay)
        // O antigo saiu, o novo está cifrado (não tem o JSON em claro) e lê-se.
        assertNull(old.get("apple:Sala"))
        val sealed = new.get("apple:Sala")!!
        assertTrue(!sealed.contains("privateKey"))
        assertArrayEquals(creds.privateKey, CompanionStore(Map(), new, box) {}.load("apple:Sala")!!.privateKey)
    }

    @Test
    fun migrateAllAtStart() {
        val old = Map().apply { put("apple:A", oldJson("plain")); put("apple:B", oldJson("airPlay")); put("apple:bad", "not json") }
        val new = Map()
        CompanionStore(old, new, Box()) {}.migrateAll()
        assertEquals(setOf("apple:bad"), old.keys())
        assertEquals(setOf("apple:A", "apple:B"), new.keys())
    }

    @Test
    fun keystoreFailureKeepsTheOldCopy() {
        val old = Map().apply { put("apple:Sala", oldJson("plain")) }
        val new = Map()
        val store = CompanionStore(old, new, Box(broken = true)) {}
        assertArrayEquals(ByteArray(32) { (it + 1).toByte() }, store.load("apple:Sala")!!.tvPublicKey)
        assertEquals(oldJson("plain"), old.get("apple:Sala"))
        assertNull(new.get("apple:Sala"))
        // Gravar sem Keystore também fica em claro, como antes.
        val creds = CompanionCredentials.fromJson(sample.getJSONObject("airPlay"))
        store.save("apple:Quarto", creds)
        assertNotEquals(null, old.get("apple:Quarto"))
    }

    @Test
    fun readBackMismatchKeepsTheOldCopy() {
        val old = Map().apply { put("apple:Sala", oldJson("plain")) }
        val new = Map()
        CompanionStore(old, new, Box(corruptOnRead = true)) {}.migrateAll()
        assertEquals(oldJson("plain"), old.get("apple:Sala"))
        assertNull(new.get("apple:Sala"))
    }

    @Test
    fun saveAndDelete() {
        val old = Map()
        val new = Map()
        val store = CompanionStore(old, new, Box()) {}
        val creds = CompanionCredentials.fromJson(sample.getJSONObject("plain"))
        store.save("apple:Sala", creds)
        assertTrue(old.keys().isEmpty())
        assertArrayEquals(creds.clientId, store.load("apple:Sala")!!.clientId)
        store.delete("apple:Sala")
        assertNull(store.load("apple:Sala"))
        assertTrue(new.keys().isEmpty())
    }
}
