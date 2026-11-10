import Foundation
import RemoteCore

/// O único caminho do volume (o comando, manter carregado, os botões do iPhone, os Atalhos): decide por onde vai cada
/// tecla (VolumeRoute) e, pelo GoatLauncher, o que fazer com a resposta (LauncherVolume.outcome), guardando o que se
/// fica a saber do launcher. Nunca manda a tecla: diz a quem chama se pode.
enum VolumeRouter {
    static func route(_ tv: SavedTV?, _ key: Key, _ press: VolumeRoute.Press, volumeControl: Bool) -> VolumeRoute {
        guard let tv else { return .key }
        return VolumeRoute.of(key, press, kind: tv.kind, known: LauncherMemory.known(tv.id), volumeControl: volumeControl)
    }

    /// O que o launcher respondeu: `.noLauncher` é a única vez em que a tecla pode ir.
    struct Sent {
        let outcome: LauncherVolume.Outcome
        let status: Int
        let refused: Bool
    }

    /// POST /volume/…; nil se a tecla não é de volume.
    @MainActor
    static func viaLauncher(_ tv: SavedTV, _ key: Key) async -> Sent? {
        guard let what = LauncherVolume.path(key) else { return nil }
        let (status, refused) = await LauncherApi(host: tv.host).volume(what)
        let outcome = LauncherVolume.outcome(known: LauncherMemory.known(tv.id), status: status, refused: refused)
        switch outcome {
        case .done:
            LauncherMemory.set(tv.id, true)
        case .noLauncher:
            DebugLog.add("Volume: no launcher on \(tv.name) (\(refused ? "refused" : "404")), using keys")
            LauncherMemory.set(tv.id, false)
        case .didntAnswer:
            DebugLog.add("Volume: launcher on \(tv.name) didn't answer (HTTP \(status)), not sending the key")
        }
        return Sent(outcome: outcome, status: status, refused: refused)
    }
}
