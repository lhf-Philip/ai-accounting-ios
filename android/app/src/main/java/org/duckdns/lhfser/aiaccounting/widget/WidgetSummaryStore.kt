package org.duckdns.lhfser.aiaccounting.widget

import android.content.Context
import org.duckdns.lhfser.aiaccounting.R

object WidgetSummaryStore {
    private const val PREF_NAME = "summary_widget_store"
    private const val KEY_TITLE = "title"
    private const val KEY_BODY = "body"

    fun save(context: Context, title: String, body: String) {
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_TITLE, title)
            .putString(KEY_BODY, body)
            .apply()
    }

    fun loadTitle(context: Context): String {
        return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .getString(KEY_TITLE, null)
            ?: context.getString(R.string.widget_title)
    }

    fun loadBody(context: Context): String {
        return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .getString(KEY_BODY, null)
            ?: context.getString(R.string.widget_placeholder)
    }
}
