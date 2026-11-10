import RemoteCore
import SwiftUI

/// Escolher uma TV para emparelhar: as que se anunciam na rede, ou um IP escrito à mão.
struct AddTVView: View {
    @Environment(RemoteModel.self) private var model
    @StateObject private var finder = TVFinder()
    @State private var manualIP = ""
    var onDone: (() -> Void)?

    init(onDone: (() -> Void)? = nil) {
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if finder.found.isEmpty, finder.blocked {
                        // Sem a autorização da rede local, o iOS não deixa procurar: diz-se onde a dar.
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Strings.goatremoteCantLookForTvsAllow)
                                .foregroundStyle(Theme.dim)
                            Button(Strings.openSettings) {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                            .foregroundStyle(Theme.accent)
                            .accessibilityIdentifier("add:settings")
                        }
                    } else if finder.found.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(Strings.lookingForTvsOnThisNetwork).foregroundStyle(Theme.dim)
                        }
                    }
                    ForEach(finder.found) { tv in
                        if model.tvs.contains(where: { $0.id == tv.id }) {
                            HStack(spacing: 12) {
                                Image(systemName: tv.kind.symbol).foregroundStyle(Theme.accent).frame(width: 28)
                                Text(tv.name).foregroundStyle(.white)
                                Spacer()
                                Text(Strings.pairedF).font(.caption).foregroundStyle(Theme.dim)
                            }
                        } else {
                            FoundTVRow(found: tv)
                        }
                    }
                } header: {
                    Text(Strings.onThisNetwork)
                } footer: {
                    Text(Strings.androidTvGoogleTvShieldSony)
                }
                Section(Strings.orByIpAddress) {
                    HStack {
                        TextField("192.168.1.50", text: $manualIP)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("manual-ip")
                        Button(Strings.pair) {
                            let ip = manualIP.trimmingCharacters(in: .whitespaces)
                            model.startPairing(name: ip, id: ip, host: ip, endpoint: nil)
                        }
                        .disabled(manualIP.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle(Strings.addATv)
            .toolbar {
                if let onDone, !model.tvs.isEmpty {
                    ToolbarItem(placement: .cancellationAction) { Button(Strings.close, action: onDone) }
                }
                // Antes de haver uma TV não há o Mais: o diagnóstico fica aqui também.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { DiagnosticsView() } label: { Image(systemName: "ladybug") }
                        .accessibilityLabel(Strings.diagnostics)
                        .accessibilityIdentifier("add:diagnostics")
                }
            }
        }
        .onAppear { finder.start() }
        .onDisappear { finder.stop() }
        .onChange(of: finder.found) { _, found in model.relocate(found) }
        .onChange(of: model.current?.id) { _, _ in if model.pairing == nil { onDone?() } }
    }
}

/// O emparelhamento: a TV mostra um código de 6 caracteres e escreve-se aqui.
struct PairingSheet: View {
    @Environment(RemoteModel.self) private var model
    let pairing: PairingModel
    @State private var code = ""
    @State private var diagnostics = false
    @FocusState private var focused: Bool

    init(pairing: PairingModel) {
        self.pairing = pairing
    }

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "tv.and.mediabox").font(.system(size: 44)).foregroundStyle(Theme.gradient)
            Text(pairing.name).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            switch pairing.phase {
            case .connecting:
                ProgressView(Strings.connectingToTheTv)
            case .waitingCode(let retry):
                Text(retry
                     ? Strings.thatCodeDoesntMatchCheckThe
                     : pairing.kind == .apple
                        ? Strings.typeThePinShownOnThe
                        : Strings.typeTheCodeShownOnThe)
                    .foregroundStyle(retry ? Theme.power : Theme.dim)
                    .multilineTextAlignment(.center)
                codeField
                // Algumas Apple TV (tvOS 26/27) entram em modo de PIN mas não o mostram: tenta-se pelo AirPlay.
                if pairing.kind == .apple, !pairing.usingAirPlay {
                    Button(Strings.noPinOnTheTv) { pairing.useAirPlay() }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("pairing:airplay")
                }
            case .checking:
                ProgressView(Strings.pairing)
            case .done:
                Label(Strings.pairedM, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
            case .failed(let why):
                Text(why).foregroundStyle(Theme.power).multilineTextAlignment(.center)
                Button(Strings.tryAgain) { pairing.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                Button(Strings.sendAReport) { diagnostics = true }
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("pairing:report")
            }
            Spacer()
            Button(Strings.cancel) {
                DebugLog.add("Pairing: Cancel tapped")
                pairing.cancel()
                model.pairing = nil
            }
            .foregroundStyle(Theme.dim)
        }
        .padding(28)
        .presentationDetents([.medium])
        .sheet(isPresented: $diagnostics) {
            NavigationStack { DiagnosticsView() }
                .preferredColorScheme(.dark)
        }
        .interactiveDismissDisabled(pairing.phase == .checking)
        .onDisappear {
            guard pairing.phase != .done else { return }
            DebugLog.add("Pairing: sheet closed (\(pairing.phase))")
            pairing.cancel()
        }
        .onChange(of: pairing.phase) { _, phase in
            if case .waitingCode = phase {
                code = ""
                focused = true
            }
        }
    }

    private var codeField: some View {
        TextField(pairing.kind == .apple ? "1234" : "A1B2C3", text: $code)
            .font(.system(size: 34, weight: .semibold, design: .monospaced))
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(pairing.kind == .apple ? .numberPad : .asciiCapable)
            .focused($focused)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            .onAppear { focused = true }
            .onChange(of: code) { _, new in
                let allowed: (Character) -> Bool = pairing.kind == .apple ? { $0.isNumber } : { $0.isHexDigit }
                let clean = String(new.uppercased().filter(allowed).prefix(pairing.codeLength))
                if clean != new { code = clean }
                if clean.count == pairing.codeLength { pairing.submit(clean) }
            }
            .accessibilityIdentifier("code-field")
    }
}
