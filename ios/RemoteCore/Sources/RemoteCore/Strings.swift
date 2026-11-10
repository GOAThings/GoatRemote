import Foundation

/// Os textos fixos da app, com os mesmos nomes que no Android (Strings.kt) e conferidos por contracts/strings.json. Cada
/// um escolhe a língua quando se lê, como o L() que estava em cada sítio (inglês ou português, conforme a língua do iPhone).
public enum Strings {
    /// Só para os testes (em Linux não há língua do iPhone).
    public static var moveUp: String { pick("Up", "Cima") }
    public static var moveDown: String { pick("Down", "Baixo") }
    public static var moveLeft: String { pick("Left", "Esquerda") }
    public static var moveRight: String { pick("Right", "Direita") }
    public static var select: String { pick("Select", "Escolher") }
    public static var language: String?

    public static func pick(_ en: String, _ pt: String) -> String {
        (language ?? Locale.preferredLanguages.first)?.lowercased().hasPrefix("pt") == true ? pt : en
    }

    public static var aFewMinutes: String { pick("a few minutes", "uns minutos") }
    public static var addATv: String { pick("Add a TV", "Juntar uma TV") }
    public static var all: String { pick("All", "Todos") }
    public static var allApps: String { pick("All apps", "Todas as apps") }
    public static var allTheTvsAppsHere: String { pick("All the TV's apps here", "Todas as apps da TV aqui") }
    public static var androidTvGoogleTvShieldSony: String { pick("Android TV, Google TV (SHIELD, Sony, Philips, TCL, Chromecast…) and Apple TV. The TV and the iPhone must be on the same Wi-Fi.", "Android TV, Google TV (SHIELD, Sony, Philips, TCL, Chromecast…) e Apple TV. A TV e o iPhone têm de estar na mesma rede Wi-Fi.") }
    public static var androidTvsDontShareTheirApp: String { pick("Android TVs don't share their app list with the remote. Apps show up here as you open them on the TV, or all of them, with their banners, if the TV has GoatLauncher.", "As Android TV não dão a lista de apps ao comando. As apps vão aparecendo aqui à medida que as abres na TV, ou todas, com os banners, se a TV tiver o GoatLauncher.") }
    public static var apps: String { pick("Apps", "Apps") }
    public static var arrows: String { pick("Arrows", "Setas") }
    public static var audio: String { pick("Audio", "Áudio") }
    public static var back: String { pick("Back", "Voltar") }
    public static var cancel: String { pick("Cancel", "Cancelar") }
    public static var cantReachIt: String { pick("Can't reach it", "Sem ligação") }
    public static var cantReachTheTv: String { pick("Can't reach the TV", "Não chego à TV") }
    public static var changeTheTvsVolumeWhileThe: String { pick("Change the TV's volume while the app is open", "Mexem no volume da TV com a app aberta") }
    public static var channelDown: String { pick("Ch −", "Can −") }
    public static var channelUp: String { pick("Ch +", "Can +") }
    public static var channels: String { pick("Channels", "Canais") }
    public static var checking: String { pick("Checking…", "A procurar…") }
    public static var clear: String { pick("Clear", "Limpar") }
    public static var clearTheDiagnosticsLog: String { pick("Clear the diagnostics log?", "Limpar o registo de diagnóstico?") }
    public static var close: String { pick("Close", "Fechar") }
    public static var connected: String { pick("connected", "ligada") }
    public static var connecting: String { pick("Connecting…", "A ligar…") }
    public static var connectingLower: String { pick("connecting", "a ligar") }
    public static var connectingToTheTv: String { pick("Connecting to the TV…", "A ligar à TV…") }
    public static var copy: String { pick("Copy", "Copiar") }
    public static var couldntCheckForUpdates: String { pick("Couldn't check for updates", "Não deu para procurar atualizações") }
    public static var couldntDownloadTheUpdate: String { pick("Couldn't download the update", "Não foi possível descarregar a atualização") }
    public static var couldntFindTheTvOnThe: String { pick("Couldn't find the TV on the network", "Não deu para encontrar a TV na rede") }
    public static var couldntGetTheChannelsFromGoattv: String { pick("Couldn't get the channels from GoatTV.", "Não deu para ter os canais do GoatTV.") }
    public static var diagnostics: String { pick("Diagnostics", "Diagnóstico") }
    public static var downloading: String { pick("Downloading…", "A descarregar…") }
    public static var favourites: String { pick("Favourites", "Favoritos") }
    public static var forget: String { pick("Forget", "Esquecer") }
    public static var forward: String { pick("Forward", "Avançar") }
    public static var goatlauncherIsntRunningOnTheTv: String { pick("GoatLauncher isn't running on the TV. Open it. If you removed it, forget this TV and pair it again", "O GoatLauncher não está a correr na TV. Abre-o. Se o tiraste, esquece esta TV e emparelha-a outra vez") }
    public static var goatremoteCantLookForTvsAllow: String { pick("GoatRemote can't look for TVs. Allow Local Network for GoatRemote in Settings, and check that the iPhone is on Wi-Fi.", "O GoatRemote não consegue procurar TVs. Autoriza a Rede local para o GoatRemote nas Definições, e vê se o iPhone está no Wi-Fi.") }
    public static var goattvDidntAnswerTryAgain: String { pick("GoatTV didn't answer. Try again", "O GoatTV não respondeu. Tenta outra vez") }
    public static var goattvDidntSwitchChannelsCheckThe: String { pick("GoatTV didn't switch channels. Check the TV and try again", "O GoatTV não mudou de canal. Vê a TV e tenta outra vez") }
    public static var goattvHasToBeOpenOn: String { pick("GoatTV has to be open on the TV", "O GoatTV tem de estar aberto na TV") }
    public static var goattvIsntOpenOnTheTv: String { pick("GoatTV isn't open on the TV.", "O GoatTV não está aberto na TV.") }
    public static var guide: String { pick("Guide", "Guia") }
    public static var home: String { pick("Home", "Início") }
    public static var homeScreen: String { pick("Home screen", "Ecrã inicial") }
    public static var howCanWeReachYouOptional: String { pick("How can we reach you? (optional)", "Como te contactamos? (opcional)") }
    public static var input: String { pick("Input", "Entrada") }
    public static var isItOnAndOnThe: String { pick("Is it on and on the same Wi-Fi? ", "Está ligada e na mesma rede Wi-Fi? ") }
    public static var keyboard: String { pick("Keyboard", "Teclado") }
    public static var lastCh: String { pick("Last ch", "Último can") }
    public static var lookingForTvsOnThisNetwork: String { pick("Looking for TVs on this network…", "À procura de TVs nesta rede…") }
    public static var more: String { pick("More", "Mais") }
    public static var mute: String { pick("Mute", "Silenciar") }
    public static var neverIncludesPinsCodesOrKeys: String { pick("Never includes PINs, codes or keys. Nothing is sent until you send or share it.", "Nunca tem PINs, códigos nem chaves. Nada sai do telemóvel até o enviares ou partilhares.") }
    public static var next: String { pick("Next", "Seguinte") }
    public static var nextChannel: String { pick("Next channel", "Canal seguinte") }
    public static var noChannelsFound: String { pick("No channels found", "Nenhum canal encontrado") }
    public static var noPinOnTheTv: String { pick("No PIN on the TV?", "Não aparece o PIN na TV?") }
    public static var noTvPairedYetOpenGoatremote: String { pick("No TV paired yet. Open GoatRemote and add one", "Ainda não há TV emparelhada. Abre o GoatRemote e junta uma") }
    public static var notPaired: String { pick("Not paired", "Não emparelhada") }
    public static var nowPlaying: String { pick("Now playing", "A dar agora") }
    public static var numbers: String { pick("Numbers", "Números") }
    public static var onThisNetwork: String { pick("On this network", "Nesta rede") }
    public static var openGoattv: String { pick("Open GoatTV", "Abrir o GoatTV") }
    public static var openSettings: String { pick("Open Settings", "Abrir Definições") }
    public static var openedOnThisTv: String { pick("Opened on this TV", "Abertas nesta TV") }
    public static var options: String { pick("Options", "Opções") }
    public static var orByIpAddress: String { pick("Or by IP address", "Ou pelo endereço IP") }
    public static var pair: String { pick("Pair", "Emparelhar") }
    public static var pairAgainTheTvWillShow: String { pick("Pair again: the TV will show a code.", "Emparelha outra vez: a TV mostra um código.") }
    public static var pairThisTvAgain: String { pick("Pair this TV again", "Emparelhar esta TV outra vez") }
    public static var pairedF: String { pick("Paired", "Emparelhada") }
    public static var pairedM: String { pick("Paired", "Emparelhado") }
    public static var pairing: String { pick("Pairing…", "A emparelhar…") }
    public static var phoneVolumeButtons: String { pick("iPhone volume buttons", "Botões de volume do iPhone") }
    public static var playPause: String { pick("Play/Pause", "Reproduzir/pausa") }
    public static var power: String { pick("Power", "Ligar") }
    public static var previous: String { pick("Previous", "Anterior") }
    public static var previousChannel: String { pick("Previous channel", "Canal anterior") }
    public static var recentlyOpened: String { pick("Recently opened", "Abertas há pouco") }
    public static var rewind: String { pick("Rewind", "Recuar") }
    public static var search: String { pick("Search", "Pesquisa") }
    public static var searchChannels: String { pick("Search channels", "Procurar canais") }
    public static var searchPassword: String { pick("Search, password…", "Pesquisa, palavra-passe…") }
    public static var send: String { pick("Send", "Enviar") }
    public static var sendAReport: String { pick("Send a report", "Enviar relatório") }
    public static var sendReport: String { pick("Send report", "Enviar relatório") }
    public static var settings: String { pick("Settings", "Definições") }
    public static var subtitles: String { pick("Subtitles", "Legendas") }
    public static var swipeLeftOnATvTo: String { pick("Swipe left on a TV to forget it.", "Desliza uma TV para a esquerda para a esquecer.") }
    public static var swipeToMoveTapToSelect: String { pick("Swipe to move · tap to select", "Desliza para andar · toca para escolher") }
    public static var thatCodeDoesntMatchCheckThe: String { pick("That code doesn't match. Check the one on the TV.", "Esse código não bate certo. Vê o que está na TV.") }
    public static var theAppleTvCantChangeThis: String { pick("The Apple TV can't change this TV's volume. Use its remote", "A Apple TV não muda o volume desta TV. Usa o comando dela") }
    public static var theAppleTvHasTooMany: String { pick("The Apple TV has too many paired devices. Remove one in Settings → Remotes and Devices → Remote App and Devices.", "A Apple TV tem demasiados aparelhos emparelhados. Remove um em Definições → Comandos e dispositivos → App Remote e dispositivos.") }
    public static var theAppleTvIsBusyPairing: String { pick("The Apple TV is busy pairing with another device. Try again in a moment.", "A Apple TV está a emparelhar com outro aparelho. Tenta outra vez daqui a pouco.") }
    public static var theAppleTvIsntAcceptingNew: String { pick("The Apple TV isn't accepting new devices. On the Apple TV, set Settings → AirPlay and HomeKit → Allow Access to “Everyone on the Same Network” and try again.", "A Apple TV não está a aceitar aparelhos novos. Na Apple TV, põe Definições → AirPlay e HomeKit → Permitir acesso em “Todos na mesma rede” e tenta outra vez.") }
    public static var theListIsTooLongOnly: String { pick("The list is too long: only part of it is shown here.", "A lista é longa demais: aqui só aparece uma parte.") }
    public static var thePinWorkedOverAirplayBut: String { pick("The PIN worked over AirPlay, but this Apple TV doesn't accept it for the remote. Send a report so we can look into it.", "O PIN funcionou pelo AirPlay, mas esta Apple TV não o aceita para o comando. Envia um relatório para vermos.") }
    public static var theTvClosedTheConnection: String { pick("The TV closed the connection", "A TV fechou a ligação") }
    public static var theTvClosedTheConnectionTry: String { pick("The TV closed the connection. Try again.", "A TV fechou a ligação. Tenta outra vez.") }
    public static var theTvsCertificateIsUnreadable: String { pick("The TV's certificate is unreadable", "O certificado da TV não se lê") }
    public static var theTvsLauncherDidntAnswer: String { pick("The TV's launcher didn't answer", "O launcher da TV não respondeu") }
    public static var theTvsLauncherDidntAnswerTry: String { pick("The TV's launcher didn't answer. Try again", "O launcher da TV não respondeu. Tenta outra vez") }
    public static var thereAreNoChannelsInGoattvs: String { pick("There are no channels in GoatTV's list", "A lista do GoatTV não tem canais") }
    public static var thisChannelIsntAvailableOnThe: String { pick("This channel isn't available on the TV", "Este canal não está disponível na TV") }
    public static var thisNetworkCantFindTheGoat: String { pick("This network can't find the GOAT server (its DNS may be blocking it). Try again on mobile data, or use Share.", "Esta rede não encontra o servidor GOAT (o DNS dela pode estar a bloqueá-lo). Tenta com os dados móveis, ou usa Partilhar.") }
    public static var thisTvDoesntKnowThisPhone: String { pick("This TV doesn't know this iPhone", "Esta TV não conhece este iPhone") }
    public static var toUseItAgainYoullHave: String { pick("To use it again, you'll have to pair it again.", "Para a voltares a usar, tens de a emparelhar outra vez.") }
    public static var tooManyReportsFromThisNetwork: String { pick("Too many reports from this network. Try again later, or use Share.", "Demasiados relatórios desta rede. Tenta mais tarde, ou usa Partilhar.") }
    public static var tooManyWrongPinsRestartThe: String { pick("Too many wrong PINs. Restart the Apple TV and try again.", "Demasiados PINs errados. Reinicia a Apple TV e tenta outra vez.") }
    public static var touchSurface: String { pick("Touch surface", "Superfície de toque") }
    public static var tryAgain: String { pick("Try again", "Tentar outra vez") }
    public static var tvIsOff: String { pick("TV is off", "A TV está desligada") }
    public static var tvs: String { pick("TVs", "TVs") }
    public static var typeOnTheTv: String { pick("Type on the TV", "Escrever na TV") }
    public static var typeTheCodeShownOnThe: String { pick("Type the code shown on the TV.", "Escreve o código que aparece na TV.") }
    public static var typeThePinShownOnThe: String { pick("Type the PIN shown on the TV.", "Escreve o PIN que aparece na TV.") }
    public static var updateGoatlauncherOnTheTvTo: String { pick("Update GoatLauncher on the TV to change the volume from here", "Atualiza o GoatLauncher na TV para mudares o volume daqui") }
    public static var version: String { pick("Version", "Versão") }
    public static var vibration: String { pick("Vibration", "Vibração") }
    public static var volDown: String { pick("Vol −", "Vol −") }
    public static var volUp: String { pick("Vol +", "Vol +") }
    public static var whatHappened: String { pick("What happened?", "O que aconteceu?") }
    public static var whatTheAppDidSoFar: String { pick("What the app did so far will be gone, and can't be sent in a report.", "O que a app fez até agora desaparece, e já não pode ir num relatório.") }
    public static var whatTheAppDidToSend: String { pick("What the app did, to send when something fails", "O que a app fez, para mandar quando algo falha") }
    public static var withGoatlauncherOnTheTvAll: String { pick("With GoatLauncher on the TV, all its apps show up here, with their banners.", "Com o GoatLauncher na TV, aparecem aqui todas as apps dela, com os banners.") }
    public static var wrongPinTryAgainTheTv: String { pick("Wrong PIN. Try again: the TV will show a new one.", "PIN errado. Tenta outra vez: a TV mostra um novo.") }
    public static var youHaveTheLatestVersion: String { pick("You have the latest version", "Tens a versão mais recente") }

    /// Todos, para o teste que os confere com contracts/strings.json.
    public static let table: [(String, () -> String)] = [
        ("moveUp", { moveUp }),
        ("moveDown", { moveDown }),
        ("moveLeft", { moveLeft }),
        ("moveRight", { moveRight }),
        ("select", { select }),
        ("aFewMinutes", { aFewMinutes }),
        ("addATv", { addATv }),
        ("all", { all }),
        ("allApps", { allApps }),
        ("allTheTvsAppsHere", { allTheTvsAppsHere }),
        ("androidTvGoogleTvShieldSony", { androidTvGoogleTvShieldSony }),
        ("androidTvsDontShareTheirApp", { androidTvsDontShareTheirApp }),
        ("apps", { apps }),
        ("arrows", { arrows }),
        ("audio", { audio }),
        ("back", { back }),
        ("cancel", { cancel }),
        ("cantReachIt", { cantReachIt }),
        ("cantReachTheTv", { cantReachTheTv }),
        ("changeTheTvsVolumeWhileThe", { changeTheTvsVolumeWhileThe }),
        ("channelDown", { channelDown }),
        ("channelUp", { channelUp }),
        ("channels", { channels }),
        ("checking", { checking }),
        ("clear", { clear }),
        ("clearTheDiagnosticsLog", { clearTheDiagnosticsLog }),
        ("close", { close }),
        ("connected", { connected }),
        ("connecting", { connecting }),
        ("connectingLower", { connectingLower }),
        ("connectingToTheTv", { connectingToTheTv }),
        ("copy", { copy }),
        ("couldntCheckForUpdates", { couldntCheckForUpdates }),
        ("couldntDownloadTheUpdate", { couldntDownloadTheUpdate }),
        ("couldntFindTheTvOnThe", { couldntFindTheTvOnThe }),
        ("couldntGetTheChannelsFromGoattv", { couldntGetTheChannelsFromGoattv }),
        ("diagnostics", { diagnostics }),
        ("downloading", { downloading }),
        ("favourites", { favourites }),
        ("forget", { forget }),
        ("forward", { forward }),
        ("goatlauncherIsntRunningOnTheTv", { goatlauncherIsntRunningOnTheTv }),
        ("goatremoteCantLookForTvsAllow", { goatremoteCantLookForTvsAllow }),
        ("goattvDidntAnswerTryAgain", { goattvDidntAnswerTryAgain }),
        ("goattvDidntSwitchChannelsCheckThe", { goattvDidntSwitchChannelsCheckThe }),
        ("goattvHasToBeOpenOn", { goattvHasToBeOpenOn }),
        ("goattvIsntOpenOnTheTv", { goattvIsntOpenOnTheTv }),
        ("guide", { guide }),
        ("home", { home }),
        ("homeScreen", { homeScreen }),
        ("howCanWeReachYouOptional", { howCanWeReachYouOptional }),
        ("input", { input }),
        ("isItOnAndOnThe", { isItOnAndOnThe }),
        ("keyboard", { keyboard }),
        ("lastCh", { lastCh }),
        ("lookingForTvsOnThisNetwork", { lookingForTvsOnThisNetwork }),
        ("more", { more }),
        ("mute", { mute }),
        ("neverIncludesPinsCodesOrKeys", { neverIncludesPinsCodesOrKeys }),
        ("next", { next }),
        ("nextChannel", { nextChannel }),
        ("noChannelsFound", { noChannelsFound }),
        ("noPinOnTheTv", { noPinOnTheTv }),
        ("noTvPairedYetOpenGoatremote", { noTvPairedYetOpenGoatremote }),
        ("notPaired", { notPaired }),
        ("nowPlaying", { nowPlaying }),
        ("numbers", { numbers }),
        ("onThisNetwork", { onThisNetwork }),
        ("openGoattv", { openGoattv }),
        ("openSettings", { openSettings }),
        ("openedOnThisTv", { openedOnThisTv }),
        ("options", { options }),
        ("orByIpAddress", { orByIpAddress }),
        ("pair", { pair }),
        ("pairAgainTheTvWillShow", { pairAgainTheTvWillShow }),
        ("pairThisTvAgain", { pairThisTvAgain }),
        ("pairedF", { pairedF }),
        ("pairedM", { pairedM }),
        ("pairing", { pairing }),
        ("phoneVolumeButtons", { phoneVolumeButtons }),
        ("playPause", { playPause }),
        ("power", { power }),
        ("previous", { previous }),
        ("previousChannel", { previousChannel }),
        ("recentlyOpened", { recentlyOpened }),
        ("rewind", { rewind }),
        ("search", { search }),
        ("searchChannels", { searchChannels }),
        ("searchPassword", { searchPassword }),
        ("send", { send }),
        ("sendAReport", { sendAReport }),
        ("sendReport", { sendReport }),
        ("settings", { settings }),
        ("subtitles", { subtitles }),
        ("swipeLeftOnATvTo", { swipeLeftOnATvTo }),
        ("swipeToMoveTapToSelect", { swipeToMoveTapToSelect }),
        ("thatCodeDoesntMatchCheckThe", { thatCodeDoesntMatchCheckThe }),
        ("theAppleTvCantChangeThis", { theAppleTvCantChangeThis }),
        ("theAppleTvHasTooMany", { theAppleTvHasTooMany }),
        ("theAppleTvIsBusyPairing", { theAppleTvIsBusyPairing }),
        ("theAppleTvIsntAcceptingNew", { theAppleTvIsntAcceptingNew }),
        ("theListIsTooLongOnly", { theListIsTooLongOnly }),
        ("thePinWorkedOverAirplayBut", { thePinWorkedOverAirplayBut }),
        ("theTvClosedTheConnection", { theTvClosedTheConnection }),
        ("theTvClosedTheConnectionTry", { theTvClosedTheConnectionTry }),
        ("theTvsCertificateIsUnreadable", { theTvsCertificateIsUnreadable }),
        ("theTvsLauncherDidntAnswer", { theTvsLauncherDidntAnswer }),
        ("theTvsLauncherDidntAnswerTry", { theTvsLauncherDidntAnswerTry }),
        ("thereAreNoChannelsInGoattvs", { thereAreNoChannelsInGoattvs }),
        ("thisChannelIsntAvailableOnThe", { thisChannelIsntAvailableOnThe }),
        ("thisNetworkCantFindTheGoat", { thisNetworkCantFindTheGoat }),
        ("thisTvDoesntKnowThisPhone", { thisTvDoesntKnowThisPhone }),
        ("toUseItAgainYoullHave", { toUseItAgainYoullHave }),
        ("tooManyReportsFromThisNetwork", { tooManyReportsFromThisNetwork }),
        ("tooManyWrongPinsRestartThe", { tooManyWrongPinsRestartThe }),
        ("touchSurface", { touchSurface }),
        ("tryAgain", { tryAgain }),
        ("tvIsOff", { tvIsOff }),
        ("tvs", { tvs }),
        ("typeOnTheTv", { typeOnTheTv }),
        ("typeTheCodeShownOnThe", { typeTheCodeShownOnThe }),
        ("typeThePinShownOnThe", { typeThePinShownOnThe }),
        ("updateGoatlauncherOnTheTvTo", { updateGoatlauncherOnTheTvTo }),
        ("version", { version }),
        ("vibration", { vibration }),
        ("volDown", { volDown }),
        ("volUp", { volUp }),
        ("whatHappened", { whatHappened }),
        ("whatTheAppDidSoFar", { whatTheAppDidSoFar }),
        ("whatTheAppDidToSend", { whatTheAppDidToSend }),
        ("withGoatlauncherOnTheTvAll", { withGoatlauncherOnTheTvAll }),
        ("wrongPinTryAgainTheTv", { wrongPinTryAgainTheTv }),
        ("youHaveTheLatestVersion", { youHaveTheLatestVersion }),
    ]
}
