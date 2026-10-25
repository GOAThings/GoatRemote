package cc.slokker.goatremote.apple

import cc.slokker.goatremote.tv.ProtocolException
import java.io.ByteArrayOutputStream

/**
 * OPACK, a serialização das mensagens da Apple TV (CoreUtils). Escreve-se sem referências (sempre válido); lê-se
 * como o pyatv, que é o que bate certo com as TVs (tabela de valores repetidos).
 */
sealed class Opack {
    data object Null : Opack()
    data class Bool(val value: Boolean) : Opack()
    /** Inteiro sem sinal (64 bits, guardado num Long). */
    data class Int(val value: Long) : Opack()
    data class Double(val value: kotlin.Double) : Opack()
    data class Str(val value: String) : Opack()
    class Data(val value: ByteArray) : Opack() {
        override fun equals(other: Any?) = other is Data && other.value.contentEquals(value)
        override fun hashCode() = value.contentHashCode()
        override fun toString() = "<${value.size} bytes>"
    }
    data class Arr(val value: List<Opack>) : Opack()
    data class Dict(val value: Map<String, Opack>) : Opack()

    operator fun get(key: String): Opack? = (this as? Dict)?.value?.get(key)

    val string: String? get() = (this as? Str)?.value
    val data: ByteArray? get() = (this as? Data)?.value
    val dict: Map<String, Opack>? get() = (this as? Dict)?.value
    val array: List<Opack>? get() = (this as? Arr)?.value

    val int: Long?
        get() = when (this) {
            is Int -> value
            is Double -> value.toLong().takeIf { it.toDouble() == value }
            is Bool -> if (value) 1 else 0
            else -> null
        }

    val encoded: ByteArray
        get() = ByteArrayOutputStream().also { write(this, it) }.toByteArray()

    companion object {
        fun dict(vararg pairs: Pair<String, Opack>) = Dict(mapOf(*pairs))
        fun of(v: Long) = Int(v)
        fun of(v: kotlin.Int) = Int(v.toLong())
        fun of(v: String) = Str(v)
        fun of(v: ByteArray) = Data(v)
        fun of(v: kotlin.Double) = Double(v)

        private fun write(v: Opack, out: ByteArrayOutputStream) {
            fun le(value: Long, width: kotlin.Int) { for (i in 0 until width) out.write((value ushr (8 * i)).toInt() and 0xFF) }
            fun sized(small: kotlin.Int, one: kotlin.Int, bytes: ByteArray) {
                when {
                    bytes.size <= 32 -> out.write(small + bytes.size)
                    bytes.size <= 0xFF -> { out.write(one); le(bytes.size.toLong(), 1) }
                    else -> { out.write(one + 1); le(bytes.size.toLong(), 2) }
                }
                out.write(bytes)
            }
            when (v) {
                Null -> out.write(0x04)
                is Bool -> out.write(if (v.value) 0x01 else 0x02)
                is Int -> {
                    val n = v.value
                    when {
                        n in 0..0x27 -> out.write(n.toInt() + 8)
                        n in 0..0xFF -> { out.write(0x30); le(n, 1) }
                        n in 0..0xFFFF -> { out.write(0x31); le(n, 2) }
                        n in 0..0xFFFF_FFFFL -> { out.write(0x32); le(n, 4) }
                        else -> { out.write(0x33); le(n, 8) }
                    }
                }
                is Double -> { out.write(0x36); le(v.value.toRawBits(), 8) }
                is Str -> sized(0x40, 0x61, v.value.toByteArray(Charsets.UTF_8))
                is Data -> sized(0x70, 0x91, v.value)
                is Arr -> {
                    out.write(0xD0 + minOf(v.value.size, 15))
                    v.value.forEach { write(it, out) }
                    if (v.value.size >= 15) out.write(0x03)
                }
                is Dict -> {
                    out.write(0xE0 + minOf(v.value.size, 15))
                    // Ordem fixa (a TV não liga à ordem; assim os testes são estáveis).
                    for (k in v.value.keys.sorted()) {
                        write(Str(k), out)
                        write(v.value.getValue(k), out)
                    }
                    if (v.value.size >= 15) out.write(0x03)
                }
            }
        }

        fun decode(bytes: ByteArray): Opack = Reader(bytes).read()
    }

    private class Reader(val bytes: ByteArray) {
        var pos = 0
        val table = mutableListOf<Opack>()

        fun take(n: kotlin.Int): ByteArray {
            if (n < 0 || pos + n > bytes.size) throw ProtocolException("OPACK cortado")
            return bytes.copyOfRange(pos, pos + n).also { pos += n }
        }

        fun le(n: kotlin.Int): Long = take(n).withIndex().fold(0L) { acc, (i, b) -> acc or ((b.toLong() and 0xFF) shl (8 * i)) }

        fun remember(v: Opack): Opack {
            if (v !in table) table.add(v)
            return v
        }

        fun ref(i: kotlin.Int): Opack = table.getOrNull(i) ?: throw ProtocolException("OPACK: referência $i fora da tabela")

        fun read(): Opack {
            val t = take(1)[0].toInt() and 0xFF
            return when (t) {
                0x01 -> Bool(true)
                0x02 -> Bool(false)
                0x04 -> Null
                0x05 -> remember(Data(take(16)))
                0x06 -> remember(Data(take(8)))
                in 0x08..0x2F -> Int((t - 8).toLong())
                in 0x30..0x33 -> remember(Int(le(1 shl (t and 0xF))))
                0x35 -> remember(Double(java.lang.Float.intBitsToFloat(le(4).toInt()).toDouble()))
                0x36 -> remember(Double(java.lang.Double.longBitsToDouble(le(8))))
                in 0x40..0x60 -> remember(Str(String(take(t - 0x40), Charsets.UTF_8)))
                in 0x61..0x64 -> remember(Str(String(take(le(t - 0x60).toInt()), Charsets.UTF_8)))
                in 0x70..0x90 -> remember(Data(take(t - 0x70)))
                in 0x91..0x94 -> remember(Data(take(le(intArrayOf(1, 2, 4, 8)[t - 0x91]).toInt())))
                in 0xA0..0xC0 -> ref(t - 0xA0)
                in 0xC1..0xC4 -> ref(le(t - 0xC0).toInt())
                in 0xD0..0xDF -> {
                    val a = mutableListOf<Opack>()
                    if (t == 0xDF) {
                        while (pos < bytes.size && bytes[pos].toInt() != 0x03) a.add(read())
                        take(1)
                    } else {
                        repeat(t and 0xF) { a.add(read()) }
                    }
                    Arr(a)
                }
                in 0xE0..0xEF -> {
                    val d = LinkedHashMap<String, Opack>()
                    fun pair() {
                        val key = read()
                        d[key.string ?: key.toString()] = read()
                    }
                    if (t == 0xEF) {
                        while (pos < bytes.size && bytes[pos].toInt() != 0x03) pair()
                        take(1)
                    } else {
                        repeat(t and 0xF) { pair() }
                    }
                    Dict(d)
                }
                else -> throw ProtocolException("OPACK 0x%02x".format(t))
            }
        }
    }
}

/** TLV8 (emparelhamento HomeKit): tipo, tamanho (até 255) e valor; valores maiores vão em pedaços seguidos. */
object Tlv8 {
    fun encode(vararg items: Pair<kotlin.Int, ByteArray>): ByteArray {
        val out = ByteArrayOutputStream()
        for ((tag, value) in items) {
            var offset = 0
            do {
                val n = minOf(255, value.size - offset)
                out.write(tag)
                out.write(n)
                out.write(value, offset, n)
                offset += n
            } while (offset < value.size)
        }
        return out.toByteArray()
    }

    /** Os pedaços com o mesmo tipo juntam-se. */
    fun decode(bytes: ByteArray): Map<kotlin.Int, ByteArray> {
        val out = LinkedHashMap<kotlin.Int, ByteArray>()
        var i = 0
        while (i + 2 <= bytes.size) {
            val tag = bytes[i].toInt() and 0xFF
            val n = bytes[i + 1].toInt() and 0xFF
            val end = minOf(i + 2 + n, bytes.size)
            out[tag] = (out[tag] ?: ByteArray(0)) + bytes.copyOfRange(i + 2, end)
            i = end
        }
        return out
    }
}
