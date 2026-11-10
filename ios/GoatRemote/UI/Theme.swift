import RemoteCore
import SwiftUI

/// O visual do GoatTV no telemóvel: fundo azul-noite, cartões opacos, botões redondos e o azul→roxo de destaque.
enum Theme {
    static let background = Color(hex: ThemeTokens.background)
    /// O fundo das folhas.
    static let surface = Color(hex: ThemeTokens.surface)
    /// Cartões (listas, teclas do Mais).
    static let card = Color(hex: ThemeTokens.card)
    /// Botões e o que está dentro de um cartão.
    static let surfaceHigh = Color(hex: ThemeTokens.surfaceHigh)
    static let surfacePressed = Color(hex: ThemeTokens.surfacePressed)
    static let accent = Color(hex: ThemeTokens.accent)
    static let accent2 = Color(hex: ThemeTokens.accent2)
    static let power = Color(hex: ThemeTokens.power)
    static let green = Color(hex: ThemeTokens.green)
    static let text = Color(hex: ThemeTokens.text)
    static let dim = Color(hex: ThemeTokens.dim).opacity(ThemeTokens.dimAlpha)
    static let faint = Color(hex: ThemeTokens.dim).opacity(ThemeTokens.faintAlpha)
    static let line = Color.white.opacity(ThemeTokens.lineAlpha)
    /// A estrela dos canais favoritos.
    static let favorite = Color(hex: ThemeTokens.favorite)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// O fundo do cartão do que está a dar e da superfície de toque: o gradiente do GoatTV e um brilho no canto.
struct HeroBackground<S: Shape>: View {
    let shape: S
    var glow = 0.22

    var body: some View {
        shape.fill(LinearGradient(colors: [Color(hex: ThemeTokens.heroTop), Color(hex: ThemeTokens.heroBottom)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                GeometryReader { geo in
                    RadialGradient(colors: [Theme.accent.opacity(glow), .clear], center: UnitPoint(x: 0.8, y: 0.1),
                                   startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * 0.7)
                }
                .clipShape(shape)
            }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Fundo opaco numa forma qualquer: botão (mais claro enquanto se carrega) ou cartão.
struct GlassBackground<S: InsettableShape>: View {
    let shape: S
    var pressed = false
    var card = false

    var body: some View {
        shape.fill(card ? (pressed ? Theme.surfaceHigh : Theme.card) : (pressed ? Theme.surfacePressed : Theme.surfaceHigh))
    }
}

extension View {
    /// O fundo das peças, como no GoatTV: botões ([interactive]) ou cartões.
    func liquidGlass<S: InsettableShape>(_ shape: S, interactive: Bool = true, pressed: Bool = false) -> some View {
        background(GlassBackground(shape: shape, pressed: pressed, card: !interactive))
    }
}

/// Um botão do comando: toque curto, ou carregar e manter (manda o início e o fim do toque longo à TV).
struct PressArea<Label: View>: View {
    let onTap: () -> Void
    var onHold: ((Bool) -> Void)?
    let label: (_ pressed: Bool) -> Label

    @State private var pressed = false
    @State private var holding = false
    @State private var holdTask: Task<Void, Never>?
    /// O que se desenha: num toque rápido o botão acendia e apagava antes de se ver; fica aceso pelo menos 0,12 s.
    @State private var lit = false
    @State private var downAt = Date()
    @State private var release: Task<Void, Never>?

    init(onTap: @escaping () -> Void, onHold: ((Bool) -> Void)? = nil, @ViewBuilder label: @escaping (_ pressed: Bool) -> Label) {
        self.onTap = onTap
        self.onHold = onHold
        self.label = label
    }

    var body: some View {
        label(lit)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        release?.cancel()
                        lit = true
                        downAt = Date()
                        guard let onHold else { return }
                        holdTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            guard !Task.isCancelled, pressed else { return }
                            holding = true
                            onHold(true)
                        }
                    }
                    .onEnded { _ in
                        holdTask?.cancel()
                        if holding { onHold?(false) } else { onTap() }
                        holding = false
                        pressed = false
                        let wait = max(0, 0.12 - Date().timeIntervalSince(downAt))
                        release = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                            guard !Task.isCancelled else { return }
                            lit = false
                        }
                    }
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: lit)
    }
}

/// Botão redondo com um símbolo. [filled]: branco com o símbolo a preto (o botão principal, voltar).
struct GlassKey: View {
    let symbol: String
    var size: CGFloat = 60
    var tint: Color = Theme.text
    var filled = false
    /// O que o VoiceOver diz (o [id] é para os testes de interface).
    let label: String
    let id: String
    let onTap: () -> Void
    var onHold: ((Bool) -> Void)?

    var body: some View {
        PressArea(onTap: onTap, onHold: onHold) { pressed in
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: filled ? .semibold : .medium))
                .foregroundStyle(filled ? Color.black : tint)
                .frame(width: size, height: size)
                .background {
                    if filled { Circle().fill(pressed ? Color(hex: 0xD9DAE0) : .white) } else { GlassBackground(shape: Circle(), pressed: pressed) }
                }
                .scaleEffect(pressed ? 0.92 : 1)
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }
}
