package cc.slokker.goatremote

import android.graphics.Color as AndroidColor
import android.os.Bundle
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import cc.slokker.goatremote.tv.Key
import cc.slokker.goatremote.ui.AddTvScreen
import cc.slokker.goatremote.ui.GoatTheme
import cc.slokker.goatremote.ui.PairingDialog
import cc.slokker.goatremote.ui.RemoteScreen
import cc.slokker.goatremote.ui.Theme

class MainActivity : ComponentActivity() {
    private val vm: RemoteViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(AndroidColor.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(AndroidColor.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        setContent {
            GoatTheme {
                Box(
                    Modifier.fillMaxSize().background(Theme.background).safeDrawingPadding(),
                ) {
                    CompositionLocalProvider(LocalContentColor provides Theme.text) {
                        if (vm.tvs.isEmpty()) AddTvScreen(vm) else RemoteScreen(vm)
                        vm.pairing?.let { PairingDialog(vm, it) }
                    }
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        DebugLog.add("App active")
        vm.connect()
    }

    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations) {
            DebugLog.add("App background")
            vm.disconnect()
        }
    }

    /** Os botões de volume do telemóvel mexem no volume da TV (com a app aberta e a opção ligada). */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val key = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> Key.VOLUME_UP
            KeyEvent.KEYCODE_VOLUME_DOWN -> Key.VOLUME_DOWN
            else -> null
        }
        if (key != null && vm.volumeButtons && vm.status == RemoteViewModel.Status.Connected) {
            if (event.action == KeyEvent.ACTION_DOWN) vm.press(key)
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
