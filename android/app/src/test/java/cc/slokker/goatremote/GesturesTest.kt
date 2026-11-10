package cc.slokker.goatremote

import cc.slokker.goatremote.ui.Gestures
import org.junit.Assert.assertEquals
import org.junit.Test

/** O tato do comando: os mesmos números que o iPhone (contracts/gestures.json). */
class GesturesTest {
    @Test
    fun timings() {
        val g = Contracts.obj("gestures.json")
        val touch = g.getJSONObject("touch")
        assertEquals(touch.getInt("stepDistance"), Gestures.Touch.STEP_DP)
        assertEquals(touch.getLong("holdMs"), Gestures.Touch.HOLD_MS)
        assertEquals(touch.getLong("repeatAfterMs"), Gestures.Touch.REPEAT_AFTER_MS)
        assertEquals(touch.getLong("repeatStartMs"), Gestures.Touch.REPEAT_START_MS)
        assertEquals(touch.getLong("repeatMinMs"), Gestures.Touch.REPEAT_MIN_MS)
        assertEquals(touch.getLong("repeatStepMs"), Gestures.Touch.REPEAT_STEP_MS)
        val dpad = g.getJSONObject("dpad")
        assertEquals(dpad.getLong("centreHoldMs"), Gestures.Dpad.CENTRE_HOLD_MS)
        assertEquals(dpad.getLong("repeatAfterMs"), Gestures.Dpad.REPEAT_AFTER_MS)
        assertEquals(dpad.getLong("repeatStartMs"), Gestures.Dpad.REPEAT_START_MS)
        assertEquals(dpad.getLong("repeatMinMs"), Gestures.Dpad.REPEAT_MIN_MS)
        assertEquals(dpad.getLong("repeatStepMs"), Gestures.Dpad.REPEAT_STEP_MS)
        assertEquals(dpad.getDouble("okRadius").toFloat(), Gestures.Dpad.OK_RADIUS, 0f)
        assertEquals(dpad.getLong("litMinMs"), Gestures.Dpad.LIT_MIN_MS)
        assertEquals(dpad.getInt("fadeMs"), Gestures.Dpad.FADE_MS)
        val key = g.getJSONObject("key")
        assertEquals(key.getLong("holdMs"), Gestures.Key.HOLD_MS)
        assertEquals(key.getLong("litMinMs"), Gestures.Key.LIT_MIN_MS)
        assertEquals(g.getLong("volumeHudMs"), Gestures.VOLUME_HUD_MS)
    }
}
