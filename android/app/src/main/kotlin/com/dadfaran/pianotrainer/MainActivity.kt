package com.dadfaran.pianotrainer

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI
import kotlin.math.pow
import kotlin.math.sin
import kotlin.concurrent.thread
import java.util.concurrent.ConcurrentHashMap

class MainActivity : FlutterActivity() {
    private val activeTracks = ConcurrentHashMap<Int, AudioTrack>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val prefs = getSharedPreferences("piano_note_trainer_progress", MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "piano_note_trainer/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> result.success(prefs.getString("progress", null))
                    "write" -> {
                        val json = call.argument<String>("json")
                        if (json == null) result.error("BAD_DATA", "Missing json", null)
                        else {
                            val ok = prefs.edit().putString("progress", json).commit()
                            if (ok) {
                                PianoProgressWidgetProvider.updateAll(this)
                                result.success(null)
                            } else result.error("SAVE_FAILED", "Could not persist data", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "piano_note_trainer/reminders")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "configure" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val hour = (call.argument<Int>("hour") ?: 19).coerceIn(0, 23)
                        val minute = (call.argument<Int>("minute") ?: 0).coerceIn(0, 59)
                        val reminderPrefs = getSharedPreferences("piano_note_trainer_reminder", MODE_PRIVATE)
                        reminderPrefs.edit().putBoolean("enabled", enabled).putInt("hour", hour).putInt("minute", minute).apply()
                        if (enabled) {
                            if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7314)
                            }
                            PianoReminderScheduler.schedule(this, hour, minute)
                        } else PianoReminderScheduler.cancel(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "piano_note_trainer/widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "update") {
                    PianoProgressWidgetProvider.updateAll(this)
                    result.success(null)
                } else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "piano_note_trainer/sound")
            .setMethodCallHandler { call, result ->
                val midi = call.argument<Int>("midi")
                when (call.method) {
                    "startNote" -> {
                        if (midi != null && midi in 36..96) {
                            try { startTone(midi); result.success(null) }
                            catch (error: Exception) { result.error("AUDIO_START_FAILED", error.message, null) }
                        } else result.error("BAD_NOTE", "Invalid MIDI note", null)
                    }
                    "stopNote" -> {
                        if (midi != null) stopTone(midi)
                        result.success(null)
                    }
                    "stopAll" -> { activeTracks.clear(); result.success(null) }
                    "playNote" -> {
                        if (midi != null && midi in 36..96) {
                            thread(name = "piano-tone-one-shot", isDaemon = true) { playTone(midi) }
                            result.success(null)
                        } else result.error("BAD_NOTE", "Invalid MIDI note", null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onPause() {
        activeTracks.clear()
        super.onPause()
    }

    private fun startTone(midi: Int) {
        stopTone(midi)
        val sampleRate = 22050
        val track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAudioFormat(AudioFormat.Builder()
                .setSampleRate(sampleRate)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(8192)
            .build()
        activeTracks[midi] = track
        thread(name = "piano-held-$midi", isDaemon = true) {
            val frequency = 440.0 * 2.0.pow((midi - 69) / 12.0)
            val buffer = ShortArray(512)
            var phase = 0.0
            try {
                track.play()
                while (activeTracks[midi] === track) {
                    for (i in buffer.indices) {
                        val wave = sin(phase) * .72 + sin(phase * 2.0) * .12 + sin(phase * 3.0) * .04
                        buffer[i] = (wave * 15000).toInt().coerceIn(-32767, 32767).toShort()
                        phase += 2.0 * PI * frequency / sampleRate
                        if (phase >= 2.0 * PI) phase -= 2.0 * PI
                    }
                    val written = track.write(buffer, 0, buffer.size)
                    if (written < 0) break
                }
            } catch (_: Exception) {
            } finally {
                activeTracks.remove(midi, track)
                try { if (track.playState == AudioTrack.PLAYSTATE_PLAYING) track.stop() } catch (_: Exception) {}
                track.release()
            }
        }
    }

    private fun stopTone(midi: Int) {
        activeTracks.remove(midi)
    }

    private fun playTone(midi: Int) {
        val sampleRate = 22050
        val duration = 0.28
        val count = (duration * sampleRate).toInt()
        val frequency = 440.0 * 2.0.pow((midi - 69) / 12.0)
        val buffer = ShortArray(count) { i ->
            val t = i.toDouble() / sampleRate
            val envelope = (1.0 - i.toDouble() / count).pow(2.0)
            val wave = sin(2 * PI * frequency * t) * .8 +
                sin(4 * PI * frequency * t) * .15
            (wave * envelope * 16000).toInt().coerceIn(-32767, 32767).toShort()
        }
        val track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAudioFormat(AudioFormat.Builder()
                .setSampleRate(sampleRate)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(buffer.size * 2)
            .build()
        try {
            track.write(buffer, 0, buffer.size)
            track.play()
            Thread.sleep(350)
        } catch (_: Exception) {
        } finally {
            track.release()
        }
    }
}
