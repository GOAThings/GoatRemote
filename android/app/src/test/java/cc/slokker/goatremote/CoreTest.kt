package cc.slokker.goatremote

import cc.slokker.goatremote.apple.BPlist
import cc.slokker.goatremote.apple.Crypto
import cc.slokker.goatremote.apple.Opack
import cc.slokker.goatremote.apple.Plist
import cc.slokker.goatremote.apple.Rti
import cc.slokker.goatremote.apple.SrpClient
import cc.slokker.goatremote.apple.Tlv8
import cc.slokker.goatremote.data.GoatTvChannels
import cc.slokker.goatremote.data.NowInfo
import cc.slokker.goatremote.data.Programme
import cc.slokker.goatremote.data.imageSampleSize
import cc.slokker.goatremote.tv.Key
import cc.slokker.goatremote.tv.LauncherVolume
import cc.slokker.goatremote.tv.Pairing
import cc.slokker.goatremote.tv.ProtoMessage
import cc.slokker.goatremote.tv.ProtoWriter
import cc.slokker.goatremote.tv.ProtocolException
import cc.slokker.goatremote.tv.RemoteProtocol
import cc.slokker.goatremote.tv.RsaKey
import cc.slokker.goatremote.tv.certificateMatches
import cc.slokker.goatremote.tv.readLimited
import cc.slokker.goatremote.tv.unsignedBytes
import java.math.BigInteger
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** Os mesmos testes (e vetores) do RemoteCore do iPhone. */
class CoreTest {
    private fun hex(s: String) = s.replace(" ", "").chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    private fun ByteArray.hex() = joinToString("") { "%02x".format(it) }

    @Test
    fun remote() {
        val r = RemoteProtocol("Pixel", "1.0")
        val configure = ProtoWriter().message(1) {
            varint(1, 622)
            message(2) { string(1, "SHIELD"); string(2, "NVIDIA") }
        }.toByteArray()
        val reply = ProtoMessage.parse(r.handle(configure)[0])
        assertEquals(622 and RemoteProtocol.FEATURES, reply.message(1).int(1))
        assertEquals("SHIELD", r.state.model)
        assertEquals(false, r.ready)
        val active = r.handle(ProtoWriter().message(2) { varint(1, 622) }.toByteArray())
        assertEquals(true, r.ready)
        assertEquals(622 and RemoteProtocol.FEATURES, ProtoMessage.parse(active[0]).message(2).int(1))
        val pong = r.handle(ProtoWriter().message(8) { varint(1, 42) }.toByteArray())
        assertEquals(42, ProtoMessage.parse(pong[0]).message(9).int(1))
        r.handle(ProtoWriter().message(40) { bool(1, true) }.toByteArray())
        r.handle(ProtoWriter().message(50) { varint(6, 100); varint(7, 35); bool(8, false) }.toByteArray())
        r.handle(ProtoWriter().message(20) { message(1) { string(12, "com.netflix.ninja") } }.toByteArray())
        r.handle(ProtoWriter().message(21) { varint(1, 7); varint(2, 3) }.toByteArray())
        assertEquals(true, r.state.isOn)
        assertEquals(35, r.state.volume)
        assertEquals("com.netflix.ninja", r.state.currentApp)
        r.handle(ProtoWriter().message(22) { message(2) { string(2, "abc"); string(6, "Search") } }.toByteArray())
        assertEquals(1, r.state.keyboardRequests)
        assertEquals("abc", r.state.textValue)
        assertEquals("Search", r.state.textLabel)
        // A TV recusar um pedido não acaba com a ligação.
        val refusal = ProtoWriter().message(3) { bool(1, true); message(2) { message(90) { string(1, "x") } } }.toByteArray()
        assertEquals(emptyList<ByteArray>(), r.handle(refusal))
        assertEquals(true, r.ready)
        assertEquals("[90]", RemoteProtocol.reportedError(refusal))
        assertEquals(null, RemoteProtocol.reportedError(ProtoWriter().message(8) { varint(1, 42) }.toByteArray()))
        val key = ProtoMessage.parse(r.key(Key.CENTER)).message(10)
        assertEquals(23, key.int(1))
        assertEquals(3, key.int(2))
        // O campo já tem "abc": escrever "abcolá" só insere "olá".
        val typed = r.text("abcolá")
        assertEquals(1, typed.size)
        val text = ProtoMessage.parse(typed[0]).message(21)
        assertEquals(7, text.int(1))
        assertEquals(3, text.int(2))
        assertEquals("olá", text.message(3).message(2).string(3))
        assertEquals(2, text.message(3).message(2).int(1))
        // Apagar "olá" e escrever "d": três Apagar e depois "d".
        val edit = r.text("abcd")
        assertEquals(listOf(67, 67, 67), edit.dropLast(1).map { ProtoMessage.parse(it).message(10).int(1) })
        assertEquals("d", ProtoMessage.parse(edit.last()).message(21).message(3).message(2).string(3))
        assertEquals(0, r.text("abcd").size)
    }

    @Test
    fun pairingSecret() {
        val client = RsaKey(BigInteger("c0ffee", 16), BigInteger.valueOf(65537))
        val server = RsaKey(BigInteger("beef01", 16), BigInteger.valueOf(65537))
        // O primeiro byte do segredo tem de ser o primeiro do código: procura-se um código que bata.
        val code = (0 until 0x10000).firstNotNullOf { n ->
            val tail = "%04X".format(n)
            (0 until 256).map { "%02X".format(it) + tail }.firstOrNull { Pairing.secret(it, client, server) != null }
        }
        assertNotNull(Pairing.secret(code.lowercase(), client, server))
        val wrongFirst = "%02X".format((code.take(2).toInt(16) + 1) % 256) + code.drop(2)
        assertNull(Pairing.secret(wrongFirst, client, server))
        assertNull(Pairing.normalize("12345"))
        assertEquals("ABCDEF", Pairing.normalize(" ab cd ef"))
    }

    @Test
    fun srp() {
        val salt = hex("0102030405060708090a0b0c0d0e0f10")
        val client = SrpClient(hex("202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f"))
        assertEquals("6823a16e8d3da8dd", client.publicKey.copyOf(8).hex())
        // B do servidor de teste: k·v + g^b mod N.
        val n = SrpClient.N
        val g = SrpClient.G
        val k = BigInteger(1, Crypto.sha512(n.unsignedBytes(), SrpClient.padded(g)))
        val x = BigInteger(1, Crypto.sha512(salt, Crypto.sha512("Pair-Setup:1111".toByteArray())))
        val b = k.multiply(g.modPow(x, n)).add(g.modPow(BigInteger(1, ByteArray(32) { 0xAA.toByte() }), n)).mod(n)
        assertEquals("8a68cfc16b392740", b.unsignedBytes().copyOf(8).hex())
        val result = client.process(salt, b.unsignedBytes(), "1111")!!
        assertEquals("042ea4421fa34713", result.sessionKey.copyOf(8).hex())
        assertEquals("6bbc4a3fe6fecde3", result.proof.copyOf(8).hex())
        assertEquals("1bec131ba64b7033", result.expectedServerProof.copyOf(8).hex())
    }

    @Test
    fun crypto() {
        assertEquals(
            "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
            Crypto.sha512("abc".toByteArray()).hex(),
        )
        val key = ByteArray(32) { it.toByte() }
        val nonce = Crypto.pairingNonce("PS-Msg05")
        val sealed = Crypto.seal(key, nonce, "olá".toByteArray(), byteArrayOf(8, 0, 0, 20))
        assertEquals("olá".toByteArray().size + 16, sealed.size)
        assertEquals("olá", String(Crypto.open(key, nonce, sealed, byteArrayOf(8, 0, 0, 20))))
        val me = Crypto.SigningKey.generate()
        val sig = me.sign("data".toByteArray())
        assertTrue(Crypto.verify(me.publicKey, sig, "data".toByteArray()))
        assertEquals(false, Crypto.verify(me.publicKey, sig, "dat4".toByteArray()))
        val a = Crypto.AgreementKey()
        val b = Crypto.AgreementKey()
        assertArrayEquals(a.shared(b.publicKey), b.shared(a.publicKey))
        // RFC 5869 não tem SHA-512; o importante é bater com o iPhone (o mesmo cálculo com sal vazio).
        assertEquals(32, Crypto.hkdf("", "ClientEncrypt-main", key).size)
    }

    @Test
    fun opack() {
        // Bytes do pyatv (com as referências a valores repetidos).
        val hidC = Opack.decode(hex("e4425f69455f68696443425f740a425f63e2455f6842745309a10e425f7831e803"))
        assertEquals("_hidC", hidC["_i"]?.string)
        assertEquals(6L, hidC["_c"]?.get("_hidC")?.int)
        assertEquals(1L, hidC["_c"]?.get("_hBtS")?.int)
        assertEquals(1000L, hidC["_x"]?.int)
        val touch = Opack.decode(hex("e4425f694b5f746f7563685374617274425f740a425f63e3475f686569676874360000000000408f40445f74466c08465f7769647468a5425f7831eb03"))
        assertEquals(Opack.Double(1000.0), touch["_c"]?.get("_width"))
        assertEquals(
            Opack.Arr(listOf(Opack.Str("foo"), Opack.Str("bar"), Opack.Str("foo"), Opack.Str("bar"))),
            Opack.decode(hex("d443666f6f43626172a0a1")),
        )
        assertEquals(Opack.Arr(listOf(Opack.Int(1), Opack.Int(2), Opack.Int(2))), Opack.decode(hex("df30013002c10103")))
        assertEquals(Opack.Double(1.0), Opack.decode(hex("350000803f")))
        assertArrayEquals(hex("31ff01"), Opack.Int(0x1FF).encoded)
        assertArrayEquals(hex("3028"), Opack.Int(40).encoded)
        assertArrayEquals(hex("6121"), Opack.Str("a".repeat(33)).encoded.copyOf(2))
        assertArrayEquals(hex("d309447465737402"), Opack.Arr(listOf(Opack.Int(1), Opack.Str("test"), Opack.Bool(false))).encoded)
        val many = Opack.Arr(List(15) { Opack.Str("a") })
        assertEquals(0xDF.toByte(), many.encoded[0])
        assertEquals(many, Opack.decode(many.encoded))
        val msg = Opack.dict(
            "_i" to Opack.Str("_launchApp"), "_t" to Opack.Int(2), "_c" to Opack.dict("_bundleID" to Opack.Str("com.netflix.Netflix")),
            "_x" to Opack.Int(1001), "f" to Opack.Double(-10.0), "d" to Opack.Data(byteArrayOf(1, 2, 3)),
        )
        assertEquals(msg, Opack.decode(msg.encoded))
    }

    @Test
    fun tlv8() {
        val big = ByteArray(300) { it.toByte() }
        val encoded = Tlv8.encode(6 to byteArrayOf(1), 3 to big, 4 to byteArrayOf(9, 9))
        assertEquals(3 + (2 + 255) + (2 + 45) + 4, encoded.size)
        val decoded = Tlv8.decode(encoded)
        assertArrayEquals(byteArrayOf(1), decoded[6])
        assertArrayEquals(big, decoded[3])
        assertArrayEquals(byteArrayOf(9, 9), decoded[4])
        // M1 real (pyatv antigo): {"_pd": TLV{0:00, 6:01}, "_pwTy": 1}
        val m1 = Opack.decode(hex("e2435f706476000100060101455f7077547909"))
        assertArrayEquals(byteArrayOf(1), Tlv8.decode(m1["_pd"]?.data ?: ByteArray(0))[6])
        assertEquals(1L, m1["_pwTy"]?.int)
    }

    /** O teclado da Apple TV: os bplist do pyatv lêem-se, e os nossos têm o mesmo significado. */
    @Test
    fun rti() {
        val fake = hex(
            "62706c6973743030d2010203085424746f7058246f626a65637473d2040506075b73657373696f6e555549445d646f63" +
                "756d656e74537461746580018002a5090a0b0e1155246e756c6c4f101030313233343536373839616263646566d10c0d" +
                "55646f6353748003d10f105f1012636f6e746578744265666f7265496e70757480045f101c46616b6520436f6d70616e" +
                "696f6e204b6579626f6172642054657874080d121b202c3a3c3e444a5d6066686b808200000000000001010000000000" +
                "000012000000000000000000000000000000a1",
        )
        val state = Rti.state(fake)!!
        assertArrayEquals("0123456789abcdef".toByteArray(), state.session)
        assertEquals("Fake Companion Keyboard Text", state.text)
        val session = "0123456789abcdef".toByteArray()
        val mine = BPlist.decode(Rti.insert("olá hello", session))
        val objects = (mine["\$objects"] as Plist.Arr).value
        assertEquals(Plist.Str("RTIKeyedArchiver"), mine["\$archiver"])
        assertEquals(Plist.Int(100_000), mine["\$version"])
        assertEquals(Plist.Uid(1), mine["\$top"]?.get("textOperations"))
        assertEquals(Plist.Uid(2), objects[1]["keyboardOutput"])
        assertEquals(Plist.Uid(5), objects[1]["targetSessionUUID"])
        assertEquals(Plist.Uid(4), objects[2]["insertionText"])
        assertEquals(Plist.Str("olá hello"), objects[4])
        assertEquals(Plist.Data(session), objects[5]["NS.uuidbytes"])
        assertEquals(Plist.Str("RTITextOperations"), objects[7]["\$classname"])
        val cleared = (BPlist.decode(Rti.clear(session))["\$objects"] as Plist.Arr).value
        assertEquals(Plist.Uid(4), cleared[1]["textToAssert"])
        assertEquals(Plist.Str(""), cleared[4])
        // E o do pyatv (insert "hello"):
        val theirs = BPlist.decode(
            hex(
                "62706c6973743030d4010203040506070a582476657273696f6e592461726368697665725424746f7058246f626a6563" +
                    "747312000186a05f10105254494b657965644172636869766572d108095e746578744f7065726174696f6e738001a80b" +
                    "0c1317181e222555246e756c6cd30d0e0f1011125e6b6579626f6172644f75747075745624636c6173735f1011746172" +
                    "67657453657373696f6e55554944800280078005d2140e15165d696e73657274696f6e54657874800380045568656c6c" +
                    "6fd2191a1b1c5a24636c6173736e616d655824636c61737365735f101054494b6579626f6172644f7574707574a21b1d" +
                    "584e534f626a656374d21f0e20215c4e532e7575696462797465734f1010303132333435363738396162636465668006" +
                    "d2191a2324564e5355554944a2231dd2191a26275f1011525449546578744f7065726174696f6e73a2261d0008001100" +
                    "1a0024002900320037004a004d005c005e0067006d00740083008a009e00a000a200a400a900b700b900bb00c100c600" +
                    "d100da00ed00f000f900fe010b011e01200125012c012f01340148000000000000020100000000000000280000000000" +
                    "000000000000000000014b",
            ),
        )
        val py = (theirs["\$objects"] as Plist.Arr).value
        assertEquals(Plist.Uid(3), py[2]["insertionText"])
        assertEquals(Plist.Str("hello"), py[3])
        assertEquals(Plist.Data(session), py[5]["NS.uuidbytes"])
    }

    private fun malformed(body: () -> Unit) {
        assertThrows(ProtocolException::class.java) { body() }
    }

    private fun bytes(vararg values: Int) = ByteArray(values.size) { values[it].toByte() }

    private fun repeated(value: Int, count: Int) = ByteArray(count) { value.toByte() }

    /** Tamanhos impossíveis num campo: erro, nunca um crash. */
    @Test
    fun protoBounds() {
        malformed { ProtoMessage.parse(bytes(0x0A) + repeated(0xFF, 9) + bytes(0x01)) } // 2^64 - 1
        malformed { ProtoMessage.parse(bytes(0x0A) + repeated(0xFF, 8) + bytes(0x7F)) } // Long.MAX_VALUE
        malformed { ProtoMessage.parse(bytes(0x08, 0x01, 0x12, 0xFF, 0xFF, 0xFF, 0xFF, 0x07)) } // Int.MAX_VALUE, já com pos > 0
        malformed { ProtoMessage.parse(bytes(0x0A, 0x85, 0x80, 0x80, 0x80, 0x10, 0x01)) } // 2^32 + 5 não é 5
        malformed { ProtoMessage.parse(bytes(0x0A, 0x05, 0x01)) }
        assertNull(RemoteProtocol.reportedError(bytes(0x0A) + repeated(0xFF, 9) + bytes(0x01)))
    }

    @Test
    fun opackBounds() {
        // O tamanho de 8 bytes: 2^64 - 1, 2^63, Long.MAX_VALUE, 2^32 + 1 (não é 1), e um que não começa no início.
        malformed { Opack.decode(bytes(0x94) + repeated(0xFF, 8)) }
        malformed { Opack.decode(bytes(0x94, 0, 0, 0, 0, 0, 0, 0, 0x80)) }
        malformed { Opack.decode(bytes(0x94) + repeated(0xFF, 7) + bytes(0x7F)) }
        malformed { Opack.decode(bytes(0x94, 1, 0, 0, 0, 1, 0, 0, 0, 0x41)) }
        malformed { Opack.decode(bytes(0xD2, 0x08, 0x94) + repeated(0xFF, 7) + bytes(0x7F)) }
        // Fundura: o limite passa, um a mais não, e uma trama inteira de aberturas também não.
        fun nested(n: Int) = repeated(0xD1, n) + bytes(0x08)
        assertEquals(1, Opack.decode(nested(64)).array?.size)
        malformed { Opack.decode(nested(65)) }
        malformed { Opack.decode(nested(1 shl 20)) }
        malformed { Opack.decode(repeated(0xE1, 1 shl 20)) }
        // Uma chave que é um contentor (referências a um texto longo), e chaves simples, que continuam a servir.
        malformed { Opack.decode(bytes(0xD2, 0x61, 200) + repeated(0x61, 200) + bytes(0xE1, 0xD2, 0xA0, 0xA0, 0x08)) }
        malformed { Opack.decode(bytes(0xE1, 0xE1, 0x41, 0x61, 0x08, 0x08)) }
        assertEquals(1, Opack.decode(bytes(0xE1, 0x09, 0x41, 0x61)).dict?.size)
        // Trabalho: valores a mais numa trama, e muitos valores diferentes lêem-se depressa e referem-se bem.
        malformed { Opack.decode(bytes(0xDF) + repeated(0x08, 100_000) + bytes(0x03)) }
        val distinct = java.io.ByteArrayOutputStream()
        distinct.write(0xDF)
        for (i in 0 until 20_000) distinct.write(bytes(0x32, i and 0xFF, i shr 8 and 0xFF, 1, 0))
        distinct.write(bytes(0xC2, 0x01, 0x00, 0x03))
        val read = Opack.decode(distinct.toByteArray()).array!!
        assertEquals(20_001, read.size)
        assertEquals(Opack.Int((1L shl 16) or 1), read.last())
        // O SRP e o RetryDelay.
        val client = SrpClient(repeated(0x20, 32))
        assertNull(client.process(bytes(1), repeated(0xFF, 1020), "1234"))
        assertNull(client.process(bytes(1), repeated(0xFF, 385), "1234"))
        assertEquals(300, Tlv8.retryDelay(bytes(0x2C, 0x01)))
        assertEquals(0, Tlv8.retryDelay(ByteArray(0)))
        assertNull(Tlv8.retryDelay(repeated(0xFF, 8)))
        assertNull(Tlv8.retryDelay(repeated(0xFF, 4)))
    }

    private fun be(v: Long, size: Int) = ByteArray(size) { (v ushr (8 * (size - 1 - it))).toByte() }

    /** Um bplist à mão, para pôr nos campos o que o [BPlist.encode] nunca escreve. */
    private fun bplist(objects: List<ByteArray>, count: Long? = null, top: Long = 0, offsetSize: Int = 2, refSize: Int = 1): ByteArray {
        var out = "bplist00".toByteArray()
        val offsets = objects.map { o -> out.size.also { out += o } }
        val table = out.size
        for (o in offsets) out += be(o.toLong(), offsetSize)
        out += bytes(0, 0, 0, 0, 0, 0, offsetSize, refSize)
        return out + be(count ?: objects.size.toLong(), 8) + be(top, 8) + be(table.toLong(), 8)
    }

    @Test
    fun bplistBounds() {
        // Referências partilhadas: cada nível aponta duas vezes para o seguinte.
        fun doubling(levels: Int) = bplist(List(levels) { bytes(0xA2, it + 1, it + 1) } + listOf(bytes(0x09)))
        BPlist.decode(doubling(8))
        malformed { BPlist.decode(doubling(40)) }
        // Um texto grande referido muitas vezes também conta.
        val refs = bytes(0xAF, 0x12, 0x00, 0x00, 0x75, 0x30) + repeated(1, 30_000)
        val text = bytes(0x5F, 0x12, 0x00, 0x03, 0x0D, 0x40) + repeated(0x61, 200_000)
        malformed { BPlist.decode(bplist(listOf(refs, text))) }
        // O rodapé: quantos objetos e onde.
        val one = listOf(bytes(0x09))
        malformed { BPlist.decode(bplist(one, count = Long.MAX_VALUE)) }
        malformed { BPlist.decode(bplist(one, count = -1L)) }
        malformed { BPlist.decode(bplist(one, count = (1L shl 32) + 1)) }
        malformed { BPlist.decode(bplist(one, top = -1L)) }
        malformed { BPlist.decode(bplist(one, top = 1L)) }
        malformed { BPlist.decode(bplist(one, offsetSize = 9)) }
        // Tamanhos alargados: negativos, enormes, ou que acabam fora dos dados.
        val eight = repeated(0xFF, 8)
        malformed { BPlist.decode(bplist(listOf(bytes(0x4F, 0x13) + eight))) }
        malformed { BPlist.decode(bplist(listOf(bytes(0x6F, 0x13, 0x7F) + repeated(0xFF, 7)))) }
        malformed { BPlist.decode(bplist(listOf(bytes(0xAF, 0x13, 0x7F) + repeated(0xFF, 7)))) }
        malformed { BPlist.decode(bplist(listOf(bytes(0x4F, 0x1F)))) }
        // Uma referência negativa (8 bytes) e um UID negativo no RTI.
        malformed { BPlist.decode(bplist(listOf(bytes(0xA1) + eight), refSize = 8)) }
        val negativeUid = bplist(
            listOf(
                bytes(0xD2, 1, 2, 3, 4), bytes(0x54) + "\$top".toByteArray(), bytes(0x58) + "\$objects".toByteArray(),
                bytes(0xD1, 5, 6), bytes(0xA0), bytes(0x5B) + "sessionUUID".toByteArray(), bytes(0x87) + eight,
            ),
        )
        assertNull(Rti.state(negativeUid))
        // Um inteiro negativo (8 bytes com sinal) continua a ser um valor válido.
        assertEquals(Plist.Int(-1), BPlist.decode(bplist(listOf(bytes(0x13) + eight))))
    }

    @Test
    fun currentApp() {
        val r = RemoteProtocol("Pixel", "1.0")
        fun report(app: String) = r.handle(ProtoWriter().message(20) { message(1) { string(12, app) } }.toByteArray())
        report("com.netflix.ninja")
        assertEquals("com.netflix.ninja", r.state.currentApp)
        // O que não é um nome de pacote, ou é grande demais, não muda nada.
        for (bad in listOf("", "a".repeat(256), "a".repeat(1 shl 20), "../x", "a b", ".a", "a.", "a..b", "é.x", "a\nb", "a/b")) {
            report(bad)
            assertEquals("com.netflix.ninja", r.state.currentApp)
        }
        for (good in listOf("android", "a".repeat(255), "org.xbmc.kodi", "com.A_b.c9", "com.1password.tv")) {
            report(good)
            assertEquals(good, r.state.currentApp)
        }
    }

    @Test
    fun launcherLimits() {
        val body = ByteArray(10_000) { it.toByte() }
        assertArrayEquals(body, body.inputStream().readLimited(10_000))
        malformed { body.inputStream().readLimited(9_999) }
        assertEquals(1, imageSampleSize(480, 270, 1024))
        assertEquals(1, imageSampleSize(1024, 1024, 1024))
        assertEquals(2, imageSampleSize(1025, 10, 1024))
        assertEquals(8, imageSampleSize(6000, 6000, 1024))
        assertEquals(64, imageSampleSize(10, 65_000, 1024))
    }

    @Test
    fun launcherVolume() {
        assertEquals("up", LauncherVolume.path(Key.VOLUME_UP))
        assertEquals("down", LauncherVolume.path(Key.VOLUME_DOWN))
        assertEquals("mute", LauncherVolume.path(Key.MUTE))
        assertNull(LauncherVolume.path(Key.HOME))
        for (known in listOf(true, false, null)) {
            assertEquals(LauncherVolume.Outcome.DONE, LauncherVolume.outcome(known, 200, false))
            assertEquals(LauncherVolume.Outcome.DIDNT_ANSWER, LauncherVolume.outcome(known, 503, false))
            assertEquals(LauncherVolume.Outcome.DIDNT_ANSWER, LauncherVolume.outcome(known, 0, false))
        }
        // Um launcher já visto nesta TV: um 404 ou uma recusa é só não ter respondido.
        assertEquals(LauncherVolume.Outcome.DIDNT_ANSWER, LauncherVolume.outcome(true, 404, false))
        assertEquals(LauncherVolume.Outcome.DIDNT_ANSWER, LauncherVolume.outcome(true, 0, true))
        // Sem nunca se ter visto um: a tecla continua a servir.
        assertEquals(LauncherVolume.Outcome.NO_LAUNCHER, LauncherVolume.outcome(null, 404, false))
        assertEquals(LauncherVolume.Outcome.NO_LAUNCHER, LauncherVolume.outcome(null, 0, true))
    }

    @Test
    fun certificatePin() {
        assertTrue(certificateMatches("aa", "aa"))
        assertEquals(false, certificateMatches("aa", "bb"))
        assertEquals(false, certificateMatches("aa", null))
        // Emparelhada antes de se guardar: ainda não há com que comparar.
        assertTrue(certificateMatches(null, "bb"))
        assertTrue(certificateMatches(null, null))
    }

    @Test
    fun tvNumbers() {
        val r = RemoteProtocol("Pixel", "1.0")
        r.handle(ProtoWriter().message(50) { varint(6, 1); varint(7, 1L shl 62); bool(8, false) }.toByteArray())
        assertEquals(1, r.state.maxVolume)
        assertEquals(100_000, r.state.volume)
        r.handle(ProtoWriter().message(50) { varint(6, -1L); varint(7, -5L); bool(8, false) }.toByteArray())
        assertEquals(0, r.state.maxVolume)
        assertEquals(0, r.state.volume)
        assertEquals(35, Opack.Double(0.35).percent)
        assertEquals(100, Opack.Double(1.0).percent)
        assertNull(Opack.Double(Double.NaN).percent)
        assertNull(Opack.Double(Double.POSITIVE_INFINITY).percent)
        assertNull(Opack.Double(-1.0).percent)
        assertNull(Opack.Double(1e300).percent)
        assertNull(Opack.Int(1).percent)
    }

    @Test
    fun goatTvChannels() {
        val list = GoatTvChannels.parse("""
            {"playlist": {"id": "p", "name": "My list"}, "current": "k2",
             "groups": [{"id": "g1", "name": "News"}, {"id": "g2", "name": "Sport"}, {"id": "g1", "name": "Again"}, {"name": "No id"}, 7],
             "channels": [
               {"key": "k1", "num": 1, "name": "One", "group": "g1", "logo": true, "favorite": true},
               {"key": "k2", "num": 2.0, "name": "Two", "group": "g2", "logo": false},
               {"key": "k1", "num": 3, "name": "Repeated"},
               {"key": "", "name": "Empty key"},
               {"key": "k4", "name": 4},
               {"name": "No key"},
               {"key": "k5", "num": -1, "name": "${"x".repeat(300)}", "group": 5, "logo": "yes", "favorite": 1},
               {"key": "k6", "num": 1.5, "name": "Six"},
               "nope"
             ]}
        """.trimIndent())
        assertEquals("My list", list.playlist)
        assertEquals("k2", list.current)
        assertEquals(listOf("g1" to "News", "g2" to "Sport"), list.groups.map { it.id to it.name })
        assertEquals(listOf("k1", "k2", "k5", "k6"), list.channels.map { it.key })
        val one = list.channels[0]
        assertEquals(1, one.num)
        assertEquals("One", one.name)
        assertEquals("g1", one.group)
        assertTrue(one.logo && one.favorite)
        assertEquals(2, list.channels[1].num)
        assertEquals(false, list.channels[1].favorite)
        val five = list.channels[2]
        assertNull(five.num)
        assertEquals(GoatTvChannels.MAX_NAME, five.name.length)
        assertNull(five.group)
        assertEquals(false, five.logo)
        assertEquals(false, five.favorite)
        assertNull(list.channels[3].num)
        assertEquals(false, list.truncated)

        // Um "current" que não está na lista (canal escondido ou bloqueado) não se mostra.
        val bare = GoatTvChannels.parse("""{"current": "hidden", "channels": [{"key": "a", "name": "A"}], "truncated": true}""")
        assertNull(bare.current)
        assertNull(bare.playlist)
        assertTrue(bare.groups.isEmpty())
        assertTrue(bare.truncated)
        assertTrue(GoatTvChannels.parse("{}").channels.isEmpty())
        assertThrows(Exception::class.java) { GoatTvChannels.parse("[]") }
        assertThrows(Exception::class.java) { GoatTvChannels.parse("not json") }

        // Chaves grandes demais ficam de fora; a lista corta-se no limite de canais.
        val longKey = GoatTvChannels.parse("""{"channels": [{"key": "${"k".repeat(GoatTvChannels.MAX_KEY + 1)}", "name": "Long"}]}""")
        assertTrue(longKey.channels.isEmpty())
        val many = (0..GoatTvChannels.MAX_CHANNELS).joinToString(",", "{\"channels\": [", "]}") { "{\"key\": \"c$it\", \"name\": \"C\"}" }
        val cut = GoatTvChannels.parse(many)
        assertEquals(GoatTvChannels.MAX_CHANNELS, cut.channels.size)
        assertTrue(cut.truncated)
    }

    @Test
    fun goatTvNow() {
        val info = GoatTvChannels.parseNow("""{"current": "rtp1", "now": {"title": " News ", "start": 1000, "end": 2000}, "next": {"title": "", "start": 2000, "end": 3000}}""")
        assertEquals("rtp1", info.current)
        assertEquals(Programme("News", 1000, 2000), info.now)
        // Sem título não é um programa.
        assertNull(info.next)
        assertEquals(0.5f, info.now!!.progress(1500), 0f)
        // Horas trocadas ou campos com o tipo errado ficam de fora.
        val bad = GoatTvChannels.parseNow("""{"current": 5, "now": {"title": "A", "start": 2000, "end": 1000}, "next": "x"}""")
        assertEquals(NowInfo(null, null, null), bad)
        assertThrows(Exception::class.java) { GoatTvChannels.parseNow("[]") }
    }

    @Test
    fun goatTvKeys() {
        assertEquals("k1", GoatTvChannels.encodeKey("k1"))
        assertEquals("AZaz09-_~", GoatTvChannels.encodeKey("AZaz09-_~"))
        assertEquals("news%2024%2Fhd", GoatTvChannels.encodeKey("news 24/hd"))
        assertEquals("%2E%2E", GoatTvChannels.encodeKey(".."))
        assertEquals("a%3Fb%23c%25d%2Be%26f", GoatTvChannels.encodeKey("a?b#c%d+e&f"))
        assertEquals("%C3%A7%C3%A3o", GoatTvChannels.encodeKey("ção"))
        assertEquals("%F0%9F%93%BA", GoatTvChannels.encodeKey("\uD83D\uDCFA"))
        assertEquals("http://192.168.1.5:6471/play/a%2Fb", GoatTvChannels.url("192.168.1.5", "play", "a/b"))
        assertEquals("http://tv.local:6471/channels", GoatTvChannels.url("tv.local", "channels"))

        assertEquals(GoatTvChannels.Play.DONE, GoatTvChannels.playOutcome(200, false))
        assertEquals(GoatTvChannels.Play.NOT_FOUND, GoatTvChannels.playOutcome(404, false))
        assertEquals(GoatTvChannels.Play.RETRY, GoatTvChannels.playOutcome(409, false))
        assertEquals(GoatTvChannels.Play.RETRY, GoatTvChannels.playOutcome(503, false))
        assertEquals(GoatTvChannels.Play.RETRY, GoatTvChannels.playOutcome(0, true))
        assertEquals(GoatTvChannels.Play.FAILED, GoatTvChannels.playOutcome(0, false))
        assertEquals(GoatTvChannels.Play.FAILED, GoatTvChannels.playOutcome(500, false))

        // Na Apple TV: pelo bundle id, senão pelo nome (IPA assinada com outro id).
        assertEquals("cc.slokker.goattv", GoatTvChannels.appleApp(mapOf("x.goattv" to "GoatTV", "cc.slokker.goattv" to "GoatTV")))
        assertEquals("x.goattv", GoatTvChannels.appleApp(mapOf("com.netflix" to "Netflix", "x.goattv" to "GoatTV")))
        assertNull(GoatTvChannels.appleApp(mapOf("com.netflix" to "Netflix")))
    }
}
