package cc.slokker.goatremote.ui

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
import androidx.compose.ui.draw.shadow
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
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** O visual do comando da Apple TV: fundo preto, peças em cinzento-vidro com um realce subtil em cima. */
object Theme {
    val background = Color.Black
    val surface = Color(0xFF1C1C1E)
    val surfaceTop = Color(0xFF26262A)
    val surfaceBottom = Color(0xFF18181B)
    val surfacePressed = Color(0xFF2C2C2E)
    val surfaceHigh = Color(0xFF2C2C2E)
    val accent = Color(0xFF38BDF8)
    val accent2 = Color(0xFF8B5CF6)
    val power = Color(0xFFEF4444)
    val green = Color(0xFF34C759)
    val orange = Color(0xFFFF9F0A)
    val dim = Color.White.copy(alpha = 0.55f)
    val faint = Color.White.copy(alpha = 0.18f)
    val gradient = Brush.linearGradient(listOf(accent, accent2))
    /** O realce da borda: mais claro em cima, quase nada em baixo (dá o ar de vidro). */
    val rim = Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.22f), Color.White.copy(alpha = 0.04f)))

    val colors: ColorScheme = darkColorScheme(
        primary = accent,
        onPrimary = Color.Black,
        secondary = accent2,
        background = background,
        surface = surface,
        surfaceContainerLow = surface,
        surfaceContainer = surface,
        surfaceContainerHigh = surfaceHigh,
        onSurface = Color.White,
        onSurfaceVariant = dim,
        error = power,
    )
}

fun hexColor(value: Long) = Color(0xFF000000 or value)

@Composable
fun GoatTheme(content: @Composable () -> Unit) = MaterialTheme(colorScheme = Theme.colors, content = content)

/** Fundo de vidro escuro numa forma qualquer. */
fun Modifier.glass(shape: Shape, pressed: Boolean = false): Modifier = this
    .shadow(10.dp, shape, ambientColor = Color.Black, spotColor = Color.Black)
    .clip(shape)
    .background(
        Brush.verticalGradient(if (pressed) listOf(Theme.surfacePressed, Theme.surfaceTop) else listOf(Theme.surfaceTop, Theme.surfaceBottom)),
    )
    .border(1.dp, Theme.rim, shape)

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

/** Botão redondo de vidro com um símbolo. */
@Composable
fun GlassKey(
    icon: ImageVector,
    label: String,
    tag: String,
    size: Dp = 60.dp,
    tint: Color = Color.White,
    onHold: ((Boolean) -> Unit)? = null,
    onTap: () -> Unit,
) {
    var pressed by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (pressed) 0.92f else 1f, spring(dampingRatio = 0.6f, stiffness = 900f), label = "press")
    Box(
        modifier = Modifier
            .size(size)
            .scale(scale)
            .glass(CircleShape, pressed)
            .pressable(onTap, onHold) { pressed = it }
            .semantics { contentDescription = label; role = Role.Button }
            .testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(size * 0.4f))
    }
}

/** Imagens da rede (banners do GoatLauncher, ícones da App Store), guardadas em memória. */
object Images {
    private val cache = LruCache<String, ImageBitmap>(64)

    suspend fun load(url: String): ImageBitmap? {
        cache.get(url)?.let { return it }
        return withContext(Dispatchers.IO) {
            runCatching {
                val c = URL(url).openConnection() as HttpURLConnection
                c.connectTimeout = 4000
                c.readTimeout = 6000
                try {
                    if (c.responseCode != 200) return@runCatching null
                    BitmapFactory.decodeStream(c.inputStream)?.asImageBitmap()
                } finally {
                    c.disconnect()
                }
            }.onFailure { Log.w("GoatRemote", "imagem $url", it) }.getOrNull()
        }?.also { cache.put(url, it) }
    }
}

@Composable
fun rememberImage(url: String?): ImageBitmap? {
    val image by produceState<ImageBitmap?>(null, url) { value = url?.let { Images.load(it) } }
    return image
}
