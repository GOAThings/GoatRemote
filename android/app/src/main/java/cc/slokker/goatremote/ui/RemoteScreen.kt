package cc.slokker.goatremote.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.LiveTv
import androidx.compose.material.icons.outlined.Tv
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Apps
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.FastForward
import androidx.compose.material.icons.rounded.FastRewind
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Keyboard
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.LiveTv
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.PowerSettingsNew
import androidx.compose.material.icons.rounded.Tv
import androidx.compose.material.icons.rounded.VolumeOff
import androidx.compose.material.icons.rounded.VolumeUp
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cc.slokker.goatremote.L
import cc.slokker.goatremote.RemoteViewModel
import cc.slokker.goatremote.RemoteViewModel.Status
import cc.slokker.goatremote.data.AppCatalog
import cc.slokker.goatremote.data.TvKind
import cc.slokker.goatremote.tv.Key
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class Sheet { APPS, MORE, TVS, ADD }

/**
 * O comando, ao jeito do da Apple TV: em cima som, a TV e ligar; ao meio uma superfície de toque; em baixo
 * play/pausa, voltar e início. Por cima destes, uma fila discreta com teclado, apps, recuar/avançar e mais.
 */
@Composable
fun RemoteScreen(vm: RemoteViewModel) {
    var sheet by remember { mutableStateOf<Sheet?>(null) }
    var volumeVisible by remember { mutableStateOf(false) }

    LaunchedEffect(vm.volumeChanged) {
        if (vm.volumeChanged == 0) return@LaunchedEffect
        volumeVisible = true
        delay(1600)
        volumeVisible = false
    }
    LaunchedEffect(vm.closeSheets) { sheet = null }
    LaunchedEffect(vm.showKeyboard) { if (vm.showKeyboard) sheet = null }

    Column(Modifier.fillMaxSize().padding(horizontal = 18.dp).padding(top = 8.dp, bottom = 12.dp)) {
        TopBar(vm) { sheet = Sheet.TVS }
        Spacer(Modifier.height(16.dp))
        Box(Modifier.weight(1f).fillMaxWidth()) {
            TouchSurface(vm)
            SurfaceInfo(vm)
            androidx.compose.animation.AnimatedVisibility(
                visible = volumeVisible,
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 16.dp),
                enter = slideInVertically { -it } + fadeIn(),
                exit = slideOutVertically { -it } + fadeOut(),
            ) { VolumeHud(vm) }
        }
        Spacer(Modifier.height(18.dp))
        val small = Color.White.copy(alpha = 0.8f)
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            GlassKey(Icons.Rounded.Keyboard, L("Keyboard", "Teclado"), "keyboard", 48.dp, small) { vm.showKeyboard = true }
            GlassKey(Icons.Rounded.Apps, "Apps", "apps", 48.dp, small) { sheet = Sheet.APPS }
            GlassKey(Icons.Rounded.FastRewind, L("Rewind", "Recuar"), "key:rewind", 48.dp, small, onHold = { vm.hold(Key.REWIND, it) }) { vm.press(Key.REWIND) }
            GlassKey(Icons.Rounded.FastForward, L("Forward", "Avançar"), "key:fastForward", 48.dp, small, onHold = { vm.hold(Key.FAST_FORWARD, it) }) {
                vm.press(Key.FAST_FORWARD)
            }
            GlassKey(Icons.Rounded.MoreHoriz, L("More", "Mais"), "more", 48.dp, small) { sheet = Sheet.MORE }
        }
        Spacer(Modifier.height(22.dp))
        Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween) {
            PlayPauseKey { vm.press(Key.PLAY_PAUSE) }
            GlassKey(Icons.AutoMirrored.Rounded.KeyboardArrowLeft, L("Back", "Voltar"), "key:back", 96.dp, onHold = { vm.hold(Key.BACK, it) }) { vm.press(Key.BACK) }
            GlassKey(Icons.Rounded.Tv, L("Home", "Início"), "key:home", 74.dp, onHold = { vm.hold(Key.HOME, it) }) { vm.press(Key.HOME) }
        }
    }

    if (vm.showKeyboard) KeyboardSheet(vm) { vm.showKeyboard = false }
    when (sheet) {
        Sheet.APPS -> AppsSheet(vm) { sheet = null }
        Sheet.MORE -> MoreSheet(vm) { sheet = null }
        Sheet.TVS -> TvsSheet(vm, onAdd = { sheet = Sheet.ADD }) { sheet = null }
        Sheet.ADD -> AddTvSheet(vm) { sheet = null }
        null -> Unit
    }
}

@Composable
private fun PlayPauseKey(onTap: () -> Unit) {
    var pressed by remember { mutableStateOf(false) }
    Row(
        Modifier.size(74.dp).glass(CircleShape, pressed).pressable(onTap) { pressed = it }
            .semantics { contentDescription = L("Play/Pause", "Reproduzir/pausa") }
            .testTag("key:playPause"),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.PlayArrow, null, tint = Color.White, modifier = Modifier.size(24.dp))
        Icon(Icons.Rounded.Pause, null, tint = Color.White, modifier = Modifier.size(22.dp).offset(x = (-4).dp))
    }
}

@Composable
private fun TopBar(vm: RemoteViewModel, onTvs: () -> Unit) {
    val muted = vm.state.muted == true
    Row(verticalAlignment = Alignment.CenterVertically) {
        GlassKey(Icons.Rounded.VolumeOff, L("Mute", "Silenciar"), "key:mute", 58.dp, if (muted) Theme.accent else Theme.dim) { vm.press(Key.MUTE) }
        Spacer(Modifier.width(12.dp))
        var pressed by remember { mutableStateOf(false) }
        Row(
            Modifier.weight(1f).heightIn(min = 58.dp).glass(RoundedCornerShape(50), pressed).pressable(onTvs) { pressed = it }
                .padding(horizontal = 18.dp)
                .semantics { contentDescription = L("TVs", "TVs") }
                .testTag("tv-menu"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // A TV num círculo de vidro, com o estado da ligação num ponto ao canto.
            Box(Modifier.size(36.dp)) {
                Box(
                    Modifier.size(34.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.08f))
                        .border(0.5.dp, Color.White.copy(alpha = 0.14f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(if (vm.current?.kind == TvKind.APPLE) Icons.Outlined.LiveTv else Icons.Outlined.Tv, null,
                        tint = Color.White.copy(alpha = 0.9f), modifier = Modifier.size(18.dp))
                }
                Box(
                    Modifier.align(Alignment.BottomEnd).size(11.dp).clip(CircleShape).background(Theme.surfaceTop).padding(2.dp)
                        .clip(CircleShape).background(statusColor(vm)),
                )
            }
            Spacer(Modifier.width(11.dp))
            Column(Modifier.weight(1f)) {
                Text(vm.current?.name ?: "GoatRemote", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(subtitle(vm), color = Theme.dim, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1,
                    overflow = TextOverflow.Ellipsis)
            }
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = Theme.dim, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(12.dp))
        GlassKey(Icons.Rounded.PowerSettingsNew, L("Power", "Ligar"), "key:power", 58.dp, if (vm.state.isOn == false) Theme.dim else Color.White) {
            vm.press(Key.POWER)
        }
    }
}

private fun statusColor(vm: RemoteViewModel) = when (vm.status) {
    Status.Connected -> if (vm.state.isOn == false) Theme.dim else Theme.green
    Status.Connecting -> Theme.orange
    Status.NoTv -> Theme.dim
    else -> Theme.power
}

private fun subtitle(vm: RemoteViewModel): String = when (vm.status) {
    Status.Connected -> {
        val app = vm.state.currentApp
        when {
            vm.state.isOn == false -> L("TV is off", "A TV está desligada")
            app != null && !AppCatalog.isLauncher(app) -> AppCatalog.name(app)
            // A Apple TV não diz que app está aberta.
            vm.current?.kind == TvKind.APPLE -> "Apple TV"
            else -> L("Home screen", "Ecrã inicial")
        }
    }
    Status.Connecting -> L("Connecting…", "A ligar…")
    Status.NotPaired -> L("Not paired", "Não emparelhada")
    is Status.Unreachable -> L("Can't reach it", "Sem ligação")
    Status.NoTv -> ""
}

/** Dentro da superfície: a app aberta em marca-d'água, ou o que se passa com a ligação (com o que fazer). */
@Composable
private fun SurfaceInfo(vm: RemoteViewModel) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        when (val s = vm.status) {
            Status.Connected -> {
                val watermark = Color.White.copy(alpha = 0.13f)
                val app = vm.state.currentApp?.takeUnless(AppCatalog::isLauncher)
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(horizontal = 20.dp).testTag("status")) {
                    Icon(
                        when {
                            vm.state.isOn == false -> Icons.Rounded.Bedtime
                            app != null -> Icons.Rounded.LiveTv
                            vm.current?.kind == TvKind.APPLE -> Icons.Rounded.Tv
                            else -> Icons.Rounded.Home
                        },
                        null, tint = watermark, modifier = Modifier.size(52.dp),
                    )
                    Spacer(Modifier.height(10.dp))
                    Text(
                        when {
                            vm.state.isOn == false -> L("TV is off", "A TV está desligada")
                            app != null -> AppCatalog.name(app)
                            vm.current?.kind == TvKind.APPLE -> "Apple TV"
                            else -> L("Home screen", "Ecrã inicial")
                        },
                        color = watermark, fontSize = 19.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                    )
                }
                // Com as setas nas bordas, as próprias setas já dizem o que fazer.
                if (!vm.dpadTaps) {
                    Text(
                        L("Swipe to move · tap to select · hold for more", "Desliza para andar · toca para escolher · mantém para mais"),
                        color = watermark.copy(alpha = 0.1f), fontSize = 11.sp, textAlign = TextAlign.Center,
                        modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 16.dp, start = 20.dp, end = 20.dp),
                    )
                }
            }
            Status.Connecting -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator(color = Theme.dim, strokeWidth = 2.dp, modifier = Modifier.size(28.dp))
                Spacer(Modifier.height(12.dp))
                Text(L("Connecting to the TV…", "A ligar à TV…"), color = Theme.dim, fontSize = 13.sp)
            }
            Status.NotPaired -> Notice(
                Icons.Rounded.Link,
                L("This TV doesn't know this phone", "Esta TV não conhece este telemóvel"),
                L("Pair again: the TV will show a code.", "Emparelha outra vez: a TV mostra um código."),
                L("Pair", "Emparelhar"),
            ) { vm.repairCurrent() }
            is Status.Unreachable -> Notice(
                Icons.Rounded.WifiOff,
                L("Can't reach the TV", "Não chego à TV"),
                L("Is it on and on the same Wi-Fi? ", "Está ligada e na mesma rede Wi-Fi? ") + s.why,
                L("Try again", "Tentar outra vez"),
            ) { vm.reconnect() }
            Status.NoTv -> Unit
        }
    }
}

@Composable
private fun Notice(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, detail: String, button: String, action: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(28.dp)) {
        Icon(icon, null, tint = Theme.accent, modifier = Modifier.size(38.dp))
        Spacer(Modifier.height(12.dp))
        Text(title, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(detail, color = Theme.dim, fontSize = 13.sp, textAlign = TextAlign.Center, maxLines = 4)
        Spacer(Modifier.height(16.dp))
        Button(onClick = action, colors = ButtonDefaults.buttonColors(containerColor = Theme.accent)) { Text(button) }
    }
}

/** O volume da TV por um bocado, quando muda (ou porque não dá, na Apple TV sem HDMI-CEC). */
@Composable
private fun VolumeHud(vm: RemoteViewModel) {
    val shape = RoundedCornerShape(50)
    if (!vm.state.volumeControl) {
        Row(Modifier.padding(horizontal = 16.dp).glass(shape).padding(horizontal = 14.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.VolumeOff, null, tint = Color.White, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(8.dp))
            Text(L("The Apple TV can't change this TV's volume. Use its remote", "A Apple TV não muda o volume desta TV. Usa o comando dela"),
                color = Color.White, fontSize = 13.sp, textAlign = TextAlign.Center)
        }
        return
    }
    val max = (vm.state.maxVolume ?: 100).toFloat()
    val level = if (max > 0) (vm.state.volume ?: 0) / max else 0f
    val muted = vm.state.muted == true
    Row(Modifier.height(30.dp).glass(shape).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(if (muted) Icons.Rounded.VolumeOff else Icons.Rounded.VolumeUp, null, tint = Color.White, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(10.dp))
        Box(Modifier.width(120.dp).height(5.dp).clip(shape).background(Theme.faint)) {
            Box(Modifier.fillMaxWidth(level.coerceIn(0f, 1f)).height(5.dp).clip(shape)
                .background(if (muted) androidx.compose.ui.graphics.SolidColor(Theme.dim) else Theme.gradient))
        }
        Spacer(Modifier.width(10.dp))
        Text("${(level * 100).roundToInt()}", color = Color.White, fontSize = 13.sp, modifier = Modifier.width(28.dp), textAlign = TextAlign.End)
    }
}

private class Ripple(val id: Int, val point: Offset, val strong: Boolean)

/**
 * A superfície de toque. Deslizar anda (um passo por cada bocado de dedo), tocar é OK, manter é OK longo.
 * Com "setas nas bordas", tocar perto de uma borda carrega nessa seta.
 */
@Composable
private fun TouchSurface(vm: RemoteViewModel) {
    val shape = RoundedCornerShape(40.dp)
    val ripples = remember { mutableStateListOf<Ripple>() }
    var nextRipple by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val step = with(LocalDensity.current) { 44.dp.toPx() }

    fun addRipple(point: Offset, strong: Boolean = false) {
        val ripple = Ripple(nextRipple++, point, strong)
        ripples.add(ripple)
        scope.launch {
            delay(500)
            ripples.remove(ripple)
        }
    }

    BoxWithConstraints(
        Modifier.fillMaxSize().glass(shape)
            .semantics { contentDescription = L("Touch surface", "Superfície de toque") }
            .testTag("touchpad")
            .pointerInput(vm.dpadTaps) {
                fun centerRadius() = min(size.width, size.height) * 0.26f
                fun target(p: Offset): Key {
                    if (!vm.dpadTaps) return Key.CENTER
                    val dx = p.x - size.width / 2f
                    val dy = p.y - size.height / 2f
                    if (hypot(dx, dy) < centerRadius()) return Key.CENTER
                    // Normaliza pela forma (a superfície é mais alta do que larga).
                    val nx = dx / (size.width / 2f)
                    val ny = dy / (size.height / 2f)
                    return if (abs(nx) > abs(ny)) (if (nx > 0) Key.RIGHT else Key.LEFT) else (if (ny > 0) Key.DOWN else Key.UP)
                }
                awaitEachGesture {
                    val start = awaitFirstDown().position
                    var anchor = start
                    var moved = false
                    var holding: Key? = null
                    val key = target(start)
                    val timer: Job = scope.launch {
                        delay(500)
                        if (!moved) {
                            holding = key
                            vm.hold(key, true)
                            addRipple(start, strong = true)
                        }
                    }
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull() ?: break
                        if (!change.pressed) break
                        change.consume()
                        if (holding != null) continue
                        val dx = change.position.x - anchor.x
                        val dy = change.position.y - anchor.y
                        if (abs(dx) >= step || abs(dy) >= step) {
                            timer.cancel()
                            vm.press(if (abs(dx) > abs(dy)) (if (dx > 0) Key.RIGHT else Key.LEFT) else (if (dy > 0) Key.DOWN else Key.UP))
                            addRipple(change.position)
                            anchor = change.position
                            moved = true
                        }
                    }
                    timer.cancel()
                    val held = holding
                    if (held != null) {
                        vm.hold(held, false)
                    } else if (!moved) {
                        vm.press(key)
                        addRipple(start, strong = true)
                    }
                }
            },
    ) {
        if (vm.dpadTaps) DpadHints()
        ripples.forEach { RippleView(it) }
    }
}

@Composable
private fun DpadHints() {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val radius = min(maxWidth.value, maxHeight.value) * 0.26f
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(Theme.faint, radius = radius.dp.toPx(), style = Stroke(1.dp.toPx()))
        }
        val tint = Theme.faint
        Icon(Icons.Rounded.KeyboardArrowUp, null, tint = tint, modifier = Modifier.align(Alignment.TopCenter).padding(top = 18.dp).size(26.dp))
        Icon(Icons.Rounded.KeyboardArrowDown, null, tint = tint, modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 18.dp).size(26.dp))
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowLeft, null, tint = tint, modifier = Modifier.align(Alignment.CenterStart).padding(start = 16.dp).size(26.dp))
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = tint, modifier = Modifier.align(Alignment.CenterEnd).padding(end = 16.dp).size(26.dp))
    }
}

/** O círculo que se expande e desvanece onde se tocou. */
@Composable
private fun RippleView(ripple: Ripple) {
    val progress = remember(ripple.id) { Animatable(0f) }
    LaunchedEffect(ripple.id) { progress.animateTo(1f, tween(450)) }
    val size = 96.dp
    val half = with(LocalDensity.current) { (size / 2).toPx() }
    val scale = 0.35f + 0.9f * progress.value
    Box(
        Modifier
            .offset { IntOffset((ripple.point.x - half).roundToInt(), (ripple.point.y - half).roundToInt()) }
            .size(size)
            .alpha(1f - progress.value)
            .padding(((1 - scale) * size.value / 2).coerceAtLeast(0f).dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = if (ripple.strong) 0.16f else 0.10f))
            .border(0.dp, Color.Transparent, CircleShape),
    )
}
