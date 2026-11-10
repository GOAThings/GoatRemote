/// O "tato" do comando: os mesmos números no Android (ui/Gestures.kt), conferidos por contracts/gestures.json.
/// Tempos em ms, distâncias em pontos.
public enum Gestures {
    /// Superfície de toque: um passo por cada bocado de dedo; manter parado é OK longo; o dedo parado repete.
    public enum Touch {
        public static let stepDistance = 44
        public static let holdMs = 500
        public static let repeatAfterMs = 350
        public static let repeatStartMs = 220
        public static let repeatMinMs = 80
        public static let repeatStepMs = 20
    }

    /// As setas: manter o OK é OK longo; manter uma seta repete-a, cada vez mais depressa.
    public enum Dpad {
        public static let centreHoldMs = 500
        public static let repeatAfterMs = 400
        public static let repeatStartMs = 180
        public static let repeatMinMs = 70
        public static let repeatStepMs = 15
        /// O raio do OK, em fração do raio das setas.
        public static let okRadius = 0.43
        /// Uma tecla tocada fica acesa pelo menos este tempo, e depois apaga-se neste.
        public static let litMinMs = 120
        public static let fadeMs = 180
    }

    /// Os botões redondos: carregar e manter, e aceso pelo menos este tempo.
    public enum Key {
        public static let holdMs = 450
        public static let litMinMs = 120
    }

    /// O indicador do volume fica este tempo à vista depois de cada mudança.
    public static let volumeHudMs = 1600

    /// Para o Task.sleep.
    public static func nanoseconds(_ ms: Int) -> UInt64 { UInt64(ms) * 1_000_000 }
}
