import AppIntents
import SwiftUI
import WidgetKit

/// Só abrem a app: mandar teclas daqui obrigava a partilhar o emparelhamento num App Group, e nem todos os serviços
/// de assinatura os mantêm.
@main
struct GoatRemoteWidgets: WidgetBundle {
    var body: some Widget {
        RemoteWidget()
        if #available(iOS 18.0, *) {
            RemoteControl()
        }
    }
}

/// O botão do Centro de Controlo (também dá para o ecrã bloqueado e o botão de ação).
@available(iOS 18.0, *)
struct RemoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "cc.slokker.goatremote.control") {
            ControlWidgetButton(action: OpenRemote()) {
                Label("GoatRemote", systemImage: "av.remote.fill")
            }
        }
        .displayName("GoatRemote")
        .description(LocalizedStringResource(String.LocalizationValue(L("Opens the remote.", "Abre o comando."))))
    }
}

/// O widget do ecrã principal e do ecrã bloqueado.
struct RemoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "cc.slokker.goatremote.widget", provider: Provider()) { _ in
            RemoteWidgetView()
        }
        .configurationDisplayName("GoatRemote")
        .description(Text(L("Opens the remote.", "Abre o comando.")))
        .supportedFamilies([.systemSmall, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

/// O conteúdo não muda: basta uma entrada.
private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never))
    }
}

private struct SimpleEntry: TimelineEntry {
    let date: Date
}

private struct RemoteWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            Image(systemName: "av.remote.fill")
                .font(.title2)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        } else {
            Color.clear
                .containerBackground(for: .widget) {
                    Image("GoatIcon").resizable().scaledToFill()
                }
        }
    }
}
