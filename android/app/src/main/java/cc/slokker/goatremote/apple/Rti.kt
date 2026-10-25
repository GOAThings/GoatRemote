package cc.slokker.goatremote.apple

import cc.slokker.goatremote.tv.ProtocolException
import java.io.ByteArrayOutputStream

/** Um valor de property list (o mínimo para o teclado da Apple TV). */
sealed class Plist {
    data class Str(val value: String) : Plist()
    data class Int(val value: Long) : Plist()
    class Data(val value: ByteArray) : Plist() {
        override fun equals(other: Any?) = other is Data && other.value.contentEquals(value)
        override fun hashCode() = value.contentHashCode()
        override fun toString() = "<${value.size} bytes>"
    }
    data class Uid(val value: kotlin.Int) : Plist()
    data class Bool(val value: Boolean) : Plist()
    data class Arr(val value: List<Plist>) : Plist()
    data class Dict(val value: Map<String, Plist>) : Plist()
    data object Null : Plist()

    operator fun get(key: String): Plist? = (this as? Dict)?.value?.get(key)
}

/** Property lists binárias ("bplist00"): só os tipos que o teclado da Apple TV usa. */
object BPlist {
    fun encode(root: Plist): ByteArray {
        val objects = mutableListOf<ByteArray>()
        val refs = mutableListOf<List<Int>>()
        val kinds = mutableListOf<Int>() // marcador de contentor (0xA0 / 0xD0) ou 0 para escalares

        fun add(v: Plist): Int {
            val i = objects.size
            objects.add(ByteArray(0)); refs.add(emptyList()); kinds.add(0)
            when (v) {
                Plist.Null -> objects[i] = byteArrayOf(0x00)
                is Plist.Bool -> objects[i] = byteArrayOf(if (v.value) 0x09 else 0x08)
                is Plist.Int -> objects[i] = int(v.value)
                is Plist.Uid -> {
                    val b = when {
                        v.value <= 0xFF -> bigEndian(v.value.toLong(), 1)
                        v.value <= 0xFFFF -> bigEndian(v.value.toLong(), 2)
                        else -> bigEndian(v.value.toLong(), 4)
                    }
                    objects[i] = byteArrayOf((0x80 or (b.size - 1)).toByte()) + b
                }
                is Plist.Data -> objects[i] = header(0x40, v.value.size) + v.value
                is Plist.Str -> {
                    val s = v.value
                    objects[i] = if (s.all { it.code < 0x80 }) {
                        header(0x50, s.length) + s.toByteArray(Charsets.US_ASCII)
                    } else {
                        header(0x60, s.length) + s.toByteArray(Charsets.UTF_16BE)
                    }
                }
                is Plist.Arr -> {
                    kinds[i] = 0xA0
                    refs[i] = v.value.map { add(it) }
                }
                is Plist.Dict -> {
                    kinds[i] = 0xD0
                    val keys = v.value.keys.sorted()
                    val k = keys.map { add(Plist.Str(it)) }
                    val vals = keys.map { add(v.value.getValue(it)) }
                    refs[i] = k + vals
                }
            }
            return i
        }
        add(root)

        val refSize = if (objects.size < 256) 1 else 2
        for (i in objects.indices) {
            if (kinds[i] == 0) continue
            val count = if (kinds[i] == 0xD0) refs[i].size / 2 else refs[i].size
            val body = ByteArrayOutputStream()
            refs[i].forEach { body.write(bigEndian(it.toLong(), refSize)) }
            objects[i] = header(kinds[i], count) + body.toByteArray()
        }
        val out = ByteArrayOutputStream()
        out.write("bplist00".toByteArray())
        val offsets = objects.map { o -> out.size().also { out.write(o) } }
        val tableOffset = out.size()
        val offsetSize = when {
            tableOffset < 256 -> 1
            tableOffset < 65_536 -> 2
            else -> 4
        }
        offsets.forEach { out.write(bigEndian(it.toLong(), offsetSize)) }
        out.write(byteArrayOf(0, 0, 0, 0, 0, 0, offsetSize.toByte(), refSize.toByte()))
        out.write(bigEndian(objects.size.toLong(), 8))
        out.write(bigEndian(0, 8))
        out.write(bigEndian(tableOffset.toLong(), 8))
        return out.toByteArray()
    }

    private fun bigEndian(v: Long, size: Int) = ByteArray(size) { (v ushr (8 * (size - 1 - it))).toByte() }

    private fun int(n: Long): ByteArray = when {
        n in 0..0xFF -> byteArrayOf(0x10) + bigEndian(n, 1)
        n in 0..0xFFFF -> byteArrayOf(0x11) + bigEndian(n, 2)
        n in 0..0xFFFF_FFFFL -> byteArrayOf(0x12) + bigEndian(n, 4)
        else -> byteArrayOf(0x13) + bigEndian(n, 8)
    }

    private fun header(marker: Int, count: Int): ByteArray =
        if (count < 15) byteArrayOf((marker or count).toByte()) else byteArrayOf((marker or 0x0F).toByte()) + int(count.toLong())

    fun decode(bytes: ByteArray): Plist {
        if (bytes.size < 40 || !bytes.copyOf(8).contentEquals("bplist00".toByteArray())) throw ProtocolException("bplist")
        fun be(from: Int, to: Int): Long {
            var v = 0L
            for (i in from until to) v = (v shl 8) or (bytes[i].toLong() and 0xFF)
            return v
        }
        val t = bytes.size - 32
        val offsetSize = bytes[t + 6].toInt()
        val refSize = bytes[t + 7].toInt()
        val count = be(t + 8, t + 16).toInt()
        val top = be(t + 16, t + 24).toInt()
        val table = be(t + 24, t + 32).toInt()
        if (offsetSize <= 0 || refSize <= 0 || table + count * offsetSize > t) throw ProtocolException("bplist: tabela")
        fun offset(i: Int): Int {
            if (i !in 0 until count) throw ProtocolException("bplist: objeto $i")
            return be(table + i * offsetSize, table + (i + 1) * offsetSize).toInt()
        }
        var depth = 0
        fun obj(i: Int): Plist {
            if (++depth > 64) throw ProtocolException("bplist: fundo demais")
            try {
                var p = offset(i)
                if (p >= bytes.size) throw ProtocolException("bplist: fora")
                val marker = bytes[p].toInt() and 0xFF
                p++
                fun length(): Int {
                    val low = marker and 0x0F
                    if (low != 0x0F) return low
                    val size = 1 shl (bytes[p].toInt() and 0x0F)
                    val v = be(p + 1, p + 1 + size).toInt()
                    p += 1 + size
                    return v
                }
                fun take(n: Int): ByteArray {
                    if (n < 0 || p + n > bytes.size) throw ProtocolException("bplist: cortado")
                    return bytes.copyOfRange(p, p + n).also { p += n }
                }
                fun refsOf(r: ByteArray, j: Int): Int {
                    var v = 0
                    for (k in 0 until refSize) v = (v shl 8) or (r[j * refSize + k].toInt() and 0xFF)
                    return v
                }
                return when (marker shr 4) {
                    0x0 -> when (marker) { 0x09 -> Plist.Bool(true); 0x08 -> Plist.Bool(false); else -> Plist.Null }
                    0x1 -> Plist.Int(take(1 shl (marker and 0x0F)).fold(0L) { acc, b -> (acc shl 8) or (b.toLong() and 0xFF) })
                    0x4 -> Plist.Data(take(length()))
                    0x5 -> Plist.Str(String(take(length()), Charsets.UTF_8))
                    0x6 -> Plist.Str(String(take(length() * 2), Charsets.UTF_16BE))
                    0x8 -> Plist.Uid(take((marker and 0x0F) + 1).fold(0) { acc, b -> (acc shl 8) or (b.toInt() and 0xFF) })
                    0xA -> {
                        val n = length()
                        val r = take(n * refSize)
                        Plist.Arr((0 until n).map { obj(refsOf(r, it)) })
                    }
                    0xD -> {
                        val n = length()
                        val r = take(n * 2 * refSize)
                        val d = LinkedHashMap<String, Plist>()
                        for (j in 0 until n) {
                            val key = obj(refsOf(r, j)) as? Plist.Str ?: continue
                            d[key.value] = obj(refsOf(r, n + j))
                        }
                        Plist.Dict(d)
                    }
                    else -> Plist.Null
                }
            } finally {
                depth--
            }
        }
        return obj(top)
    }
}

/** O teclado da Apple TV (RTI): o _tiD que a TV manda e os que se lhe mandam (arquivos "RTIKeyedArchiver"). */
object Rti {
    class State(val session: ByteArray, val text: String)

    /** O id da sessão de texto e o texto antes do cursor, do _tiD da TV. */
    fun state(tiD: ByteArray): State? {
        val root = runCatching { BPlist.decode(tiD) }.getOrNull() ?: return null
        val objects = (root["\$objects"] as? Plist.Arr)?.value ?: return null
        val top = root["\$top"] ?: return null
        fun resolve(v: Plist?): Plist? = if (v is Plist.Uid) objects.getOrNull(v.value) else v
        val session = when (val s = resolve(top["sessionUUID"])) {
            is Plist.Data -> s.value
            is Plist.Dict -> (s.value["NS.uuidbytes"] as? Plist.Data)?.value
            else -> null
        } ?: return null
        val text = resolve(resolve(resolve(top["documentState"])?.get("docSt"))?.get("contextBeforeInput")) as? Plist.Str
        return State(session, text?.value ?: "")
    }

    /** Apaga o texto da caixa. */
    fun clear(session: ByteArray) = archive(session, mapOf("textToAssert" to Plist.Uid(4)), emptyMap(), Plist.Str(""))

    /** Escreve [text] no cursor ("\n" é o return do teclado). */
    fun insert(text: String, session: ByteArray) =
        archive(session, emptyMap(), mapOf("insertionText" to Plist.Uid(4)), Plist.Str(text))

    /**
     * \$objects: 0 \$null, 1 operações, 2 saída do teclado, 3 classe da saída, 4 texto, 5 uuid, 6 classe NSUUID,
     * 7 classe das operações.
     */
    private fun archive(session: ByteArray, operation: Map<String, Plist>, output: Map<String, Plist>, extra: Plist): ByteArray {
        fun cls(name: String) = Plist.Dict(
            mapOf("\$classname" to Plist.Str(name), "\$classes" to Plist.Arr(listOf(Plist.Str(name), Plist.Str("NSObject")))),
        )
        val ops = mapOf("\$class" to Plist.Uid(7), "targetSessionUUID" to Plist.Uid(5), "keyboardOutput" to Plist.Uid(2)) + operation
        val out = mapOf("\$class" to Plist.Uid(3)) + output
        return BPlist.encode(
            Plist.Dict(
                mapOf(
                    "\$version" to Plist.Int(100_000),
                    "\$archiver" to Plist.Str("RTIKeyedArchiver"),
                    "\$top" to Plist.Dict(mapOf("textOperations" to Plist.Uid(1))),
                    "\$objects" to Plist.Arr(
                        listOf(
                            Plist.Str("\$null"), Plist.Dict(ops), Plist.Dict(out), cls("TIKeyboardOutput"), extra,
                            Plist.Dict(mapOf("NS.uuidbytes" to Plist.Data(session), "\$class" to Plist.Uid(6))),
                            cls("NSUUID"), cls("RTITextOperations"),
                        ),
                    ),
                ),
            ),
        )
    }
}
