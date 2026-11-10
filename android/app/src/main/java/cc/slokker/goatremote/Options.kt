package cc.slokker.goatremote

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import cc.slokker.goatremote.data.PrefKeys

/** As opções (Mais → Opções), guardadas nas SharedPreferences "options" com os nomes de sempre. */
class Options(private val prefs: SharedPreferences) {
    var haptics by mutableStateOf(prefs.getBoolean(PrefKeys.HAPTICS, true))
        private set
    /** Os botões de volume do telemóvel mexem no volume da TV (com a app aberta). */
    var volumeButtons by mutableStateOf(prefs.getBoolean(PrefKeys.VOLUME_BUTTONS, true))
        private set
    /** Superfície de toque ou setas (D-pad). Quem tinha as "setas nas bordas" ligadas começa nas setas. */
    var layout by mutableStateOf(
        RemoteLayout.saved(prefs.getString(PrefKeys.LAYOUT, null), prefs.getBoolean(PrefKeys.DPAD_TAPS, false)),
    )
        private set

    fun changeHaptics(on: Boolean) { haptics = on; prefs.edit().putBoolean(PrefKeys.HAPTICS, on).apply() }
    fun changeVolumeButtons(on: Boolean) { volumeButtons = on; prefs.edit().putBoolean(PrefKeys.VOLUME_BUTTONS, on).apply() }
    fun changeLayout(new: RemoteLayout) { layout = new; prefs.edit().putString(PrefKeys.LAYOUT, new.name).remove(PrefKeys.DPAD_TAPS).apply() }
}
