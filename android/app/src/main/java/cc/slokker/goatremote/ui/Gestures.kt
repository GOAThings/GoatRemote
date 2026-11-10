package cc.slokker.goatremote.ui

/**
 * O "tato" do comando: os mesmos números no iPhone (RemoteCore Gestures), conferidos por contracts/gestures.json.
 * Tempos em ms, distâncias em dp.
 */
object Gestures {
    /** Superfície de toque: um passo por cada bocado de dedo; manter parado é OK longo; o dedo parado repete. */
    object Touch {
        const val STEP_DP = 44
        const val HOLD_MS = 500L
        const val REPEAT_AFTER_MS = 350L
        const val REPEAT_START_MS = 220L
        const val REPEAT_MIN_MS = 80L
        const val REPEAT_STEP_MS = 20L
    }

    /** As setas: manter o OK é OK longo; manter uma seta repete-a, cada vez mais depressa. */
    object Dpad {
        const val CENTRE_HOLD_MS = 500L
        const val REPEAT_AFTER_MS = 400L
        const val REPEAT_START_MS = 180L
        const val REPEAT_MIN_MS = 70L
        const val REPEAT_STEP_MS = 15L
        /** O raio do OK, em fração do raio das setas. */
        const val OK_RADIUS = 0.43f
        /** Uma tecla tocada fica acesa pelo menos este tempo, e depois apaga-se neste. */
        const val LIT_MIN_MS = 120L
        const val FADE_MS = 180
    }

    /** Os botões redondos: carregar e manter, e aceso pelo menos este tempo. */
    object Key {
        const val HOLD_MS = 450L
        const val LIT_MIN_MS = 120L
    }

    /** O indicador do volume fica este tempo à vista depois de cada mudança. */
    const val VOLUME_HUD_MS = 1600L
}
