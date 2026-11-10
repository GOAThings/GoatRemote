package cc.slokker.goatremote

import java.util.Locale
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Os textos do Android são os de contracts/strings.json, com os mesmos nomes que no iPhone (U8). */
class StringsTest {
    @Test
    fun table() {
        val json = Contracts.obj("strings.json")
        val strings = json.getJSONObject("strings")
        val phone = json.getJSONObject("phone").getJSONObject("android")
        val mine = Strings.table.toMap()
        val expected = strings.keys().asSequence().filter { key ->
            strings.getJSONObject(key).getJSONArray("platforms").let { a -> (0 until a.length()).any { a.getString(it) == "android" } }
        }.toSet()
        assertEquals(expected, mine.keys)
        val saved = Locale.getDefault()
        try {
            for (lang in listOf("en", "pt")) {
                Locale.setDefault(Locale.forLanguageTag(lang))
                for ((key, text) in mine) {
                    val entry = strings.getJSONObject(key)
                    val override = entry.optJSONObject("android") ?: JSONObject()
                    val want = override.optString(lang).ifEmpty { entry.getString(lang) }.replace("{phone}", phone.getString(lang))
                    assertEquals("$key ($lang)", want, text())
                }
            }
        } finally {
            Locale.setDefault(saved)
        }
        assertTrue(mine.size > 100)
    }
}
