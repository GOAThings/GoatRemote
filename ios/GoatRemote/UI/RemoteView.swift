import RemoteCore
import SwiftUI

/// O comando, ao jeito do da Apple TV: em cima som, a TV e ligar; ao meio uma superfície de toque; em baixo
/// play/pausa, voltar e início. Por cima destes, uma fila discreta com teclado, apps, recuar/avançar e mais.
struct RemoteView: View {
    @Environment(RemoteModel.self) private var model
    @State private var showApps = false
    @State private var showMore = false
    @State private var showTVs = false
    @State private var volumeVisible = false
    @State private var volumeToken = 0

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            topBar
                .padding(.bottom, 16)
            TouchSurface()
                .overlay { SurfaceInfo() }
                .overlay(alignment: .top) {
                    if volumeVisible {
                        VolumeHUD().padding(.top, 16).transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 18)
            HStack {
                GlassKey(symbol: "keyboard", size: 48, tint: .white.opacity(0.8), id: "keyboard") { model.showKeyboard = true }
                Spacer()
                GlassKey(symbol: "square.grid.2x2", size: 48, tint: .white.opacity(0.8), id: "apps") { showApps = true }
                Spacer()
                GlassKey(symbol: "backward.fill", size: 48, tint: .white.opacity(0.8), id: "key:rewind") { model.press(.rewind) } onHold: { model.hold(.rewind, down: $0) }
                Spacer()
                GlassKey(symbol: "forward.fill", size: 48, tint: .white.opacity(0.8), id: "key:fastForward") { model.press(.fastForward) } onHold: { model.hold(.fastForward, down: $0) }
                Spacer()
                GlassKey(symbol: "ellipsis", size: 48, tint: .white.opacity(0.8), id: "more") { showMore = true }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 22)
            HStack(alignment: .center) {
                GlassKey(symbol: "playpause", size: 74, id: "key:playPause") { model.press(.playPause) }
                Spacer()
                GlassKey(symbol: "chevron.left", size: 96, id: "key:back") { model.press(.back) } onHold: { model.hold(.back, down: $0) }
                Spacer()
                GlassKey(symbol: "tv", size: 74, id: "key:home") { model.press(.home) } onHold: { model.hold(.home, down: $0) }
            }
            .padding(.horizontal, 10)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background {
            if model.volumeButtons, model.status == .connected {
                VolumeButtonsHost { up in model.press(up ? .volumeUp : .volumeDown) }
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: model.volumeChanged) { _, _ in showVolume() }
        .onChange(of: model.showKeyboard) { _, show in
            // A TV pediu o teclado com outra folha aberta: fecha-se essa e abre-se o teclado a seguir.
            guard show, showApps || showMore || showTVs else { return }
            model.showKeyboard = false
            showApps = false
            showMore = false
            showTVs = false
            Task {
                try? await Task.sleep(nanoseconds: 650_000_000)
                model.showKeyboard = true
            }
        }
        .sheet(isPresented: $model.showKeyboard) { KeyboardSheet().presentationDetents([.height(250)]) }
        .sheet(isPresented: $showApps) { AppsSheet().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showMore) { MoreSheet().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showTVs) { TVsSheet().presentationDetents([.medium, .large]) }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            GlassKey(symbol: model.state.muted == true ? "speaker.slash.fill" : "speaker.slash", size: 58,
                     tint: model.state.muted == true ? Theme.accent : Theme.dim, id: "key:mute") { model.press(.mute) }
            Button { showTVs = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "tv.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.gradient))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.current?.name ?? "GoatRemote")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Circle().fill(statusColor).frame(width: 6, height: 6)
                            Text(subtitle).lineLimit(1)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(GlassBackground(shape: Capsule()))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tv-menu")
            GlassKey(symbol: "power", size: 58, tint: model.state.isOn == false ? Theme.dim : .white, id: "key:power") { model.press(.power) }
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .connected: return model.state.isOn == false ? Theme.dim : .green
        case .connecting: return .orange
        case .noTV: return Theme.dim
        default: return Theme.power
        }
    }

    private var subtitle: String {
        switch model.status {
        case .connected:
            if model.state.isOn == false { return L("TV is off", "A TV está desligada") }
            if let app = model.state.currentApp, !AppCatalog.isLauncher(app) { return AppCatalog.name(app) }
            return L("Home screen", "Ecrã inicial")
        case .connecting: return L("Connecting…", "A ligar…")
        case .notPaired: return L("Not paired", "Não emparelhada")
        case .unreachable: return L("Can't reach it", "Sem ligação")
        case .noTV: return ""
        }
    }

    private func showVolume() {
        volumeToken += 1
        let token = volumeToken
        withAnimation(.easeOut(duration: 0.15)) { volumeVisible = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard token == volumeToken else { return }
            withAnimation(.easeIn(duration: 0.3)) { volumeVisible = false }
        }
    }
}

/// Dentro da superfície: a app aberta em marca-d'água, ou o que se passa com a ligação (com o que fazer).
struct SurfaceInfo: View {
    @Environment(RemoteModel.self) private var model

    var body: some View {
        switch model.status {
        case .connected:
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: symbol).font(.system(size: 46, weight: .light))
                Text(title).font(.system(size: 19, weight: .semibold, design: .rounded))
                Spacer()
                // Com as setas nas bordas, as próprias setas já dizem o que fazer.
                Text(L("Swipe to move · tap to select · hold for more", "Desliza para andar · toca para escolher · mantém para mais"))
                    .font(.caption2)
                    .opacity(model.dpadTaps ? 0 : 0.8)
                    .padding(.bottom, 16)
            }
            .foregroundStyle(Color.white.opacity(0.13))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("status")
        case .connecting:
            VStack(spacing: 12) {
                ProgressView().tint(Theme.dim)
                Text(L("Connecting to the TV…", "A ligar à TV…")).font(.footnote).foregroundStyle(Theme.dim)
            }
            .allowsHitTesting(false)
        case .notPaired:
            notice(symbol: "link", title: L("This TV doesn't know this iPhone", "Esta TV não conhece este iPhone"),
                   detail: L("Pair again: the TV will show a code.", "Emparelha outra vez: a TV mostra um código."),
                   button: L("Pair", "Emparelhar")) { model.repairCurrent() }
        case .unreachable(let why):
            notice(symbol: "wifi.exclamationmark", title: L("Can't reach the TV", "Não chego à TV"),
                   detail: L("Is it on and on the same Wi-Fi? ", "Está ligada e na mesma rede Wi-Fi? ") + why,
                   button: L("Try again", "Tentar outra vez")) { model.reconnect() }
        case .noTV:
            EmptyView()
        }
    }

    private var symbol: String {
        if model.state.isOn == false { return "moon.zzz" }
        if let app = model.state.currentApp, !AppCatalog.isLauncher(app) { return AppCatalog.app(app)?.symbol ?? "play.tv" }
        return "house"
    }

    private var title: String {
        if model.state.isOn == false { return L("TV is off", "A TV está desligada") }
        if let app = model.state.currentApp, !AppCatalog.isLauncher(app) { return AppCatalog.name(app) }
        return L("Home screen", "Ecrã inicial")
    }

    private func notice(symbol: String, title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(Theme.gradient)
            Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(detail).font(.footnote).foregroundStyle(Theme.dim).multilineTextAlignment(.center).lineLimit(4)
            Button(button, action: action)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.top, 4)
        }
        .padding(28)
    }
}

/// O volume da TV por um bocado, quando muda.
struct VolumeHUD: View {
    @Environment(RemoteModel.self) private var model

    var body: some View {
        let max = Double(model.state.maxVolume ?? 100)
        let level = max > 0 ? Double(model.state.volume ?? 0) / max : 0
        let muted = model.state.muted == true
        HStack(spacing: 10) {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.footnote)
            GeometryReader { geo in
                Capsule().fill(Theme.faint)
                    .overlay(alignment: .leading) {
                        Capsule().fill(muted ? AnyShapeStyle(Theme.dim) : AnyShapeStyle(Theme.gradient)).frame(width: geo.size.width * level)
                    }
            }
            .frame(width: 120, height: 5)
            Text("\(Int((level * 100).rounded()))").font(.footnote.monospacedDigit()).frame(width: 28, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(GlassBackground(shape: Capsule()))
        .accessibilityIdentifier("volume-hud")
    }
}

/// A superfície de toque. Deslizar anda (um passo por cada bocado de dedo), tocar é OK, manter é OK longo.
/// Com "setas nas bordas", tocar perto de uma borda carrega nessa seta.
struct TouchSurface: View {
    @Environment(RemoteModel.self) private var model
    @State private var ripples: [Ripple] = []
    @State private var last: CGPoint?
    @State private var moved = false
    @State private var holding: Key?
    @State private var holdTask: Task<Void, Never>?
    private let step: CGFloat = 44

    struct Ripple: Identifiable {
        let id = UUID()
        let point: CGPoint
        var strong = false
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GlassBackground(shape: RoundedRectangle(cornerRadius: 40, style: .continuous))
                if model.dpadTaps { dpadHints(geo.size) }
                ForEach(ripples) { ripple in
                    RippleView(strong: ripple.strong).position(ripple.point)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            .gesture(drag(in: geo.size))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Touch surface", "Superfície de toque"))
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityIdentifier("touchpad")
    }

    private func dpadHints(_ size: CGSize) -> some View {
        ZStack {
            Circle().strokeBorder(Theme.faint, lineWidth: 1).frame(width: centerRadius(size) * 2, height: centerRadius(size) * 2)
            Image(systemName: "chevron.up").position(x: size.width / 2, y: 30)
            Image(systemName: "chevron.down").position(x: size.width / 2, y: size.height - 30)
            Image(systemName: "chevron.left").position(x: 28, y: size.height / 2)
            Image(systemName: "chevron.right").position(x: size.width - 28, y: size.height / 2)
        }
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(Theme.faint)
    }

    private func centerRadius(_ size: CGSize) -> CGFloat { min(size.width, size.height) * 0.26 }

    /// A tecla de um toque nesse ponto: OK, ou a seta da borda (com as setas nas bordas).
    private func target(_ point: CGPoint, _ size: CGSize) -> Key {
        guard model.dpadTaps else { return .center }
        let dx = point.x - size.width / 2
        let dy = point.y - size.height / 2
        if hypot(dx, dy) < centerRadius(size) { return .center }
        // Normaliza pela forma (a superfície é mais alta do que larga).
        let nx = dx / (size.width / 2)
        let ny = dy / (size.height / 2)
        if abs(nx) > abs(ny) { return nx > 0 ? .right : .left }
        return ny > 0 ? .down : .up
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if last == nil {
                    last = value.startLocation
                    let key = target(value.startLocation, size)
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled, !moved else { return }
                        holding = key
                        model.hold(key, down: true)
                        addRipple(value.startLocation, strong: true)
                    }
                }
                guard holding == nil, let anchor = last else { return }
                let dx = value.location.x - anchor.x
                let dy = value.location.y - anchor.y
                if abs(dx) >= step || abs(dy) >= step {
                    holdTask?.cancel()
                    if abs(dx) > abs(dy) { model.press(dx > 0 ? .right : .left) } else { model.press(dy > 0 ? .down : .up) }
                    addRipple(value.location)
                    last = value.location
                    moved = true
                }
            }
            .onEnded { value in
                holdTask?.cancel()
                if let key = holding {
                    model.hold(key, down: false)
                } else if !moved {
                    model.press(target(value.startLocation, size))
                    addRipple(value.startLocation, strong: true)
                }
                last = nil
                moved = false
                holding = nil
            }
    }

    private func addRipple(_ point: CGPoint, strong: Bool = false) {
        let ripple = Ripple(point: point, strong: strong)
        ripples.append(ripple)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            ripples.removeAll { $0.id == ripple.id }
        }
    }
}

/// O círculo que se expande e desvanece onde se tocou.
struct RippleView: View {
    let strong: Bool
    @State private var grown = false

    var body: some View {
        Circle()
            .fill(Color.white.opacity(strong ? 0.16 : 0.10))
            .frame(width: 96, height: 96)
            .scaleEffect(grown ? 1.25 : 0.35)
            .opacity(grown ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 0.45)) { grown = true } }
            .allowsHitTesting(false)
    }
}
