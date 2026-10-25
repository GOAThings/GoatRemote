import RemoteCore
import SwiftUI

/// Escrever no campo de texto aberto na TV (aparece sozinho quando a TV abre um).
struct KeyboardSheet: View {
    @Environment(RemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.state.textLabel ?? L("Type on the TV", "Escrever na TV")).font(.headline)
            TextField(L("Search, password…", "Pesquisa, palavra-passe…"), text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(14)
                .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: false)
                .submitLabel(.send)
                .onSubmit(send)
                .onChange(of: text) { _, new in model.type(new) }
                .accessibilityIdentifier("keyboard-field")
            HStack {
                Button(L("Clear", "Limpar")) { text = "" }
                    .disabled(text.isEmpty)
                Spacer()
                Button(L("Send", "Enviar"), action: send)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .accessibilityIdentifier("send-text")
            }
        }
        .padding(20)
        .onAppear {
            text = model.state.textValue
            focused = true
        }
    }

    private func send() {
        model.press(.enter)
        dismiss()
    }
}

/// Abrir apps: as que se viu abertas nesta TV e as conhecidas, em mosaicos.
struct AppsSheet: View {
    @Environment(RemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let recents = model.recentApps.filter { AppCatalog.app($0) == nil }
                    if !recents.isEmpty {
                        Text(L("Recently opened", "Abertas há pouco")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.dim)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(recents, id: \.self) { package in
                                tile(name: AppCatalog.name(package), symbol: "app.fill", color: Theme.surfaceHigh, link: "market://launch?id=\(package)")
                            }
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(AppCatalog.apps) { app in
                            tile(name: app.name, symbol: app.symbol, color: Color(hex: app.color), link: app.link)
                        }
                    }
                    Text(L("If the TV doesn't have the app, it opens its store.", "Se a TV não tiver a app, abre a loja."))
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
                .padding(18)
            }
            .navigationTitle(L("Apps", "Apps"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func tile(name: String, symbol: String, color: Color, link: String) -> some View {
        Button {
            model.open(link)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                Text(name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 76)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("app:\(name)")
    }
}

/// As teclas que não cabem no comando, os números e as opções.
struct MoreSheet: View {
    @Environment(RemoteModel.self) private var model
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        key(.volumeDown, "speaker.minus.fill", L("Vol −", "Vol −"))
                        key(.volumeUp, "speaker.plus.fill", L("Vol +", "Vol +"))
                        key(.channelDown, "chevron.down.2", L("Ch −", "Can −"))
                        key(.channelUp, "chevron.up.2", L("Ch +", "Can +"))
                        key(.search, "magnifyingglass", L("Search", "Pesquisa"))
                        key(.menu, "line.3.horizontal", "Menu")
                        key(.guide, "list.bullet.rectangle", L("Guide", "Guia"))
                        key(.info, "info.circle", "Info")
                        key(.captions, "captions.bubble", L("Subtitles", "Legendas"))
                        key(.input, "rectangle.connected.to.line.below", L("Input", "Entrada"))
                        key(.settings, "gearshape", L("Settings", "Definições"))
                        key(.stop, "stop.fill", "Stop")
                    }
                    Text(L("Numbers", "Números")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.dim)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                        ForEach(0..<10) { n in
                            let digit = (n + 1) % 10
                            Button { model.press(Key(rawValue: Key.num0.rawValue + digit)!) } label: {
                                Text("\(digit)").font(.title3.weight(.semibold)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("num:\(digit)")
                        }
                    }
                    Text(L("Options", "Opções")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.dim)
                    VStack(spacing: 0) {
                        Toggle(L("Vibration", "Vibração"), isOn: $model.haptics)
                            .padding(.vertical, 12)
                        Divider()
                        Toggle(isOn: $model.volumeButtons) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("iPhone volume buttons", "Botões de volume do iPhone"))
                                Text(L("Change the TV's volume while the app is open", "Mexem no volume da TV com a app aberta"))
                                    .font(.footnote).foregroundStyle(Theme.dim)
                            }
                        }
                        .padding(.vertical, 12)
                        Divider()
                        Toggle(isOn: $model.dpadTaps) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("Arrows on the edges", "Setas nas bordas"))
                                Text(L("Tap near an edge of the touch surface for that arrow", "Tocar perto de uma borda da superfície carrega nessa seta"))
                                    .font(.footnote).foregroundStyle(Theme.dim)
                            }
                        }
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("opt:dpad")
                    }
                    .padding(.horizontal, 16)
                    .liquidGlass(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false)
                    .tint(Theme.accent)
                }
                .padding(18)
            }
            .navigationTitle(L("More", "Mais"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func key(_ key: Key, _ symbol: String, _ title: String) -> some View {
        PressArea(onTap: { model.press(key) }, onHold: { model.hold(key, down: $0) }) { pressed in
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                Text(title).font(.caption2).lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 68)
            .liquidGlass(RoundedRectangle(cornerRadius: 16, style: .continuous), pressed: pressed)
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("key:\(key)")
        .accessibilityLabel(title)
    }
}

/// As TVs: escolher, juntar, emparelhar outra vez e esquecer.
struct TVsSheet: View {
    @Environment(RemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.tvs) { tv in
                        Button {
                            model.select(tv)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tv").foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tv.name).foregroundStyle(.white)
                                    Text(subtitle(tv)).font(.caption).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                if tv.id == model.current?.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { model.forget(tv) } label: { Label(L("Forget", "Esquecer"), systemImage: "trash") }
                        }
                    }
                } footer: {
                    Text(L("Swipe left on a TV to forget it.", "Desliza uma TV para a esquerda para a esquecer."))
                }
                Section {
                    Button { adding = true } label: { Label(L("Add a TV", "Juntar uma TV"), systemImage: "plus") }
                    if model.current != nil {
                        Button {
                            dismiss()
                            model.repairCurrent()
                        } label: { Label(L("Pair this TV again", "Emparelhar esta TV outra vez"), systemImage: "link") }
                    }
                }
            }
            .navigationTitle(L("TVs", "TVs"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $adding) { AddTVView(onDone: { adding = false }) }
        }
    }

    private func subtitle(_ tv: SavedTV) -> String {
        guard tv.id == model.current?.id else { return tv.host }
        var parts = [tv.host]
        if let vendor = model.state.vendor, let m = model.state.model { parts.append("\(vendor) \(m)") }
        switch model.status {
        case .connected: parts.append(L("connected", "ligada"))
        case .connecting: parts.append(L("connecting", "a ligar"))
        default: break
        }
        return parts.joined(separator: " · ")
    }
}
