import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0A0D16)
    static let surface = Color(hex: 0x161B28)
    static let surfaceHigh = Color(hex: 0x222A3B)
    static let accent = Color(hex: 0x38BDF8)
    static let accent2 = Color(hex: 0x8B5CF6)
    static let power = Color(hex: 0xEF4444)
    static let dim = Color.white.opacity(0.55)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Um botão do comando: toque curto, ou carregar e manter (manda o início e o fim do toque longo à TV).
struct PressArea<Label: View>: View {
    let onTap: () -> Void
    var onHold: ((Bool) -> Void)?
    @ViewBuilder let label: (_ pressed: Bool) -> Label

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
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

/// Botão redondo com um símbolo.
struct RoundKey: View {
    let symbol: String
    var size: CGFloat = 58
    var tint: Color = .white
    var background: Color = Theme.surface
    let id: String
    let onTap: () -> Void
    var onHold: ((Bool) -> Void)?

    var body: some View {
        PressArea(onTap: onTap, onHold: onHold) { pressed in
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(pressed ? Theme.surfaceHigh : background))
                .scaleEffect(pressed ? 0.92 : 1)
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
        .accessibilityLabel(id)
    }
}
