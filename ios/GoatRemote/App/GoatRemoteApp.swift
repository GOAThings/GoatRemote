import SwiftUI

@main
struct GoatRemoteApp: App {
    @State private var model = RemoteModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    // O iOS não deixa a ligação aberta em segundo plano: fecha-se e volta-se a abrir.
                    if phase == .active { model.connect() }
                    if phase == .background { model.disconnect() }
                }
        }
    }
}

struct ContentView: View {
    @Environment(RemoteModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            Theme.background.ignoresSafeArea()
            // Um brilho muito leve em cima, para dar fundo ao vidro.
            RadialGradient(colors: [Theme.accent2.opacity(0.13), Theme.accent.opacity(0.04), .clear],
                           center: .top, startRadius: 10, endRadius: 520)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if model.tvs.isEmpty {
                AddTVView()
            } else {
                RemoteView()
            }
        }
        .tint(Theme.accent)
        .sheet(item: $model.pairing) { pairing in
            PairingSheet(pairing: pairing)
        }
    }
}
