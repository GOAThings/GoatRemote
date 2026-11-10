import OSLog
import RemoteCore
import SwiftUI
import UIKit

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
