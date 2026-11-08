package com.dadfaran.pianotrainer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

class PianoProgressWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { updateOne(context, manager, it) }
    }

    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, PianoProgressWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { updateOne(context, manager, it) }
        }

        private fun dayKey(date: Date): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(date)

        private fun updateOne(context: Context, manager: AppWidgetManager, id: Int) {
            val prefs = context.getSharedPreferences("piano_note_trainer_progress", Context.MODE_PRIVATE)
            val raw = prefs.getString("progress", null)
            val data = try { if (raw.isNullOrBlank()) JSONObject() else JSONObject(raw) } catch (_: Exception) { JSONObject() }
            val secondsMap = data.optJSONObject("practiceSecondsByDay") ?: JSONObject()
            val today = Calendar.getInstance()
            val todaySeconds = secondsMap.optInt(dayKey(today.time), 0)
            var weekSeconds = 0
            var weekDays = 0
            for (offset in 0..6) {
                val d = (today.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, -offset) }.time
                val value = secondsMap.optInt(dayKey(d), 0)
                weekSeconds += value
                if (value >= 60) weekDays++
            }
            var monthSeconds = 0
            var monthDays = 0
            val dayOfMonth = today.get(Calendar.DAY_OF_MONTH)
            for (day in 1..dayOfMonth) {
                val d = (today.clone() as Calendar).apply { set(Calendar.DAY_OF_MONTH, day) }.time
                val value = secondsMap.optInt(dayKey(d), 0)
                monthSeconds += value
                if (value >= 60) monthDays++
            }
            val views = RemoteViews(context.packageName, R.layout.piano_progress_widget)
            views.setTextViewText(R.id.widget_today, "امروز: ${todaySeconds / 60} دقیقه")
            views.setTextViewText(R.id.widget_week, "این هفته: ${weekSeconds / 60} دقیقه • $weekDays روز")
            views.setTextViewText(R.id.widget_month, "این ماه: ${monthSeconds / 60} دقیقه • $monthDays روز")
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                val pending = PendingIntent.getActivity(context, id, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                views.setOnClickPendingIntent(R.id.widget_root, pending)
            }
            manager.updateAppWidget(id, views)
        }
    }
}

