import ImageIO
import OSLog
import RemoteCore
import SwiftUI
import UIKit

/// Escrever no campo de texto aberto na TV (aparece sozinho quando a TV abre um).
struct KeyboardSheet: View {
    @Environment(RemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// O que a TV já tem na caixa: põe-se no campo mas não se manda de volta.
    @State private var seeded: String?
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
                .onChange(of: text) { _, new in
                    defer { seeded = nil }
                    if new != seeded { model.type(new) }
                }
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
            seeded = model.state.textValue
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

/// Os canais do GoatTV: o que está a dar, os favoritos, a pesquisa e os grupos, e a lista. Tocar muda de canal e a folha
/// fica aberta, para fazer zapping.
struct ChannelsSheet: View {
    @Environment(RemoteModel.self) private var model
    @State private var query = ""
    @State private var group: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if let problem = model.playProblem {
                        Text(problem).font(.footnote).foregroundStyle(.orange).padding(.bottom, 6)
                            .accessibilityIdentifier("channels-problem")
                    }
                    if let list = model.channels {
                        content(list)
                    } else {
                        state
                    }
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("Channels", "Canais"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { model.refreshChannels() }
    }

    @ViewBuilder
    private func content(_ list: ChannelList) -> some View {
        let groupNames = Dictionary(list.groups.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        if let current = list.channels.first(where: { $0.key == list.current }) {
            nowPlaying(current)
        }
        let favorites = list.channels.filter(\.favorite)
        if !favorites.isEmpty {
            section(L("Favourites", "Favoritos")).padding(.top, 10)
            ForEach(favorites) { row($0, current: $0.key == list.current, group: $0.group.flatMap { groupNames[$0] }) }
        }
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
            TextField(L("Search channels", "Procurar canais"), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("channels-search")
        }
        .padding(12)
        .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: false)
        .padding(.top, 10)
        if !list.groups.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(L("All", "Todos"), selected: group == nil, id: "group:*") { group = nil }
                    ForEach(list.groups) { g in
                        chip(g.name, selected: group == g.id, id: "group:\(g.name)") { group = g.id }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        let shown = filtered(list)
        if shown.isEmpty {
            Text(list.channels.isEmpty ? L("There are no channels in GoatTV's list", "A lista do GoatTV não tem canais")
                                       : L("No channels found", "Nenhum canal encontrado"))
                .font(.subheadline).foregroundStyle(Theme.dim).padding(.vertical, 12)
        }
        ForEach(shown) { row($0, current: $0.key == list.current, group: $0.group.flatMap { groupNames[$0] }) }
        if list.truncated {
            Text(L("The list is too long: only part of it is shown here.", "A lista é longa demais: aqui só aparece uma parte."))
                .font(.caption).foregroundStyle(Theme.dim).padding(.vertical, 8)
        }
    }

    private func filtered(_ list: ChannelList) -> [TVChannel] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return list.channels.filter { ch in
            (group == nil || ch.group == group) &&
                (q.isEmpty || ch.name.localizedCaseInsensitiveContains(q) || (ch.num.map { String($0).hasPrefix(q) } ?? false))
        }
    }

    /// Sem lista: a carregar, o GoatTV fechado (com "Abrir o GoatTV" se der para o abrir daqui) ou uma falha.
    @ViewBuilder
    private var state: some View {
        VStack(spacing: 10) {
            if model.openingGoatTV || model.channelsStatus == .unknown {
                ProgressView().tint(Theme.dim)
            } else if model.channelsStatus == .closed {
                if model.goatTVApp != nil {
                    Text(L("GoatTV isn't open on the TV.", "O GoatTV não está aberto na TV.")).font(.subheadline).foregroundStyle(Theme.dim)
                    Button(L("Open GoatTV", "Abrir o GoatTV")) { model.openGoatTV() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .accessibilityIdentifier("open-goattv")
                } else {
                    Text(model.goatTVClosedLine).font(.subheadline).foregroundStyle(Theme.dim)
                        .accessibilityIdentifier("goattv-closed")
                }
            } else {
                Text(L("Couldn't get the channels from GoatTV.", "Não deu para ter os canais do GoatTV.")).font(.subheadline).foregroundStyle(Theme.dim)
                Button(L("Try again", "Tentar outra vez")) { model.refreshChannels() }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .liquidGlass(RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 12, weight: .bold)).tracking(0.7).foregroundStyle(Theme.faint)
    }

    /// O canal que está a dar, em cartão no topo da lista.
    private func nowPlaying(_ channel: TVChannel) -> some View {
        Button {
            model.play(channel)
        } label: {
            HStack(spacing: 12) {
                ChannelLogoView(channel: channel, size: CGSize(width: 56, height: 38), background: .black.opacity(0.35))
                VStack(alignment: .leading, spacing: 2) {
                    Text((L("Now playing", "A dar agora") + (channel.num.map { " · \($0)" } ?? "")).uppercased())
                        .font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Theme.faint).lineLimit(1)
                    Text(channel.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill").foregroundStyle(Theme.accent)
            }
            .padding(12)
            .background(HeroBackground(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("channel:\(channel.name)")
    }

    private func chip(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(selected ? .bold : .regular)).lineLimit(1)
                .foregroundStyle(selected ? Color.black : Theme.faint)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Color.white : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func row(_ channel: TVChannel, current: Bool, group: String?) -> some View {
        Button {
            model.play(channel)
        } label: {
            HStack(spacing: 12) {
                Text(channel.num.map { String($0) } ?? "")
                    .font(.footnote.monospacedDigit()).foregroundStyle(Theme.faint)
                    .frame(width: 36, alignment: .leading)
                ChannelLogoView(channel: channel)
                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(current ? Theme.accent : Theme.text).lineLimit(1)
                    if let group { Text(group).font(.footnote).foregroundStyle(Theme.faint).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if current {
                    Image(systemName: "play.fill").foregroundStyle(Theme.accent)
                } else if channel.favorite {
                    Image(systemName: "star.fill").font(.footnote).foregroundStyle(Theme.favorite)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(current ? Theme.accent.opacity(0.13) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("channel:\(channel.name)")
    }
}

/// A versão instalada. Tocar procura já uma versão nova (e diz o que encontrou); com uma mais recente, tocar descarrega
/// a IPA e passa-a à app que a assina. Se o download falhar, abre-se a página da versão no GitHub.
struct UpdateRow: View {
    private static let latest = URL(string: "https://api.github.com/repos/GOAThings/GoatRemote/releases/latest")!
    private static let ipa = URL(string: "https://github.com/GOAThings/GoatRemote/releases/latest/download/GoatRemote.ipa")!
    private static let page = URL(string: "https://github.com/GOAThings/GoatRemote/releases/latest")!

    struct Downloaded: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    @State private var newer: String?
    @State private var busy = false
    /// O que se diz por baixo, em vez do número da versão (a procurar, a descarregar, o resultado).
    @State private var note: String?
    @State private var downloaded: Downloaded?

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(newer.map { L("Update to \($0)", "Atualizar para \($0)") } ?? L("Version", "Versão"))
                    .foregroundStyle(newer != nil ? Theme.accent : .white)
                Text(note ?? current)
                    .font(.footnote).foregroundStyle(Theme.dim)
                    .accessibilityIdentifier("opt:update-note")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier("opt:update")
        .task { newer = try? await latestNewer() }
        .sheet(item: $downloaded) { IPAShare(url: $0.url) }
    }

    /// A versão publicada, se for mais recente do que esta (nil: esta é a mais recente); erro se não deu para saber.
    private func latestNewer() async throws -> String? {
        var request = URLRequest(url: Self.latest)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { throw URLError(.badServerResponse) }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return version.compare(current, options: .numeric) == .orderedDescending ? version : nil
    }

    private func tap() {
        if newer != nil { return download() }
        busy = true
        note = L("Checking…", "A procurar…")
        Task {
            defer { busy = false }
            do {
                newer = try await latestNewer()
                note = newer == nil ? L("You have the latest version", "Tens a versão mais recente") : nil
            } catch {
                DebugLog.add("Update check failed: \(error)")
                note = L("Couldn't check for updates", "Não deu para procurar atualizações")
            }
        }
    }

    private func download() {
        busy = true
        note = L("Downloading…", "A descarregar…")
        Task {
            defer { busy = false }
            do {
                let (file, response) = try await URLSession.shared.download(from: Self.ipa)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let target = FileManager.default.temporaryDirectory.appendingPathComponent("GoatRemote.ipa")
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: file, to: target)
                downloaded = Downloaded(url: target)
                note = nil
            } catch {
                DebugLog.add("Update download failed: \(error)")
                note = L("Couldn't download the update", "Não foi possível descarregar a atualização")
                await UIApplication.shared.open(Self.page)
            }
        }
    }
}

private struct IPAShare: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
                    Text(L("Numbers", "Números").uppercased()).font(.system(size: 12, weight: .bold)).tracking(0.7).foregroundStyle(Theme.faint)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                        ForEach(0..<10) { n in
                            let digit = (n + 1) % 10
                            Button { model.press(Key(rawValue: Key.num0.rawValue + digit)!) } label: {
                                Text("\(digit)").font(.title3.weight(.semibold)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: false)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("num:\(digit)")
                        }
                    }
                    Text(L("Options", "Opções").uppercased()).font(.system(size: 12, weight: .bold)).tracking(0.7).foregroundStyle(Theme.faint)
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
                        UpdateRow()
                        Divider()
                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("Diagnostics", "Diagnóstico")).foregroundStyle(.white)
                                    Text(L("What the app did, to send when something fails", "O que a app fez, para mandar quando algo falha"))
                                        .font(.footnote).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.dim)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("opt:diagnostics")
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
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.text)
                Text(title).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .liquidGlass(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false, pressed: pressed)
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("key:\(key)")
        .accessibilityLabel(title)
    }
}

/// O registo de diagnóstico (DebugLog): ver, copiar, partilhar ou limpar. Não sai do telemóvel a não ser que se partilhe.
struct DiagnosticsView: View {
    @State private var text = ""
    @State private var message = ""
    @State private var contact = ""
    @State private var sending = false
    @State private var result: String?
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(L("What happened?", "O que aconteceu?"), text: $message, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("diagnostics:message")
                    Divider()
                    TextField(L("How can we reach you? (optional)", "Como te contactamos? (opcional)"), text: $contact)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            if sending { ProgressView().tint(.white) }
                            Text(L("Send report", "Enviar relatório")).fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(sending)
                    .accessibilityIdentifier("diagnostics:send")
                    if let result {
                        Text(result).font(.footnote).foregroundStyle(.white)
                    }
                }
                .padding(16)
                .liquidGlass(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false)
                Text(L("Never includes PINs, codes or keys. Nothing is sent until you send or share it.",
                       "Nunca tem PINs, códigos nem chaves. Nada sai do telemóvel até o enviares ou partilhares."))
                    .font(.footnote).foregroundStyle(Theme.dim)
                Text(text)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("diagnostics:text")
            }
            .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(L("Diagnostics", "Diagnóstico"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { UIPasteboard.general.string = text } label: { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel(L("Copy", "Copiar"))
                ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityIdentifier("diagnostics:share")
            }
            ToolbarItem(placement: .bottomBar) {
                Button(L("Clear", "Limpar"), role: .destructive) { confirmClear = true }
                    .accessibilityIdentifier("diagnostics:clear")
            }
        }
        .alert(L("Clear the diagnostics log?", "Limpar o registo de diagnóstico?"), isPresented: $confirmClear) {
            Button(L("Clear", "Limpar"), role: .destructive) {
                DebugLog.clear()
                text = DebugLog.text
            }
            Button(L("Cancel", "Cancelar"), role: .cancel) {}
        } message: {
            Text(L("What the app did so far will be gone, and can't be sent in a report.",
                   "O que a app fez até agora desaparece, e já não pode ir num relatório."))
        }
        .onAppear { text = DebugLog.text }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            let id = try await DebugLog.send(message: message, contact: contact)
            result = L("Sent. Report \(id).", "Enviado. Relatório \(id).")
            message = ""
        } catch DebugLog.SendFailure.tooMany {
            result = L("Too many reports from this network. Try again later, or use Share.",
                       "Demasiados relatórios desta rede. Tenta mais tarde, ou usa Partilhar.")
        } catch let error as URLError where error.code == .cannotFindHost || error.code == .dnsLookupFailed {
            // Visto num iPhone: o DNS da rede (filtro no router ou no fornecedor) não encontrava o servidor.
            result = L("This network can't find the GOAT server (its DNS may be blocking it). Try again on mobile data, or use Share.",
                       "Esta rede não encontra o servidor GOAT (o DNS dela pode estar a bloqueá-lo). Tenta com os dados móveis, ou usa Partilhar.")
        } catch DebugLog.SendFailure.http(let status) {
            result = L("Couldn't send (HTTP \(status)). Use Share instead.", "Não deu para enviar (HTTP \(status)). Usa Partilhar.")
        } catch {
            result = L("Couldn't send: \(error.localizedDescription)", "Não deu para enviar: \(error.localizedDescription)")
        }
        text = DebugLog.text
    }
}

/// As TVs: escolher, juntar, emparelhar outra vez e esquecer.
struct TVsSheet: View {
    @Environment(RemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @StateObject private var finder = TVFinder()
    @State private var adding = false
    /// A TV que se vai esquecer, à espera da confirmação.
    @State private var forgetting: SavedTV?

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
                                IconTile(symbol: tv.kind.symbol, tint: tv.id == model.current?.id ? Theme.green : Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tv.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                                    Text(subtitle(tv)).font(.footnote).foregroundStyle(Theme.faint).lineLimit(1)
                                }
                                Spacer()
                                if tv.id == model.current?.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                        // Sem o deslizar até ao fim: esquecer pede sempre confirmação.
                        .swipeActions(allowsFullSwipe: false) {
                            Button(role: .destructive) { forgetting = tv } label: { Label(L("Forget", "Esquecer"), systemImage: "trash") }
                        }
                        .listRowBackground(Theme.card)
                    }
                } footer: {
                    Text(L("Swipe left on a TV to forget it.", "Desliza uma TV para a esquerda para a esquecer."))
                }
                let unpaired = finder.found.filter { found in !model.tvs.contains { $0.id == found.id } }
                if !unpaired.isEmpty {
                    Section(L("On this network", "Nesta rede")) {
                        ForEach(unpaired) { found in FoundTVRow(found: found).listRowBackground(Theme.card) }
                    }
                }
                Section {
                    Button { adding = true } label: { actionLabel(L("Add a TV", "Juntar uma TV"), "plus") }
                        .listRowBackground(Theme.card)
                    if model.current != nil {
                        Button {
                            model.repairCurrent()
                        } label: { actionLabel(L("Pair this TV again", "Emparelhar esta TV outra vez"), "link") }
                            .listRowBackground(Theme.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(L("TVs", "TVs"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $adding) { AddTVView(onDone: { adding = false }) }
            .alert(forgetting.map { L("Forget \($0.name)?", "Esquecer \($0.name)?") } ?? "",
                   isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
                   presenting: forgetting) { tv in
                Button(L("Forget", "Esquecer"), role: .destructive) { model.forget(tv) }
                Button(L("Cancel", "Cancelar"), role: .cancel) {}
            } message: { _ in
                Text(L("To use it again, you'll have to pair it again.", "Para a voltares a usar, tens de a emparelhar outra vez."))
            }
        }
        .onAppear { finder.start() }
        .onDisappear { finder.stop() }
        .onChange(of: finder.found) { _, found in model.relocate(found) }
    }

    private func actionLabel(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: Theme.accent)
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
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

/// Uma TV encontrada na rede e ainda por emparelhar: tocar emparelha.
struct FoundTVRow: View {
    @Environment(RemoteModel.self) private var model
    let found: FoundTV

    var body: some View {
        Button {
            model.startPairing(found)
        } label: {
            HStack(spacing: 12) {
                IconTile(symbol: found.kind.symbol, tint: Theme.accent2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(found.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(found.kind == .apple ? "Apple TV" : "Android TV · Google TV").font(.footnote).foregroundStyle(Theme.faint)
                }
                Spacer()
                Text(L("Pair", "Emparelhar")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            }
        }
        .accessibilityIdentifier("found:\(found.name)")
    }
}

/// Uma imagem da rede (banners do GoatLauncher, ícones da App Store, logótipos do GoatTV), guardada em memória. O
/// AsyncImage cancelava os pedidos dentro da grelha das apps e ficava sem imagem.
struct RemoteImage<Content: View>: View {
    let url: URL
    /// Os logótipos dos canais têm limites mais pequenos do que os banners.
    var limit = 4 << 20
    var maxPixelSize = 1024
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
                let side = maxPixelSize
                do {
                    let (data, status) = try await BoundedHTTP.get(request, limit: limit)
                    let decoded = await Task.detached(priority: .userInitiated) { ImageCache.decode(data, maxPixelSize: side) }.value
                    guard status == 200, let loaded = decoded else {
                        imageLog.error("\(url.absoluteString, privacy: .public): \(status) \(data.count) bytes")
                        return
                    }
                    Self.cache.setObject(loaded, forKey: url as NSURL, cost: Int(loaded.size.width * loaded.size.height) * 4)
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
        cache.totalCostLimit = 32 << 20
        return cache
    }()

    /// Lê primeiro o tamanho e reduz o que for maior do que alguma vez se mostra.
    static func decode(_ data: Data, maxPixelSize: Int = 1024) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions as CFDictionary) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}

/// Um símbolo num quadrado com a cor dele, como nas Definições do GoatTV.
struct IconTile: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.16)))
    }
}
