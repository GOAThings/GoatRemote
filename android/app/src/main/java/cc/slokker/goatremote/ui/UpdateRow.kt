package cc.slokker.goatremote.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cc.slokker.goatremote.BuildConfig
import cc.slokker.goatremote.DebugLog
import cc.slokker.goatremote.L
import cc.slokker.goatremote.data.AppUpdater
import kotlinx.coroutines.launch

/** A versão instalada e, se houver outra mais recente, tocar para a instalar. */
@Composable
fun UpdateRow() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var newer by remember { mutableStateOf<String?>(null) }
    var note by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (AppUpdater.enabled) newer = runCatching { AppUpdater.newer() }.getOrNull()
    }
    val version = newer
    Column(
        Modifier.fillMaxWidth().clickable(enabled = version != null && !busy) {
            if (!AppUpdater.canInstall(context)) {
                note = L("Allow GoatRemote to install apps, then tap again", "Autoriza o GoatRemote a instalar apps e toca outra vez")
                AppUpdater.openInstallPermission(context)
                return@clickable
            }
            busy = true
            note = L("Downloading…", "A descarregar…")
            scope.launch {
                runCatching { AppUpdater.install(context) }
                    .onSuccess { note = null }
                    .onFailure {
                        DebugLog.add("Update download failed: $it")
                        note = L("Couldn't download the update", "Não foi possível descarregar a atualização")
                    }
                busy = false
            }
        }.padding(vertical = 12.dp).testTag("opt:update"),
    ) {
        Text(
            if (version != null) L("Update to $version", "Atualizar para $version") else L("Version", "Versão"),
            fontSize = 16.sp,
            color = if (version != null) Theme.accent else androidx.compose.ui.graphics.Color.White,
        )
        Text(note ?: BuildConfig.VERSION_NAME, color = Theme.dim, fontSize = 13.sp)
    }
}
