package cc.slokker.goatremote.ui

import android.os.SystemClock
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.material.icons.automirrored.rounded.List
import androidx.compose.material.icons.rounded.Gamepad
import androidx.compose.material.icons.rounded.TouchApp
import androidx.compose.ui.semantics.selected
import cc.slokker.goatremote.RemoteLayout
import cc.slokker.goatremote.data.TvChannel
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
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.rounded.VolumeDown
import androidx.compose.material.icons.rounded.VolumeUp
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
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
import cc.slokker.goatremote.Strings
import cc.slokker.goatremote.text
import cc.slokker.goatremote.RemoteViewModel
import cc.slokker.goatremote.RemoteViewModel.Status
import cc.slokker.goatremote.data.AppCatalog
import cc.slokker.goatremote.data.OnScreen
import cc.slokker.goatremote.data.TvKind
import cc.slokker.goatremote.tv.Key
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class Sheet { APPS, CHANNELS, MORE, TVS, ADD }

/**
 * O comando, com o visual do GoatTV: em cima o nome da TV (tocar escolhe outra), som e ligar; o canal do GoatTV quando
 * ele está a dar; ao meio a superfície de toque ou as setas; em baixo play/pausa, voltar e início, e por cima destes uma
 * fila com teclado, apps, recuar/avançar e mais.
 */
@Composable
fun RemoteScreen(vm: RemoteViewModel) {
    var sheet by remember { mutableStateOf<Sheet?>(null) }
    var volumeVisible by remember { mutableStateOf(false) }

    LaunchedEffect(vm.volumeChanged) {
        if (vm.volumeChanged == 0) return@LaunchedEffect
        volumeVisible = true
        delay(Gestures.VOLUME_HUD_MS)
        volumeVisible = false
    }
    LaunchedEffect(vm.closeSheets) { sheet = null }
    LaunchedEffect(vm.showKeyboard) { if (vm.showKeyboard) sheet = null }

    Column(Modifier.fillMaxSize().padding(horizontal = 18.dp).padding(top = 8.dp, bottom = 12.dp)) {
        Header(vm) { sheet = Sheet.TVS }
        val now = vm.nowPlaying
        if (now != null) {
            Spacer(Modifier.height(14.dp))
            NowCard(vm, now) { sheet = Sheet.CHANNELS }
        }
        Spacer(Modifier.height(12.dp))
        Box(Modifier.weight(1f).fillMaxWidth()) {
            val connected = vm.status == Status.Connected
            // A ligar (a abrir a app, a voltar de segundo plano) fica o comando escolhido, esbatido até a TV responder.
            val live = connected || vm.status == Status.Connecting
            if (live && vm.layout == RemoteLayout.DPAD) {
                Dpad(vm, ready = connected)
            } else {
                TouchSurface(vm)
                SurfaceInfo(vm)
            }
            if (live) LayoutSwitch(vm, Modifier.align(Alignment.TopEnd).padding(12.dp))
            androidx.compose.animation.AnimatedVisibility(
                visible = volumeVisible,
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 60.dp),
                enter = slideInVertically { -it } + fadeIn(),
                exit = slideOutVertically { -it } + fadeOut(),
            ) { VolumeHud(vm) }
        }
        Spacer(Modifier.height(18.dp))
        val small = Theme.dim
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            GlassKey(Icons.Rounded.Keyboard, Strings.keyboard, "keyboard", 52.dp, small) { vm.showKeyboard = true }
            GlassKey(Icons.Rounded.Apps, "Apps", "apps", 52.dp, small) { sheet = Sheet.APPS }
            // Com o GoatTV a dar um canal, a lista abre-se no cartão dele.
            if (vm.hasChannels && now == null) GlassKey(Icons.Rounded.LiveTv, Strings.channels, "channels", 52.dp, small) { sheet = Sheet.CHANNELS }
            GlassKey(Icons.Rounded.FastRewind, Strings.rewind, "key:rewind", 52.dp, small, onHold = { vm.hold(Key.REWIND, it) }) { vm.press(Key.REWIND) }
            GlassKey(Icons.Rounded.FastForward, Strings.forward, "key:fastForward", 52.dp, small, onHold = { vm.hold(Key.FAST_FORWARD, it) }) {
                vm.press(Key.FAST_FORWARD)
            }
            GlassKey(Icons.Rounded.MoreHoriz, Strings.more, "more", 52.dp, small) { sheet = Sheet.MORE }
        }
        Spacer(Modifier.height(22.dp))
        Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween) {
            PlayPauseKey { vm.press(Key.PLAY_PAUSE) }
            GlassKey(Icons.AutoMirrored.Rounded.KeyboardArrowLeft, Strings.back, "key:back", 96.dp, filled = true, onHold = { vm.hold(Key.BACK, it) }) {
                vm.press(Key.BACK)
            }
            GlassKey(Icons.Rounded.Tv, Strings.home, "key:home", 74.dp, onHold = { vm.hold(Key.HOME, it) }) { vm.press(Key.HOME) }
        }
    }

    if (vm.showKeyboard) KeyboardSheet(vm) { vm.showKeyboard = false }
    when (sheet) {
        Sheet.APPS -> AppsSheet(vm) { sheet = null }
        Sheet.CHANNELS -> ChannelsSheet(vm) { sheet = null }
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
            .semantics { contentDescription = Strings.playPause }
            .testTag("key:playPause"),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.PlayArrow, null, tint = Color.White, modifier = Modifier.size(24.dp))
        Icon(Icons.Rounded.Pause, null, tint = Color.White, modifier = Modifier.size(22.dp).offset(x = (-4).dp))
    }
}

/** O nome da TV em grande (tocar abre as TVs), com o estado por baixo; à direita, som e ligar. */
@Composable
private fun Header(vm: RemoteViewModel, onTvs: () -> Unit) {
    val muted = vm.state.muted == true
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(
            Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).clickable(onClick = onTvs)
                .semantics { contentDescription = Strings.tvs }
                .testTag("tv-menu"),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(vm.current?.name ?: "GoatRemote", color = Theme.text, fontSize = 30.sp, fontWeight = FontWeight.ExtraBold,
                    letterSpacing = (-0.5).sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                Icon(Icons.Rounded.KeyboardArrowDown, null, tint = Theme.faint, modifier = Modifier.padding(start = 2.dp).size(26.dp))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(7.dp).clip(CircleShape).background(statusColor(vm)))
                Spacer(Modifier.width(7.dp))
                Text(subtitle(vm), color = Theme.dim, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Spacer(Modifier.width(10.dp))
        GlassKey(Icons.Rounded.VolumeOff, Strings.mute, "key:mute", 42.dp, if (muted) Theme.accent else Theme.dim) { vm.press(Key.MUTE) }
        Spacer(Modifier.width(8.dp))
        GlassKey(Icons.Rounded.PowerSettingsNew, Strings.power, "key:power", 42.dp, if (vm.state.isOn == false) Theme.dim else Theme.power) {
            vm.press(Key.POWER)
        }
    }
}

/** O canal que o GoatTV está a dar: canal anterior/seguinte e a lista. */
@Composable
private fun NowCard(vm: RemoteViewModel, channel: TvChannel, onList: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().hero(RoundedCornerShape(20.dp)).padding(14.dp).testTag("now-card"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ChannelLogo(vm, channel, 62.dp, 42.dp, Color.Black.copy(alpha = 0.35f))
        Spacer(Modifier.width(12.dp))
        // Com o /now do GoatTV: o programa, as horas, quanto falta e uma barra; sem ele, só o canal.
        val now by produceState(System.currentTimeMillis()) {
            while (true) {
                delay(15_000)
                value = System.currentTimeMillis()
            }
        }
        val programme = vm.nowInfo?.takeIf { it.current == channel.key }?.now?.takeIf { it.startMs <= now && it.endMs > now }
        Column(Modifier.weight(1f)) {
            val caption = if (programme != null) listOfNotNull(channel.num?.toString(), channel.name).joinToString(" · ")
            else "GoatTV" + (channel.num?.let { " · $it" } ?: "")
            Text(caption.uppercase(), color = Theme.faint, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(programme?.title ?: channel.name, color = Theme.text, fontSize = 17.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1,
                overflow = TextOverflow.Ellipsis)
            if (programme != null) {
                Box(Modifier.padding(top = 7.dp).fillMaxWidth().height(3.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.12f))) {
                    Box(Modifier.fillMaxWidth(programme.progress(now)).height(3.dp).clip(CircleShape).background(Theme.gradient))
                }
                val left = ((programme.endMs - now) / 60_000 + 1).toInt()
                Text("${clock(programme.startMs)} – ${clock(programme.endMs)} · " + L("$left min left", "faltam $left min"),
                    color = Theme.dim, fontSize = 12.sp, maxLines = 1, modifier = Modifier.padding(top = 5.dp).testTag("now-programme"))
            }
        }
        Spacer(Modifier.width(8.dp))
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            ZapKey(Icons.Rounded.KeyboardArrowUp, Strings.nextChannel, "zap:next") { vm.zap(1) }
            ZapKey(Icons.Rounded.KeyboardArrowDown, Strings.previousChannel, "zap:previous") { vm.zap(-1) }
        }
        Spacer(Modifier.width(10.dp))
        Box(
            Modifier.size(44.dp).clip(CircleShape).background(Color.White).clickable(onClick = onList)
                .semantics { contentDescription = Strings.channels }
                .testTag("channels"),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.AutoMirrored.Rounded.List, null, tint = Color.Black, modifier = Modifier.size(22.dp)) }
    }
}

/** Hora:minuto, como o telemóvel as mostra. */
private fun clock(ms: Long): String = java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date(ms))

@Composable
private fun ZapKey(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, tag: String, onTap: () -> Unit) {
    var pressed by remember { mutableStateOf(false) }
    Box(
        Modifier.size(34.dp, 30.dp).clip(RoundedCornerShape(10.dp)).background(Color.White.copy(alpha = if (pressed) 0.18f else 0.08f))
            .pressable(onTap) { pressed = it }
            .semantics { contentDescription = label }
            .testTag(tag),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = Theme.text, modifier = Modifier.size(18.dp)) }
}

/** Superfície de toque ou setas; a escolha fica guardada. */
@Composable
private fun LayoutSwitch(vm: RemoteViewModel, modifier: Modifier) {
    Row(modifier.clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.35f)).padding(3.dp)) {
        for ((layout, icon, label) in listOf(
            Triple(RemoteLayout.TOUCH, Icons.Rounded.TouchApp, Strings.touchSurface),
            Triple(RemoteLayout.DPAD, Icons.Rounded.Gamepad, Strings.arrows),
        )) {
            val on = vm.layout == layout
            Box(
                Modifier.size(38.dp, 30.dp).clip(RoundedCornerShape(50)).background(if (on) Color.White else Color.Transparent)
                    .clickable { vm.changeLayout(layout) }
                    .semantics { contentDescription = label; selected = on }
                    .testTag("layout:" + layout.name.lowercase()),
                contentAlignment = Alignment.Center,
            ) { Icon(icon, null, tint = if (on) Color.Black else Theme.faint, modifier = Modifier.size(17.dp)) }
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
    Status.Connected -> screenLabel(vm)
    Status.Connecting -> Strings.connecting
    Status.NotPaired -> Strings.notPaired
    is Status.Unreachable -> Strings.cantReachIt
    Status.NoTv -> ""
}

private fun onScreen(vm: RemoteViewModel) = OnScreen.of(vm.state.isOn, vm.state.currentApp, vm.current?.kind)

/** O que está no ecrã da TV: o subtítulo do cabeçalho e a marca-d'água da superfície dizem o mesmo. */
private fun screenLabel(vm: RemoteViewModel): String = when (onScreen(vm)) {
    OnScreen.OFF -> Strings.tvIsOff
    OnScreen.APP -> AppCatalog.name(vm.state.currentApp.orEmpty())
    // A Apple TV não diz que app está aberta.
    OnScreen.APPLE_TV -> "Apple TV"
    OnScreen.HOME -> Strings.homeScreen
}

/** Dentro da superfície: a app aberta em marca-d'água, ou o que se passa com a ligação (com o que fazer). */
@Composable
private fun SurfaceInfo(vm: RemoteViewModel) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        when (val s = vm.status) {
            Status.Connected -> {
                val watermark = Color.White.copy(alpha = 0.13f)
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(horizontal = 20.dp).testTag("status")) {
                    Icon(
                        when (onScreen(vm)) {
                            OnScreen.OFF -> Icons.Rounded.Bedtime
                            OnScreen.APP -> Icons.Rounded.LiveTv
                            OnScreen.APPLE_TV -> Icons.Rounded.Tv
                            OnScreen.HOME -> Icons.Rounded.Home
                        },
                        null, tint = watermark, modifier = Modifier.size(52.dp),
                    )
                    Spacer(Modifier.height(10.dp))
                    Text(
                        screenLabel(vm),
                        color = watermark, fontSize = 19.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                    )
                }
                Text(
                    Strings.swipeToMoveTapToSelect,
                    color = Theme.faint.copy(alpha = 0.25f), fontSize = 12.sp, textAlign = TextAlign.Center,
                    modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 16.dp, start = 20.dp, end = 20.dp),
                )
            }
            Status.Connecting -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator(color = Theme.dim, strokeWidth = 2.dp, modifier = Modifier.size(28.dp))
                Spacer(Modifier.height(12.dp))
                Text(Strings.connectingToTheTv, color = Theme.dim, fontSize = 13.sp)
            }
            Status.NotPaired -> Notice(
                Icons.Rounded.Link,
                Strings.thisTvDoesntKnowThisPhone,
                Strings.pairAgainTheTvWillShow,
                Strings.pair,
            ) { vm.repairCurrent() }
            is Status.Unreachable -> Notice(
                Icons.Rounded.WifiOff,
                Strings.cantReachTheTv,
                Strings.isItOnAndOnThe + s.why,
                Strings.tryAgain,
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
    val problem = vm.volumeProblem
    if (problem != null) {
        Row(Modifier.padding(horizontal = 16.dp).glass(shape).padding(horizontal = 14.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Warning, null, tint = Color.White, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(8.dp))
            Text(problem.text, color = Color.White, fontSize = 13.sp, textAlign = TextAlign.Center)
        }
        return
    }
    if (!vm.state.volumeControl) {
        Row(Modifier.padding(horizontal = 16.dp).glass(shape).padding(horizontal = 14.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.VolumeOff, null, tint = Color.White, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(8.dp))
            Text(Strings.theAppleTvCantChangeThis,
                color = Color.White, fontSize = 13.sp, textAlign = TextAlign.Center)
        }
        return
    }
    vm.volumePressed?.let { key ->
        // Sem valor para mostrar (HDMI-CEC): só o que se carregou.
        Row(Modifier.height(30.dp).glass(shape).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(when (key) {
                Key.MUTE -> Icons.Rounded.VolumeOff
                Key.VOLUME_UP -> Icons.Rounded.VolumeUp
                else -> Icons.Rounded.VolumeDown
            }, null, tint = Color.White, modifier = Modifier.size(16.dp))
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

/** A superfície de toque. Deslizar anda (um passo por cada bocado de dedo), tocar é OK, manter é OK longo. */
@Composable
private fun TouchSurface(vm: RemoteViewModel) {
    val shape = RoundedCornerShape(28.dp)
    val ripples = remember { mutableStateListOf<Ripple>() }
    var nextRipple by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val step = with(LocalDensity.current) { Gestures.Touch.STEP_DP.dp.toPx() }
    DisposableEffect(vm.keyHold) { onDispose { vm.keyHold.end() } }

    fun addRipple(point: Offset, strong: Boolean = false) {
        val ripple = Ripple(nextRipple++, point, strong)
        ripples.add(ripple)
        scope.launch {
            delay(500)
            ripples.remove(ripple)
        }
    }

    BoxWithConstraints(
        Modifier.fillMaxSize().hero(shape, glow = 0.16f)
            .semantics { contentDescription = Strings.touchSurface }
            .testTag("touchpad")
            .pointerInput(Unit) {
                awaitEachGesture {
                    val start = awaitFirstDown().position
                    var anchor = start
                    var moved = false
                    var holding: Key? = null
                    // Dedo parado depois de deslizar: a mesma direção repete-se, cada vez mais depressa.
                    var repeating: Job? = null
                    val key = Key.CENTER
                    val timer: Job = vm.keyHold.later(scope) {
                        delay(Gestures.Touch.HOLD_MS)
                        if (!moved) {
                            holding = key
                            vm.hold(key, true)
                            vm.keyHold.longStarted(key) { vm.hold(it, false) }
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
                            repeating?.cancel()
                            val direction = if (abs(dx) > abs(dy)) (if (dx > 0) Key.RIGHT else Key.LEFT) else (if (dy > 0) Key.DOWN else Key.UP)
                            vm.press(direction)
                            addRipple(change.position)
                            anchor = change.position
                            moved = true
                            val position = change.position
                            repeating = vm.keyHold.later(scope) {
                                delay(Gestures.Touch.REPEAT_AFTER_MS)
                                vm.repeatStarted()
                                var interval = Gestures.Touch.REPEAT_START_MS
                                while (true) {
                                    vm.press(direction, haptic = false)
                                    addRipple(position)
                                    delay(interval)
                                    interval = (interval - Gestures.Touch.REPEAT_STEP_MS).coerceAtLeast(Gestures.Touch.REPEAT_MIN_MS)
                                }
                            }
                        }
                    }
                    timer.cancel()
                    repeating?.cancel()
                    val held = holding
                    if (held != null) {
                        vm.keyHold.longEnded()
                        vm.hold(held, false)
                    } else if (!moved) {
                        vm.press(key)
                        addRipple(start, strong = true)
                    }
                }
            },
    ) {
        ripples.forEach { RippleView(it) }
    }
}

/**
 * As setas e o OK, como num comando físico. Manter uma seta repete-a, cada vez mais depressa; manter o OK é o OK longo.
 */
@Composable
private fun Dpad(vm: RemoteViewModel, ready: Boolean) {
    // A tecla acesa e o brilho dela: acende ao tocar e apaga devagar ao largar, nunca antes de LIT_MIN_MS (num toque
    // rápido, só enquanto o dedo estava em cima, mal se via).
    var lit by remember { mutableStateOf<Key?>(null) }
    val glow = remember { Animatable(0f) }
    var fade by remember { mutableStateOf<Job?>(null) }
    val scope = rememberCoroutineScope()
    DisposableEffect(vm.keyHold) { onDispose { vm.keyHold.end() } }
    BoxWithConstraints(Modifier.fillMaxSize().hero(RoundedCornerShape(28.dp), glow = 0.16f).padding(20.dp), contentAlignment = Alignment.Center) {
        val side = minOf(maxWidth, maxHeight, 320.dp)
        Box(
            Modifier.size(side)
                .alpha(if (ready) 1f else 0.4f)
                .semantics { contentDescription = Strings.arrows }
                .testTag("dpad")
                .pointerInput(Unit) {
                    fun keyAt(p: Offset): Key? {
                        val half = size.width / 2f
                        val dx = p.x - half
                        val dy = p.y - half
                        val r = hypot(dx, dy)
                        return when {
                            r > half -> null
                            r < half * DPAD_INNER -> Key.CENTER
                            abs(dx) > abs(dy) -> if (dx > 0) Key.RIGHT else Key.LEFT
                            else -> if (dy > 0) Key.DOWN else Key.UP
                        }
                    }
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        val key = keyAt(down.position) ?: return@awaitEachGesture
                        down.consume()
                        val downAt = SystemClock.uptimeMillis()
                        fade?.cancel()
                        lit = key
                        scope.launch { glow.snapTo(1f) }
                        var held = false
                        val timer = vm.keyHold.later(scope) {
                            if (key == Key.CENTER) {
                                delay(Gestures.Dpad.CENTRE_HOLD_MS)
                                held = true
                                vm.hold(Key.CENTER, true)
                                vm.keyHold.longStarted(Key.CENTER) { vm.hold(it, false) }
                            } else {
                                delay(Gestures.Dpad.REPEAT_AFTER_MS)
                                held = true
                                vm.repeatStarted()
                                var interval = Gestures.Dpad.REPEAT_START_MS
                                while (true) {
                                    vm.press(key, haptic = false)
                                    delay(interval)
                                    interval = (interval - Gestures.Dpad.REPEAT_STEP_MS).coerceAtLeast(Gestures.Dpad.REPEAT_MIN_MS)
                                }
                            }
                        }
                        waitForUpOrCancellation()
                        timer.cancel()
                        if (!held) {
                            vm.press(key)
                        } else if (key == Key.CENTER) {
                            vm.keyHold.longEnded()
                            vm.hold(Key.CENTER, false)
                        }
                        fade = scope.launch {
                            delay((LIT_MIN_MS - (SystemClock.uptimeMillis() - downAt)).coerceAtLeast(0))
                            glow.animateTo(0f, tween(LIT_FADE_MS))
                            lit = null
                        }
                    }
                },
        ) {
            Canvas(Modifier.fillMaxSize()) {
                val radius = size.minDimension / 2f
                val inner = radius * DPAD_INNER
                val line = 1.5.dp.toPx()
                drawCircle(Color.White.copy(alpha = 0.04f), radius)
                val sector = when (lit) {
                    Key.RIGHT -> -45f
                    Key.DOWN -> 45f
                    Key.LEFT -> 135f
                    Key.UP -> 225f
                    else -> null
                }
                if (sector != null) {
                    // Só o anel: o OK é transparente e não pode acender com a seta.
                    val hole = Path().apply { addOval(Rect(center, inner)) }
                    clipPath(hole, ClipOp.Difference) { drawArc(Color.White.copy(alpha = 0.14f * glow.value), sector, 90f, useCenter = true) }
                }
                for (angle in listOf(45.0, 135.0, 225.0, 315.0)) {
                    val a = Math.toRadians(angle)
                    val dir = Offset(kotlin.math.cos(a).toFloat(), kotlin.math.sin(a).toFloat())
                    drawLine(WHEEL_LINE, center + dir * inner, center + dir * radius, strokeWidth = line)
                }
                drawCircle(Color.White.copy(alpha = 0.05f + if (lit == Key.CENTER) 0.10f * glow.value else 0f), inner)
                drawCircle(WHEEL_LINE, inner, style = Stroke(line))
                drawCircle(WHEEL_LINE, radius - line / 2, style = Stroke(line))
            }
            val edge = side * 0.07f
            val arrow = Modifier.size(34.dp)
            Icon(Icons.Rounded.KeyboardArrowUp, null, tint = Theme.text, modifier = Modifier.align(Alignment.TopCenter).padding(top = edge).then(arrow))
            Icon(Icons.Rounded.KeyboardArrowDown, null, tint = Theme.text, modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = edge).then(arrow))
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowLeft, null, tint = Theme.text, modifier = Modifier.align(Alignment.CenterStart).padding(start = edge).then(arrow))
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = Theme.text, modifier = Modifier.align(Alignment.CenterEnd).padding(end = edge).then(arrow))
            Text("OK", color = Theme.text, fontSize = 19.sp, fontWeight = FontWeight.Bold, modifier = Modifier.align(Alignment.Center))
        }
    }
}

private const val DPAD_INNER = Gestures.Dpad.OK_RADIUS
private const val LIT_MIN_MS = Gestures.Dpad.LIT_MIN_MS
private const val LIT_FADE_MS = Gestures.Dpad.FADE_MS

/** O contorno da roda e as divisões entre as setas. */
private val WHEEL_LINE = Color.White.copy(alpha = 0.16f)

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
