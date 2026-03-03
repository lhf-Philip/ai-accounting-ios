package org.duckdns.lhfser.aiaccounting.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.widget.RemoteViews
import org.duckdns.lhfser.aiaccounting.R

class SummaryWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        updateWidgets(context = context, appWidgetManager = appWidgetManager, appWidgetIds = appWidgetIds)
    }

    companion object {
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, SummaryWidgetProvider::class.java)
            val appWidgetIds = manager.getAppWidgetIds(component)
            if (appWidgetIds.isNotEmpty()) {
                updateWidgets(context = context, appWidgetManager = manager, appWidgetIds = appWidgetIds)
            }
        }

        private fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray
        ) {
            val title = WidgetSummaryStore.loadTitle(context)
            val body = WidgetSummaryStore.loadBody(context)

            appWidgetIds.forEach { appWidgetId ->
                val views = RemoteViews(context.packageName, R.layout.widget_summary)
                views.setTextViewText(R.id.widgetTitle, title)
                views.setTextViewText(R.id.widgetBody, body)
                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }
    }
}
