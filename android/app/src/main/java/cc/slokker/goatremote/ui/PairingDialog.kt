package cc.slokker.goatremote.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Tv
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import cc.slokker.goatremote.DebugLog
import cc.slokker.goatremote.L
import cc.slokker.goatremote.PairingModel
import cc.slokker.goatremote.Phase
import cc.slokker.goatremote.RemoteViewModel
import cc.slokker.goatremote.data.TvKind

/** O emparelhamento: a TV mostra um código (6 caracteres na Android TV, 4 algarismos na Apple TV) e escreve-se aqui. */
@Composable
fun PairingDialog(vm: RemoteViewModel, pairing: PairingModel) {
    fun cancel() {
        DebugLog.add("Pairing: cancelled from the dialog (${pairing.phase})")
        pairing.cancel()
        vm.pairing = null
    }
    val phase = pairing.phase
    var diagnostics by remember { mutableStateOf(false) }
    if (diagnostics) DiagnosticsSheet { diagnostics = false }
    Dialog(
        onDismissRequest = { if (phase != Phase.Checking) cancel() },
        properties = DialogProperties(dismissOnClickOutside = false),
    ) {
        Surface(shape = RoundedCornerShape(28.dp), color = Theme.surface, contentColor = Color.White) {
            Column(Modifier.padding(28.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Rounded.Tv, null, tint = Theme.accent, modifier = Modifier.size(44.dp))
                Spacer(Modifier.height(14.dp))
                Text(pairing.name, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                Spacer(Modifier.height(18.dp))
                when (phase) {
                    Phase.Connecting -> Busy(L("Connecting to the TV…", "A ligar à TV…"))
                    is Phase.WaitingCode -> {
                        Text(
                            when {
                                phase.retry -> L("That code doesn't match. Check the one on the TV.", "Esse código não bate certo. Vê o que está na TV.")
                                pairing.kind == TvKind.APPLE -> L("Type the PIN shown on the TV.", "Escreve o PIN que aparece na TV.")
                                else -> L("Type the code shown on the TV.", "Escreve o código que aparece na TV.")
                            },
                            color = if (phase.retry) Theme.power else Theme.dim,
                            textAlign = TextAlign.Center,
                        )
                        Spacer(Modifier.height(14.dp))
                        CodeField(pairing, phase)
                    }
                    Phase.Checking -> Busy(L("Pairing…", "A emparelhar…"))
                    Phase.Done -> Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.CheckCircle, null, tint = Theme.green)
                        Spacer(Modifier.width(8.dp))
                        Text(L("Paired", "Emparelhado"), color = Theme.green, fontSize = 19.sp)
                    }
                    is Phase.Failed -> {
                        Text(phase.why, color = Theme.power, textAlign = TextAlign.Center)
                        Spacer(Modifier.height(14.dp))
                        Button(onClick = pairing::retry, colors = ButtonDefaults.buttonColors(containerColor = Theme.accent)) {
                            Text(L("Try again", "Tentar outra vez"))
                        }
                        TextButton({ diagnostics = true }, Modifier.testTag("pairing:report")) {
                            Text(L("Send a report", "Enviar relatório"), color = Theme.accent)
                        }
                    }
                }
                Spacer(Modifier.height(18.dp))
                TextButton(onClick = ::cancel) { Text(L("Cancel", "Cancelar"), color = Theme.dim) }
            }
        }
    }
}

@Composable
private fun Busy(text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        CircularProgressIndicator(color = Theme.dim, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(12.dp))
        Text(text, color = Theme.dim)
    }
}

@Composable
private fun CodeField(pairing: PairingModel, phase: Any) {
    var code by remember(phase) { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    val apple = pairing.kind == TvKind.APPLE
    OutlinedTextField(
        value = code,
        onValueChange = { new ->
            val clean = new.uppercase().filter { if (apple) it.isDigit() else it in '0'..'9' || it in 'A'..'F' }.take(pairing.codeLength)
            code = clean
            if (clean.length == pairing.codeLength) pairing.submit(clean)
        },
        placeholder = {
            Text(if (apple) "1234" else "A1B2C3", modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center,
                fontSize = 30.sp, fontFamily = FontFamily.Monospace)
        },
        singleLine = true,
        textStyle = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace,
            textAlign = TextAlign.Center, color = Color.White),
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.Characters,
            autoCorrectEnabled = false,
            keyboardType = if (apple) KeyboardType.NumberPassword else KeyboardType.Ascii,
        ),
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Theme.accent, unfocusedBorderColor = Theme.faint),
        modifier = Modifier.fillMaxWidth().focusRequester(focus).testTag("code-field"),
    )
    LaunchedEffect(phase) { runCatching { focus.requestFocus() } }
}
