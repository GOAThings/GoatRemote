package cc.slokker.goatremote

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import cc.slokker.goatremote.data.ChannelList
import cc.slokker.goatremote.data.NowInfo
import cc.slokker.goatremote.data.SavedTv
import cc.slokker.goatremote.data.TvApp
import cc.slokker.goatremote.tv.Key
import cc.slokker.goatremote.tv.TvControl
import cc.slokker.goatremote.tv.TvState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * Tudo o que é de uma TV: a ligação e o que ela conta, as apps, os canais, o que está a dar, o indicador do volume e
 * as tentativas, e os trabalhos em curso (no [scope]). Mudar de TV, emparelhar ou esquecer cria uma sessão nova e
 * fecha a anterior inteira: nada de uma TV passa para a outra (antes era uma lista de campos a limpar à mão, B2/B3).
 */
class TvSession(
    /** A TV desta sessão (null: não há nenhuma). */
    val tvId: String?,
    recents: List<String>,
    hasChannels: Boolean,
) {
    /** Os trabalhos desta TV: fechar a sessão cancela-os todos. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    var status by mutableStateOf<RemoteViewModel.Status>(if (tvId == null) RemoteViewModel.Status.NoTv else RemoteViewModel.Status.Connecting)
    var state by mutableStateOf(TvState())
    var recentApps by mutableStateOf(recents)
    var installedApps by mutableStateOf<List<TvApp>>(emptyList())
    var hasChannels by mutableStateOf(hasChannels)
    var channels by mutableStateOf<ChannelList?>(null)
    var channelsStatus by mutableStateOf(RemoteViewModel.ChannelsStatus.UNKNOWN)
    var openingGoatTv by mutableStateOf(false)
    var nowInfo by mutableStateOf<NowInfo?>(null)
    var playProblem by mutableStateOf<String?>(null)
    var volumePressed by mutableStateOf<Key?>(null)
    var volumeProblem by mutableStateOf<String?>(null)
    /** Ícones das apps da Apple TV (da App Store, por bundle id). */
    val appleArtwork = mutableStateMapOf<String, String>()

    var link: TvControl? = null
    var stateJob: Job? = null
    var autoReconnect: Job? = null
    var channelsJob: Job? = null
    var playJob: Job? = null
    var lastAutoReconnect = 0L
    /** Recusas seguidas desta TV que ainda não se mostraram. */
    var notPairedRetries = 0
    var volumeSettlesAt = 0L
    /** O GoatTV desta TV não tem o /now (responde 404): até voltar a ligar, não se pergunta. */
    var withoutNow = false

    fun close() {
        scope.cancel()
        link?.close()
        link = null
    }
}
