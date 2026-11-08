package com.dadfaran.pianotrainer

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

class MainActivity : FlutterActivity() {
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
                            if (ok) result.success(null)
                            else result.error("SAVE_FAILED", "Could not persist data", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "piano_note_trainer/sound")
            .setMethodCallHandler { call, result ->
                if (call.method == "playNote") {
                    val midi = call.argument<Int>("midi")
                    if (midi != null && midi in 48..96) {
                        thread(name = "piano-tone", isDaemon = true) { playTone(midi) }
                        result.success(null)
                    } else result.error("BAD_NOTE", "Invalid MIDI note", null)
                } else result.notImplemented()
            }
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
