package cc.slokker.goatremote

import java.util.Locale

/** Inglês ou português, conforme a língua do telemóvel (como na app do iPhone). */
fun L(en: String, pt: String) = if (Locale.getDefault().language == "pt") pt else en

/**
 * Os textos fixos da app, com os mesmos nomes que no iPhone (RemoteCore Strings) e conferidos por contracts/strings.json.
 * Cada um escolhe a língua quando se lê, como o L() que estava em cada sítio.
 */
object Strings {
    val moveUp: String get() = L("Up", "Cima")
    val moveDown: String get() = L("Down", "Baixo")
    val moveLeft: String get() = L("Left", "Esquerda")
    val moveRight: String get() = L("Right", "Direita")
    val select: String get() = L("Select", "Escolher")
    val aFewMinutes: String get() = L("a few minutes", "uns minutos")
    val addATv: String get() = L("Add a TV", "Juntar uma TV")
    val all: String get() = L("All", "Todos")
    val allApps: String get() = L("All apps", "Todas as apps")
    val allTheTvsAppsHere: String get() = L("All the TV's apps here", "Todas as apps da TV aqui")
    val allowGoatremoteToInstallAppsThen: String get() = L("Allow GoatRemote to install apps, then tap again", "Autoriza o GoatRemote a instalar apps e toca outra vez")
    val androidTvGoogleTvShieldSony: String get() = L("Android TV, Google TV (SHIELD, Sony, Philips, TCL, Chromecast…) and Apple TV. The TV and the phone must be on the same Wi-Fi.", "Android TV, Google TV (SHIELD, Sony, Philips, TCL, Chromecast…) e Apple TV. A TV e o telemóvel têm de estar na mesma rede Wi-Fi.")
    val androidTvsDontShareTheirApp: String get() = L("Android TVs don't share their app list with the remote. Apps show up here as you open them on the TV, or all of them, with their banners, if the TV has GoatLauncher.", "As Android TV não dão a lista de apps ao comando. As apps vão aparecendo aqui à medida que as abres na TV, ou todas, com os banners, se a TV tiver o GoatLauncher.")
    val arrows: String get() = L("Arrows", "Setas")
    val audio: String get() = L("Audio", "Áudio")
    val back: String get() = L("Back", "Voltar")
    val cancel: String get() = L("Cancel", "Cancelar")
    val cantReachIt: String get() = L("Can't reach it", "Sem ligação")
    val cantReachTheTv: String get() = L("Can't reach the TV", "Não chego à TV")
    val changeTheTvsVolumeWhileThe: String get() = L("Change the TV's volume while the app is open", "Mexem no volume da TV com a app aberta")
    val channelDown: String get() = L("Ch −", "Can −")
    val channelUp: String get() = L("Ch +", "Can +")
    val channels: String get() = L("Channels", "Canais")
    val checking: String get() = L("Checking…", "A procurar…")
    val clear: String get() = L("Clear", "Limpar")
    val clearTheDiagnosticsLog: String get() = L("Clear the diagnostics log?", "Limpar o registo de diagnóstico?")
    val connected: String get() = L("connected", "ligada")
    val connecting: String get() = L("Connecting…", "A ligar…")
    val connectingLower: String get() = L("connecting", "a ligar")
    val connectingToTheTv: String get() = L("Connecting to the TV…", "A ligar à TV…")
    val copy: String get() = L("Copy", "Copiar")
    val couldntCheckForUpdates: String get() = L("Couldn't check for updates", "Não deu para procurar atualizações")
    val couldntDownloadTheUpdate: String get() = L("Couldn't download the update", "Não foi possível descarregar a atualização")
    val couldntFindTheTvOnThe: String get() = L("Couldn't find the TV on the network", "Não deu para encontrar a TV na rede")
    val couldntGetTheChannelsFromGoattv: String get() = L("Couldn't get the channels from GoatTV.", "Não deu para ter os canais do GoatTV.")
    val diagnostics: String get() = L("Diagnostics", "Diagnóstico")
    val downloading: String get() = L("Downloading…", "A descarregar…")
    val favourites: String get() = L("Favourites", "Favoritos")
    val forget: String get() = L("Forget", "Esquecer")
    val forward: String get() = L("Forward", "Avançar")
    val goatlauncherIsntRunningOnTheTv: String get() = L("GoatLauncher isn't running on the TV. Open it. If you removed it, forget this TV and pair it again", "O GoatLauncher não está a correr na TV. Abre-o. Se o tiraste, esquece esta TV e emparelha-a outra vez")
    val goattvDidntAnswerTryAgain: String get() = L("GoatTV didn't answer. Try again", "O GoatTV não respondeu. Tenta outra vez")
    val goattvDidntSwitchChannelsCheckThe: String get() = L("GoatTV didn't switch channels. Check the TV and try again", "O GoatTV não mudou de canal. Vê a TV e tenta outra vez")
    val goattvHasToBeOpenOn: String get() = L("GoatTV has to be open on the TV", "O GoatTV tem de estar aberto na TV")
    val goattvIsntOpenOnTheTv: String get() = L("GoatTV isn't open on the TV.", "O GoatTV não está aberto na TV.")
    val guide: String get() = L("Guide", "Guia")
    val home: String get() = L("Home", "Início")
    val homeScreen: String get() = L("Home screen", "Ecrã inicial")
    val howCanWeReachYouOptional: String get() = L("How can we reach you? (optional)", "Como te contactamos? (opcional)")
    val input: String get() = L("Input", "Entrada")
    val isItOnAndOnThe: String get() = L("Is it on and on the same Wi-Fi? ", "Está ligada e na mesma rede Wi-Fi? ")
    val keyboard: String get() = L("Keyboard", "Teclado")
    val lastCh: String get() = L("Last ch", "Último can")
    val lookingForTvsOnThisNetwork: String get() = L("Looking for TVs on this network…", "À procura de TVs nesta rede…")
    val more: String get() = L("More", "Mais")
    val mute: String get() = L("Mute", "Silenciar")
    val neverIncludesPinsCodesOrKeys: String get() = L("Never includes PINs, codes or keys. Nothing is sent until you send or share it.", "Nunca tem PINs, códigos nem chaves. Nada sai do telemóvel até o enviares ou partilhares.")
    val next: String get() = L("Next", "Seguinte")
    val nextChannel: String get() = L("Next channel", "Canal seguinte")
    val noChannelsFound: String get() = L("No channels found", "Nenhum canal encontrado")
    val noPinOnTheTv: String get() = L("No PIN on the TV?", "Não aparece o PIN na TV?")
    val notPaired: String get() = L("Not paired", "Não emparelhada")
    val nowPlaying: String get() = L("Now playing", "A dar agora")
    val numbers: String get() = L("Numbers", "Números")
    val onThisNetwork: String get() = L("On this network", "Nesta rede")
    val openGoattv: String get() = L("Open GoatTV", "Abrir o GoatTV")
    val openedOnThisTv: String get() = L("Opened on this TV", "Abertas nesta TV")
    val options: String get() = L("Options", "Opções")
    val orByIpAddress: String get() = L("Or by IP address", "Ou pelo endereço IP")
    val pair: String get() = L("Pair", "Emparelhar")
    val pairAgainTheTvWillShow: String get() = L("Pair again: the TV will show a code.", "Emparelha outra vez: a TV mostra um código.")
    val pairThisTvAgain: String get() = L("Pair this TV again", "Emparelhar esta TV outra vez")
    val pairedF: String get() = L("Paired", "Emparelhada")
    val pairedM: String get() = L("Paired", "Emparelhado")
    val pairing: String get() = L("Pairing…", "A emparelhar…")
    val phoneVolumeButtons: String get() = L("Phone volume buttons", "Botões de volume do telemóvel")
    val playPause: String get() = L("Play/Pause", "Reproduzir/pausa")
    val power: String get() = L("Power", "Ligar")
    val previous: String get() = L("Previous", "Anterior")
    val previousChannel: String get() = L("Previous channel", "Canal anterior")
    val recentlyOpened: String get() = L("Recently opened", "Abertas há pouco")
    val rewind: String get() = L("Rewind", "Recuar")
    val search: String get() = L("Search", "Pesquisa")
    val searchChannels: String get() = L("Search channels", "Procurar canais")
    val searchPassword: String get() = L("Search, password…", "Pesquisa, palavra-passe…")
    val send: String get() = L("Send", "Enviar")
    val sendAReport: String get() = L("Send a report", "Enviar relatório")
    val sendReport: String get() = L("Send report", "Enviar relatório")
    val settings: String get() = L("Settings", "Definições")
    val share: String get() = L("Share", "Partilhar")
    val subtitles: String get() = L("Subtitles", "Legendas")
    val swipeToMoveTapToSelect: String get() = L("Swipe to move · tap to select", "Desliza para andar · toca para escolher")
    val tapTheBinToForgetA: String get() = L("Tap the bin to forget a TV.", "Toca no caixote para esquecer uma TV.")
    val thatCodeDoesntMatchCheckThe: String get() = L("That code doesn't match. Check the one on the TV.", "Esse código não bate certo. Vê o que está na TV.")
    val theAppleTvCantChangeThis: String get() = L("The Apple TV can't change this TV's volume. Use its remote", "A Apple TV não muda o volume desta TV. Usa o comando dela")
    val theAppleTvHasTooMany: String get() = L("The Apple TV has too many paired devices. Remove one in Settings → Remotes and Devices → Remote App and Devices.", "A Apple TV tem demasiados aparelhos emparelhados. Remove um em Definições → Comandos e dispositivos → App Remote e dispositivos.")
    val theAppleTvIsBusyPairing: String get() = L("The Apple TV is busy pairing with another device. Try again in a moment.", "A Apple TV está a emparelhar com outro aparelho. Tenta outra vez daqui a pouco.")
    val theAppleTvIsntAcceptingNew: String get() = L("The Apple TV isn't accepting new devices. On the Apple TV, set Settings → AirPlay and HomeKit → Allow Access to “Everyone on the Same Network” and try again.", "A Apple TV não está a aceitar aparelhos novos. Na Apple TV, põe Definições → AirPlay e HomeKit → Permitir acesso em “Todos na mesma rede” e tenta outra vez.")
    val theListIsTooLongOnly: String get() = L("The list is too long: only part of it is shown here.", "A lista é longa demais: aqui só aparece uma parte.")
    val thePinWorkedOverAirplayBut: String get() = L("The PIN worked over AirPlay, but this Apple TV doesn't accept it for the remote. Send a report so we can look into it.", "O PIN funcionou pelo AirPlay, mas esta Apple TV não o aceita para o comando. Envia um relatório para vermos.")
    val theTvClosedTheConnection: String get() = L("The TV closed the connection", "A TV fechou a ligação")
    val theTvClosedTheConnectionTry: String get() = L("The TV closed the connection. Try again.", "A TV fechou a ligação. Tenta outra vez.")
    val theTvsCertificateIsUnreadable: String get() = L("The TV's certificate is unreadable", "O certificado da TV não se lê")
    val theTvsLauncherDidntAnswerTry: String get() = L("The TV's launcher didn't answer. Try again", "O launcher da TV não respondeu. Tenta outra vez")
    val thereAreNoChannelsInGoattvs: String get() = L("There are no channels in GoatTV's list", "A lista do GoatTV não tem canais")
    val thisChannelIsntAvailableOnThe: String get() = L("This channel isn't available on the TV", "Este canal não está disponível na TV")
    val thisNetworkCantFindTheGoat: String get() = L("This network can't find the GOAT server (its DNS may be blocking it). Try again on mobile data, or use Share.", "Esta rede não encontra o servidor GOAT (o DNS dela pode estar a bloqueá-lo). Tenta com os dados móveis, ou usa Partilhar.")
    val thisTvDoesntKnowThisPhone: String get() = L("This TV doesn't know this phone", "Esta TV não conhece este telemóvel")
    val toUseItAgainYoullHave: String get() = L("To use it again, you'll have to pair it again.", "Para a voltares a usar, tens de a emparelhar outra vez.")
    val tooManyReportsFromThisNetwork: String get() = L("Too many reports from this network. Try again later, or use Share.", "Demasiados relatórios desta rede. Tenta mais tarde, ou usa Partilhar.")
    val tooManyWrongPinsRestartThe: String get() = L("Too many wrong PINs. Restart the Apple TV and try again.", "Demasiados PINs errados. Reinicia a Apple TV e tenta outra vez.")
    val touchSurface: String get() = L("Touch surface", "Superfície de toque")
    val tryAgain: String get() = L("Try again", "Tentar outra vez")
    val tvIsOff: String get() = L("TV is off", "A TV está desligada")
    val tvs: String get() = L("TVs", "TVs")
    val typeOnTheTv: String get() = L("Type on the TV", "Escrever na TV")
    val typeTheCodeShownOnThe: String get() = L("Type the code shown on the TV.", "Escreve o código que aparece na TV.")
    val typeThePinShownOnThe: String get() = L("Type the PIN shown on the TV.", "Escreve o PIN que aparece na TV.")
    val updateGoatlauncherOnTheTvTo: String get() = L("Update GoatLauncher on the TV to change the volume from here", "Atualiza o GoatLauncher na TV para mudares o volume daqui")
    val version: String get() = L("Version", "Versão")
    val vibration: String get() = L("Vibration", "Vibração")
    val volDown: String get() = L("Vol −", "Vol −")
    val volUp: String get() = L("Vol +", "Vol +")
    val whatHappened: String get() = L("What happened?", "O que aconteceu?")
    val whatTheAppDidSoFar: String get() = L("What the app did so far will be gone, and can't be sent in a report.", "O que a app fez até agora desaparece, e já não pode ir num relatório.")
    val whatTheAppDidToSend: String get() = L("What the app did, to send when something fails", "O que a app fez, para mandar quando algo falha")
    val withGoatlauncherOnTheTvAll: String get() = L("With GoatLauncher on the TV, all its apps show up here, with their banners.", "Com o GoatLauncher na TV, aparecem aqui todas as apps dela, com os banners.")
    val wrongPinTryAgainTheTv: String get() = L("Wrong PIN. Try again: the TV will show a new one.", "PIN errado. Tenta outra vez: a TV mostra um novo.")
    val youHaveTheLatestVersion: String get() = L("You have the latest version", "Tens a versão mais recente")

    /** Todos, para o teste que os confere com contracts/strings.json. */
    val table: List<Pair<String, () -> String>> = listOf(
        "moveUp" to { moveUp },
        "moveDown" to { moveDown },
        "moveLeft" to { moveLeft },
        "moveRight" to { moveRight },
        "select" to { select },
        "aFewMinutes" to { aFewMinutes },
        "addATv" to { addATv },
        "all" to { all },
        "allApps" to { allApps },
        "allTheTvsAppsHere" to { allTheTvsAppsHere },
        "allowGoatremoteToInstallAppsThen" to { allowGoatremoteToInstallAppsThen },
        "androidTvGoogleTvShieldSony" to { androidTvGoogleTvShieldSony },
        "androidTvsDontShareTheirApp" to { androidTvsDontShareTheirApp },
        "arrows" to { arrows },
        "audio" to { audio },
        "back" to { back },
        "cancel" to { cancel },
        "cantReachIt" to { cantReachIt },
        "cantReachTheTv" to { cantReachTheTv },
        "changeTheTvsVolumeWhileThe" to { changeTheTvsVolumeWhileThe },
        "channelDown" to { channelDown },
        "channelUp" to { channelUp },
        "channels" to { channels },
        "checking" to { checking },
        "clear" to { clear },
        "clearTheDiagnosticsLog" to { clearTheDiagnosticsLog },
        "connected" to { connected },
        "connecting" to { connecting },
        "connectingLower" to { connectingLower },
        "connectingToTheTv" to { connectingToTheTv },
        "copy" to { copy },
        "couldntCheckForUpdates" to { couldntCheckForUpdates },
        "couldntDownloadTheUpdate" to { couldntDownloadTheUpdate },
        "couldntFindTheTvOnThe" to { couldntFindTheTvOnThe },
        "couldntGetTheChannelsFromGoattv" to { couldntGetTheChannelsFromGoattv },
        "diagnostics" to { diagnostics },
        "downloading" to { downloading },
        "favourites" to { favourites },
        "forget" to { forget },
        "forward" to { forward },
        "goatlauncherIsntRunningOnTheTv" to { goatlauncherIsntRunningOnTheTv },
        "goattvDidntAnswerTryAgain" to { goattvDidntAnswerTryAgain },
        "goattvDidntSwitchChannelsCheckThe" to { goattvDidntSwitchChannelsCheckThe },
        "goattvHasToBeOpenOn" to { goattvHasToBeOpenOn },
        "goattvIsntOpenOnTheTv" to { goattvIsntOpenOnTheTv },
        "guide" to { guide },
        "home" to { home },
        "homeScreen" to { homeScreen },
        "howCanWeReachYouOptional" to { howCanWeReachYouOptional },
        "input" to { input },
        "isItOnAndOnThe" to { isItOnAndOnThe },
        "keyboard" to { keyboard },
        "lastCh" to { lastCh },
        "lookingForTvsOnThisNetwork" to { lookingForTvsOnThisNetwork },
        "more" to { more },
        "mute" to { mute },
        "neverIncludesPinsCodesOrKeys" to { neverIncludesPinsCodesOrKeys },
        "next" to { next },
        "nextChannel" to { nextChannel },
        "noChannelsFound" to { noChannelsFound },
        "noPinOnTheTv" to { noPinOnTheTv },
        "notPaired" to { notPaired },
        "nowPlaying" to { nowPlaying },
        "numbers" to { numbers },
        "onThisNetwork" to { onThisNetwork },
        "openGoattv" to { openGoattv },
        "openedOnThisTv" to { openedOnThisTv },
        "options" to { options },
        "orByIpAddress" to { orByIpAddress },
        "pair" to { pair },
        "pairAgainTheTvWillShow" to { pairAgainTheTvWillShow },
        "pairThisTvAgain" to { pairThisTvAgain },
        "pairedF" to { pairedF },
        "pairedM" to { pairedM },
        "pairing" to { pairing },
        "phoneVolumeButtons" to { phoneVolumeButtons },
        "playPause" to { playPause },
        "power" to { power },
        "previous" to { previous },
        "previousChannel" to { previousChannel },
        "recentlyOpened" to { recentlyOpened },
        "rewind" to { rewind },
        "search" to { search },
        "searchChannels" to { searchChannels },
        "searchPassword" to { searchPassword },
        "send" to { send },
        "sendAReport" to { sendAReport },
        "sendReport" to { sendReport },
        "settings" to { settings },
        "share" to { share },
        "subtitles" to { subtitles },
        "swipeToMoveTapToSelect" to { swipeToMoveTapToSelect },
        "tapTheBinToForgetA" to { tapTheBinToForgetA },
        "thatCodeDoesntMatchCheckThe" to { thatCodeDoesntMatchCheckThe },
        "theAppleTvCantChangeThis" to { theAppleTvCantChangeThis },
        "theAppleTvHasTooMany" to { theAppleTvHasTooMany },
        "theAppleTvIsBusyPairing" to { theAppleTvIsBusyPairing },
        "theAppleTvIsntAcceptingNew" to { theAppleTvIsntAcceptingNew },
        "theListIsTooLongOnly" to { theListIsTooLongOnly },
        "thePinWorkedOverAirplayBut" to { thePinWorkedOverAirplayBut },
        "theTvClosedTheConnection" to { theTvClosedTheConnection },
        "theTvClosedTheConnectionTry" to { theTvClosedTheConnectionTry },
        "theTvsCertificateIsUnreadable" to { theTvsCertificateIsUnreadable },
        "theTvsLauncherDidntAnswerTry" to { theTvsLauncherDidntAnswerTry },
        "thereAreNoChannelsInGoattvs" to { thereAreNoChannelsInGoattvs },
        "thisChannelIsntAvailableOnThe" to { thisChannelIsntAvailableOnThe },
        "thisNetworkCantFindTheGoat" to { thisNetworkCantFindTheGoat },
        "thisTvDoesntKnowThisPhone" to { thisTvDoesntKnowThisPhone },
        "toUseItAgainYoullHave" to { toUseItAgainYoullHave },
        "tooManyReportsFromThisNetwork" to { tooManyReportsFromThisNetwork },
        "tooManyWrongPinsRestartThe" to { tooManyWrongPinsRestartThe },
        "touchSurface" to { touchSurface },
        "tryAgain" to { tryAgain },
        "tvIsOff" to { tvIsOff },
        "tvs" to { tvs },
        "typeOnTheTv" to { typeOnTheTv },
        "typeTheCodeShownOnThe" to { typeTheCodeShownOnThe },
        "typeThePinShownOnThe" to { typeThePinShownOnThe },
        "updateGoatlauncherOnTheTvTo" to { updateGoatlauncherOnTheTvTo },
        "version" to { version },
        "vibration" to { vibration },
        "volDown" to { volDown },
        "volUp" to { volUp },
        "whatHappened" to { whatHappened },
        "whatTheAppDidSoFar" to { whatTheAppDidSoFar },
        "whatTheAppDidToSend" to { whatTheAppDidToSend },
        "withGoatlauncherOnTheTvAll" to { withGoatlauncherOnTheTvAll },
        "wrongPinTryAgainTheTv" to { wrongPinTryAgainTheTv },
        "youHaveTheLatestVersion" to { youHaveTheLatestVersion },
    )
}

/** O que o indicador do volume mostra para cada motivo. */
val cc.slokker.goatremote.data.VolumeProblem.text: String
    get() = when (this) {
        cc.slokker.goatremote.data.VolumeProblem.UPDATE_LAUNCHER -> Strings.updateGoatlauncherOnTheTvTo
        cc.slokker.goatremote.data.VolumeProblem.LAUNCHER_NOT_RUNNING -> Strings.goatlauncherIsntRunningOnTheTv
        cc.slokker.goatremote.data.VolumeProblem.NO_ANSWER -> Strings.theTvsLauncherDidntAnswerTry
    }
