package cc.slokker.goatremote.data

/**
 * O registo de diagnóstico antes de sair do telemóvel (enviar, copiar ou partilhar): as regras do GoatTV
 * (BugReportRules, no itv-shared) e do GoatLauncher, mais os emails e o IPv6. O mesmo que o iPhone faz (RemoteCore
 * LogRedaction), conferido dos dois lados por contracts/redaction.json.
 *
 * Aqui o registo é quase todo sobre achar as TVs na rede, por isso os IPs e os MACs não passam a `***`: cada um leva
 * um nome que se mantém no relatório inteiro (o primeiro IP é `ip1`, o seguinte `ip2`…; os MACs `mac1`…), para se
 * perceber qual é qual sem se ver o endereço. As portas ficam. Os nomes das TVs também (foi a pessoa que os deu).
 */
object LogRedaction {
    /** Troca por `***` os [secrets] e o que tem cara de credencial ou de servidor; os IPs e os MACs por `ipN`/`macN`. */
    fun redact(text: String, secrets: List<String> = emptyList()): String {
        var out = text
        for (secret in secrets.filter { it.length >= 3 }.distinct().sortedByDescending { it.length }) out = out.replace(secret, "***")
        // Os links podem ter credenciais em qualquer parte do caminho ou do servidor: sai o URL inteiro, menos o IP e a
        // porta de uma TV (que levam o nome no fim, como os outros IPs).
        out = URL.replace(out) { m ->
            val scheme = m.groupValues[1]
            val lan = LAN_URL.matchEntire(m.value)
            if (lan == null) "$scheme://***" else "$scheme://${lan.groupValues[1]}${lan.groupValues[2]}${if (lan.groupValues[3].isEmpty()) "" else "/***"}"
        }
        out = QUERY.replace(out) { "${it.groupValues[1]}=***" }
        out = XTREAM_PATH.replace(out) { "/${it.groupValues[1]}/***/***/" }
        out = STALKER_PATH.replace(out, "/stalker/***/***/")
        out = USER_INFO.replace(out) { "${it.groupValues[1]}***@" }
        out = AUTH.replace(out) { "${it.groupValues[1]} ***" }
        // O email antes dos servidores, senão ficava `nome@***`.
        out = EMAIL.replace(out, "***")
        out = HOST.replace(out) { if (looksLikeCode(it.value)) it.value else "***" }
        // Por fim os MACs e os IPs, numa só passagem, para os nomes irem pela ordem em que aparecem.
        val names = HashMap<String, String>()
        var ips = 0
        var macs = 0
        out = ADDRESS.replace(out) { m ->
            val mac = m.groups[1]?.value
            when {
                mac != null -> names.getOrPut("mac " + mac.lowercase().replace("%3a", ":")) { "mac${++macs}" }
                // Um `::` sozinho (Kotlin, C++) não é endereço.
                m.value.none(Char::isLetterOrDigit) -> m.value
                // O mesmo IPv6 com ou sem a interface (`fe80::1%wlan0`) é o mesmo aparelho.
                else -> names.getOrPut("ip " + m.value.substringBefore('%').lowercase()) { "ip${++ips}" }
            }
        }
        return out
    }

    /**
     * Um nome com pontos que é código, um ficheiro ou um pacote (fica, para o relatório servir) e não um servidor. Na
     * dúvida, é servidor. Os tipos de serviço da procura (`_androidtvremote2._tcp.local`) também ficam.
     */
    private fun looksLikeCode(name: String): Boolean {
        val labels = name.split('.')
        val last = labels.last().lowercase()
        if (last in FILE_ENDINGS) return true
        if (labels.size >= 3 && labels[0] in PACKAGE_ROOTS) return true
        if (labels.any { it.startsWith('_') }) return true
        if (last.length == 2 || last in COMMON_TLDS || '-' in name) return false
        return name.any { it.isUpperCase() } || labels[0] in CODE_ROOTS || "${labels[0]}.${labels[1]}" in CODE_ROOTS
    }

    private const val H = "[0-9A-Fa-f]{1,4}"
    private const val V4 = "\\d{1,3}(?:\\.\\d{1,3}){3}"
    /**
     * Os IPv6 inteiros (8 grupos) ou com `::`, também com um IPv4 no fim (`::ffff:1.2.3.4`) e com a interface
     * (`fe80::1%wlan0`). Uma hora (`01:12:03`) não tem `::` nem 8 grupos, por isso fica.
     */
    private const val IPV6 = "(?<![A-Za-z0-9_:.%])(?:" +
        "(?:(?:$H:){6}|(?:$H(?::$H){0,5})?::(?:$H:){0,5})$V4(?![A-Za-z0-9_]|\\.\\d)" +
        "|(?:(?:$H:){7}$H|(?:$H(?::$H){0,6})?::(?:$H(?::$H){0,6})?)(?:%[A-Za-z0-9_.-]+|(?![A-Za-z0-9_:%]|\\.\\d))" +
        ")"
    private const val IPV4 = "(?<![A-Za-z0-9_.])$V4(?![A-Za-z0-9_.])"

    private val URL = Regex("\\b([a-zA-Z][a-zA-Z0-9+.-]*)://[^\\s\"'<>]+")
    /** Um URL para um IP (o de uma TV): o IP (com os parênteses retos do IPv6), a porta e o resto (caminho, `)`…). */
    private val LAN_URL = Regex("[a-zA-Z][a-zA-Z0-9+.-]*://(?:[^/\\s@]*@)?($V4|\\[[0-9A-Fa-f:.]+(?:%[A-Za-z0-9_.-]+)?])(:\\d{1,5})?((?:[^A-Za-z0-9.:%-]).*)?")
    private val QUERY = Regex("(?i)\\b(password|passwd|pass|pwd|username|user|token|access_token|auth|key|api_key|apikey|secret|mac|sn|device_id|device_id2|signature|play_token)=([^&\\s\"']+)")
    private val XTREAM_PATH = Regex("/(live|movie|series|timeshift)/[^/\\s]+/[^/\\s]+/")
    private val STALKER_PATH = Regex("/stalker/[^/\\s]+/[^/\\s]+/")
    private val USER_INFO = Regex("([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\\s@]+@")
    private val AUTH = Regex("(?i)(authorization:?|bearer)\\s+(?:(?:bearer|basic|token)\\s+)?[^\\s,]+")
    private val EMAIL = Regex("(?<![A-Za-z0-9_.+-])[A-Za-z0-9_.+-]+@(?:[A-Za-z0-9-]+\\.)+[A-Za-z][A-Za-z0-9-]+")
    private val HOST = Regex("(?<![A-Za-z0-9_.-])(?:[A-Za-z0-9_-]+\\.)+[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9](?![A-Za-z0-9_-])")
    /** Um MAC (no grupo 1), um IPv6 ou um IPv4. */
    private val ADDRESS = Regex("(?<![A-Za-z0-9_])((?i:[0-9a-f]{2}(?:(?::|%3A)[0-9a-f]{2}){5}))(?![A-Za-z0-9_])|$IPV6|$IPV4")
    private val FILE_ENDINGS = setOf("kt", "java", "swift", "cpp", "dex", "jar", "apk", "ipa", "dylib", "xml", "json", "png", "jpg", "webp", "gz", "ts", "m3u", "m3u8", "mp4", "mkv", "php", "html", "js", "css", "txt", "log")
    private val COMMON_TLDS = setOf("com", "net", "org", "info", "biz", "xyz", "top", "site", "online", "club", "live", "pro", "stream", "app", "dev", "tech", "store", "shop", "cloud", "link", "icu", "vip", "fun", "space", "website", "one", "world", "today", "media", "example", "invalid", "test", "local", "lan")
    private val CODE_ROOTS = setOf("java", "javax", "kotlin", "kotlinx", "android", "androidx", "dalvik", "libcore", "sun", "okhttp3", "okio", "retrofit2", "coil", "coil3", "com.android", "com.google", "com.squareup", "com.apple", "org.videolan", "org.json", "cc.slokker")
    /** Os começos dos pacotes das apps (`com.netflix.ninja`), que um servidor quase nunca tem. */
    private val PACKAGE_ROOTS = setOf("com", "org", "net", "io")
}
