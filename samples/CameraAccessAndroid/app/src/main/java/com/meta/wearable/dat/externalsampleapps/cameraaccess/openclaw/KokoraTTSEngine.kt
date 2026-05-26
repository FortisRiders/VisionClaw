package com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

// KokoraTTSEngine: High-quality on-device TTS using Android's TextToSpeech engine.
//
// To enable Kokoro (sherpa-onnx Adam voice):
//  1. Download sherpa-onnx-android-v1.13.2.aar from github.com/k2-fsa/sherpa-onnx/releases
//  2. Place in app/libs/sherpa-onnx-android.aar
//  3. Copy kokoro model files to app/src/main/assets/kokoro/:
//       model.int8.onnx, voices.bin, tokens.txt, espeak-ng-data/
//  4. Set KOKORO_ENABLED = true below and add the sherpa-onnx imports + implementation.

class KokoraTTSEngine private constructor(private val context: Context) {

    companion object {
        private const val TAG = "KokoraTTSEngine"
        private const val KOKORO_ENABLED = false

        @Volatile
        private var instance: KokoraTTSEngine? = null

        fun getInstance(context: Context): KokoraTTSEngine =
            instance ?: synchronized(this) {
                instance ?: KokoraTTSEngine(context.applicationContext).also { instance = it }
            }
    }

    var isReady = false
        private set

    var onFinish: (() -> Unit)? = null
    var onPlaybackStarted: (() -> Unit)? = null

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var generationJob: Job? = null
    private var audioTrack: AudioTrack? = null

    private var tts: TextToSpeech? = null
    private var ttsReady = false

    init {
        initAndroidTTS()
    }

    private fun initAndroidTTS() {
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val result = tts?.setLanguage(Locale.US)
                ttsReady = result != TextToSpeech.LANG_MISSING_DATA && result != TextToSpeech.LANG_NOT_SUPPORTED
                if (ttsReady) {
                    tts?.setSpeechRate(0.95f)
                    tts?.setPitch(0.9f)
                    isReady = true
                    Log.d(TAG, "Android TTS initialized OK")
                } else {
                    Log.e(TAG, "Android TTS language not supported")
                }
            } else {
                Log.e(TAG, "Android TTS init failed: $status")
            }
        }
    }

    fun speak(text: String, voiceId: Int = 5, finishCallback: () -> Unit) {
        if (!isReady) {
            finishCallback()
            return
        }

        generationJob?.cancel()
        onFinish = finishCallback

        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                scope.launch {
                    onPlaybackStarted?.invoke()
                    onPlaybackStarted = null
                    Log.d(TAG, "TTS playback started")
                }
            }

            override fun onDone(utteranceId: String?) {
                scope.launch {
                    Log.d(TAG, "TTS playback finished")
                    val cb = onFinish
                    onFinish = null
                    cb?.invoke()
                }
            }

            @Deprecated("Deprecated in API 21")
            override fun onError(utteranceId: String?) {
                scope.launch {
                    Log.e(TAG, "TTS error")
                    val cb = onFinish
                    onFinish = null
                    cb?.invoke()
                }
            }
        })

        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "jarvis-tts")
    }

    fun stop() {
        generationJob?.cancel()
        generationJob = null
        tts?.stop()
        audioTrack?.stop()
        audioTrack?.flush()
        audioTrack = null
        onFinish = null
        onPlaybackStarted = null
    }

    fun shutdown() {
        stop()
        tts?.shutdown()
        tts = null
        isReady = false
    }
}
