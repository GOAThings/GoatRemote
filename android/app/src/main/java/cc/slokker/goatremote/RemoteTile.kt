package cc.slokker.goatremote

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Build
import android.service.quicksettings.TileService
import android.widget.RemoteViews

/** Abre a app como o ícone: volta à que já está aberta em vez de criar outra. */
private fun openApp(context: Context): PendingIntent =
    PendingIntent.getActivity(
        context, 0,
        context.packageManager.getLaunchIntentForPackage(context.packageName),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

/** Os mosaicos das definições rápidas: as setas e a cabra do logo, ou um comando. */
open class RemoteTile : TileService() {
    override fun onClick() {
        if (isLocked) unlockAndRun { open() } else open()
    }

    private fun open() {
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(openApp(this))
        } else {
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
            startActivityAndCollapse(packageManager.getLaunchIntentForPackage(packageName)!!)
        }
    }
}

class RemoteShapeTile : RemoteTile()

/** O widget do ecrã principal. */
class RemoteWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = RemoteViews(context.packageName, R.layout.remote_widget)
        views.setOnClickPendingIntent(R.id.widget_icon, openApp(context))
        manager.updateAppWidget(ids, views)
    }
}
