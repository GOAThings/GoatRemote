package cc.slokker.goatremote.data

import android.content.SharedPreferences

/**
 * O que se sabe do GoatLauncher de cada TV ("launcher.<id>"): true se já respondeu, false se se viu que não há,
 * null enquanto não se sabe. É disto que depende mandar ou não o volume como tecla (ver LauncherVolume.outcome).
 */
class LauncherMemory(private val prefs: SharedPreferences) {
    fun known(tvId: String): Boolean? =
        if (prefs.contains(PrefKeys.launcher(tvId))) prefs.getBoolean(PrefKeys.launcher(tvId), false) else null

    fun set(tvId: String, value: Boolean) = prefs.edit().putBoolean(PrefKeys.launcher(tvId), value).apply()
}
