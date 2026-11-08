package com.dadfaran.pianotrainer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PianoReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) return
        val prefs = context.getSharedPreferences("piano_note_trainer_reminder", Context.MODE_PRIVATE)
        if (prefs.getBoolean("enabled", false)) {
            PianoReminderScheduler.schedule(context, prefs.getInt("hour", 19), prefs.getInt("minute", 0))
        }
    }
}
