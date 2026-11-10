package cc.slokker.goatremote

import cc.slokker.goatremote.tv.Key
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * As teclas mantidas (o OK longo, uma seta a repetir) de uma sessão: os temporizadores correm aqui, não no ecrã. Um
 * controlo que sai do ecrã a meio (a TV desligou-se, mudou o layout) chama [end]: a repetição pára e um OK longo
 * acaba com o fim do toque longo (B5: antes a repetição podia continuar sozinha, ou o OK ficava "carregado" na TV).
 */
class KeyHold(private val scope: CoroutineScope) {
    private val jobs = mutableSetOf<Job>()
    private var long: Key? = null
    private var endLong: ((Key) -> Unit)? = null

    /** Um temporizador ou repetição desta tecla mantida. */
    fun later(block: suspend CoroutineScope.() -> Unit): Job {
        val job = scope.launch(block = block)
        jobs.add(job)
        job.invokeOnCompletion { jobs.remove(job) }
        return job
    }

    /** O início do toque longo já foi para a TV; [end] manda o fim se o controlo sair antes. */
    fun longStarted(key: Key, end: (Key) -> Unit) {
        long = key
        endLong = end
    }

    /** O fim do toque longo já foi (o dedo saiu). */
    fun longEnded() {
        long = null
        endLong = null
    }

    /** O controlo saiu do ecrã: pára tudo e acaba o toque longo, se havia. */
    fun end() {
        jobs.toList().forEach { it.cancel() }
        jobs.clear()
        val key = long ?: return
        val end = endLong
        longEnded()
        end?.invoke(key)
    }
}
