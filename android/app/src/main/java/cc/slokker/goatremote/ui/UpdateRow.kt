package cc.slokker.goatremote.ui

import android.content.Intent
import android.net.Uri
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
import cc.slokker.goatremote.Strings
import cc.slokker.goatremote.data.AppUpdater
import kotlinx.coroutines.launch

/**
 * A versão instalada. Tocar procura já uma versão nova (e diz o que encontrou); com uma mais recente, tocar instala-a.
 * Se o download falhar, abre-se a página da versão no GitHub.
 */
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
        Modifier.fillMaxWidth().clickable(enabled = !busy) {
            if (version == null) {
                busy = true
                note = Strings.checking
                scope.launch {
                    note = try {
                        val found = AppUpdater.newer()
                        when {
                            found == null -> Strings.youHaveTheLatestVersion
                            // As versões de teste não podem receber o APK publicado: só se diz que há.
                            !AppUpdater.enabled -> L("Version $found is out", "Já saiu a versão $found")
                            else -> {
                                newer = found
                                null
                            }
                        }
                    } catch (e: kotlinx.coroutines.CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        DebugLog.add("Update check failed: $e")
                        Strings.couldntCheckForUpdates
                    }
                    busy = false
                }
                return@clickable
            }
            if (!AppUpdater.canInstall(context)) {
                note = Strings.allowGoatremoteToInstallAppsThen
                AppUpdater.openInstallPermission(context)
                return@clickable
            }
            busy = true
            note = Strings.downloading
            scope.launch {
                runCatching { AppUpdater.install(context) }
                    .onSuccess { note = null }
                    .onFailure {
                        DebugLog.add("Update download failed: $it")
                        note = Strings.couldntDownloadTheUpdate
                        // Como no iPhone: a página da versão, para a descarregar à mão.
                        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(AppUpdater.PAGE))) }
                    }
                busy = false
            }
        }.padding(vertical = 12.dp).testTag("opt:update"),
    ) {
        Text(
            if (version != null) L("Update to $version", "Atualizar para $version") else Strings.version,
            fontSize = 16.sp,
            color = if (version != null) Theme.accent else androidx.compose.ui.graphics.Color.White,
        )
        Text(note ?: BuildConfig.VERSION_NAME, color = Theme.dim, fontSize = 13.sp, modifier = Modifier.testTag("opt:update-note"))
    }
}
