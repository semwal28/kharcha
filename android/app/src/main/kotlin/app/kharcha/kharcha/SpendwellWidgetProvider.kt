package app.kharcha.kharcha

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Home screen widget: "Safe to spend today", filled in by the app. */
class SpendwellWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.spendwell_widget).apply {
                setTextViewText(R.id.widget_amount, widgetData.getString("safe_today", null) ?: "—")
                setTextViewText(R.id.widget_spent, widgetData.getString("spent", null) ?: "Open Spendwell to start")
                val pct = widgetData.getString("budget_pct", null).orEmpty()
                setTextViewText(R.id.widget_budget, pct)
                setViewVisibility(R.id.widget_budget, if (pct.isEmpty()) View.GONE else View.VISIBLE)
                setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
