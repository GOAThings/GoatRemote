package cc.slokker.goatremote

import cc.slokker.goatremote.Contracts.boolOrNull
import cc.slokker.goatremote.Contracts.objects
import cc.slokker.goatremote.Contracts.same
import cc.slokker.goatremote.Contracts.stringOrNull
import cc.slokker.goatremote.Contracts.strings
import cc.slokker.goatremote.data.ChannelsOutcome
import cc.slokker.goatremote.data.ConnectPolicy
import cc.slokker.goatremote.data.GoatTvChannels
import cc.slokker.goatremote.data.NowOutcome
import cc.slokker.goatremote.data.PlayStep
import cc.slokker.goatremote.data.RecentApps
import cc.slokker.goatremote.data.TvKind
import cc.slokker.goatremote.data.VolumeRoute
import cc.slokker.goatremote.tv.Key
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** As regras de contracts/policies/: as mesmas tabelas que o iPhone testa. */
class PoliciesTest {
    private fun rows(file: String, key: String = "rows") = Contracts.obj("policies/$file").getJSONArray(key).objects()

    private fun kind(name: String) = TvKind.entries.first { it.name.equals(name, ignoreCase = true) }

    private fun <E : Enum<E>> named(entries: List<E>, name: String) = entries.first { same(it, name) }

    @Test
    fun connect() {
        for (row in rows("connect.json")) {
            val got = ConnectPolicy.next(named(ConnectPolicy.Failure.entries, row.getString("failure")), row.getInt("notPairedRetries"),
                row.getBoolean("retry"), kind(row.getString("kind")), row.getLong("sinceAutoReconnectMs"))
            val want = row.getJSONObject("expected")
            val expected = if (want.has("show")) ConnectPolicy.Decision.Give(named(ConnectPolicy.Show.entries, want.getString("show")))
            else ConnectPolicy.Decision.Retry(want.getLong("retryMs"), want.getBoolean("retryOnFailure"))
            assertEquals(row.toString(), expected, got)
        }
    }

    @Test
    fun channels() {
        for (row in rows("channels.json")) {
            val got = ChannelsOutcome.of(row.getInt("status"), row.getBoolean("refused"), row.getBoolean("parsed"), row.getBoolean("hadList"))
            assertTrue("$row → $got", same(got, row.getString("outcome")))
        }
    }

    @Test
    fun now() {
        for (row in rows("now.json")) {
            val got = NowOutcome.of(row.getInt("status"), row.getBoolean("refused"), row.getBoolean("parsed"))
            assertTrue("$row → $got", same(got, row.getString("outcome")))
        }
        for (row in rows("now.json", "listRows")) {
            val got = NowOutcome.list(row.stringOrNull("nowCurrent"), row.stringOrNull("listCurrent"), row.getBoolean("inList"))
            assertTrue("$row → $got", same(got, row.getString("list")))
        }
    }

    @Test
    fun play() {
        for (row in rows("play.json")) {
            val got = PlayStep.of(named(GoatTvChannels.Play.entries, row.getString("outcome")), row.getBoolean("waiting"),
                row.getBoolean("timedOut"), row.getBoolean("inFront"), row.getBoolean("canOpen"))
            assertTrue("$row → $got", same(got, row.getString("step")))
        }
    }

    /** A regra que impede a SHIELD de reiniciar. */
    @Test
    fun volumeRoute() {
        val table = Contracts.obj("policies/volume-route.json")
        val keys = mapOf("volumeUp" to Key.VOLUME_UP, "volumeDown" to Key.VOLUME_DOWN, "mute" to Key.MUTE, "home" to Key.HOME)
        val rows = table.getJSONArray("rows").objects()
        assertEquals(144, rows.size)
        for (row in rows) {
            val got = VolumeRoute.of(keys.getValue(row.getString("key")), named(VolumeRoute.Press.entries, row.getString("press")),
                kind(row.getString("kind")), row.boolOrNull("known"), row.getBoolean("volumeControl"))
            assertTrue("$row → $got", same(got, row.getString("route")))
        }
        fun pair(a: JSONArray) = (if (a.isNull(0)) null else a.getInt(0)) to (if (a.isNull(1)) null else a.getBoolean(1))
        for (row in table.getJSONArray("learn").objects()) {
            val (bv, bm) = pair(row.getJSONArray("before"))
            val (av, am) = pair(row.getJSONArray("after"))
            assertEquals(row.toString(), row.getBoolean("unknown"), VolumeRoute.learnUnknown(bv, bm, av, am))
        }
        for (row in table.getJSONArray("changed").objects()) {
            assertEquals(row.toString(), row.getBoolean("changed"),
                VolumeRoute.changed(pair(row.getJSONArray("old")), pair(row.getJSONArray("new")), row.getBoolean("unknown"), row.getBoolean("settled")))
        }
        for (row in table.getJSONArray("problems").objects()) {
            val got = cc.slokker.goatremote.data.VolumeProblem.of(row.getInt("status"), row.getBoolean("refused"))
            assertTrue("$row → $got", same(got, row.getString("problem")))
        }
        val timings = table.getJSONObject("timings")
        assertEquals(timings.getLong("learnAfterMs"), VolumeRoute.LEARN_AFTER_MS)
        assertEquals(timings.getLong("settleMs"), VolumeRoute.SETTLE_MS)
    }

    @Test
    fun onScreen() {
        for (row in rows("on-screen.json")) {
            val got = cc.slokker.goatremote.data.OnScreen.of(row.boolOrNull("isOn"), row.stringOrNull("currentApp"), kind(row.getString("kind")))
            assertTrue("$row → $got", same(got, row.getString("onScreen")))
        }
    }

    @Test
    fun recents() {
        val table = Contracts.obj("policies/recents.json")
        for (row in table.getJSONArray("push").objects()) {
            val app = row.stringOrNull("app")
            val want = if (row.isNull("result")) null else row.getJSONArray("result").strings()
            assertEquals(row.toString(), want, RecentApps.push(row.getJSONArray("list").strings(), app))
        }
        for (row in table.getJSONArray("sanitize").objects()) {
            assertEquals(row.getJSONArray("result").strings(), RecentApps.sanitize(row.getJSONArray("saved").strings()))
        }
    }
}
