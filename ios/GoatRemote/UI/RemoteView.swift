import RemoteCore
import SwiftUI

/// O comando, com o visual do GoatTV: em cima o nome da TV (tocar escolhe outra), som e ligar; o canal do GoatTV quando
/// ele está a dar; ao meio a superfície de toque ou as setas; em baixo play/pausa, voltar e início, e por cima destes
/// uma fila com teclado, apps, recuar/avançar e mais.
struct RemoteView: View {
    @Environment(RemoteModel.self) private var model
    @State private var showApps = false
    @State private var showChannels = false
    @State private var showMore = false
    @State private var showTVs = false
    @State private var volumeVisible = false
    @State private var volumeToken = 0

    var body: some View {
        @Bindable var model = model
        let now = model.nowPlaying
        let connected = model.status == .connected
        VStack(spacing: 0) {
            header
                .padding(.bottom, now == nil ? 12 : 14)
            if let now {
                NowCard(channel: now) { showChannels = true }
                    .padding(.bottom, 12)
            }
            Group {
                if connected, model.layout == .dpad {
                    DPad()
                } else {
                    TouchSurface().overlay { SurfaceInfo() }
                }
            }
            .overlay(alignment: .topTrailing) {
                if connected { LayoutSwitch().padding(12) }
            }
            .overlay(alignment: .top) {
                if volumeVisible {
                    VolumeHUD().padding(.top, 60).transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.bottom, 18)
            HStack {
                GlassKey(symbol: "keyboard", size: 52, tint: Theme.dim, id: "keyboard") { model.showKeyboard = true }
                Spacer()
                GlassKey(symbol: "square.grid.2x2", size: 52, tint: Theme.dim, id: "apps") { showApps = true }
                Spacer()
                // Com o GoatTV a dar um canal, a lista abre-se no cartão dele.
                if model.hasChannels, now == nil {
                    GlassKey(symbol: "play.tv", size: 52, tint: Theme.dim, id: "channels") { showChannels = true }
                    Spacer()
                }
                GlassKey(symbol: "backward.fill", size: 52, tint: Theme.dim, id: "key:rewind") { model.press(.rewind) } onHold: { model.hold(.rewind, down: $0) }
                Spacer()
                GlassKey(symbol: "forward.fill", size: 52, tint: Theme.dim, id: "key:fastForward") { model.press(.fastForward) } onHold: { model.hold(.fastForward, down: $0) }
                Spacer()
                GlassKey(symbol: "ellipsis", size: 52, tint: Theme.dim, id: "more") { showMore = true }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 22)
            HStack(alignment: .center) {
                GlassKey(symbol: "playpause", size: 74, id: "key:playPause") { model.press(.playPause) }
                Spacer()
                GlassKey(symbol: "chevron.left", size: 96, filled: true, id: "key:back") { model.press(.back) } onHold: { model.hold(.back, down: $0) }
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
        .onChange(of: model.closeSheets) { _, _ in
            showApps = false
            showChannels = false
            showMore = false
            showTVs = false
            model.showKeyboard = false
        }
        .onChange(of: model.showKeyboard) { _, show in
            // A TV pediu o teclado com outra folha aberta: fecha-se essa e abre-se o teclado a seguir.
            guard show, showApps || showChannels || showMore || showTVs else { return }
            model.showKeyboard = false
            showApps = false
            showChannels = false
            showMore = false
            showTVs = false
            Task {
                try? await Task.sleep(nanoseconds: 650_000_000)
                model.showKeyboard = true
            }
        }
        .sheet(isPresented: $model.showKeyboard) { KeyboardSheet().presentationDetents([.height(250)]).presentationBackground(Theme.surface) }
        .sheet(isPresented: $showApps) { AppsSheet().presentationDetents([.medium, .large]).presentationBackground(Theme.surface) }
        .sheet(isPresented: $showChannels) { ChannelsSheet().presentationDetents([.medium, .large]).presentationBackground(Theme.surface) }
        .sheet(isPresented: $showMore) { MoreSheet().presentationDetents([.medium, .large]).presentationBackground(Theme.surface) }
        .sheet(isPresented: $showTVs) { TVsSheet().presentationDetents([.medium, .large]).presentationBackground(Theme.surface) }
    }

    /// O nome da TV em grande (tocar abre as TVs), com o estado por baixo; à direita, som e ligar.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { showTVs = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(model.current?.name ?? "GoatRemote")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.faint)
                    }
                    HStack(spacing: 7) {
                        Circle().fill(statusColor).frame(width: 7, height: 7)
                        Text(subtitle).font(.footnote).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tv-menu")
            GlassKey(symbol: model.state.muted == true ? "speaker.slash.fill" : "speaker.slash", size: 42,
                     tint: model.state.muted == true ? Theme.accent : Theme.dim, id: "key:mute") { model.press(.mute) }
            GlassKey(symbol: "power", size: 42, tint: model.state.isOn == false ? Theme.dim : Theme.power, id: "key:power") { model.press(.power) }
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .connected: return model.state.isOn == false ? Theme.dim : Theme.green
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
            // A Apple TV não diz que app está aberta.
            return model.current?.kind == .apple ? "Apple TV" : L("Home screen", "Ecrã inicial")
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
                Text(L("Swipe to move · tap to select", "Desliza para andar · toca para escolher"))
                    .font(.caption)
                    .foregroundStyle(Theme.faint.opacity(0.6))
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
        return model.current?.kind == .apple ? "appletv" : "house"
    }

    private var title: String {
        if model.state.isOn == false { return L("TV is off", "A TV está desligada") }
        if let app = model.state.currentApp, !AppCatalog.isLauncher(app) { return AppCatalog.name(app) }
        return model.current?.kind == .apple ? "Apple TV" : L("Home screen", "Ecrã inicial")
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
        if let problem = model.volumeProblem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .liquidGlass(Capsule(), interactive: false)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("volume-hud")
        } else if let key = model.volumePressed {
            // Sem valor para mostrar (HDMI-CEC): só o que se carregou.
            Image(systemName: key == .mute ? "speaker.slash.fill" : key == .volumeUp ? "speaker.wave.3.fill" : "speaker.wave.1.fill")
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .liquidGlass(Capsule(), interactive: false)
                .accessibilityIdentifier("volume-hud")
        } else if model.state.volumeControl {
            level
        } else {
            Label(L("The Apple TV can't change this TV's volume. Use its remote",
                    "A Apple TV não muda o volume desta TV. Usa o comando dela"), systemImage: "speaker.slash.fill")
                .font(.footnote)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .liquidGlass(Capsule(), interactive: false)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("volume-hud")
        }
    }

    @ViewBuilder
    private var level: some View {
        let max = Double(model.state.maxVolume ?? 100)
        let level = max > 0 ? Swift.min(Swift.max(Double(model.state.volume ?? 0) / max, 0), 1) : 0
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
        .liquidGlass(Capsule(), interactive: false)
        .accessibilityIdentifier("volume-hud")
    }
}

/// A superfície de toque. Deslizar anda (um passo por cada bocado de dedo), tocar é OK, manter é OK longo.
struct TouchSurface: View {
    @Environment(RemoteModel.self) private var model
    @State private var ripples: [Ripple] = []
    @State private var last: CGPoint?
    @State private var moved = false
    @State private var holding: Key?
    @State private var holdTask: Task<Void, Never>?
    @State private var repeatTask: Task<Void, Never>?
    private let step: CGFloat = 44

    struct Ripple: Identifiable {
        let id = UUID()
        let point: CGPoint
        var strong = false
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HeroBackground(shape: RoundedRectangle(cornerRadius: 28, style: .continuous), glow: 0.16)
                ForEach(ripples) { ripple in
                    RippleView(strong: ripple.strong).position(ripple.point)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .gesture(drag(in: geo.size))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Touch surface", "Superfície de toque"))
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityIdentifier("touchpad")
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if last == nil {
                    last = value.startLocation
                    let key = Key.center
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
                    repeatTask?.cancel()
                    let direction: Key = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
                    model.press(direction)
                    addRipple(value.location)
                    last = value.location
                    moved = true
                    // Dedo parado depois de deslizar: a mesma direção repete-se, cada vez mais depressa.
                    let location = value.location
                    repeatTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        var interval: UInt64 = 220
                        while !Task.isCancelled {
                            model.press(direction)
                            addRipple(location)
                            try? await Task.sleep(nanoseconds: interval * 1_000_000)
                            interval = max(80, interval - 20)
                        }
                    }
                }
            }
            .onEnded { value in
                holdTask?.cancel()
                repeatTask?.cancel()
                if let key = holding {
                    model.hold(key, down: false)
                } else if !moved {
                    model.press(.center)
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

/// O logótipo de um canal do GoatTV (vem da TV), ou um símbolo enquanto não vem.
struct ChannelLogoView: View {
    @Environment(RemoteModel.self) private var model
    let channel: TVChannel
    var size = CGSize(width: 52, height: 36)
    var background: Color = Theme.surfaceHigh

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(background)
            if let url = model.channelLogoURL(channel) {
                RemoteImage(url: url, limit: GoatTVChannels.maxLogoBytes, maxPixelSize: GoatTVChannels.logoSide) { image in
                    if let image {
                        image.resizable().scaledToFit().padding(4).accessibilityIdentifier("logo")
                    } else {
                        Image(systemName: "tv").foregroundStyle(Theme.dim)
                    }
                }
            } else {
                Image(systemName: "tv").foregroundStyle(Theme.dim)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// O canal que o GoatTV está a dar: canal anterior/seguinte e a lista.
struct NowCard: View {
    @Environment(RemoteModel.self) private var model
    let channel: TVChannel
    let onList: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ChannelLogoView(channel: channel, size: CGSize(width: 62, height: 42), background: .black.opacity(0.35))
            VStack(alignment: .leading, spacing: 2) {
                Text(("GoatTV" + (channel.num.map { " · \($0)" } ?? "")).uppercased())
                    .font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Theme.faint).lineLimit(1)
                Text(channel.name).font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.text).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                zapKey("chevron.up", L("Next channel", "Canal seguinte"), "zap:next") { model.zap(1) }
                zapKey("chevron.down", L("Previous channel", "Canal anterior"), "zap:previous") { model.zap(-1) }
            }
            Button(action: onList) {
                Image(systemName: "list.bullet").font(.system(size: 18, weight: .semibold)).foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Channels", "Canais"))
            .accessibilityIdentifier("channels")
        }
        .padding(14)
        .background(HeroBackground(shape: RoundedRectangle(cornerRadius: 20, style: .continuous)))
        .accessibilityIdentifier("now-card")
    }

    private func zapKey(_ symbol: String, _ label: String, _ id: String, action: @escaping () -> Void) -> some View {
        PressArea(onTap: action) { pressed in
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                .frame(width: 34, height: 30)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(pressed ? 0.18 : 0.08)))
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Superfície de toque ou setas; a escolha fica guardada.
struct LayoutSwitch: View {
    @Environment(RemoteModel.self) private var model

    var body: some View {
        HStack(spacing: 2) {
            option(.touch, "hand.point.up.left", L("Touch surface", "Superfície de toque"))
            option(.dpad, "dpad", L("Arrows", "Setas"))
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.35)))
    }

    private func option(_ layout: RemoteLayout, _ symbol: String, _ label: String) -> some View {
        let on = model.layout == layout
        return Button { model.layout = layout } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(on ? Color.black : Theme.faint)
                .frame(width: 38, height: 30)
                .background(Capsule().fill(on ? Color.white : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("layout:\(layout.rawValue)")
    }
}

/// As setas e o OK, como num comando físico. Manter uma seta repete-a, cada vez mais depressa; manter o OK é o OK longo.
struct DPad: View {
    @Environment(RemoteModel.self) private var model
    @State private var pressed: Key?
    @State private var held = false
    @State private var task: Task<Void, Never>?
    /// O raio do OK, em fração do raio das setas.
    private static let inner: CGFloat = 0.43

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height, 320)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(hex: 0x1E2538), Color(hex: 0x121621)], center: UnitPoint(x: 0.7, y: 0.2),
                                             startRadius: 0, endRadius: side * 0.9))
                if let start = sectorStart {
                    Sector(start: .degrees(start)).fill(Theme.surfacePressed)
                }
                ForEach([45.0, 135.0, 225.0, 315.0], id: \.self) { angle in
                    Path { p in
                        let a = angle * .pi / 180
                        let r = side / 2
                        p.move(to: CGPoint(x: r + cos(a) * r * Self.inner, y: r + sin(a) * r * Self.inner))
                        p.addLine(to: CGPoint(x: r + cos(a) * r, y: r + sin(a) * r))
                    }
                    .stroke(Theme.background, lineWidth: 3)
                }
                Circle().fill(pressed == .center ? Theme.surfacePressed : Color(hex: 0x232A3D))
                    .overlay(Circle().strokeBorder(Theme.background, lineWidth: 3))
                    .frame(width: side * Self.inner, height: side * Self.inner)
                Text("OK").font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.text)
                Group {
                    Image(systemName: "chevron.up").position(x: side / 2, y: side * 0.11)
                    Image(systemName: "chevron.down").position(x: side / 2, y: side * 0.89)
                    Image(systemName: "chevron.left").position(x: side * 0.11, y: side / 2)
                    Image(systemName: "chevron.right").position(x: side * 0.89, y: side / 2)
                }
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .gesture(drag(side))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Arrows", "Setas"))
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityIdentifier("dpad")
    }

    private var sectorStart: Double? {
        switch pressed {
        case .right: return -45
        case .down: return 45
        case .left: return 135
        case .up: return 225
        default: return nil
        }
    }

    private func keyAt(_ point: CGPoint, side: CGFloat) -> Key? {
        let r = side / 2
        let dx = point.x - r
        let dy = point.y - r
        let distance = hypot(dx, dy)
        if distance > r { return nil }
        if distance < r * Self.inner { return .center }
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }

    private func drag(_ side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard pressed == nil, let key = keyAt(value.startLocation, side: side) else { return }
                pressed = key
                held = false
                task = Task { @MainActor in
                    if key == .center {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled else { return }
                        held = true
                        model.hold(.center, down: true)
                    } else {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        var interval: UInt64 = 180
                        while !Task.isCancelled {
                            held = true
                            model.press(key)
                            try? await Task.sleep(nanoseconds: interval * 1_000_000)
                            interval = max(70, interval - 15)
                        }
                    }
                }
            }
            .onEnded { _ in
                task?.cancel()
                task = nil
                if let key = pressed {
                    if !held { model.press(key) } else if key == .center { model.hold(.center, down: false) }
                }
                pressed = nil
                held = false
            }
    }
}

/// Um quarto de círculo (a seta carregada), a começar em [start] e no sentido dos ponteiros.
private struct Sector: Shape {
    let start: Angle

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: c)
        p.addArc(center: c, radius: rect.width / 2, startAngle: start, endAngle: start + .degrees(90), clockwise: false)
        p.closeSubpath()
        return p
    }
}
