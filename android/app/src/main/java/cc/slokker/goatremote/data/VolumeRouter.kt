package cc.slokker.goatremote.data

import cc.slokker.goatremote.DebugLog
import cc.slokker.goatremote.tv.Key
import cc.slokker.goatremote.tv.LauncherVolume

/**
 * O único caminho do volume (o comando, manter carregado, os botões do telemóvel): decide por onde vai cada tecla
 * ([VolumeRoute]) e, pelo GoatLauncher, o que fazer com a resposta ([LauncherVolume.outcome]), guardando o que se fica
 * a saber do launcher. Nunca manda a tecla: diz a quem chama se pode.
 */
class VolumeRouter(private val memory: LauncherMemory) {
    fun route(tv: SavedTv?, key: Key, press: VolumeRoute.Press, volumeControl: Boolean): VolumeRoute =
        if (tv == null) VolumeRoute.KEY else VolumeRoute.of(key, press, tv.kind, memory.known(tv.id), volumeControl)

    /** O que o launcher respondeu: [outcome] NO_LAUNCHER é a única vez em que a tecla pode ir. */
    class Sent(val outcome: LauncherVolume.Outcome, val status: Int, val refused: Boolean)

    /** POST /volume/…; null se a tecla não é de volume. */
    suspend fun viaLauncher(tv: SavedTv, key: Key): Sent? {
        val what = LauncherVolume.path(key) ?: return null
        val r = LauncherApi(tv.host).volume(what)
        r.error?.let { DebugLog.add("Volume via launcher failed: $it") }
        val outcome = LauncherVolume.outcome(memory.known(tv.id), r.status, r.refused)
        when (outcome) {
            LauncherVolume.Outcome.DONE -> memory.set(tv.id, true)
            LauncherVolume.Outcome.NO_LAUNCHER -> {
                DebugLog.add("Volume: no launcher on ${tv.name} (${if (r.refused) "refused" else "404"}), using keys")
                memory.set(tv.id, false)
            }
            LauncherVolume.Outcome.DIDNT_ANSWER ->
                DebugLog.add("Volume: launcher on ${tv.name} didn't answer (HTTP ${r.status}), not sending the key")
        }
        return Sent(outcome, r.status, r.refused)
    }
}
