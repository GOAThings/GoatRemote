package cc.slokker.goatremote

import cc.slokker.goatremote.Contracts.boolOrNull
import cc.slokker.goatremote.Contracts.intOrNull
import cc.slokker.goatremote.Contracts.keyNames
import cc.slokker.goatremote.Contracts.objects
import cc.slokker.goatremote.Contracts.same
import cc.slokker.goatremote.Contracts.stringOrNull
import cc.slokker.goatremote.Contracts.strings
import cc.slokker.goatremote.Contracts.vector
import cc.slokker.goatremote.Contracts.vectorHex
import cc.slokker.goatremote.apple.CompanionCredentials
import cc.slokker.goatremote.apple.Crypto
import cc.slokker.goatremote.data.GoatTvChannels
import cc.slokker.goatremote.data.LanHttp
import cc.slokker.goatremote.data.LauncherApi
import cc.slokker.goatremote.data.LauncherApps
import cc.slokker.goatremote.data.PrefKeys
import cc.slokker.goatremote.data.Programme
import cc.slokker.goatremote.data.SavedTv
import cc.slokker.goatremote.data.TvKind
import cc.slokker.goatremote.tv.IdentityStore
import cc.slokker.goatremote.tv.Key
import cc.slokker.goatremote.tv.KeyDirection
import cc.slokker.goatremote.tv.LauncherVolume
import cc.slokker.goatremote.tv.Pairing
import cc.slokker.goatremote.tv.RemoteProtocol
import cc.slokker.goatremote.tv.RsaKey
import cc.slokker.goatremote.ui.Theme
import androidx.compose.ui.graphics.toArgb
import java.io.DataInputStream
import java.math.BigInteger
import java.nio.file.Files
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** Os contratos de contracts/: o protocolo, o GoatLauncher (6470), o GoatTV (6471) e o que fica guardado. */
class ContractsTest {
    private fun ByteArray.hex() = joinToString("") { "%02x".format(it) }

    // ---- Protocolo da Android TV ----

    @Test
    fun pairingFrames() {
        assertEquals(vectorHex("pairing.request"), Pairing.request("Phone").hex())
        assertEquals(vectorHex("pairing.options"), Pairing.options.hex())
        assertEquals(vectorHex("pairing.configuration"), Pairing.configuration.hex())
        assertEquals(vectorHex("pairing.secretMessage_0to31"), Pairing.secretMessage(ByteArray(32) { it.toByte() }).hex())
        val client = RsaKey(BigInteger(vectorHex("secret.clientModulus"), 16), BigInteger(vectorHex("secret.clientExponent"), 16))
        val server = RsaKey(BigInteger(vectorHex("secret.serverModulus"), 16), BigInteger(vectorHex("secret.serverExponent"), 16))
        assertEquals(vectorHex("secret.secret"), Pairing.secret(vectorHex("secret.code"), client, server)!!.hex())
    }

    @Test
    fun remoteFrames() {
        val r = RemoteProtocol("Phone", "1.0")
        assertEquals(vectorHex("remote.configureReply_android"), r.handle(vector("remote.configure"))[0].hex())
        assertEquals(vectorHex("remote.setActiveReply"), r.handle(vector("remote.setActive"))[0].hex())
        assertEquals(vectorHex("remote.pong"), r.handle(vector("remote.ping"))[0].hex())
        assertEquals(vectorHex("remote.keyCenter"), r.key(Key.CENTER).hex())
        assertEquals(vectorHex("remote.keyHomeStartLong"), r.key(Key.HOME, KeyDirection.START_LONG).hex())
        assertEquals(vectorHex("remote.keyHomeEndLong"), r.key(Key.HOME, KeyDirection.END_LONG).hex())
        r.handle(vector("remote.imeShow_abc_Search"))
        r.handle(vector("remote.imeBatchEdit_7_3"))
        assertEquals(listOf(vectorHex("remote.text_abcola")), r.text("abcolá").map { it.hex() })
        val delete = vectorHex("remote.text_abcd_delete")
        assertEquals(listOf(delete, delete, delete, vectorHex("remote.text_abcd_insert")), r.text("abcd").map { it.hex() })
        assertEquals(vectorHex("remote.appLink_netflix"), r.appLink("market://launch?id=com.netflix.ninja").hex())
    }

    /** Os ids dos testes de interface são os nomes do enum Key do iPhone. */
    @Test
    fun keyIds() {
        assertEquals("volumeUp", Key.VOLUME_UP.id)
        assertEquals("playPause", Key.PLAY_PAUSE.id)
        assertEquals("num7", Key.NUM7.id)
        assertEquals("lastChannel", Key.LAST_CHANNEL.id)
        assertEquals("home", Key.HOME.id)
    }

    @Test
    fun companionCrypto() {
        val key = ByteArray(32) { it.toByte() }
        assertEquals(vectorHex("hkdf.pairVerify"), Crypto.hkdf("Pair-Verify-Encrypt-Salt", "Pair-Verify-Encrypt-Info", key).hex())
        assertEquals(vectorHex("hkdf.clientEncrypt"), Crypto.hkdf("", "ClientEncrypt-main", key).hex())
        assertEquals(vectorHex("nonce.psMsg05"), Crypto.pairingNonce("PS-Msg05").hex())
        assertEquals(vectorHex("sha512.abc"), Crypto.sha512("abc".toByteArray()).hex())
    }

    // ---- GoatTV (6471) ----

    private fun payload(dir: String, value: String) = if (value.startsWith("@")) Contracts.text("$dir/${value.drop(1)}") else value

    @Test
    fun goatTvChannels() {
        for (case in Contracts.obj("goattv-6471/channels.expected.json").getJSONArray("cases").objects()) {
            val text = payload("goattv-6471", case.getString("payload"))
            if (case.opt("expected") == "error") {
                assertThrows(text, Exception::class.java) { GoatTvChannels.parse(text) }
                continue
            }
            val want = case.getJSONObject("expected")
            val list = GoatTvChannels.parse(text)
            assertEquals(want.stringOrNull("playlist"), list.playlist)
            assertEquals(want.stringOrNull("current"), list.current)
            assertEquals(want.getJSONArray("groups").objects().map { it.getString("id") to it.getString("name") }, list.groups.map { it.id to it.name })
            val channels = want.getJSONArray("channels").objects()
            assertEquals(channels.map { it.getString("key") }, list.channels.map { it.key })
            for ((w, c) in channels.zip(list.channels)) {
                assertEquals(w.intOrNull("num"), c.num)
                assertEquals(w.getString("name"), c.name)
                assertEquals(w.stringOrNull("group"), c.group)
                assertEquals(w.getBoolean("logo"), c.logo)
                assertEquals(w.getBoolean("favorite"), c.favorite)
            }
            assertEquals(want.getBoolean("truncated"), list.truncated)
        }
    }

    @Test
    fun goatTvNow() {
        fun programme(o: JSONObject, key: String) = if (o.isNull(key)) null else o.getJSONObject(key).let {
            Programme(it.getString("title"), it.getLong("start"), it.getLong("end"))
        }
        for (case in Contracts.obj("goattv-6471/now.json").getJSONArray("cases").objects()) {
            val text = case.getString("payload")
            if (case.opt("expected") == "error") {
                assertThrows(text, Exception::class.java) { GoatTvChannels.parseNow(text) }
                continue
            }
            val want = case.getJSONObject("expected")
            val info = GoatTvChannels.parseNow(text)
            assertEquals(text, want.stringOrNull("current"), info.current)
            assertEquals(text, programme(want, "now"), info.now)
            assertEquals(text, programme(want, "next"), info.next)
        }
    }

    @Test
    fun goatTvKeysAndOutcomes() {
        val keys = Contracts.obj("goattv-6471/encode-key.json")
        for (i in 0 until keys.getJSONArray("keys").length()) {
            val pair = keys.getJSONArray("keys").getJSONArray(i)
            assertEquals(pair.getString(1), GoatTvChannels.encodeKey(pair.getString(0)))
        }
        for (u in keys.getJSONArray("urls").objects()) {
            assertEquals(u.getString("url"), GoatTvChannels.url(u.getString("host"), u.getString("what"), u.stringOrNull("key")))
        }
        for (row in Contracts.obj("goattv-6471/play-outcome.json").getJSONArray("rows").objects()) {
            val got = GoatTvChannels.playOutcome(row.getInt("status"), row.getBoolean("refused"))
            assertTrue("$row → $got", same(got, row.getString("outcome")))
        }
        for (row in Contracts.obj("goattv-6471/apple-app.json").getJSONArray("rows").objects()) {
            val apps = row.getJSONObject("apps").let { o -> o.keys().asSequence().associateWith { o.getString(it) } }
            assertEquals(row.stringOrNull("expected"), GoatTvChannels.appleApp(apps))
        }
    }

    // ---- A rede de casa ----

    /** B6: os IPv6 vão entre parênteses retos, senão o URL não se lê. */
    @Test
    fun lanUrls() {
        for (row in Contracts.obj("lan-url.json").getJSONArray("rows").objects()) {
            val url = LanHttp.url(row.getString("host"), row.getInt("port"), row.getString("path"))
            assertEquals(row.getString("url"), url)
            java.net.URL(url)
        }
        assertEquals("http://[fe80::1]:6471/play/a%2Fb", GoatTvChannels.url("fe80::1", "play", "a/b"))
        assertEquals("http://[fe80::1]:6470/icon/com.x", LauncherApi("fe80::1").iconUrl("com.x"))
    }

    // ---- GoatLauncher (6470) ----

    @Test
    fun launcherApps() {
        val expected = Contracts.obj("launcher-6470/apps.expected.json")
        val apps = LauncherApps.parse(Contracts.text("launcher-6470/" + expected.getString("input")))
        val want = expected.getJSONArray("expected").objects()
        assertEquals(want.map { it.getString("package") }, apps.map { it.pkg })
        for ((w, a) in want.zip(apps)) {
            assertEquals(w.getString("label"), a.label)
            assertEquals(w.getBoolean("banner"), a.banner)
            assertEquals(w.stringOrNull("color"), a.color)
        }
        for (bad in expected.getJSONArray("notAList").strings()) assertThrows(bad, Exception::class.java) { LauncherApps.parse(bad) }
        for (row in Contracts.obj("launcher-6470/open-fallback.json").getJSONArray("rows").objects()) {
            assertEquals(row.toString(), row.getBoolean("fallback"), LauncherApps.openFallsBack(row.getInt("status")))
        }
    }

    /** A regra que impede a SHIELD de reiniciar: tecla de volume só com a certeza de que não há launcher. */
    @Test
    fun launcherVolumeTable() {
        val rows = Contracts.obj("launcher-6470/volume-outcome.json").getJSONArray("rows").objects()
        assertEquals(24, rows.size)
        for (row in rows) {
            val got = LauncherVolume.outcome(row.boolOrNull("known"), row.getInt("status"), row.getBoolean("refused"))
            assertTrue("$row → $got", same(got, row.getString("outcome")))
        }
    }

    // ---- O que fica guardado ----

    @Test
    fun savedTvs() {
        val sample = Contracts.obj("persisted/android/tvs.json")
        val tvs = sample.getJSONArray("stored").objects().map(SavedTv::fromJson)
        assertEquals(SavedTv("SHIELD", "SHIELD", "192.168.1.10"), tvs[0])
        assertEquals(SavedTv("Sala", "Sala", "192.168.1.11", certSha256 = "ab12cd"), tvs[1])
        assertEquals(SavedTv("apple:Quarto", "Quarto", "192.168.1.20", TvKind.APPLE, 49153), tvs[2])
        val written = sample.getJSONArray("written").objects()
        assertEquals(written.size, tvs.size)
        for ((w, tv) in written.zip(tvs)) {
            assertTrue("${tv.toJson()} != $w", Contracts.sameJson(tv.toJson(), w))
            assertEquals(tv, SavedTv.fromJson(JSONObject(tv.toJson().toString())))
        }
    }

    @Test
    fun companionCredentials() {
        val sample = Contracts.obj("persisted/android/companion.json")
        val plain = CompanionCredentials.fromJson(sample.getJSONObject("plain"))
        assertArrayEquals(ByteArray(32) { (it + 1).toByte() }, plain.tvPublicKey)
        assertArrayEquals(ByteArray(32) { (it + 100).toByte() }, plain.privateKey)
        assertEquals("0B1C2D3E-4F50-6172-8394-A5B6C7D8E9F0", String(plain.clientId))
        assertEquals(false, plain.viaAirPlay)
        assertNull(plain.companionId)
        assertTrue(Contracts.sameJson(plain.toJson(), sample.getJSONObject("plain")))
        val airPlay = CompanionCredentials.fromJson(sample.getJSONObject("airPlay"))
        assertEquals(true, airPlay.viaAirPlay)
        assertEquals("companion-id", String(airPlay.companionId!!))
        assertTrue(Contracts.sameJson(airPlay.toJson(), sample.getJSONObject("airPlay")))
    }

    @Test
    fun optionKeys() {
        val android = Contracts.obj("persisted/options-keys.json").getJSONObject("android")
        assertEquals(PrefKeys.TVS_PREFS, android.getJSONObject("tvsPrefs").getString("name"))
        assertEquals(setOf(PrefKeys.TVS, PrefKeys.CURRENT), android.getJSONObject("tvsPrefs").getJSONObject("keys").keyNames())
        val options = android.getJSONObject("optionsPrefs")
        assertEquals(PrefKeys.OPTIONS_PREFS, options.getString("name"))
        assertEquals(setOf(PrefKeys.HAPTICS, PrefKeys.VOLUME_BUTTONS, PrefKeys.LAYOUT, PrefKeys.DPAD_TAPS, PrefKeys.COMPANION_ID),
            options.getJSONObject("global").keyNames())
        assertEquals(options.getJSONObject("perTv").keyNames(), PrefKeys.PER_TV.toSet())
        assertEquals(PrefKeys.COMPANION_PREFS, android.getJSONObject("companionPrefs").getString("name"))
        assertEquals(listOf("recents.x", "launcher.x", "volumeUnknown.x", "goattv.x"), PrefKeys.perTvKeys("x"))
        assertEquals(android.getJSONArray("layoutValues").strings(), RemoteLayout.entries.map { it.name })
    }

    /** Quem tinha as "setas nas bordas" (dpadTaps) começa nas setas; um layout guardado ganha sempre. */
    @Test
    fun layoutMigration() {
        assertEquals(RemoteLayout.TOUCH, RemoteLayout.saved(null, false))
        assertEquals(RemoteLayout.DPAD, RemoteLayout.saved(null, true))
        assertEquals(RemoteLayout.TOUCH, RemoteLayout.saved("TOUCH", true))
        assertEquals(RemoteLayout.DPAD, RemoteLayout.saved("DPAD", false))
        // Um valor desconhecido (ou o do iPhone, em minúsculas) não é um layout: vale o dpadTaps.
        assertEquals(RemoteLayout.TOUCH, RemoteLayout.saved("dpad", false))
    }

    @Test
    fun identityFile() {
        val dir = Files.createTempDirectory("identity").toFile()
        try {
            val file = java.io.File(dir, "identity")
            val first = IdentityStore(file).get()
            assertTrue(file.exists())
            assertTrue(!java.io.File(dir, "identity.tmp").exists())
            // O formato: tamanho + PKCS#8, tamanho + DER do certificado.
            DataInputStream(file.inputStream()).use { input ->
                val key = ByteArray(input.readInt()).also(input::readFully)
                val cert = ByteArray(input.readInt()).also(input::readFully)
                assertArrayEquals(first.privateKey.encoded, key)
                assertArrayEquals(first.certificate.encoded, cert)
                assertEquals(-1, input.read())
            }
            val again = IdentityStore(file).get()
            assertArrayEquals(first.privateKey.encoded, again.privateKey.encoded)
            assertArrayEquals(first.certificate.encoded, again.certificate.encoded)
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun themeTokens() {
        val theme = Contracts.obj("theme.json")
        val tokens = theme.getJSONObject("tokens")
        fun rgb(c: androidx.compose.ui.graphics.Color) = "%06X".format(c.toArgb() and 0xFFFFFF)
        assertEquals(tokens.getString("background"), rgb(Theme.background))
        assertEquals(tokens.getString("surface"), rgb(Theme.surface))
        assertEquals(tokens.getString("card"), rgb(Theme.card))
        assertEquals(tokens.getString("surfaceHigh"), rgb(Theme.surfaceHigh))
        assertEquals(tokens.getString("surfacePressed"), rgb(Theme.surfacePressed))
        assertEquals(tokens.getString("accent"), rgb(Theme.accent))
        assertEquals(tokens.getString("accent2"), rgb(Theme.accent2))
        assertEquals(tokens.getString("power"), rgb(Theme.power))
        assertEquals(tokens.getString("green"), rgb(Theme.green))
        assertEquals(tokens.getString("text"), rgb(Theme.text))
        assertEquals(tokens.getString("dim"), rgb(Theme.dim))
        assertEquals(tokens.getString("faint"), rgb(Theme.faint))
        assertEquals(tokens.getString("heroTop"), rgb(Theme.heroTop))
        assertEquals(tokens.getString("heroBottom"), rgb(Theme.heroBottom))
        assertEquals(tokens.getString("favorite"), rgb(Theme.favorite))
        assertEquals(theme.getJSONObject("androidOnly").getString("orange"), rgb(Theme.orange))
        val alpha = theme.getJSONObject("alpha")
        assertEquals(alpha.getDouble("dim").toFloat(), Theme.dim.alpha, 0.01f)
        assertEquals(alpha.getDouble("faint").toFloat(), Theme.faint.alpha, 0.01f)
        assertEquals(alpha.getDouble("line").toFloat(), Theme.line.alpha, 0.01f)
    }
}
