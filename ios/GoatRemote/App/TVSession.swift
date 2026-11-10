import Foundation
import Observation
import RemoteCore

/// Tudo o que é de uma TV: a ligação e o que ela conta, as apps, os canais, o que está a dar, o indicador do volume e
/// as tentativas, e os trabalhos em curso. Mudar de TV, emparelhar ou esquecer cria uma sessão nova e fecha a anterior
/// inteira: nada de uma TV passa para a outra (antes era uma lista de campos a limpar à mão, B2/B3).
@MainActor
@Observable
final class TVSession {
    /// A TV desta sessão (nil: não há nenhuma).
    let tvID: String?

    var status: RemoteModel.Status
    var state = TVState()
    var recentApps: [String]
    var installedApps: [TVApp] = []
    var hasChannels: Bool
    var channels: ChannelList?
    var channelsStatus: RemoteModel.ChannelsStatus = .unknown
    var openingGoatTV = false
    var playProblem: String?
    var nowInfo: NowInfo?
    var volumePressed: Key?
    var volumeProblem: String?
    /// Ícones das apps da Apple TV (da App Store, por bundle id).
    var appleArtwork: [String: URL] = [:]

    @ObservationIgnored var link: TVControl?
    @ObservationIgnored var autoReconnect: Task<Void, Never>?
    @ObservationIgnored var lastAutoReconnect = Date.distantPast
    /// Recusas seguidas desta TV que ainda não se mostraram.
    @ObservationIgnored var notPairedRetries = 0
    @ObservationIgnored var volumeSettlesAt = Date.distantPast
    /// O GoatTV desta TV não tem o /now (responde 404): até voltar a ligar, não se pergunta.
    @ObservationIgnored var withoutNow = false
    /// O pedido da lista em curso: trocar de TV cancela-o em vez de esperar por ele.
    @ObservationIgnored var channelsTask: (id: UUID, task: Task<Void, Never>)?
    @ObservationIgnored var playTask: Task<Void, Never>?
    /// As teclas mantidas desta TV (ver KeyHold).
    let keyHold = KeyHold()

    init(tvID: String?, status: RemoteModel.Status, recents: [String], hasChannels: Bool) {
        self.tvID = tvID
        self.status = status
        self.recentApps = recents
        self.hasChannels = hasChannels
    }

    func close() {
        autoReconnect?.cancel()
        channelsTask?.task.cancel()
        playTask?.cancel()
        keyHold.end()
        link?.close()
        link = nil
    }
}
