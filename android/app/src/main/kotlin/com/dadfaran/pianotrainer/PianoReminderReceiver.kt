package com.dadfaran.pianotrainer

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

class PianoReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val prefs = context.getSharedPreferences("piano_note_trainer_reminder", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("enabled", false)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(
                CHANNEL_ID, "یادآور تمرین پیانو", NotificationManager.IMPORTANCE_DEFAULT
            ).apply { description = "یادآوری روزانه برای تمرین نت‌خوانی پیانو" })
        }
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = launch?.let {
            PendingIntent.getActivity(context, 7316, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        if (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle("وقت تمرین پیانو رسیده! 🎹")
                .setContentText("چند دقیقه نت‌خوانی تمرین کنیم؟")
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            if (contentIntent != null) builder.setContentIntent(contentIntent)
            val notification = builder.build()
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        }
        PianoReminderScheduler.schedule(context, prefs.getInt("hour", 19), prefs.getInt("minute", 0))
    }

    companion object {
        private const val CHANNEL_ID = "piano_daily_practice"
        private const val NOTIFICATION_ID = 7317
    }
}
