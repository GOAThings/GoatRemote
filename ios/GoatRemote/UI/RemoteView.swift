import RemoteCore
import SwiftUI

/// O comando: TV escolhida, estado, setas (ou touchpad), teclas, volume, teclado e apps.
struct RemoteView: View {
    @Environment(RemoteModel.self) private var model
    @AppStorage("touchpad") private var touchpad = false
    @State private var showKeyboard = false
    @State private var showApps = false
    @State private var showAddTV = false

    var body: some View {
        VStack(spacing: 18) {
            topBar
            statusLine
            Group {
                if touchpad { Touchpad() } else { DPad() }
            }
            .frame(maxWidth: 320)
            .padding(.top, 4)
            HStack(spacing: 22) {
                RoundKey(symbol: "arrow.uturn.backward", id: "key:back") { model.press(.back) } onHold: { model.hold(.back, down: $0) }
                RoundKey(symbol: "house.fill", id: "key:home") { model.press(.home) } onHold: { model.hold(.home, down: $0) }
                RoundKey(symbol: "line.3.horizontal", id: "key:menu") { model.press(.menu) }
                RoundKey(symbol: touchpad ? "circle.grid.cross" : "hand.point.up.left", id: "mode") { touchpad.toggle() }
            }
            HStack(spacing: 22) {
                RoundKey(symbol: "backward.fill", id: "key:rewind") { model.press(.rewind) } onHold: { model.hold(.rewind, down: $0) }
                RoundKey(symbol: "playpause.fill", size: 66, background: Theme.surfaceHigh, id: "key:playPause") { model.press(.playPause) }
                RoundKey(symbol: "forward.fill", id: "key:fastForward") { model.press(.fastForward) } onHold: { model.hold(.fastForward, down: $0) }
            }
            HStack(spacing: 14) {
                VolumeRocker()
                Spacer(minLength: 0)
                RoundKey(symbol: "keyboard", id: "keyboard") { showKeyboard = true }
                RoundKey(symbol: "square.grid.2x2.fill", id: "apps") { showApps = true }
            }
            .padding(.horizontal, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .sheet(isPresented: $showKeyboard) { KeyboardSheet().presentationDetents([.height(240)]) }
        .sheet(isPresented: $showApps) { AppsSheet().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showAddTV) { AddTVView(onDone: { showAddTV = false }) }
    }

    private var topBar: some View {
        HStack {
            Menu {
                ForEach(model.tvs) { tv in
                    Button {
                        model.select(tv)
                    } label: {
                        if tv.id == model.current?.id { Label(tv.name, systemImage: "checkmark") } else { Text(tv.name) }
                    }
                }
                Divider()
                Button { showAddTV = true } label: { Label(L("Add a TV", "Juntar uma TV"), systemImage: "plus") }
                if let tv = model.current {
                    Button { model.repairCurrent() } label: { Label(L("Pair again", "Emparelhar outra vez"), systemImage: "link") }
                    Button(role: .destructive) { model.forget(tv) } label: { Label(L("Forget \(tv.name)", "Esquecer \(tv.name)"), systemImage: "trash") }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 9, height: 9)
                    Text(model.current?.name ?? "GoatRemote").font(.title3.weight(.semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.footnote.weight(.bold)).foregroundStyle(Theme.dim)
                }
                .foregroundStyle(.white)
            }
            .accessibilityIdentifier("tv-menu")
            Spacer()
            RoundKey(symbol: "power", size: 48, tint: .white, background: Theme.power, id: "key:power") { model.press(.power) }
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .connected: return .green
        case .connecting: return .orange
        default: return Theme.power
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch model.status {
        case .connected:
            HStack(spacing: 10) {
                if let app = model.state.currentApp, !AppCatalog.isLauncher(app) {
                    Label(AppCatalog.name(app), systemImage: AppCatalog.app(app)?.symbol ?? "app.fill")
                } else if model.state.isOn == false {
                    Label(L("TV is off", "A TV está desligada"), systemImage: "moon.fill")
                } else {
                    Label(L("Home screen", "Ecrã inicial"), systemImage: "house")
                }
                Spacer()
                if let volume = model.state.volume, let max = model.state.maxVolume, max > 0 {
                    Label("\(volume * 100 / max)%", systemImage: model.state.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .monospacedDigit()
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.dim)
            .accessibilityIdentifier("status")
        case .connecting:
            HStack {
                ProgressView().tint(Theme.dim)
                Text(L("Connecting…", "A ligar…")).foregroundStyle(Theme.dim)
                Spacer()
            }
            .font(.subheadline)
        case .notPaired:
            Button { model.repairCurrent() } label: {
                Label(L("This TV doesn't know this iPhone: pair again", "Esta TV não conhece este iPhone: emparelhar outra vez"), systemImage: "link")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tint(Theme.accent)
        case .unreachable(let why):
            Button { model.reconnect() } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(L("Can't reach the TV: tap to try again", "Não chego à TV: toca para tentar outra vez"), systemImage: "wifi.exclamationmark")
                        .font(.subheadline.weight(.medium))
                    Text(why).font(.caption).foregroundStyle(Theme.dim).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tint(Theme.accent)
        case .noTV:
            EmptyView()
        }
    }
}

/// Setas e OK num anel.
struct DPad: View {
    @Environment(RemoteModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(Theme.surface)
                Circle().strokeBorder(Theme.gradient.opacity(0.35), lineWidth: 1.5)
                arrow(.up, "chevron.up").offset(y: -size * 0.34)
                arrow(.down, "chevron.down").offset(y: size * 0.34)
                arrow(.left, "chevron.left").offset(x: -size * 0.34)
                arrow(.right, "chevron.right").offset(x: size * 0.34)
                PressArea(onTap: { model.press(.center) }, onHold: { model.hold(.center, down: $0) }) { pressed in
                    Circle()
                        .fill(pressed ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surfaceHigh))
                        .overlay(Text("OK").font(.headline).foregroundStyle(.white))
                        .frame(width: size * 0.36, height: size * 0.36)
                }
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("key:center")
                .accessibilityLabel("OK")
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func arrow(_ key: Key, _ symbol: String) -> some View {
        PressArea(onTap: { model.press(key) }, onHold: { model.hold(key, down: $0) }) { pressed in
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(pressed ? Theme.accent : .white)
                .frame(width: 76, height: 76)
                .background(Circle().fill(pressed ? Theme.surfaceHigh : .clear))
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("key:\(key)")
        .accessibilityLabel("\(key)")
    }
}

/// Touchpad: deslizar anda (um passo por cada bocado de dedo), tocar é OK.
struct Touchpad: View {
    @Environment(RemoteModel.self) private var model
    @State private var last: CGPoint?
    @State private var moved = false
    private let step: CGFloat = 46

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.gradient.opacity(0.35), lineWidth: 1.5))
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "hand.draw").font(.title)
                    Text(L("Swipe to move, tap for OK", "Desliza para andar, toca para OK")).font(.footnote)
                }
                .foregroundStyle(Theme.dim)
            )
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let anchor = last ?? value.startLocation
                        let dx = value.location.x - anchor.x
                        let dy = value.location.y - anchor.y
                        if abs(dx) >= step || abs(dy) >= step {
                            if abs(dx) > abs(dy) { model.press(dx > 0 ? .right : .left) } else { model.press(dy > 0 ? .down : .up) }
                            last = value.location
                            moved = true
                        } else if last == nil {
                            last = value.startLocation
                        }
                    }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        if !moved, distance < 12 { model.press(.center) }
                        last = nil
                        moved = false
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Touchpad", "Touchpad"))
            .accessibilityIdentifier("touchpad")
    }
}

/// Volume: menos, sem som, mais (manter carregado repete).
struct VolumeRocker: View {
    @Environment(RemoteModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            RoundKey(symbol: "speaker.minus.fill", size: 52, background: .clear, id: "key:volumeDown") { model.press(.volumeDown) } onHold: { model.hold(.volumeDown, down: $0) }
            RoundKey(symbol: "speaker.slash.fill", size: 44, tint: Theme.dim, background: .clear, id: "key:mute") { model.press(.mute) }
            RoundKey(symbol: "speaker.plus.fill", size: 52, background: .clear, id: "key:volumeUp") { model.press(.volumeUp) } onHold: { model.hold(.volumeUp, down: $0) }
        }
        .padding(4)
        .background(Capsule().fill(Theme.surface))
    }
}

/// Escrever no campo de texto aberto na TV (pesquisa, palavras-passe…).
struct KeyboardSheet: View {
    @Environment(RemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Type on the TV", "Escrever na TV")).font(.headline)
            Text(L("Goes to the text box open on the TV.", "Vai para a caixa de texto aberta na TV."))
                .font(.footnote).foregroundStyle(Theme.dim)
            TextField(L("Search, password…", "Pesquisa, palavra-passe…"), text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                .submitLabel(.send)
                .onSubmit {
                    model.press(.enter)
                    dismiss()
                }
                .onChange(of: text) { _, new in model.type(new) }
                .accessibilityIdentifier("keyboard-field")
            HStack {
                Button(L("Clear", "Limpar")) { text = "" }.disabled(text.isEmpty)
                Spacer()
                Button(L("Send", "Enviar")) {
                    model.press(.enter)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .padding(20)
        .onAppear { focused = true }
    }
}

/// Abrir apps: as que se viu abertas nesta TV e as conhecidas.
struct AppsSheet: View {
    @Environment(RemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let recents = model.recentApps.filter { AppCatalog.app($0) == nil }
                    if !recents.isEmpty {
                        Text(L("Recently opened", "Abertas há pouco")).font(.headline)
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(recents, id: \.self) { package in
                                tile(name: AppCatalog.name(package), symbol: "app.fill", color: Theme.surfaceHigh, link: "market://launch?id=\(package)")
                            }
                        }
                    }
                    Text(L("Apps", "Apps")).font(.headline)
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(AppCatalog.apps) { app in
                            tile(name: app.name, symbol: app.symbol, color: Color(hex: app.color), link: app.link)
                        }
                    }
                    Text(L("Apps that aren't installed on the TV open its store.", "As apps que a TV não tem abrem a loja."))
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
                .padding(20)
            }
            .navigationTitle(L("Open an app", "Abrir uma app"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func tile(name: String, symbol: String, color: Color, link: String) -> some View {
        Button {
            model.open(link)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color))
                Text(name).font(.caption).foregroundStyle(.white).lineLimit(1)
            }
        }
        .accessibilityIdentifier("app:\(name)")
    }
}
