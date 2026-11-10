package cc.slokker.goatremote.data

import cc.slokker.goatremote.tv.Key
import cc.slokker.goatremote.tv.RemoteProtocol

// As regras do comando, sem ligações nem estado: as mesmas (com os mesmos nomes) no RemoteCore do iPhone, e testadas
// dos dois lados pelas tabelas de contracts/policies/.

/** Ligar à TV: tentar outra vez daqui a pouco, ou mostrar o problema. */
object ConnectPolicy {
    enum class Failure {
        /** A TV não aceita este telemóvel (pode ser só por uns segundos: a SHIELD, a meio de mudar de canal). */
        NOT_PAIRED,
        /** Não ligou (recusada, tempo esgotado, outro erro). */
        FAILED,
        /** Estava ligada e a TV fechou a ligação. */
        CLOSED,
    }

    enum class Show { NOT_PAIRED, UNREACHABLE, CLOSED }

    sealed interface Decision {
        /** Tentar outra vez daqui a [delayMs]; [retryOnFailure] é o "retry" dessa tentativa. */
        data class Retry(val delayMs: Long, val retryOnFailure: Boolean = true) : Decision
        data class Give(val show: Show) : Decision
    }

    const val NOT_PAIRED_RETRIES = 3
    const val NOT_PAIRED_STEP_MS = 2000L
    const val RETRY_MS = 1500L
    const val AUTO_RECONNECT_MS = 1500L
    /** Uma ligação que fecha outra vez antes disto já não se liga sozinha: mostra-se o aviso. */
    const val AUTO_RECONNECT_EVERY_MS = 10_000L

    /**
     * [notPairedRetries]: as recusas seguidas que já se tentaram de novo; [retry]: esta tentativa ainda pode tentar
     * outra vez se falhar; [sinceAutoReconnectMs]: desde a última vez que uma ligação fechada se ligou sozinha.
     * "Não emparelhado" tenta mais três vezes (2, 4 e 6 s, uns 12 s); outra falha tenta uma vez daí a 1,5 s; uma
     * ligação fechada só se liga sozinha numa Android TV, no máximo uma vez a cada 10 s.
     */
    fun next(failure: Failure, notPairedRetries: Int, retry: Boolean, kind: TvKind, sinceAutoReconnectMs: Long): Decision = when (failure) {
        Failure.NOT_PAIRED ->
            if (notPairedRetries < NOT_PAIRED_RETRIES) Decision.Retry(NOT_PAIRED_STEP_MS * (notPairedRetries + 1))
            else Decision.Give(Show.NOT_PAIRED)
        Failure.FAILED -> if (retry) Decision.Retry(RETRY_MS, retryOnFailure = false) else Decision.Give(Show.UNREACHABLE)
        Failure.CLOSED ->
            if (kind == TvKind.ANDROID && sinceAutoReconnectMs > AUTO_RECONNECT_EVERY_MS) Decision.Retry(AUTO_RECONNECT_MS)
            else Decision.Give(Show.CLOSED)
    }
}

/** A resposta de GET /channels: o que fica no ecrã. */
enum class ChannelsOutcome {
    READY,
    /** Ligação recusada ou 503: o GoatTV não está aberto (ou ainda não carregou a lista). */
    CLOSED,
    /** Outra resposta (ou nenhuma), com uma lista já mostrada: fica essa. */
    KEEP,
    /** Outra resposta, e nenhuma lista: falhou. */
    FAILED;

    companion object {
        fun of(status: Int, refused: Boolean, parsed: Boolean, hadList: Boolean): ChannelsOutcome = when {
            parsed -> READY
            refused || status == 503 -> CLOSED
            hadList -> KEEP
            else -> FAILED
        }
    }
}

/** A resposta de GET /now: o que fazer ao cartão. */
enum class NowOutcome {
    /** Veio o que está a dar. */
    UPDATE,
    /** 404: um GoatTV sem o /now; não se pergunta até voltar a ligar. */
    NO_NOW,
    /** Recusado ou 503: o GoatTV fechou, o cartão sai. */
    CLOSE,
    /** Outra resposta: fica tudo como está. */
    NOTHING;

    /** Com o que está a dar ([UPDATE]): o canal da lista muda, ou a lista vem outra vez (um canal que ela não tem). */
    enum class List { SAME, SET_CURRENT, REFETCH }

    companion object {
        fun of(status: Int, refused: Boolean, parsed: Boolean): NowOutcome = when {
            parsed -> UPDATE
            status == 404 -> NO_NOW
            refused || status == 503 -> CLOSE
            else -> NOTHING
        }

        fun list(nowCurrent: String?, listCurrent: String?, inList: Boolean): List = when {
            nowCurrent == listCurrent -> List.SAME
            nowCurrent == null || inList -> List.SET_CURRENT
            else -> List.REFETCH
        }
    }
}

/** Mudar de canal (POST /play): um passo do ciclo que abre o GoatTV e tenta outra vez até 10 s. */
enum class PlayStep {
    DONE,
    NOT_FOUND,
    FAILED,
    /** Já está à frente, só ainda não pode (a meio de mudar de canal): espera, sem o abrir outra vez. */
    START_WAITING,
    /** Não está à frente: abre-se e espera-se. */
    OPEN_AND_WAIT,
    /** Não se sabe abrir o GoatTV nesta TV. */
    CANNOT_OPEN,
    KEEP_WAITING,
    /** Passaram os 10 s. */
    TIMED_OUT;

    companion object {
        const val WAIT_MS = 10_000L
        const val RETRY_EVERY_MS = 1000L
        /** Depois de mudar, espera-se isto antes de perguntar o que está a dar. */
        const val NOW_AFTER_MS = 800L

        /**
         * [waiting]: já se começou a esperar (o prazo existe); [timedOut]: o prazo passou; [inFront]: numa Android TV,
         * o GoatTV é a app aberta; [canOpen]: há como o abrir.
         */
        fun of(outcome: GoatTvChannels.Play, waiting: Boolean, timedOut: Boolean, inFront: Boolean, canOpen: Boolean): PlayStep = when (outcome) {
            GoatTvChannels.Play.DONE -> DONE
            GoatTvChannels.Play.NOT_FOUND -> NOT_FOUND
            GoatTvChannels.Play.FAILED -> FAILED
            GoatTvChannels.Play.RETRY -> when {
                waiting -> if (timedOut) TIMED_OUT else KEEP_WAITING
                inFront -> START_WAITING
                canOpen -> OPEN_AND_WAIT
                else -> CANNOT_OPEN
            }
        }
    }
}

/**
 * Por onde vai uma tecla de volume. A regra que impede a SHIELD de reiniciar: com o GoatLauncher, ou sem se saber se ele
 * lá está, o volume nunca vai como tecla (vai pelo launcher, POST /volume/…); a tecla só quando se tem a certeza de que
 * não há launcher (ver [cc.slokker.goatremote.tv.LauncherVolume.outcome]). Vem dos incidentes c06672a, bcc9ca4 e b272212.
 */
enum class VolumeRoute {
    /** A tecla, pelo protocolo da TV. */
    KEY,
    /** Pelo GoatLauncher. */
    LAUNCHER,
    /** Esta TV não muda o volume: o indicador explica porquê. */
    EXPLAIN,
    /** Nada (largar uma tecla de volume que foi pelo launcher, que não tem "manter"). */
    NOTHING;

    enum class Press { TAP, HOLD_DOWN, HOLD_UP }

    companion object {
        val VOLUME_KEYS = listOf(Key.VOLUME_UP, Key.VOLUME_DOWN, Key.MUTE)

        /** [known]: o que se sabe do launcher desta TV (null: ainda não se sabe); [volumeControl]: a TV diz que o muda. */
        fun of(key: Key, press: Press, kind: TvKind, known: Boolean?, volumeControl: Boolean): VolumeRoute {
            if (key !in VOLUME_KEYS) return KEY
            if (press != Press.HOLD_UP && !volumeControl) return EXPLAIN
            if (kind == TvKind.ANDROID && known != false) return if (press == Press.HOLD_UP) NOTHING else LAUNCHER
            return KEY
        }

        /** HDMI-CEC: o launcher mudou o volume e o valor que a TV conta não mexeu (passados [LEARN_AFTER_MS]). */
        fun learnUnknown(beforeVolume: Int?, beforeMuted: Boolean?, afterVolume: Int?, afterMuted: Boolean?) =
            beforeVolume == afterVolume && beforeMuted == afterMuted

        const val LEARN_AFTER_MS = 800L
        /** Ao ligar, a TV manda vários valores seguidos (na SHIELD, com HDMI-CEC, acaba em 0): isso não é mudar o volume. */
        const val SETTLE_MS = 5000L

        /** O volume mudou (o indicador aparece): não ao ligar, nem numa TV que não sabe o valor. */
        fun changed(old: Pair<Int?, Boolean?>, new: Pair<Int?, Boolean?>, unknown: Boolean, settled: Boolean) =
            old.first != null && (new.first != old.first || new.second != old.second) && !unknown && settled
    }
}

/** As apps que se viu abertas numa TV (as mais recentes primeiro), para as abrir com um toque. */
object RecentApps {
    const val MAX = 12

    /** A lista com [app] à frente, ou null se não muda (o ecrã inicial não conta, nem a que já está à frente). */
    fun push(list: List<String>, app: String?): List<String>? {
        if (app == null || AppCatalog.isLauncher(app) || list.firstOrNull() == app) return null
        return (listOf(app) + list.filterNot { it == app }).take(MAX)
    }

    /** O que estava guardado: só nomes de pacote, sem repetidos, até [MAX]. */
    fun sanitize(saved: List<String>): List<String> = saved.filter { RemoteProtocol.isPackageName(it) }.distinct().take(MAX)
}
