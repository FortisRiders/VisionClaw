package com.meta.wearable.dat.externalsampleapps.cameraaccess.gemini

import android.graphics.Bitmap
import android.util.Log
import androidx.lifecycle.ViewModel

import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.OpenClawConnectionState
import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.ToolCallStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class GeminiUiState(
    val isGeminiActive: Boolean = false,
    val connectionState: GeminiConnectionState = GeminiConnectionState.Disconnected,
    val isModelSpeaking: Boolean = false,
    val errorMessage: String? = null,
    val userTranscript: String = "",
    val aiTranscript: String = "",
    val toolCallStatus: ToolCallStatus = ToolCallStatus.Idle,
    val openClawConnectionState: OpenClawConnectionState = OpenClawConnectionState.NotConfigured,
)

// GeminiSessionViewModel: Handles Gemini Live session for camera frame analysis only.
// Audio in/out is handled by JarvisVoiceSession via OpenClaw. Gemini manages video frames.
class GeminiSessionViewModel : ViewModel() {
    companion object {
        private const val TAG = "GeminiSessionVM"
    }

    private val _uiState = MutableStateFlow(GeminiUiState())
    val uiState: StateFlow<GeminiUiState> = _uiState.asStateFlow()

    private val geminiService = GeminiLiveService()
    private var lastVideoFrameTime: Long = 0

    fun startSession() {
        if (_uiState.value.isGeminiActive) return

        if (!GeminiConfig.isConfigured) {
            _uiState.value = _uiState.value.copy(
                errorMessage = "Gemini API key not configured. Open Settings and add your key."
            )
            return
        }

        _uiState.value = _uiState.value.copy(isGeminiActive = true)

        geminiService.onDisconnected = { reason ->
            if (_uiState.value.isGeminiActive) {
                stopSession()
                _uiState.value = _uiState.value.copy(
                    errorMessage = "Gemini disconnected: ${reason ?: "Unknown"}"
                )
            }
        }

        geminiService.connect { setupOk ->
            if (!setupOk) {
                val msg = when (val state = geminiService.connectionState.value) {
                    is GeminiConnectionState.Error -> state.message
                    else -> "Failed to connect to Gemini"
                }
                stopSession()
                _uiState.value = _uiState.value.copy(errorMessage = msg)
            }
        }
    }

    fun stopSession() {
        geminiService.disconnect()
        _uiState.value = GeminiUiState()
    }

    fun sendVideoFrameIfThrottled(bitmap: Bitmap) {
        if (!GeminiConfig.isConfigured) return
        if (!_uiState.value.isGeminiActive) return
        if (_uiState.value.connectionState != GeminiConnectionState.Ready) return
        val now = System.currentTimeMillis()
        if (now - lastVideoFrameTime < GeminiConfig.VIDEO_FRAME_INTERVAL_MS) return
        lastVideoFrameTime = now
        geminiService.sendVideoFrame(bitmap)
        Log.d(TAG, "Forwarded video frame to Gemini")
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    override fun onCleared() {
        super.onCleared()
        stopSession()
    }
}
