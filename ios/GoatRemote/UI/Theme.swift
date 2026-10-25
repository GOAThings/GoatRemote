import SwiftUI

/// O visual do comando da Apple TV: fundo preto, peças em cinzento-vidro com um realce subtil em cima.
enum Theme {
    static let background = Color.black
    static let surface = Color(hex: 0x1C1C1E)
    static let surfaceTop = Color(hex: 0x26262A)
    static let surfaceBottom = Color(hex: 0x18181B)
    static let surfacePressed = Color(hex: 0x2C2C2E)
    static let surfaceHigh = Color(hex: 0x2C2C2E)
    static let accent = Color(hex: 0x38BDF8)
    static let accent2 = Color(hex: 0x8B5CF6)
    static let power = Color(hex: 0xEF4444)
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.18)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// O realce da borda: mais claro em cima, quase nada em baixo (dá o ar de vidro).
    static let rim = LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Fundo de vidro numa forma qualquer.
struct GlassBackground<S: InsettableShape>: View {
    let shape: S
    var pressed = false

    var body: some View {
        shape
            .fill(LinearGradient(colors: pressed ? [Theme.surfacePressed, Theme.surfaceTop] : [Theme.surfaceTop, Theme.surfaceBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(Theme.rim, lineWidth: 1))
            .shadow(color: .black.opacity(0.7), radius: 10, y: 5)
    }
}

extension View {
    /// Liquid Glass do iOS 26 (com o brilho que segue o dedo e o salto ao carregar); antes disso, o vidro escuro.
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(_ shape: S, interactive: Bool = true, pressed: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(GlassBackground(shape: shape, pressed: pressed))
        }
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

    init(onTap: @escaping () -> Void, onHold: ((Bool) -> Void)? = nil, @ViewBuilder label: @escaping (_ pressed: Bool) -> Label) {
        self.onTap = onTap
        self.onHold = onHold
        self.label = label
    }

    var body: some View {
        label(pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
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
                    }
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: pressed)
    }
}

/// Botão redondo de vidro com um símbolo.
struct GlassKey: View {
    let symbol: String
    var size: CGFloat = 60
    var tint: Color = .white
    let id: String
    let onTap: () -> Void
    var onHold: ((Bool) -> Void)?

    var body: some View {
        PressArea(onTap: onTap, onHold: onHold) { pressed in
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .liquidGlass(Circle(), pressed: pressed)
                .scaleEffect(pressed ? 0.92 : 1)
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
        .accessibilityLabel(id)
    }
}
