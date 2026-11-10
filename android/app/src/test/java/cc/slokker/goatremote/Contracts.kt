package cc.slokker.goatremote

import java.io.File
import org.json.JSONArray
import org.json.JSONObject

/** O que está em contracts/ na raiz do repositório: os mesmos ficheiros que os testes do iPhone lêem. */
object Contracts {
    val dir: File = File(System.getProperty("contracts") ?: error("sem a propriedade contracts (ver build.gradle.kts)"))

    fun text(path: String): String = File(dir, path).readText()

    fun obj(path: String) = JSONObject(text(path))

    /** Um vetor de vectors.json pelo caminho ("srp.salt"), em bytes. */
    fun vector(path: String): ByteArray = hex(vectorHex(path))

    fun vectorHex(path: String): String {
        var o = vectors
        val parts = path.split('.')
        for (part in parts.dropLast(1)) o = o.getJSONObject(part)
        return o.getString(parts.last())
    }

    private val vectors by lazy { obj("vectors.json") }

    fun hex(s: String) = s.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    /** "NOT_FOUND" e "notFound" são o mesmo resultado (os nomes do Kotlin e do Swift). */
    fun same(kotlin: Enum<*>, name: String) = kotlin.name.replace("_", "").equals(name, ignoreCase = true)

    fun JSONObject.stringOrNull(key: String): String? = if (isNull(key)) null else getString(key)

    fun JSONObject.intOrNull(key: String): Int? = if (isNull(key)) null else getInt(key)

    fun JSONObject.boolOrNull(key: String): Boolean? = if (isNull(key)) null else getBoolean(key)

    fun JSONObject.keyNames(): Set<String> = keys().asSequence().toSet()

    /** O mesmo JSON (as mesmas chaves e valores, por qualquer ordem). */
    fun sameJson(a: Any?, b: Any?): Boolean = when {
        a is JSONObject && b is JSONObject -> a.keyNames() == b.keyNames() && a.keyNames().all { sameJson(a.opt(it), b.opt(it)) }
        a is JSONArray && b is JSONArray -> a.length() == b.length() && (0 until a.length()).all { sameJson(a.opt(it), b.opt(it)) }
        a is Number && b is Number -> a.toDouble() == b.toDouble()
        else -> a == b
    }

    fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }

    fun JSONArray.strings(): List<String> = (0 until length()).map { getString(it) }
}
