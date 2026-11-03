import AppIntents

/// Abre a app. Compila na app e na extensão dos widgets: o iOS só abre a app se a intenção existir nas duas.
struct OpenRemote: AppIntent {
    static let title: LocalizedStringResource = "Open GoatRemote"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        .result()
    }
}
