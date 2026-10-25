import OSLog
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

/// Abrir apps. Com o GoatLauncher na TV: as instaladas, com os banners dela. Sem ele, só as que já se viu abertas
/// nesta TV (nunca uma lista inventada de apps que a TV pode não ter).
struct AppsSheet: View {
    @Environment(RemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.installedApps.isEmpty {
                        seenOnly
                    } else {
                        installed
                    }
                }
                .padding(18)
            }
            .navigationTitle(L("Apps", "Apps"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { model.refreshApps() }
    }

    /// As apps da TV, as abertas há pouco primeiro.
    @ViewBuilder
    private var installed: some View {
        let byPackage = Dictionary(model.installedApps.map { ($0.package, $0) }, uniquingKeysWith: { a, _ in a })
        let recent = model.recentApps.compactMap { byPackage[$0] }.prefix(4)
        if !recent.isEmpty {
            section(L("Recently opened", "Abertas há pouco"))
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(recent)) { app in tile(app) }
            }
            section(L("All apps", "Todas as apps")).padding(.top, 6)
        }
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(model.installedApps) { app in tile(app) }
        }
    }

    /// Sem GoatLauncher: as apps vistas nesta TV e como ter a lista toda.
    @ViewBuilder
    private var seenOnly: some View {
        if !model.recentApps.isEmpty {
            section(L("Opened on this TV", "Abertas nesta TV"))
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.recentApps, id: \.self) { package in
                    let known = AppCatalog.app(package)
                    tile(TVApp(package: package, label: AppCatalog.name(package), banner: false,
                               color: known.map { String(format: "#%06X", $0.color) }), symbol: known?.symbol ?? "app.fill", remoteImage: false)
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            Label(L("All the TV's apps here", "Todas as apps da TV aqui"), systemImage: "square.grid.2x2")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(model.recentApps.isEmpty
                 ? L("Android TVs don't share their app list with the remote. Apps show up here as you open them on the TV, or all of them, with their banners, if the TV has GoatLauncher.",
                     "As Android TV não dão a lista de apps ao comando. As apps vão aparecendo aqui à medida que as abres na TV, ou todas, com os banners, se a TV tiver o GoatLauncher.")
                 : L("With GoatLauncher on the TV, all its apps show up here, with their banners.",
                     "Com o GoatLauncher na TV, aparecem aqui todas as apps dela, com os banners."))
                .font(.footnote)
                .foregroundStyle(Theme.dim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
        .padding(.top, 4)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.dim)
    }

    private func tile(_ app: TVApp, symbol: String = "app.fill", remoteImage: Bool = true) -> some View {
        Button {
            model.launch(app)
            dismiss()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [app.tint, app.tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if remoteImage, let url = model.iconURL(app.package) {
                    RemoteImage(url: url) { image in
                        if let image {
                            if app.banner {
                                image.resizable().scaledToFill().accessibilityIdentifier("banner")
                            } else {
                                VStack(spacing: 6) {
                                    image.resizable().scaledToFit().frame(width: 46, height: 46).accessibilityIdentifier("banner")
                                    Text(app.label).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                                }
                            }
                        } else {
                            fallback(app, symbol: symbol)
                        }
                    }
                } else {
                    fallback(app, symbol: symbol)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("app:\(app.label)")
    }

    private func fallback(_ app: TVApp, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 24, weight: .semibold))
            Text(app.label).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
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
                        key(.audioTrack, "waveform", L("Audio", "Áudio"))
                        key(.lastChannel, "arrow.uturn.backward.circle", L("Last ch", "Último can"))
                        key(.input, "rectangle.connected.to.line.below", L("Input", "Entrada"))
                        key(.settings, "gearshape", L("Settings", "Definições"))
                        key(.stop, "stop.fill", "Stop")
                        key(.previous, "backward.end.fill", L("Previous", "Anterior"))
                        key(.next, "forward.end.fill", L("Next", "Seguinte"))
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
    @StateObject private var finder = TVFinder()
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
                                Image(systemName: tv.kind.symbol).foregroundStyle(Theme.accent).frame(width: 28)
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
                let unpaired = finder.found.filter { found in !model.tvs.contains { $0.id == found.id } }
                if !unpaired.isEmpty {
                    Section(L("On this network", "Nesta rede")) {
                        ForEach(unpaired) { found in FoundTVRow(found: found) }
                    }
                }
                Section {
                    Button { adding = true } label: { Label(L("Add a TV", "Juntar uma TV"), systemImage: "plus") }
                    if model.current != nil {
                        Button {
                            model.repairCurrent()
                        } label: { Label(L("Pair this TV again", "Emparelhar esta TV outra vez"), systemImage: "link") }
                    }
                }
            }
            .navigationTitle(L("TVs", "TVs"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $adding) { AddTVView(onDone: { adding = false }) }
        }
        .onAppear { finder.start() }
        .onDisappear { finder.stop() }
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

/// Uma TV encontrada na rede e ainda por emparelhar: tocar emparelha.
struct FoundTVRow: View {
    @Environment(RemoteModel.self) private var model
    let found: FoundTV

    var body: some View {
        Button {
            model.startPairing(found)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: found.kind.symbol).foregroundStyle(Theme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(found.name).foregroundStyle(.white)
                    Text(found.kind == .apple ? "Apple TV" : "Android TV · Google TV").font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                if found.kind == .apple && !RemoteModel.appleTVReady {
                    Text(L("Soon", "Em breve")).font(.caption).foregroundStyle(Theme.dim)
                } else {
                    Text(L("Pair", "Emparelhar")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
        }
        .disabled(found.kind == .apple && !RemoteModel.appleTVReady)
        .accessibilityIdentifier("found:\(found.name)")
    }
}

/// Uma imagem da rede (banners do GoatLauncher, ícones da App Store), guardada em memória. O AsyncImage cancelava
/// os pedidos dentro da grelha das apps e ficava sem imagem.
struct RemoteImage<Content: View>: View {
    let url: URL
    @ViewBuilder let content: (Image?) -> Content
    @State private var image: UIImage?

    var body: some View {
        content(image.map { Image(uiImage: $0) })
            .task(id: url) {
                if let cached = Self.cache.object(forKey: url as NSURL) {
                    image = cached
                    return
                }
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200, let loaded = UIImage(data: data) else {
                        imageLog.error("\(url.absoluteString, privacy: .public): \(status) \(data.count) bytes")
                        return
                    }
                    Self.cache.setObject(loaded, forKey: url as NSURL)
                    image = loaded
                } catch {
                    imageLog.error("\(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
    }

    private static var cache: NSCache<NSURL, UIImage> { ImageCache.shared }
}

private let imageLog = Logger(subsystem: "cc.slokker.goatremote", category: "images")

private enum ImageCache {
    nonisolated(unsafe) static let shared: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 64
        return cache
    }()
}
