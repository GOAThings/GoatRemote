package cc.slokker.goatremote.data

import java.net.URL
import java.net.URLEncoder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Os ícones das apps da Apple TV, da App Store (pelo bundle id). */
object AppStoreArtwork {
    /** O URL do ícone (512 px, senão 100), ou null. */
    suspend fun lookup(bundleId: String): String? = withContext(Dispatchers.IO) {
        runCatching {
            val url = URL("https://itunes.apple.com/lookup?bundleId=" + URLEncoder.encode(bundleId, "UTF-8"))
            val json = JSONObject(url.readText())
            json.getJSONArray("results").optJSONObject(0)?.let { it.optString("artworkUrl512").ifEmpty { it.optString("artworkUrl100") } }
        }.getOrNull()
    }
}
