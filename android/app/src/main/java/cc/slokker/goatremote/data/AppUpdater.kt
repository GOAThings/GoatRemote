package cc.slokker.goatremote.data

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import cc.slokker.goatremote.BuildConfig
import cc.slokker.goatremote.InstallResultReceiver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** Versões novas: as releases do repositório levam o APK, e o instalador do Android só o aceita com a mesma chave. */
object AppUpdater {
    private const val LATEST = "https://api.github.com/repos/GOAThings/GoatRemote/releases/latest"
    private const val APK = "https://github.com/GOAThings/GoatRemote/releases/latest/download/GoatRemote.apk"

    /** As versões de teste têm outro id e não podem receber o APK publicado. */
    val enabled: Boolean get() = BuildConfig.APPLICATION_ID == "cc.slokker.goatremote"

    /** A versão publicada, se for mais recente do que esta. */
    suspend fun newer(): String? = withContext(Dispatchers.IO) {
        val c = URL(LATEST).openConnection() as HttpURLConnection
        c.setRequestProperty("Accept", "application/vnd.github+json")
        c.connectTimeout = 20_000
        c.readTimeout = 20_000
        try {
            val version = JSONObject(c.inputStream.bufferedReader().readText()).getString("tag_name").removePrefix("v")
            version.takeIf { isNewer(it, BuildConfig.VERSION_NAME) }
        } finally {
            c.disconnect()
        }
    }

    fun isNewer(remote: String, current: String): Boolean {
        fun parts(v: String) = v.split('.', '-').map { it.toIntOrNull() ?: 0 }
        val a = parts(remote)
        val b = parts(current)
        for (i in 0 until maxOf(a.size, b.size)) {
            val x = a.getOrElse(i) { 0 }
            val y = b.getOrElse(i) { 0 }
            if (x != y) return x > y
        }
        return false
    }

    /** O Android deixa esta app instalar APKs? (Android 8+: "Instalar apps desconhecidas".) */
    fun canInstall(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    fun openInstallPermission(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        runCatching {
            context.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")))
        }
    }

    /** Descarrega o APK e entrega-o ao instalador (que pede confirmação: ver [InstallResultReceiver]). */
    suspend fun install(context: Context) = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        val apk = File(dir, "GoatRemote.apk")
        URL(APK).openStream().use { input -> apk.outputStream().use { input.copyTo(it) } }
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(context.packageName)
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("base.apk", 0, apk.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val intent = PendingIntent.getBroadcast(context, id, Intent(context, InstallResultReceiver::class.java), flags)
            session.commit(intent.intentSender)
        }
    }
}
