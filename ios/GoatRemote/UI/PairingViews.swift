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
                    if finder.found.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(L("Looking for TVs on this network…", "À procura de TVs nesta rede…")).foregroundStyle(Theme.dim)
                        }
                    }
                    ForEach(finder.found) { tv in
                        if model.tvs.contains(where: { $0.id == tv.id }) {
                            HStack(spacing: 12) {
                                Image(systemName: tv.kind.symbol).foregroundStyle(Theme.accent).frame(width: 28)
                                Text(tv.name).foregroundStyle(.white)
                                Spacer()
                                Text(L("Paired", "Emparelhada")).font(.caption).foregroundStyle(Theme.dim)
                            }
                        } else {
                            FoundTVRow(found: tv)
                        }
                    }
                } header: {
                    Text(L("On this network", "Nesta rede"))
                } footer: {
                    Text(L("Android TV, Google TV (SHIELD, Sony, Philips, TCL, Chromecast…) and Apple TV. The TV and the iPhone must be on the same Wi-Fi.",
                           "Android TV, Google TV (SHIELD, Sony, Philips, TCL, Chromecast…) e Apple TV. A TV e o iPhone têm de estar na mesma rede Wi-Fi."))
                }
                Section(L("Or by IP address", "Ou pelo endereço IP")) {
                    HStack {
                        TextField("192.168.1.50", text: $manualIP)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("manual-ip")
                        Button(L("Pair", "Emparelhar")) {
                            let ip = manualIP.trimmingCharacters(in: .whitespaces)
                            model.startPairing(name: ip, id: ip, host: ip, endpoint: nil)
                        }
                        .disabled(manualIP.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle(L("Add a TV", "Juntar uma TV"))
            .toolbar {
                if let onDone, !model.tvs.isEmpty {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Close", "Fechar"), action: onDone) }
                }
                // Antes de haver uma TV não há o Mais: o diagnóstico fica aqui também.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { DiagnosticsView() } label: { Image(systemName: "ladybug") }
                        .accessibilityLabel(L("Diagnostics", "Diagnóstico"))
                        .accessibilityIdentifier("add:diagnostics")
                }
            }
        }
        .onAppear { finder.start() }
        .onDisappear { finder.stop() }
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
                ProgressView(L("Connecting to the TV…", "A ligar à TV…"))
            case .waitingCode(let retry):
                Text(retry
                     ? L("That code doesn't match. Check the one on the TV.", "Esse código não bate certo. Vê o que está na TV.")
                     : pairing.kind == .apple
                        ? L("Type the PIN shown on the TV.", "Escreve o PIN que aparece na TV.")
                        : L("Type the code shown on the TV.", "Escreve o código que aparece na TV."))
                    .foregroundStyle(retry ? Theme.power : Theme.dim)
                    .multilineTextAlignment(.center)
                codeField
            case .checking:
                ProgressView(L("Pairing…", "A emparelhar…"))
            case .done:
                Label(L("Paired", "Emparelhado"), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
            case .failed(let why):
                Text(why).foregroundStyle(Theme.power).multilineTextAlignment(.center)
                Button(L("Try again", "Tentar outra vez")) { pairing.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                Button(L("Send a report", "Enviar relatório")) { diagnostics = true }
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("pairing:report")
            }
            Spacer()
            Button(L("Cancel", "Cancelar")) {
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
        .onDisappear { if pairing.phase != .done { pairing.cancel() } }
        .onChange(of: pairing.phase) { _, phase in
            if case .waitingCode = phase {
                code = ""
                focused = true
            }
            if phase == .done {
                Task {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    model.pairing = nil
                }
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
