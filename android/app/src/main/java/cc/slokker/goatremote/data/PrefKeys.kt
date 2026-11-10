package cc.slokker.goatremote.data

/**
 * Os nomes de tudo o que fica guardado (contracts/persisted/options-keys.json). Quem já tem a app guarda isto: um nome
 * que mude é uma opção, uma TV ou um emparelhamento que se perde.
 */
object PrefKeys {
    /** As SharedPreferences das TVs (ver [TvStore]). */
    const val TVS_PREFS = "tvs"
    const val TVS = "tvs"
    const val CURRENT = "current"

    /** As SharedPreferences das opções e do que se sabe de cada TV. */
    const val OPTIONS_PREFS = "options"
    const val HAPTICS = "haptics"
    const val VOLUME_BUTTONS = "volumeButtons"
    const val LAYOUT = "layout"
    /** As "setas nas bordas" de antes: só se lê sem [LAYOUT], e sai na próxima mudança. */
    const val DPAD_TAPS = "dpadTaps"
    /** O _i estável que a Apple TV vê. */
    const val COMPANION_ID = "companion.id"

    /** As SharedPreferences das credenciais da Apple TV (uma chave por TV, o id dela). */
    const val COMPANION_PREFS = "companion"
    /** As mesmas credenciais, cifradas com uma chave do Android Keystore (ver CompanionStore); as de cima migram para aqui. */
    const val COMPANION_KEYSTORE_PREFS = "companion.keystore"

    const val RECENTS = "recents"
    const val LAUNCHER = "launcher"
    const val VOLUME_UNKNOWN = "volumeUnknown"
    const val GOATTV = "goattv"

    /** O que é de uma TV guarda-se como "<prefixo>.<id da TV>"; esquecê-la apaga todos. */
    val PER_TV = listOf(RECENTS, LAUNCHER, VOLUME_UNKNOWN, GOATTV)

    fun perTv(prefix: String, tvId: String) = "$prefix.$tvId"
    fun recents(tvId: String) = perTv(RECENTS, tvId)
    fun launcher(tvId: String) = perTv(LAUNCHER, tvId)
    fun volumeUnknown(tvId: String) = perTv(VOLUME_UNKNOWN, tvId)
    fun goatTv(tvId: String) = perTv(GOATTV, tvId)

    /** Todas as chaves de uma TV (para a esquecer). */
    fun perTvKeys(tvId: String) = PER_TV.map { perTv(it, tvId) }
}
