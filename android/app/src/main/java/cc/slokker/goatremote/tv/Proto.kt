package cc.slokker.goatremote.tv

import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream

/**
 * Protobuf mínimo, só o que o protocolo do comando precisa (varints e campos com tamanho). As mensagens são poucas e
 * pequenas: não vale a pena o plugin do protobuf nem a biblioteca.
 */
class ProtoWriter {
    private val out = ByteArrayOutputStream()

    fun varint(field: Int, value: Long) = apply {
        tag(field, WIRE_VARINT)
        writeVarint(out, value)
    }

    fun varint(field: Int, value: Int) = varint(field, value.toLong())

    fun bool(field: Int, value: Boolean) = varint(field, if (value) 1L else 0L)

    fun bytes(field: Int, value: ByteArray) = apply {
        tag(field, WIRE_LEN)
        writeVarint(out, value.size.toLong())
        out.write(value)
    }

    fun string(field: Int, value: String) = bytes(field, value.toByteArray(Charsets.UTF_8))

    fun message(field: Int, build: ProtoWriter.() -> Unit) = bytes(field, ProtoWriter().apply(build).toByteArray())

    fun toByteArray(): ByteArray = out.toByteArray()

    private fun tag(field: Int, wire: Int) = writeVarint(out, (field.toLong() shl 3) or wire.toLong())
}

/** Uma mensagem lida: os campos por número, com os valores pela ordem em que vieram. */
class ProtoMessage(private val fields: Map<Int, List<Any>>) {
    fun has(field: Int) = fields.containsKey(field)

    fun long(field: Int): Long = fields[field]?.lastOrNull() as? Long ?: 0L

    fun int(field: Int): Int = long(field).toInt()

    fun bool(field: Int): Boolean = long(field) != 0L

    fun bytes(field: Int): ByteArray = fields[field]?.lastOrNull() as? ByteArray ?: ByteArray(0)

    fun string(field: Int): String = bytes(field).toString(Charsets.UTF_8)

    /** Um campo com uma mensagem lá dentro; vazia se não veio. */
    fun message(field: Int): ProtoMessage = parse(bytes(field))

    fun messages(field: Int): List<ProtoMessage> = fields[field].orEmpty().filterIsInstance<ByteArray>().map(::parse)

    companion object {
        fun parse(data: ByteArray): ProtoMessage {
            val fields = LinkedHashMap<Int, MutableList<Any>>()
            var pos = 0
            fun varint(): Long {
                var result = 0L
                var shift = 0
                while (true) {
                    if (pos >= data.size) throw ProtocolException("varint cortado")
                    val b = data[pos++].toInt() and 0xFF
                    result = result or ((b and 0x7F).toLong() shl shift)
                    if (b and 0x80 == 0) return result
                    shift += 7
                    if (shift > 63) throw ProtocolException("varint demasiado longo")
                }
            }
            while (pos < data.size) {
                val tag = varint()
                val field = (tag ushr 3).toInt()
                when ((tag and 7).toInt()) {
                    WIRE_VARINT -> fields.getOrPut(field) { mutableListOf() }.add(varint())
                    WIRE_LEN -> {
                        val len = varint().toInt()
                        if (len < 0 || pos + len > data.size) throw ProtocolException("campo cortado")
                        fields.getOrPut(field) { mutableListOf() }.add(data.copyOfRange(pos, pos + len))
                        pos += len
                    }
                    WIRE_I64 -> pos += 8
                    WIRE_I32 -> pos += 4
                    else -> throw ProtocolException("tipo de campo desconhecido")
                }
            }
            return ProtoMessage(fields)
        }
    }
}

class ProtocolException(message: String) : Exception(message)

private const val WIRE_VARINT = 0
private const val WIRE_I64 = 1
private const val WIRE_LEN = 2
private const val WIRE_I32 = 5

/** Cada mensagem vai precedida do tamanho, em varint. */
fun OutputStream.writeFrame(message: ByteArray) {
    val buf = ByteArrayOutputStream(message.size + 5)
    writeVarint(buf, message.size.toLong())
    buf.write(message)
    write(buf.toByteArray())
    flush()
}

/** Lê uma mensagem inteira; [EOFException] quando a ligação fecha. */
fun InputStream.readFrame(): ByteArray {
    var len = 0
    var shift = 0
    while (true) {
        val b = read()
        if (b < 0) throw EOFException()
        len = len or ((b and 0x7F) shl shift)
        if (b and 0x80 == 0) break
        shift += 7
        if (shift > 28) throw ProtocolException("tamanho inválido")
    }
    if (len > MAX_FRAME) throw ProtocolException("mensagem demasiado grande")
    val data = ByteArray(len)
    var read = 0
    while (read < len) {
        val n = read(data, read, len - read)
        if (n < 0) throw EOFException()
        read += n
    }
    return data
}

private const val MAX_FRAME = 1 shl 20

private fun writeVarint(out: OutputStream, value: Long) {
    var v = value
    while (true) {
        if (v and 0x7FL.inv() == 0L) {
            out.write(v.toInt())
            return
        }
        out.write(((v and 0x7F) or 0x80).toInt())
        v = v ushr 7
    }
}
