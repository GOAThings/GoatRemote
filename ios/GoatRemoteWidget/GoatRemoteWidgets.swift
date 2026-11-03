import SwiftUI
import WidgetKit

/// Só abre a app. Sem botão do Centro de Controlo: assinado no Signulous, o iOS não prepara a ação do controlo e a
/// extensão crasha ("Can't create CHSIntentReference"). O iOS já tem um controlo próprio para abrir apps.
@main
struct GoatRemoteWidgets: WidgetBundle {
    var body: some Widget {
        RemoteWidget()
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
            Image("goatremote.logo")
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
