package org.duckdns.lhfser.aiaccounting.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import org.duckdns.lhfser.aiaccounting.R

class SummaryWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { appWidgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_summary)
            views.setTextViewText(R.id.widgetTitle, context.getString(R.string.widget_title))
            views.setTextViewText(R.id.widgetBody, context.getString(R.string.widget_placeholder))
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
