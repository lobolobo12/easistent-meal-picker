package com.easistent.mealpicker

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class MealWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.meal_widget)

            val todayMenu = widgetData.getString("today_menu", "") ?: ""
            val todayDesc = widgetData.getString("today_desc", "") ?: ""
            val tomorrowMenu = widgetData.getString("tomorrow_menu", "") ?: ""
            val tomorrowDesc = widgetData.getString("tomorrow_desc", "") ?: ""

            views.setTextViewText(
                R.id.today_menu,
                todayMenu.ifEmpty { "Ni podatkov" }
            )
            views.setTextViewText(R.id.today_desc, todayDesc)

            views.setTextViewText(
                R.id.tomorrow_menu,
                tomorrowMenu.ifEmpty { "Ni podatkov" }
            )
            views.setTextViewText(R.id.tomorrow_desc, tomorrowDesc)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
