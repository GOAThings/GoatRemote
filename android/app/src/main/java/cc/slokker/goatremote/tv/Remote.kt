package cc.slokker.goatremote.tv

/** As teclas que se mandam (os códigos do Android, KeyEvent.KEYCODE_*). */
enum class Key(val code: Int) {
    HOME(3), BACK(4),
    NUM0(7), NUM1(8), NUM2(9), NUM3(10), NUM4(11), NUM5(12), NUM6(13), NUM7(14), NUM8(15), NUM9(16),
    UP(19), DOWN(20), LEFT(21), RIGHT(22), CENTER(23),
    VOLUME_UP(24), VOLUME_DOWN(25), POWER(26),
    ENTER(66), DELETE(67),
    MENU(82), SEARCH(84),
    PLAY_PAUSE(85), STOP(86), NEXT(87), PREVIOUS(88), REWIND(89), FAST_FORWARD(90),
    MUTE(164), INFO(165), CHANNEL_UP(166), CHANNEL_DOWN(167), GUIDE(172),
    CAPTIONS(175), SETTINGS(176), INPUT(178),
    AUDIO_TRACK(222), LAST_CHANNEL(229);

    companion object {
        fun digit(n: Int): Key = entries.first { it.code == NUM0.code + n }
    }
}

/** Carregar e largar, ou carregar e manter (início e fim do toque longo). */
enum class KeyDirection(val code: Int) { START_LONG(1), END_LONG(2), SHORT(3) }

/** O que a TV conta: ligada ou não, volume, app aberta. */
data class TvState(
    val isOn: Boolean? = null,
    val volume: Int? = null,
    val maxVolume: Int? = null,
    val muted: Boolean? = null,
    /** Se dá para mudar o volume (a Apple TV só consegue com HDMI-CEC ou colunas dela). */
    val volumeControl: Boolean = true,
    val currentApp: String? = null,
    val model: String? = null,
    val vendor: String? = null,
    /** Sobe cada vez que a TV abre uma caixa de texto (o telemóvel mostra o teclado). */
    val keyboardRequests: Int = 0,
    /** O que a caixa de texto já tem e o nome dela (ex.: "Pesquisar"). */
    val textValue: String = "",
    val textLabel: String? = null,
)

/**
 * O comando (porta 6466), sem a ligação: recebe as mensagens da TV, devolve as respostas e guarda o estado.
 *
 * RemoteMessage: remote_configure 1 {code1 1, device_info 2 {model 1, vendor 2, unknown1 3, unknown2 4,
 * package_name 5, app_version 6}}, remote_set_active 2 {active 1}, remote_error 3, remote_ping_request 8 {val1 1},
 * remote_ping_response 9 {val1 1}, remote_key_inject 10 {key_code 1, direction 2}, remote_ime_key_inject 20
 * {app_info 1 {app_package 12}}, remote_ime_show_request 22 {remote_text_field_status 2 {value 2, label 6}},
 * remote_ime_batch_edit 21 {ime_counter 1, field_counter 2, edit_info 3 {insert 1,
 * text_field_status 2 {start 1, end 2, value 3}}}, remote_start 40 {started 1}, remote_set_volume_level 50
 * {player_model 3, volume_max 6, volume_level 7, volume_muted 8}, remote_app_link_launch_request 90 {app_link 1}.
 */
class RemoteProtocol(private val model: String, private val appVersion: String) {
    var state = TvState()
        private set

    /** Já se pode mandar teclas (a TV mandou set_active e respondemos). */
    var ready = false
        private set

    private var imeCounter = 0
    private var fieldCounter = 0

    /** As funções que a TV aceita e nós também (a resposta ao configure e ao set_active). */
    private var active = FEATURES

    /** Trata uma mensagem da TV; devolve o que há a responder. */
    fun handle(frame: ByteArray): List<ByteArray> {
        val m = ProtoMessage.parse(frame)
        when {
            m.has(1) -> {
                val configure = m.message(1)
                val info = configure.message(2)
                state = state.copy(model = info.string(1).ifEmpty { null }, vendor = info.string(2).ifEmpty { null })
                active = FEATURES and configure.int(1)
                return listOf(
                    ProtoWriter().message(1) {
                        varint(1, active)
                        message(2) {
                            string(1, model); string(2, "Android"); varint(3, 1); string(4, "1")
                            string(5, "cc.slokker.goatremote"); string(6, appVersion)
                        }
                    }.toByteArray(),
                )
            }
            m.has(2) -> {
                ready = true
                return listOf(ProtoWriter().message(2) { varint(1, active) }.toByteArray())
            }
            m.has(8) -> return listOf(ProtoWriter().message(9) { varint(1, m.message(8).long(1)) }.toByteArray())
            m.has(40) -> state = state.copy(isOn = m.message(40).bool(1))
            m.has(50) -> {
                val v = m.message(50)
                state = state.copy(maxVolume = v.int(6), volume = v.int(7), muted = v.bool(8))
            }
            m.has(20) -> {
                val app = m.message(20).message(1).string(12)
                if (app.isNotEmpty()) state = state.copy(currentApp = app)
            }
            m.has(21) -> {
                val edit = m.message(21)
                imeCounter = edit.int(1)
                fieldCounter = edit.int(2)
            }
            m.has(22) -> {
                val field = m.message(22).message(2)
                state = state.copy(
                    textValue = field.string(2),
                    textLabel = field.string(6).ifEmpty { null },
                    keyboardRequests = state.keyboardRequests + 1,
                )
            }
            m.has(3) -> throw ProtocolException("a TV mandou um erro")
        }
        return emptyList()
    }

    fun key(key: Key, direction: KeyDirection = KeyDirection.SHORT): ByteArray =
        ProtoWriter().message(10) { varint(1, key.code); varint(2, direction.code) }.toByteArray()

    /** Escreve [text] no campo de texto aberto na TV (substitui o que lá estiver). */
    fun text(text: String): ByteArray {
        // O cursor no fim (em caracteres Unicode, como o cliente de referência).
        val end = maxOf(text.codePointCount(0, text.length) - 1, 0)
        return ProtoWriter().message(21) {
            varint(1, imeCounter)
            varint(2, fieldCounter)
            message(3) {
                varint(1, 1)
                message(2) { varint(1, end); varint(2, end); string(3, text) }
            }
        }.toByteArray()
    }

    /** Abre uma app por link (ex.: https://www.youtube.com, market://launch?id=…). */
    fun appLink(link: String): ByteArray = ProtoWriter().message(90) { string(1, link) }.toByteArray()

    companion object {
        const val PORT = 6466
        /** PING, KEY, IME, POWER, VOLUME, APP_LINK. */
        const val FEATURES = 1 or 2 or 4 or 32 or 64 or 512
        /** Como as Android TV se anunciam na rede. */
        const val SERVICE = "_androidtvremote2._tcp"
    }
}
