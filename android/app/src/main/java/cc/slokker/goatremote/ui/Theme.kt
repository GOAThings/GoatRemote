package cc.slokker.goatremote.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import android.util.LruCache
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import cc.slokker.goatremote.data.imageSampleSize
import cc.slokker.goatremote.tv.readLimited
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** O visual do GoatTV no telemóvel: fundo azul-noite, cartões opacos, botões redondos e o azul→roxo de destaque. */
object Theme {
    val background = Color(0xFF05070D)
    /** O fundo das folhas. */
    val surface = Color(0xFF0B0D14)
    /** Cartões (listas, teclas do Mais). */
    val card = Color(0xFF12151D)
    /** Botões e o que está dentro de um cartão. */
    val surfaceHigh = Color(0xFF191D28)
    val surfacePressed = Color(0xFF262C3D)
    val accent = Color(0xFF5AA9FF)
    val accent2 = Color(0xFF8B7CFF)
    val power = Color(0xFFF2777E)
    val green = Color(0xFF34D399)
    val orange = Color(0xFFFF9F0A)
    val text = Color(0xFFF5F5F7)
    val dim = Color(0xFFEBEBF5).copy(alpha = 0.6f)
    val faint = Color(0xFFEBEBF5).copy(alpha = 0.38f)
    val line = Color.White.copy(alpha = 0.08f)
    val gradient = Brush.linearGradient(listOf(accent, accent2))
    /** O cartão do que está a dar: o azul-escuro do GoatTV com um brilho do destaque no canto. */
    val hero = Brush.linearGradient(listOf(Color(0xFF1D2236), Color(0xFF0E1018)))

    val colors: ColorScheme = darkColorScheme(
        primary = accent,
        onPrimary = Color.Black,
        secondary = accent2,
        background = background,
        surface = surface,
        surfaceContainerLow = surface,
        surfaceContainer = surface,
        surfaceContainerHigh = surfaceHigh,
        onSurface = text,
        onSurfaceVariant = dim,
        error = power,
    )
}

fun hexColor(value: Long) = Color(0xFF000000 or value)

@Composable
fun GoatTheme(content: @Composable () -> Unit) = MaterialTheme(colorScheme = Theme.colors, content = content)

/** Fundo de botão numa forma qualquer: opaco, mais claro enquanto se carrega. */
fun Modifier.glass(shape: Shape, pressed: Boolean = false): Modifier = this
    .clip(shape)
    .background(if (pressed) Theme.surfacePressed else Theme.surfaceHigh)

/** Fundo de cartão (listas, teclas do Mais). */
fun Modifier.card(shape: Shape, pressed: Boolean = false): Modifier = this
    .clip(shape)
    .background(if (pressed) Theme.surfaceHigh else Theme.card)

/** O fundo do cartão do que está a dar e da superfície de toque: o gradiente do GoatTV e um brilho no canto. */
fun Modifier.hero(shape: Shape, glow: Float = 0.22f): Modifier = this
    .clip(shape)
    .background(Theme.hero)
    .drawBehind {
        drawRect(Brush.radialGradient(listOf(Theme.accent.copy(alpha = glow), Color.Transparent),
            center = androidx.compose.ui.geometry.Offset(size.width * 0.8f, size.height * 0.1f), radius = size.maxDimension * 0.7f))
    }

/**
 * Um botão do comando: toque curto, ou carregar e manter (manda o início e o fim do toque longo à TV).
 * [pressed] diz ao desenho se está carregado.
 */
@Composable
fun Modifier.pressable(onTap: () -> Unit, onHold: ((Boolean) -> Unit)? = null, pressed: (Boolean) -> Unit = {}): Modifier {
    val scope = rememberCoroutineScope()
    val tap by rememberUpdatedState(onTap)
    val hold by rememberUpdatedState(onHold)
    val press by rememberUpdatedState(pressed)
    return pointerInput(Unit) {
        awaitEachGesture {
            awaitFirstDown()
            press(true)
            var holding = false
            val timer: Job? = hold?.let { h ->
                scope.launch {
                    delay(450)
                    holding = true
                    h(true)
                }
            }
            val up = waitForUpOrCancellation()
            timer?.cancel()
            if (holding) hold?.invoke(false) else if (up != null) tap()
            press(false)
        }
    }
}

/** Botão redondo com um símbolo. [filled]: branco com o símbolo a preto (o botão principal, voltar). */
@Composable
fun GlassKey(
    icon: ImageVector,
    label: String,
    tag: String,
    size: Dp = 60.dp,
    tint: Color = Theme.text,
    filled: Boolean = false,
    onHold: ((Boolean) -> Unit)? = null,
    onTap: () -> Unit,
) {
    var pressed by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (pressed) 0.92f else 1f, spring(dampingRatio = 0.6f, stiffness = 900f), label = "press")
    Box(
        modifier = Modifier
            .size(size)
            .scale(scale)
            .then(if (filled) Modifier.clip(CircleShape).background(if (pressed) Color(0xFFD9DAE0) else Color.White) else Modifier.glass(CircleShape, pressed))
            .pressable(onTap, onHold) { pressed = it }
            .semantics { contentDescription = label; role = Role.Button }
            .testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = if (filled) Color.Black else tint, modifier = Modifier.size(size * 0.4f))
    }
}

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
