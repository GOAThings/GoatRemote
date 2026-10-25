import AVFoundation
import MediaPlayer
import SwiftUI

/// Os botões de volume do iPhone a mexer no volume da TV (como o comando da Apple TV), com a app aberta.
///
/// O iOS não dá os botões às apps: põe-se o volume do iPhone a meio, ouve-se quando muda (subiu ou desceu) e volta-se
/// a pô-lo a meio. Uma MPVolumeView quase invisível esconde o indicador de volume do sistema e deixa mexer no
/// volume. Ao sair, o volume do iPhone volta ao que estava.
struct VolumeButtonsHost: UIViewRepresentable {
    let onStep: (_ up: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onStep: onStep) }

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.alpha = 0.01
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        context.coordinator.onStep = onStep
    }

    static func dismantleUIView(_ view: MPVolumeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        var onStep: (Bool) -> Void
        private var observation: NSKeyValueObservation?
        private weak var slider: UISlider?
        private var original: Float?
        private let middle: Float = 0.5

        init(onStep: @escaping (Bool) -> Void) {
            self.onStep = onStep
        }

        func attach(_ view: MPVolumeView) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setActive(true)
            original = session.outputVolume
            // A MPVolumeView só tem o UISlider depois de estar no ecrã.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak view] in
                guard let self else { return }
                self.slider = view?.subviews.compactMap { $0 as? UISlider }.first
                self.slider?.value = self.middle
            }
            observation = session.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
                guard let new = change.newValue, let old = change.oldValue, new != old else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    // Fomos nós a pô-lo a meio: não é um botão.
                    if abs(new - self.middle) < 0.001 { return }
                    self.onStep(new > old)
                    self.slider?.value = self.middle
                }
            }
        }

        func detach() {
            observation?.invalidate()
            observation = nil
            if let original { slider?.value = original }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
