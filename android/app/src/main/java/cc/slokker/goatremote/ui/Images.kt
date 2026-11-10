package cc.slokker.goatremote.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import android.util.LruCache
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import cc.slokker.goatremote.data.imageSampleSize
import cc.slokker.goatremote.tv.readLimited
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Imagens da rede (banners do GoatLauncher, ícones da App Store, logótipos do GoatTV), guardadas em memória. */
object Images {
    const val MAX_BYTES = 4 shl 20
    const val MAX_SIDE = 1024

    private val cache = object : LruCache<String, ImageBitmap>(32 shl 20) {
        override fun sizeOf(key: String, value: ImageBitmap) = value.width * value.height * 4
    }

    /** [maxBytes] e [maxSide]: os logótipos dos canais têm limites mais pequenos do que os banners. */
    suspend fun load(url: String, maxBytes: Int = MAX_BYTES, maxSide: Int = MAX_SIDE): ImageBitmap? {
        cache.get(url)?.let { return it }
        return withContext(Dispatchers.IO) {
            runCatching {
                val c = URL(url).openConnection() as HttpURLConnection
                c.connectTimeout = 4000
                c.readTimeout = 6000
                try {
                    if (c.responseCode != 200) return@runCatching null
                    decode(c.inputStream.readLimited(maxBytes), maxSide)?.asImageBitmap()
                } finally {
                    c.disconnect()
                }
            }.onFailure { Log.w("GoatRemote", "imagem $url", it) }.getOrNull()
        }?.also { cache.put(url, it) }
    }

    /** Lê primeiro o tamanho e reduz o que for maior do que alguma vez se mostra. */
    private fun decode(data: ByteArray, maxSide: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options = BitmapFactory.Options().apply { inSampleSize = imageSampleSize(bounds.outWidth, bounds.outHeight, maxSide) }
        return BitmapFactory.decodeByteArray(data, 0, data.size, options)
    }
}

@Composable
fun rememberImage(url: String?, maxBytes: Int = Images.MAX_BYTES, maxSide: Int = Images.MAX_SIDE): ImageBitmap? {
    val image by produceState<ImageBitmap?>(null, url) { value = url?.let { Images.load(it, maxBytes, maxSide) } }
    return image
}
