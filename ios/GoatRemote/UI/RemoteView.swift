import RemoteCore
import SwiftUI

/// O comando, com o visual do GoatTV: em cima o nome da TV (tocar escolhe outra), som e ligar; o canal do GoatTV quando
/// ele está a dar; ao meio a superfície de toque ou as setas; em baixo play/pausa, voltar e início, e por cima destes
/// uma fila com teclado, apps, recuar/avançar e mais.
struct RemoteView: View {
    @Environment(RemoteModel.self) private var model
    /// A folha aberta por cima do comando (uma de cada vez). O teclado e o emparelhamento vêm do modelo e substituem-na.
    @State private var sheet: RemoteSheet?
    @State private var volumeVisible = false
    @State private var volumeToken = 0

    var body: some View {
        @Bindable var model = model
        let now = model.nowPlaying
        let connected = model.status == .connected
        let live = connected || model.status == .connecting
        VStack(spacing: 0) {
            header
                .padding(.bottom, now == nil ? 12 : 14)
            if let now {
                NowCard(channel: now) { sheet = .channels }
                    .padding(.bottom, 12)
            }
            Group {
                // A ligar (a abrir a app, a voltar de segundo plano) fica o comando escolhido, esbatido até a TV responder.
                if live, model.layout == .dpad {
                    DPad(ready: connected)
                } else {
                    TouchSurface().overlay { SurfaceInfo() }
                }
            }
            .overlay(alignment: .topTrailing) {
                if live { LayoutSwitch().padding(12) }
            }
            .overlay(alignment: .top) {
                if volumeVisible {
                    VolumeHUD().padding(.top, 60).transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.bottom, 18)
            HStack {
                GlassKey(symbol: "keyboard", size: 52, tint: Theme.dim, label: Strings.keyboard, id: "keyboard") { model.showKeyboard = true }
                Spacer()
                GlassKey(symbol: "square.grid.2x2", size: 52, tint: Theme.dim, label: "Apps", id: "apps") { sheet = .apps }
                Spacer()
                // Com o GoatTV a dar um canal, a lista abre-se no cartão dele.
                if model.hasChannels, now == nil {
                    GlassKey(symbol: "play.tv", size: 52, tint: Theme.dim, label: Strings.channels, id: "channels") { sheet = .channels }
                    Spacer()
                }
                GlassKey(symbol: "backward.fill", size: 52, tint: Theme.dim, label: Strings.rewind, id: "key:rewind") { model.press(.rewind) } onHold: { model.hold(.rewind, down: $0) }
                Spacer()
                GlassKey(symbol: "forward.fill", size: 52, tint: Theme.dim, label: Strings.forward, id: "key:fastForward") { model.press(.fastForward) } onHold: { model.hold(.fastForward, down: $0) }
                Spacer()
                GlassKey(symbol: "ellipsis", size: 52, tint: Theme.dim, label: Strings.more, id: "more") { sheet = .more }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 22)
            HStack(alignment: .center) {
                GlassKey(symbol: "playpause", size: 74, label: Strings.playPause, id: "key:playPause") { model.press(.playPause) }
                Spacer()
                GlassKey(symbol: "chevron.left", size: 96, filled: true, label: Strings.back, id: "key:back") { model.press(.back) } onHold: { model.hold(.back, down: $0) }
                Spacer()
                GlassKey(symbol: "tv", size: 74, label: Strings.home, id: "key:home") { model.press(.home) } onHold: { model.hold(.home, down: $0) }
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
            sheet = nil
            model.showKeyboard = false
        }
        .onChange(of: model.showKeyboard) { _, show in
            // A TV pediu o teclado com outra folha aberta: fecha-se essa e abre-se o teclado a seguir.
            guard show, sheet != nil else { return }
            model.showKeyboard = false
            sheet = nil
            Task {
                try? await Task.sleep(nanoseconds: SheetHandoff.nanoseconds)
                model.showKeyboard = true
            }
        }
        .sheet(isPresented: $model.showKeyboard) { KeyboardSheet().presentationDetents([.height(250)]).presentationBackground(Theme.surface) }
        .sheet(isPresented: shown(.apps)) { AppsSheet().presentationDetents([.medium, .large]).presentationBackground(Theme.surface) }
        .sheet(isPresented: shown(.channels)) { ChannelsSheet().presentationDetents([.medium, .large]).presentationBackground(Theme.surface) }
        .sheet(isPresented: shown(.more)) { MoreSheet().presentationDetents([.medium, .large]).presentationBackground(Theme.surface) }
        .sheet(isPresented: shown(.tvs)) { TVsSheet().presentationDetents([.medium, .large]).presentationBackground(Theme.surface) }
    }

    /// Aberta enquanto for esta a folha; fechá-la (deslizar para baixo) deixa o comando sem folha.
    private func shown(_ which: RemoteSheet) -> Binding<Bool> {
        Binding(get: { sheet == which }, set: { open in
            if open { sheet = which } else if sheet == which { sheet = nil }
        })
    }

    /// O nome da TV em grande (tocar abre as TVs), com o estado por baixo; à direita, som e ligar.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { sheet = .tvs } label: {
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
                     tint: model.state.muted == true ? Theme.accent : Theme.dim, label: Strings.mute, id: "key:mute") { model.press(.mute) }
            GlassKey(symbol: "power", size: 42, tint: model.state.isOn == false ? Theme.dim : Theme.power, label: Strings.power, id: "key:power") { model.press(.power) }
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
        case .connected: return screenLabel(model)
        case .connecting: return Strings.connecting
        case .notPaired: return Strings.notPaired
        case .unreachable: return Strings.cantReachIt
        case .noTV: return ""
        }
    }

    private func showVolume() {
        volumeToken += 1
        let token = volumeToken
        withAnimation(.easeOut(duration: 0.15)) { volumeVisible = true }
        Task {
            try? await Task.sleep(nanoseconds: Gestures.nanoseconds(Gestures.volumeHudMs))
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
                Text(Strings.swipeToMoveTapToSelect)
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
                Text(Strings.connectingToTheTv).font(.footnote).foregroundStyle(Theme.dim)
            }
            .allowsHitTesting(false)
        case .notPaired:
            notice(symbol: "link", title: Strings.thisTvDoesntKnowThisPhone,
                   detail: Strings.pairAgainTheTvWillShow,
                   button: Strings.pair) { model.repairCurrent() }
        case .unreachable(let why):
            notice(symbol: "wifi.exclamationmark", title: Strings.cantReachTheTv,
                   detail: Strings.isItOnAndOnThe + why,
                   button: Strings.tryAgain) { model.reconnect() }
        case .noTV:
            EmptyView()
        }
    }

    private var symbol: String {
        switch onScreen(model) {
        case .off: return "moon.zzz"
        case .app: return model.state.currentApp.flatMap { AppCatalog.app($0)?.symbol } ?? "play.tv"
        case .appleTV: return "appletv"
        case .home: return "house"
        }
    }

    private var title: String { screenLabel(model) }

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
            Label(problem.text, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .liquidGlass(Capsule(), interactive: false)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("volume-hud")
        } else if !model.state.volumeControl {
            Label(Strings.theAppleTvCantChangeThis, systemImage: "speaker.slash.fill")
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
        } else {
            level
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
    private let step = CGFloat(Gestures.Touch.stepDistance)

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
        .accessibilityLabel(Strings.touchSurface)
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityIdentifier("touchpad")
        .onDisappear { model.keyHold.end() }
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if last == nil {
                    last = value.startLocation
                    let key = Key.center
                    holdTask = model.keyHold.later { @MainActor in
                        try? await Task.sleep(nanoseconds: Gestures.nanoseconds(Gestures.Touch.holdMs))
                        guard !Task.isCancelled, !moved else { return }
                        holding = key
                        model.hold(key, down: true)
                        model.keyHold.longStarted(key) { model.hold($0, down: false) }
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
                    repeatTask = model.keyHold.later { @MainActor in
                        try? await Task.sleep(nanoseconds: Gestures.nanoseconds(Gestures.Touch.repeatAfterMs))
                        guard !Task.isCancelled else { return }
                        model.repeatStarted()
                        var interval = Gestures.Touch.repeatStartMs
                        while !Task.isCancelled {
                            model.press(direction, haptic: false)
                            addRipple(location)
                            try? await Task.sleep(nanoseconds: Gestures.nanoseconds(interval))
                            interval = max(Gestures.Touch.repeatMinMs, interval - Gestures.Touch.repeatStepMs)
                        }
                    }
                }
            }
            .onEnded { value in
                holdTask?.cancel()
                repeatTask?.cancel()
                if let key = holding {
                    model.keyHold.longEnded()
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
            // Com o /now do GoatTV: o programa, as horas, quanto falta e uma barra; sem ele, só o canal.
            TimelineView(.periodic(from: .now, by: 15)) { context in
                info(at: Int64(context.date.timeIntervalSince1970 * 1000))
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                zapKey("chevron.up", Strings.nextChannel, "zap:next") { model.zap(1) }
                zapKey("chevron.down", Strings.previousChannel, "zap:previous") { model.zap(-1) }
            }
            Button(action: onList) {
                Image(systemName: "list.bullet").font(.system(size: 18, weight: .semibold)).foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.channels)
            .accessibilityIdentifier("channels")
        }
        .padding(14)
        .background(HeroBackground(shape: RoundedRectangle(cornerRadius: 20, style: .continuous)))
        .accessibilityIdentifier("now-card")
    }

    private func info(at now: Int64) -> some View {
        let programme = model.nowInfo.flatMap { $0.current == channel.key ? $0.now : nil }.flatMap { $0.startMs <= now && $0.endMs > now ? $0 : nil }
        let caption = programme != nil ? [channel.num.map { String($0) }, channel.name].compactMap { $0 }.joined(separator: " · ")
            : "GoatTV" + (channel.num.map { " · \($0)" } ?? "")
        return VStack(alignment: .leading, spacing: 2) {
            Text(caption.uppercased())
                .font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Theme.faint).lineLimit(1)
            Text(programme?.title ?? channel.name).font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.text).lineLimit(1)
            if let programme {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Theme.gradient).frame(width: geo.size.width * programme.progress(now: now))
                    }
                }
                .frame(height: 3)
                .padding(.top, 5)
                let left = (programme.endMs - now) / 60_000 + 1
                Text("\(Self.clock(programme.startMs)) – \(Self.clock(programme.endMs)) · " + L("\(left) min left", "faltam \(left) min"))
                    .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                    .padding(.top, 3)
                    .accessibilityIdentifier("now-programme")
            }
        }
    }

    /// Hora:minuto, como o telemóvel as mostra.
    private static func clock(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1000).formatted(date: .omitted, time: .shortened)
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
            option(.touch, "hand.point.up.left", Strings.touchSurface)
            option(.dpad, "dpad", Strings.arrows)
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
    /// A tecla acesa e o brilho dela: acende ao tocar e apaga devagar ao largar, nunca antes de 0,12 s (num toque
    /// rápido, só enquanto o dedo estava em cima, mal se via).
    @State private var lit: Key?
    @State private var glow = 0.0
    @State private var fade: Task<Void, Never>?
    @State private var downAt = Date()
    /// false enquanto liga: a roda fica esbatida.
    var ready = true
    /// O raio do OK, em fração do raio das setas.
    private static let inner = CGFloat(Gestures.Dpad.okRadius)
    /// O contorno da roda e as divisões entre as setas.
    private static let line = Color.white.opacity(0.16)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height, 320)
            ZStack {
                Circle().fill(.white.opacity(0.04))
                if let start = sectorStart {
                    Sector(start: .degrees(start), inner: Self.inner).fill(.white.opacity(0.14 * glow))
                }
                ForEach([45.0, 135.0, 225.0, 315.0], id: \.self) { angle in
                    Path { p in
                        let a = angle * .pi / 180
                        let r = side / 2
                        p.move(to: CGPoint(x: r + cos(a) * r * Self.inner, y: r + sin(a) * r * Self.inner))
                        p.addLine(to: CGPoint(x: r + cos(a) * r, y: r + sin(a) * r))
                    }
                    .stroke(Self.line, lineWidth: 1.5)
                }
                Circle().strokeBorder(Self.line, lineWidth: 1.5)
                Circle().fill(.white.opacity(0.05 + (lit == .center ? 0.10 * glow : 0)))
                    .overlay(Circle().strokeBorder(Self.line, lineWidth: 1.5))
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
            .opacity(ready ? 1 : 0.4)
            .contentShape(Circle())
            .gesture(drag(side))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .padding(20)
        .background(HeroBackground(shape: RoundedRectangle(cornerRadius: 28, style: .continuous), glow: 0.16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.arrows)
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityIdentifier("dpad")
        .onDisappear { model.keyHold.end() }
    }

    private var sectorStart: Double? {
        switch lit {
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
                fade?.cancel()
                lit = key
                glow = 1
                downAt = Date()
                task = model.keyHold.later { @MainActor in
                    if key == .center {
                        try? await Task.sleep(nanoseconds: Gestures.nanoseconds(Gestures.Dpad.centreHoldMs))
                        guard !Task.isCancelled else { return }
                        held = true
                        model.hold(.center, down: true)
                        model.keyHold.longStarted(.center) { model.hold($0, down: false) }
                    } else {
                        try? await Task.sleep(nanoseconds: Gestures.nanoseconds(Gestures.Dpad.repeatAfterMs))
                        guard !Task.isCancelled else { return }
                        held = true
                        model.repeatStarted()
                        var interval = Gestures.Dpad.repeatStartMs
                        while !Task.isCancelled {
                            model.press(key, haptic: false)
                            try? await Task.sleep(nanoseconds: Gestures.nanoseconds(interval))
                            interval = max(Gestures.Dpad.repeatMinMs, interval - Gestures.Dpad.repeatStepMs)
                        }
                    }
                }
            }
            .onEnded { _ in
                task?.cancel()
                task = nil
                if let key = pressed {
                    if !held {
                        model.press(key)
                    } else if key == .center {
                        model.keyHold.longEnded()
                        model.hold(.center, down: false)
                    }
                }
                pressed = nil
                held = false
                let wait = max(0, Double(Gestures.Dpad.litMinMs) / 1000 - Date().timeIntervalSince(downAt))
                fade = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: Double(Gestures.Dpad.fadeMs) / 1000)) { glow = 0 }
                }
            }
    }
}

/// Um quarto do anel (a seta carregada), a começar em [start] e no sentido dos ponteiros. Fica de fora do OK, que é transparente.
private struct Sector: Shape {
    let start: Angle
    /// O raio do OK, em fração do raio da roda.
    let inner: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width / 2
        p.addArc(center: c, radius: r, startAngle: start, endAngle: start + .degrees(90), clockwise: false)
        p.addArc(center: c, radius: r * inner, startAngle: start + .degrees(90), endAngle: start, clockwise: true)
        p.closeSubpath()
        return p
    }
}

@MainActor
private func onScreen(_ model: RemoteModel) -> OnScreen {
    OnScreen.of(isOn: model.state.isOn, currentApp: model.state.currentApp, kind: model.current?.kind)
}

/// O que está no ecrã da TV: o subtítulo do cabeçalho e a marca-d'água da superfície dizem o mesmo.
@MainActor
private func screenLabel(_ model: RemoteModel) -> String {
    switch onScreen(model) {
    case .off: return Strings.tvIsOff
    case .app: return AppCatalog.name(model.state.currentApp ?? "")
    // A Apple TV não diz que app está aberta.
    case .appleTV: return "Apple TV"
    case .home: return Strings.homeScreen
    }
}

/// As folhas do comando: só uma de cada vez. Uma folha nova junta-se aqui, e o teclado e o emparelhamento fecham-na
/// sem mais listas (antes havia quatro booleanos repetidos em dois sítios, U2).
enum RemoteSheet: Equatable {
    case apps, channels, more, tvs
}

/// O SwiftUI não mostra uma folha enquanto outra está a fechar: o teclado e o emparelhamento esperam isto.
enum SheetHandoff {
    static let delayMs = 650
    static var nanoseconds: UInt64 { UInt64(delayMs) * 1_000_000 }
}
