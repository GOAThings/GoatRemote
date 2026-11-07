package cc.slokker.goatremote.ui

import android.content.Intent
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import cc.slokker.goatremote.DebugLog
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Apps
import androidx.compose.material.icons.rounded.BugReport
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ClosedCaption
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Input
import androidx.compose.material.icons.rounded.KeyboardDoubleArrowDown
import androidx.compose.material.icons.rounded.KeyboardDoubleArrowUp
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.ListAlt
import androidx.compose.material.icons.rounded.LiveTv
import androidx.compose.material.icons.rounded.Menu
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material.icons.rounded.Tv
import androidx.compose.material.icons.rounded.VolumeDown
import androidx.compose.material.icons.rounded.VolumeUp
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cc.slokker.goatremote.L
import cc.slokker.goatremote.RemoteViewModel
import cc.slokker.goatremote.data.AppCatalog
import cc.slokker.goatremote.data.FoundTv
import cc.slokker.goatremote.data.GoatTvChannels
import cc.slokker.goatremote.data.TvChannel
import cc.slokker.goatremote.data.SavedTv
import cc.slokker.goatremote.data.TvApp
import cc.slokker.goatremote.data.TvKind
import cc.slokker.goatremote.tv.Key

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GoatSheet(onDismiss: () -> Unit, skipPartial: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = skipPartial),
        containerColor = Theme.surface,
        contentColor = Color.White,
        content = content,
    )
}

@Composable
private fun SheetTitle(title: String) {
    Text(title, fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 10.dp))
}

@Composable
private fun Section(title: String) {
    Text(title.uppercase(), color = Theme.faint, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.7.sp,
        modifier = Modifier.padding(start = 2.dp, top = 14.dp, bottom = 6.dp))
}

/** O logótipo de um canal do GoatTV (vem da TV), ou um símbolo enquanto não vem. */
@Composable
internal fun ChannelLogo(vm: RemoteViewModel, channel: TvChannel, width: Dp, height: Dp, background: Color = Theme.surfaceHigh) {
    val logo = rememberImage(vm.channelLogoUrl(channel), GoatTvChannels.MAX_LOGO_BYTES, GoatTvChannels.LOGO_SIDE)
    Box(Modifier.size(width, height).clip(RoundedCornerShape(9.dp)).background(background), contentAlignment = Alignment.Center) {
        if (logo != null) {
            Image(logo, null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize().padding(4.dp).testTag("logo"))
        } else {
            Icon(Icons.Rounded.LiveTv, null, tint = Theme.dim, modifier = Modifier.size(20.dp))
        }
    }
}

/** Um símbolo num quadrado com a cor dele, como nas Definições do GoatTV. */
@Composable
private fun IconTile(icon: ImageVector, tint: Color) {
    Box(Modifier.size(38.dp).clip(RoundedCornerShape(10.dp)).background(tint.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(20.dp))
    }
}

private fun tvIcon(kind: TvKind) = if (kind == TvKind.APPLE) Icons.Rounded.LiveTv else Icons.Rounded.Tv

/** Escrever no campo de texto aberto na TV (aparece sozinho quando a TV abre um). */
@Composable
fun KeyboardSheet(vm: RemoteViewModel, onDismiss: () -> Unit) {
    var text by remember { mutableStateOf(vm.state.textValue) }
    val focus = remember { FocusRequester() }
    fun send() {
        vm.press(Key.ENTER)
        onDismiss()
    }
    GoatSheet(onDismiss, skipPartial = true) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 24.dp)) {
            Text(vm.state.textLabel ?: L("Type on the TV", "Escrever na TV"), fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(14.dp))
            OutlinedTextField(
                value = text,
                onValueChange = {
                    text = it
                    vm.type(it)
                },
                placeholder = { Text(L("Search, password…", "Pesquisa, palavra-passe…")) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { send() }),
                shape = RoundedCornerShape(14.dp),
                colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Theme.accent, unfocusedBorderColor = Theme.faint),
                modifier = Modifier.fillMaxWidth().focusRequester(focus).testTag("keyboard-field"),
            )
            Spacer(Modifier.height(14.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = {
                    text = ""
                    vm.type("")
                }, enabled = text.isNotEmpty()) { Text(L("Clear", "Limpar")) }
                Spacer(Modifier.weight(1f))
                Button(onClick = ::send, colors = ButtonDefaults.buttonColors(containerColor = Theme.accent), modifier = Modifier.testTag("send-text")) {
                    Text(L("Send", "Enviar"))
                }
            }
        }
    }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
}

/**
 * Abrir apps. Com o GoatLauncher na TV: as instaladas, com os banners dela. Sem ele, só as que já se viu abertas
 * nesta TV (nunca uma lista inventada de apps que a TV pode não ter).
 */
@Composable
fun AppsSheet(vm: RemoteViewModel, onDismiss: () -> Unit) {
    LaunchedEffect(Unit) { vm.refreshApps() }
    GoatSheet(onDismiss) {
        SheetTitle("Apps")
        LazyVerticalGrid(
            modifier = Modifier.testTag("apps-grid"),
            columns = GridCells.Fixed(2),
            contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val full = GridItemSpan(2)
            if (vm.installedApps.isEmpty()) {
                if (vm.recentApps.isNotEmpty()) {
                    item(span = { full }) { Section(L("Opened on this TV", "Abertas nesta TV")) }
                    items(vm.recentApps) { pkg ->
                        val known = AppCatalog.app(pkg)
                        AppTile(vm, TvApp(pkg, AppCatalog.name(pkg), color = known?.let { "#%06X".format(it.color) }), remoteImage = false, onDismiss)
                    }
                }
                item(span = { full }) {
                    Column(Modifier.padding(top = 4.dp).fillMaxWidth().card(RoundedCornerShape(18.dp)).padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.Apps, null, tint = Color.White, modifier = Modifier.size(20.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(L("All the TV's apps here", "Todas as apps da TV aqui"), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                        }
                        Spacer(Modifier.height(8.dp))
                        Text(
                            if (vm.recentApps.isEmpty()) {
                                L("Android TVs don't share their app list with the remote. Apps show up here as you open them on the TV, or all of them, with their banners, if the TV has GoatLauncher.",
                                    "As Android TV não dão a lista de apps ao comando. As apps vão aparecendo aqui à medida que as abres na TV, ou todas, com os banners, se a TV tiver o GoatLauncher.")
                            } else {
                                L("With GoatLauncher on the TV, all its apps show up here, with their banners.",
                                    "Com o GoatLauncher na TV, aparecem aqui todas as apps dela, com os banners.")
                            },
                            color = Theme.dim, fontSize = 13.sp,
                        )
                    }
                }
            } else {
                val byPackage = vm.installedApps.associateBy { it.pkg }
                val recent = vm.recentApps.mapNotNull { byPackage[it] }.take(4)
                if (recent.isNotEmpty()) {
                    item(span = { full }) { Section(L("Recently opened", "Abertas há pouco")) }
                    items(recent, key = { "r:" + it.pkg }) { AppTile(vm, it, true, onDismiss) }
                    item(span = { full }) { Section(L("All apps", "Todas as apps")) }
                }
                items(vm.installedApps, key = { it.pkg }) { AppTile(vm, it, true, onDismiss) }
            }
        }
    }
}

@Composable
private fun AppTile(vm: RemoteViewModel, app: TvApp, remoteImage: Boolean, onDismiss: () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    val tint = app.tint?.let(::hexColor) ?: Theme.surfaceHigh
    val image = rememberImage(if (remoteImage) vm.iconUrl(app.pkg) else null)
    Box(
        Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(shape)
            .background(Brush.linearGradient(listOf(tint, tint.copy(alpha = 0.6f))))
            .clickable {
                vm.launch(app)
                onDismiss()
            }
            .semantics { contentDescription = app.label }
            .testTag("app:" + app.label),
        contentAlignment = Alignment.Center,
    ) {
        when {
            image != null && app.banner -> Image(image, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().testTag("image"))
            image != null -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Image(image, null, modifier = Modifier.size(46.dp).clip(RoundedCornerShape(10.dp)).testTag("image"))
                Spacer(Modifier.height(6.dp))
                Text(app.label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(horizontal = 8.dp))
            }
            else -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Rounded.Apps, null, tint = Color.White, modifier = Modifier.size(26.dp))
                Spacer(Modifier.height(6.dp))
                Text(app.label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(horizontal = 8.dp))
            }
        }
    }
}

/**
 * Os canais do GoatTV: o que está a dar, os favoritos, a pesquisa e os grupos, e a lista. Tocar muda de canal e a folha
 * fica aberta, para fazer zapping.
 */
@Composable
fun ChannelsSheet(vm: RemoteViewModel, onDismiss: () -> Unit) {
    LaunchedEffect(Unit) { vm.refreshChannels() }
    var query by remember { mutableStateOf("") }
    var group by remember { mutableStateOf<String?>(null) }
    val list = vm.channels
    val shown by remember(list) {
        derivedStateOf {
            val q = query.trim()
            list?.channels.orEmpty().filter { ch ->
                (group == null || ch.group == group) &&
                    (q.isEmpty() || ch.name.contains(q, ignoreCase = true) || ch.num?.toString()?.startsWith(q) == true)
            }
        }
    }
    GoatSheet(onDismiss, skipPartial = true) {
        SheetTitle(L("Channels", "Canais"))
        LazyColumn(
            modifier = Modifier.testTag("channels-list"),
            contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            vm.playProblem?.let { problem ->
                item(key = "problem") {
                    Text(problem, color = Theme.orange, fontSize = 13.sp, modifier = Modifier.padding(bottom = 6.dp).testTag("channels-problem"))
                }
            }
            if (list == null) {
                item(key = "state") { ChannelsState(vm) }
                return@LazyColumn
            }
            val current = list.channels.firstOrNull { it.key == list.current }
            if (current != null) item(key = "c:" + current.key) { NowPlayingRow(vm, current) }
            val groupNames = list.groups.associate { it.id to it.name }
            val favorites = list.channels.filter { it.favorite }
            if (favorites.isNotEmpty()) {
                item(key = "s:fav") { Section(L("Favourites", "Favoritos")) }
                items(favorites, key = { "f:" + it.key }) { ChannelRow(vm, it, it.key == list.current, groupNames[it.group]) }
            }
            item(key = "search") {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it.take(100) },
                    placeholder = { Text(L("Search channels", "Procurar canais")) },
                    leadingIcon = { Icon(Icons.Rounded.Search, null, tint = Theme.dim) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Search),
                    shape = RoundedCornerShape(14.dp),
                    colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Theme.accent, unfocusedBorderColor = Theme.faint),
                    modifier = Modifier.fillMaxWidth().padding(top = 10.dp).testTag("channels-search"),
                )
            }
            if (list.groups.isNotEmpty()) {
                item(key = "groups") {
                    LazyRow(Modifier.padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        item { GroupChip(L("All", "Todos"), group == null, "group:*") { group = null } }
                        items(list.groups, key = { it.id }) { g -> GroupChip(g.name, group == g.id, "group:" + g.name) { group = g.id } }
                    }
                }
            }
            if (shown.isEmpty()) {
                item(key = "empty") {
                    Text(
                        if (list.channels.isEmpty()) L("There are no channels in GoatTV's list", "A lista do GoatTV não tem canais")
                        else L("No channels found", "Nenhum canal encontrado"),
                        color = Theme.dim, fontSize = 14.sp, modifier = Modifier.padding(vertical = 12.dp),
                    )
                }
            }
            items(shown, key = { "l:" + it.key }) { ChannelRow(vm, it, it.key == list.current, groupNames[it.group]) }
            if (list.truncated) {
                item(key = "truncated") {
                    Text(L("The list is too long: only part of it is shown here.", "A lista é longa demais: aqui só aparece uma parte."),
                        color = Theme.dim, fontSize = 12.sp, modifier = Modifier.padding(vertical = 8.dp))
                }
            }
        }
    }
}

/** Sem lista: a carregar, o GoatTV fechado (com "Abrir o GoatTV" se der para o abrir daqui) ou uma falha. */
@Composable
private fun ChannelsState(vm: RemoteViewModel) {
    Column(Modifier.fillMaxWidth().card(RoundedCornerShape(18.dp)).padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        when {
            vm.openingGoatTv || vm.channelsStatus == RemoteViewModel.ChannelsStatus.UNKNOWN ->
                CircularProgressIndicator(color = Theme.dim, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
            vm.channelsStatus == RemoteViewModel.ChannelsStatus.CLOSED -> {
                val app = vm.goatTvApp
                if (app != null) {
                    Text(L("GoatTV isn't open on the TV.", "O GoatTV não está aberto na TV."), color = Theme.dim, fontSize = 14.sp)
                    Spacer(Modifier.height(10.dp))
                    Button(onClick = vm::openGoatTv, colors = ButtonDefaults.buttonColors(containerColor = Theme.accent),
                        modifier = Modifier.testTag("open-goattv")) {
                        Text(L("Open GoatTV", "Abrir o GoatTV"))
                    }
                } else {
                    Text(vm.goatTvClosedLine(), color = Theme.dim, fontSize = 14.sp, modifier = Modifier.testTag("goattv-closed"))
                }
            }
            else -> {
                Text(L("Couldn't get the channels from GoatTV.", "Não deu para ter os canais do GoatTV."), color = Theme.dim, fontSize = 14.sp)
                TextButton(onClick = vm::refreshChannels) { Text(L("Try again", "Tentar outra vez")) }
            }
        }
    }
}

@Composable
private fun GroupChip(title: String, selected: Boolean, tag: String, onClick: () -> Unit) {
    val shape = RoundedCornerShape(50)
    Box(
        Modifier.clip(shape)
            .background(if (selected) Color.White else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 7.dp)
            .testTag(tag),
    ) {
        Text(title, color = if (selected) Color.Black else Theme.faint, fontSize = 14.sp, fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** O canal que está a dar, em cartão no topo da lista. */
@Composable
private fun NowPlayingRow(vm: RemoteViewModel, channel: TvChannel) {
    Row(
        Modifier.fillMaxWidth().padding(bottom = 4.dp).hero(RoundedCornerShape(18.dp))
            .clickable { vm.play(channel) }
            .padding(12.dp)
            .semantics { contentDescription = channel.name }
            .testTag("channel:" + channel.name),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ChannelLogo(vm, channel, 56.dp, 38.dp, Color.Black.copy(alpha = 0.35f))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text((L("Now playing", "A dar agora") + (channel.num?.let { " · $it" } ?: "")).uppercase(), color = Theme.faint, fontSize = 11.sp,
                fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp, maxLines = 1)
            Text(channel.name, fontSize = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Icon(Icons.Rounded.PlayArrow, null, tint = Theme.accent, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun ChannelRow(vm: RemoteViewModel, channel: TvChannel, current: Boolean, group: String?) {
    val shape = RoundedCornerShape(12.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape)
            .background(if (current) Theme.accent.copy(alpha = 0.13f) else Color.Transparent)
            .clickable { vm.play(channel) }
            .padding(horizontal = 8.dp, vertical = 7.dp)
            .semantics { contentDescription = channel.name }
            .testTag("channel:" + channel.name),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(channel.num?.toString() ?: "", color = Theme.faint, fontSize = 13.sp, maxLines = 1, modifier = Modifier.width(40.dp))
        ChannelLogo(vm, channel, 52.dp, 36.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(channel.name, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                color = if (current) Theme.accent else Theme.text)
            if (group != null) Text(group, color = Theme.faint, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (current) Icon(Icons.Rounded.PlayArrow, null, tint = Theme.accent, modifier = Modifier.size(20.dp))
        else if (channel.favorite) Icon(Icons.Rounded.Star, null, tint = Color(0xFFF5C04A), modifier = Modifier.size(18.dp))
    }
}

/** As teclas que não cabem no comando, os números e as opções. */
@Composable
fun MoreSheet(vm: RemoteViewModel, onDismiss: () -> Unit) {
    var diagnostics by remember { mutableStateOf(false) }
    if (diagnostics) DiagnosticsSheet { diagnostics = false }
    GoatSheet(onDismiss) {
        SheetTitle(L("More", "Mais"))
        LazyVerticalGrid(
            modifier = Modifier.testTag("more-grid"),
            columns = GridCells.Fixed(20),
            contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            val keys = listOf(
                Triple(Key.VOLUME_DOWN, Icons.Rounded.VolumeDown, L("Vol −", "Vol −")),
                Triple(Key.VOLUME_UP, Icons.Rounded.VolumeUp, L("Vol +", "Vol +")),
                Triple(Key.CHANNEL_DOWN, Icons.Rounded.KeyboardDoubleArrowDown, L("Ch −", "Can −")),
                Triple(Key.CHANNEL_UP, Icons.Rounded.KeyboardDoubleArrowUp, L("Ch +", "Can +")),
                Triple(Key.SEARCH, Icons.Rounded.Search, L("Search", "Pesquisa")),
                Triple(Key.MENU, Icons.Rounded.Menu, "Menu"),
                Triple(Key.GUIDE, Icons.Rounded.ListAlt, L("Guide", "Guia")),
                Triple(Key.INFO, Icons.Rounded.Info, "Info"),
                Triple(Key.CAPTIONS, Icons.Rounded.ClosedCaption, L("Subtitles", "Legendas")),
                Triple(Key.AUDIO_TRACK, Icons.Rounded.GraphicEq, L("Audio", "Áudio")),
                Triple(Key.LAST_CHANNEL, Icons.Rounded.History, L("Last ch", "Último can")),
                Triple(Key.INPUT, Icons.Rounded.Input, L("Input", "Entrada")),
                Triple(Key.SETTINGS, Icons.Rounded.Settings, L("Settings", "Definições")),
                Triple(Key.STOP, Icons.Rounded.Stop, "Stop"),
                Triple(Key.PREVIOUS, Icons.Rounded.SkipPrevious, L("Previous", "Anterior")),
                Triple(Key.NEXT, Icons.Rounded.SkipNext, L("Next", "Seguinte")),
            )
            items(keys, span = { GridItemSpan(5) }) { (key, icon, title) -> MoreKey(vm, key, icon, title) }
            item(span = { GridItemSpan(20) }) { Section(L("Numbers", "Números")) }
            items((1..10).map { it % 10 }, span = { GridItemSpan(4) }) { digit -> DigitKey(vm, digit) }
            item(span = { GridItemSpan(20) }) { Section(L("Options", "Opções")) }
            item(span = { GridItemSpan(20) }) {
                Column(Modifier.fillMaxWidth().card(RoundedCornerShape(16.dp)).padding(horizontal = 16.dp)) {
                    Option(L("Vibration", "Vibração"), null, vm.haptics, vm::changeHaptics)
                    HorizontalDivider(color = Theme.line)
                    Option(L("Phone volume buttons", "Botões de volume do telemóvel"),
                        L("Change the TV's volume while the app is open", "Mexem no volume da TV com a app aberta"),
                        vm.volumeButtons, vm::changeVolumeButtons)
                    HorizontalDivider(color = Theme.line)
                    UpdateRow()
                    HorizontalDivider(color = Theme.line)
                    Row(Modifier.fillMaxWidth().clickable { diagnostics = true }.padding(vertical = 12.dp).testTag("opt:diagnostics"),
                        verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(L("Diagnostics", "Diagnóstico"), fontSize = 16.sp)
                            Text(L("What the app did, to send when something fails", "O que a app fez, para mandar quando algo falha"),
                                color = Theme.dim, fontSize = 13.sp)
                        }
                        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = Theme.dim)
                    }
                }
            }
        }
    }
}

/** O registo de diagnóstico (DebugLog): enviar para o site, ver, copiar, partilhar ou limpar. */
@Composable
fun DiagnosticsSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf(DebugLog.text) }
    var message by remember { mutableStateOf("") }
    var contact by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }
    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedBorderColor = Theme.accent, unfocusedBorderColor = Theme.faint, cursorColor = Theme.accent,
        focusedTextColor = Color.White, unfocusedTextColor = Color.White,
    )
    GoatSheet(onDismiss, skipPartial = true) {
        SheetTitle(L("Diagnostics", "Diagnóstico"))
        Column(Modifier.padding(horizontal = 18.dp).padding(bottom = 24.dp).verticalScroll(rememberScrollState())) {
            OutlinedTextField(
                message, { message = it.take(2000) },
                placeholder = { Text(L("What happened?", "O que aconteceu?"), color = Theme.dim) },
                minLines = 2, maxLines = 5, colors = fieldColors,
                modifier = Modifier.fillMaxWidth().testTag("diagnostics:message"),
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                contact, { contact = it.take(200) },
                placeholder = { Text(L("How can we reach you? (optional)", "Como te contactamos? (opcional)"), color = Theme.dim) },
                singleLine = true, colors = fieldColors,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = {
                    sending = true
                    scope.launch {
                        result = try {
                            val id = DebugLog.send(message, contact)
                            message = ""
                            L("Sent. Report $id.", "Enviado. Relatório $id.")
                        } catch (e: DebugLog.TooManyReports) {
                            L("Too many reports from this network. Try again later, or use Share.",
                                "Demasiados relatórios desta rede. Tenta mais tarde, ou usa Partilhar.")
                        } catch (e: DebugLog.ReportFailed) {
                            L("Couldn't send (HTTP ${e.status}). Use Share instead.", "Não deu para enviar (HTTP ${e.status}). Usa Partilhar.")
                        } catch (e: java.net.UnknownHostException) {
                            // O DNS da rede (filtro no router ou no fornecedor) pode não encontrar o servidor.
                            L("This network can't find the GOAT server (its DNS may be blocking it). Try again on mobile data, or use Share.",
                                "Esta rede não encontra o servidor GOAT (o DNS dela pode estar a bloqueá-lo). Tenta com os dados móveis, ou usa Partilhar.")
                        } catch (e: kotlinx.coroutines.CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            L("Couldn't send: ${e.message}", "Não deu para enviar: ${e.message}")
                        }
                        text = DebugLog.text
                        sending = false
                    }
                },
                enabled = !sending,
                colors = ButtonDefaults.buttonColors(containerColor = Theme.accent, contentColor = Color.White),
                modifier = Modifier.fillMaxWidth().height(48.dp).testTag("diagnostics:send"),
            ) {
                if (sending) CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                else Text(L("Send report", "Enviar relatório"), fontWeight = FontWeight.SemiBold)
            }
            result?.let { Text(it, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp).testTag("diagnostics:result")) }
            Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton({
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_SUBJECT, "GoatRemote diagnostics")
                        .putExtra(Intent.EXTRA_TEXT, text)
                    context.startActivity(Intent.createChooser(send, null))
                }, Modifier.testTag("diagnostics:share")) { Text(L("Share", "Partilhar"), color = Color.White) }
                TextButton({ clipboard.setText(AnnotatedString(text)) }) { Text(L("Copy", "Copiar"), color = Color.White) }
                TextButton({ DebugLog.clear(); text = DebugLog.text }) { Text(L("Clear", "Limpar"), color = Theme.dim) }
            }
            Text(L("Never includes PINs, codes or keys. Nothing is sent until you send or share it.",
                "Nunca tem PINs, códigos nem chaves. Nada sai do telemóvel até o enviares ou partilhares."), color = Theme.dim, fontSize = 13.sp)
            Spacer(Modifier.height(12.dp))
            SelectionContainer(Modifier.fillMaxWidth()) {
                Text(text, fontFamily = FontFamily.Monospace, fontSize = 11.sp, lineHeight = 15.sp, modifier = Modifier.testTag("diagnostics:text"))
            }
        }
    }
}

@Composable
private fun MoreKey(vm: RemoteViewModel, key: Key, icon: ImageVector, title: String) {
    var pressed by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxWidth().heightIn(min = 72.dp).card(RoundedCornerShape(16.dp), pressed)
            .pressable({ vm.press(key) }, { vm.hold(key, it) }) { pressed = it }
            .padding(vertical = 12.dp)
            .semantics { contentDescription = title }
            .testTag("key:" + key.name),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(icon, null, tint = Theme.text, modifier = Modifier.size(22.dp))
        Spacer(Modifier.height(7.dp))
        Text(title, color = Theme.dim, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun DigitKey(vm: RemoteViewModel, digit: Int) {
    var pressed by remember { mutableStateOf(false) }
    Box(
        Modifier.fillMaxWidth().height(50.dp).card(RoundedCornerShape(14.dp), pressed)
            .pressable({ vm.press(Key.digit(digit)) }) { pressed = it },
        contentAlignment = Alignment.Center,
    ) { Text("$digit", fontSize = 20.sp, fontWeight = FontWeight.SemiBold) }
}

@Composable
private fun Option(title: String, detail: String?, value: Boolean, onChange: (Boolean) -> Unit, tag: String = title) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!value) }.padding(vertical = 12.dp).testTag(tag), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 16.sp)
            if (detail != null) Text(detail, color = Theme.dim, fontSize = 13.sp)
        }
        Switch(value, onChange, colors = SwitchDefaults.colors(checkedTrackColor = Theme.accent))
    }
}

/** As TVs: escolher, juntar, emparelhar outra vez e esquecer. */
@Composable
fun TvsSheet(vm: RemoteViewModel, onAdd: () -> Unit, onDismiss: () -> Unit) {
    val found by vm.finder.found.collectAsState()
    DisposableEffect(Unit) {
        vm.finder.start()
        onDispose { vm.finder.stop() }
    }
    GoatSheet(onDismiss) {
        SheetTitle(L("TVs", "TVs"))
        LazyColumn(contentPadding = PaddingValues(start = 14.dp, end = 14.dp, bottom = 24.dp)) {
            item {
                CardColumn {
                    vm.tvs.forEachIndexed { i, tv ->
                        if (i > 0) RowDivider()
                        SavedTvRow(vm, tv, onDismiss)
                    }
                }
            }
            item {
                Text(L("Tap the bin to forget a TV.", "Toca no caixote para esquecer uma TV."), color = Theme.faint, fontSize = 12.sp,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp))
            }
            val unpaired = found.filter { f -> vm.tvs.none { it.id == f.id } }
            if (unpaired.isNotEmpty()) {
                item { Section(L("On this network", "Nesta rede")) }
                item {
                    CardColumn {
                        unpaired.forEachIndexed { i, tv ->
                            if (i > 0) RowDivider()
                            FoundTvRow(vm, tv)
                        }
                    }
                }
            }
            item { Spacer(Modifier.height(14.dp)) }
            item {
                CardColumn {
                    ActionRow(Icons.Rounded.Add, L("Add a TV", "Juntar uma TV"), onAdd)
                    if (vm.current != null) {
                        RowDivider()
                        ActionRow(Icons.Rounded.Link, L("Pair this TV again", "Emparelhar esta TV outra vez")) { vm.repairCurrent() }
                    }
                }
            }
        }
    }
}

@Composable
private fun CardColumn(content: @Composable ColumnScope.() -> Unit) =
    Column(Modifier.fillMaxWidth().card(RoundedCornerShape(16.dp)), content = content)

@Composable
private fun RowDivider() = HorizontalDivider(color = Theme.line, modifier = Modifier.padding(start = 64.dp))

@Composable
private fun SavedTvRow(vm: RemoteViewModel, tv: SavedTv, onDismiss: () -> Unit) {
    val selected = tv.id == vm.current?.id
    Row(
        Modifier.fillMaxWidth().clickable {
            vm.select(tv)
            onDismiss()
        }.padding(start = 14.dp, top = 11.dp, bottom = 11.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconTile(tvIcon(tv.kind), if (selected) Theme.green else Theme.accent)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(tv.name, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle(vm, tv), color = Theme.faint, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (selected) Icon(Icons.Rounded.Check, null, tint = Theme.accent)
        IconButton(onClick = { vm.forget(tv) }) { Icon(Icons.Rounded.Delete, L("Forget", "Esquecer"), tint = Theme.faint) }
    }
}

private fun subtitle(vm: RemoteViewModel, tv: SavedTv): String {
    if (tv.id != vm.current?.id) return tv.host
    val parts = mutableListOf(tv.host)
    val vendor = vm.state.vendor
    val model = vm.state.model
    if (vendor != null && model != null) parts.add("$vendor $model")
    when (vm.status) {
        RemoteViewModel.Status.Connected -> parts.add(L("connected", "ligada"))
        RemoteViewModel.Status.Connecting -> parts.add(L("connecting", "a ligar"))
        else -> Unit
    }
    return parts.joinToString(" · ")
}

@Composable
private fun ActionRow(icon: ImageVector, title: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
        IconTile(icon, Theme.accent)
        Spacer(Modifier.width(12.dp))
        Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = Theme.faint)
    }
}

/** Uma TV encontrada na rede e ainda por emparelhar: tocar emparelha. */
@Composable
private fun FoundTvRow(vm: RemoteViewModel, found: FoundTv) {
    Row(
        Modifier.fillMaxWidth().clickable { vm.startPairing(found) }.padding(horizontal = 14.dp, vertical = 11.dp)
            .testTag("found:" + found.name),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconTile(tvIcon(found.kind), Theme.accent2)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(found.name, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(if (found.kind == TvKind.APPLE) "Apple TV" else "Android TV · Google TV", color = Theme.faint, fontSize = 13.sp)
        }
        Text(L("Pair", "Emparelhar"), color = Color.Black, fontSize = 14.sp, fontWeight = FontWeight.Bold,
            modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.White).padding(horizontal = 14.dp, vertical = 7.dp))
    }
}

/** Juntar uma TV, numa folha por cima do comando. */
@Composable
fun AddTvSheet(vm: RemoteViewModel, onDismiss: () -> Unit) {
    GoatSheet(onDismiss) {
        SheetTitle(L("Add a TV", "Juntar uma TV"))
        AddTvList(vm, Modifier)
    }
}

/** O ecrã inicial sem TVs: juntar a primeira. */
@Composable
fun AddTvScreen(vm: RemoteViewModel) {
    var diagnostics by remember { mutableStateOf(false) }
    if (diagnostics) DiagnosticsSheet { diagnostics = false }
    Column(Modifier.fillMaxSize().padding(top = 24.dp)) {
        Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(L("Add a TV", "Juntar uma TV"), fontSize = 30.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.weight(1f))
            // Antes de haver uma TV não há o Mais: o diagnóstico fica aqui também.
            IconButton({ diagnostics = true }, Modifier.testTag("add:diagnostics")) {
                Icon(Icons.Rounded.BugReport, L("Diagnostics", "Diagnóstico"), tint = Theme.dim)
            }
        }
        Spacer(Modifier.height(12.dp))
        AddTvList(vm, Modifier.weight(1f))
    }
}

/** Escolher uma TV para emparelhar: as que se anunciam na rede, ou um IP escrito à mão. */
@Composable
private fun AddTvList(vm: RemoteViewModel, modifier: Modifier) {
    val found by vm.finder.found.collectAsState()
    var manualIp by remember { mutableStateOf("") }
    DisposableEffect(Unit) {
        vm.finder.start()
        onDispose { vm.finder.stop() }
    }
    LazyColumn(modifier, contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 24.dp)) {
        item { Section(L("On this network", "Nesta rede")) }
        if (found.isEmpty()) {
            item {
                Row(Modifier.padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(color = Theme.dim, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(L("Looking for TVs on this network…", "À procura de TVs nesta rede…"), color = Theme.dim)
                }
            }
        }
        if (found.isNotEmpty()) {
            item {
                CardColumn {
                    found.forEachIndexed { i, tv ->
                        if (i > 0) RowDivider()
                        if (vm.tvs.any { it.id == tv.id }) {
                            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
                                IconTile(tvIcon(tv.kind), Theme.green)
                                Spacer(Modifier.width(12.dp))
                                Text(tv.name, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                                Text(L("Paired", "Emparelhada"), color = Theme.faint, fontSize = 13.sp)
                            }
                        } else {
                            FoundTvRow(vm, tv)
                        }
                    }
                }
            }
        }
        item {
            Text(
                L("Android TV, Google TV (SHIELD, Sony, Philips, TCL, Chromecast…) and Apple TV. The TV and the phone must be on the same Wi-Fi.",
                    "Android TV, Google TV (SHIELD, Sony, Philips, TCL, Chromecast…) e Apple TV. A TV e o telemóvel têm de estar na mesma rede Wi-Fi."),
                color = Theme.dim, fontSize = 12.sp, modifier = Modifier.padding(vertical = 8.dp),
            )
        }
        item { Section(L("Or by IP address", "Ou pelo endereço IP")) }
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = manualIp,
                    onValueChange = { manualIp = it },
                    placeholder = { Text("192.168.1.50") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, autoCorrectEnabled = false),
                    shape = RoundedCornerShape(14.dp),
                    colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Theme.accent, unfocusedBorderColor = Theme.faint),
                    modifier = Modifier.weight(1f).testTag("manual-ip"),
                )
                Spacer(Modifier.width(10.dp))
                val ip = manualIp.trim()
                TextButton(onClick = { vm.startPairing(ip, ip, ip) }, enabled = ip.isNotEmpty(), modifier = Modifier.testTag("pair-ip")) {
                    Text(L("Pair", "Emparelhar"))
                }
            }
        }
    }
}
