package com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw

import android.util.Log
import com.meta.wearable.dat.externalsampleapps.cameraaccess.gemini.GeminiConfig
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

class OpenClawBridge {
    companion object {
        private const val TAG = "OpenClawBridge"
        private const val MAX_HISTORY_TURNS = 10
        private const val DEFAULT_AGENT_ID = "main"
    }

    private val _lastToolCallStatus = MutableStateFlow<ToolCallStatus>(ToolCallStatus.Idle)
    val lastToolCallStatus: StateFlow<ToolCallStatus> = _lastToolCallStatus.asStateFlow()

    private val _connectionState = MutableStateFlow<OpenClawConnectionState>(OpenClawConnectionState.NotConfigured)
    val connectionState: StateFlow<OpenClawConnectionState> = _connectionState.asStateFlow()

    fun setToolCallStatus(status: ToolCallStatus) {
        _lastToolCallStatus.value = status
    }

    private val client = OkHttpClient.Builder()
        .readTimeout(120, TimeUnit.SECONDS)
        .connectTimeout(10, TimeUnit.SECONDS)
        .build()

    private val pingClient = OkHttpClient.Builder()
        .readTimeout(5, TimeUnit.SECONDS)
        .connectTimeout(5, TimeUnit.SECONDS)
        .build()

    private var _sessionKey: String = "agent:$DEFAULT_AGENT_ID:main"
    val currentSessionKey: String get() = _sessionKey

    private val conversationHistory = mutableListOf<JSONObject>()

    suspend fun checkConnection() = withContext(Dispatchers.IO) {
        if (!GeminiConfig.isOpenClawConfigured) {
            _connectionState.value = OpenClawConnectionState.NotConfigured
            return@withContext
        }
        _connectionState.value = OpenClawConnectionState.Checking

        val url = "${GeminiConfig.openClawHost}:${GeminiConfig.openClawPort}/v1/chat/completions"
        try {
            val request = Request.Builder()
                .url(url)
                .get()
                .addHeader("Authorization", "Bearer ${GeminiConfig.openClawGatewayToken}")
                .addHeader("x-openclaw-message-channel", "glass")
                .build()

            val response = pingClient.newCall(request).execute()
            val code = response.code
            response.close()

            if (code in 200..499) {
                _connectionState.value = OpenClawConnectionState.Connected
                Log.d(TAG, "Gateway reachable (HTTP $code)")
            } else {
                _connectionState.value = OpenClawConnectionState.Unreachable("Unexpected response")
            }
        } catch (e: Exception) {
            _connectionState.value = OpenClawConnectionState.Unreachable(e.message ?: "Unknown error")
            Log.d(TAG, "Gateway unreachable: ${e.message}")
        }
    }

    fun resetSession() {
        conversationHistory.clear()
        Log.d(TAG, "Session reset (key retained: $_sessionKey)")
    }

    fun switchProfile() {
        conversationHistory.clear()
        _sessionKey = "agent:$DEFAULT_AGENT_ID:main"
        Log.d(TAG, "Profile switched, session reset")
    }

    fun switchToSession(sessionKey: String, withHistory: List<Map<String, String>> = emptyList()) {
        _sessionKey = sessionKey
        conversationHistory.clear()
        for (msg in withHistory) {
            val role = msg["role"] ?: continue
            val content = msg["content"] ?: continue
            conversationHistory.add(JSONObject().apply {
                put("role", role)
                put("content", content)
            })
        }
        Log.d(TAG, "Switched to session: $sessionKey, loaded ${conversationHistory.size} history messages")
    }

    suspend fun generateNewChatSessionKey(): String = withContext(Dispatchers.IO) {
        val id = JarvisChat.makeId()
        "agent:$DEFAULT_AGENT_ID:chat-$id"
    }

    suspend fun fetchSessionList(): List<String> = withContext(Dispatchers.IO) {
        if (!GeminiConfig.isOpenClawConfigured) return@withContext emptyList()
        try {
            val url = "${GeminiConfig.openClawHost}:${GeminiConfig.openClawPort}/v1/sessions"
            val request = Request.Builder()
                .url(url)
                .get()
                .addHeader("Authorization", "Bearer ${GeminiConfig.openClawGatewayToken}")
                .build()
            val response = pingClient.newCall(request).execute()
            val body = response.body?.string() ?: ""
            response.close()
            if (!response.isSuccessful) return@withContext emptyList()
            val json = JSONObject(body)
            val sessions = json.optJSONArray("sessions") ?: return@withContext emptyList()
            (0 until sessions.length()).mapNotNull { sessions.optString(it).ifEmpty { null } }
        } catch (e: Exception) {
            Log.e(TAG, "fetchSessionList error: ${e.message}")
            emptyList()
        }
    }

    suspend fun fetchSessionHistory(sessionKey: String, limit: Int = 20): List<Map<String, String>> =
        withContext(Dispatchers.IO) {
            if (!GeminiConfig.isOpenClawConfigured) return@withContext emptyList()
            try {
                val encodedKey = java.net.URLEncoder.encode(sessionKey, "UTF-8")
                val url = "${GeminiConfig.openClawHost}:${GeminiConfig.openClawPort}/v1/sessions/$encodedKey/history?limit=$limit"
                val request = Request.Builder()
                    .url(url)
                    .get()
                    .addHeader("Authorization", "Bearer ${GeminiConfig.openClawGatewayToken}")
                    .build()
                val response = pingClient.newCall(request).execute()
                val body = response.body?.string() ?: ""
                response.close()
                if (!response.isSuccessful) return@withContext emptyList()
                val json = JSONObject(body)
                val messages = json.optJSONArray("messages") ?: return@withContext emptyList()
                (0 until messages.length()).mapNotNull { i ->
                    val msg = messages.optJSONObject(i) ?: return@mapNotNull null
                    val role = msg.optString("role").ifEmpty { return@mapNotNull null }
                    val content = msg.optString("content").ifEmpty { return@mapNotNull null }
                    mapOf("role" to role, "content" to content)
                }
            } catch (e: Exception) {
                Log.e(TAG, "fetchSessionHistory error: ${e.message}")
                emptyList()
            }
        }

    suspend fun delegateTask(
        task: String,
        toolName: String = "execute"
    ): ToolResult = withContext(Dispatchers.IO) {
        _lastToolCallStatus.value = ToolCallStatus.Executing(toolName)

        val url = "${GeminiConfig.openClawHost}:${GeminiConfig.openClawPort}/v1/chat/completions"

        conversationHistory.add(JSONObject().apply {
            put("role", "user")
            put("content", task)
        })

        if (conversationHistory.size > MAX_HISTORY_TURNS * 2) {
            val trimmed = conversationHistory.takeLast(MAX_HISTORY_TURNS * 2)
            conversationHistory.clear()
            conversationHistory.addAll(trimmed)
        }

        Log.d(TAG, "Sending ${conversationHistory.size} messages in conversation")

        try {
            val messagesArray = JSONArray()
            for (msg in conversationHistory) {
                messagesArray.put(msg)
            }

            val body = JSONObject().apply {
                put("model", "openclaw")
                put("messages", messagesArray)
                put("stream", false)
            }

            val request = Request.Builder()
                .url(url)
                .post(body.toString().toRequestBody("application/json".toMediaType()))
                .addHeader("Authorization", "Bearer ${GeminiConfig.openClawGatewayToken}")
                .addHeader("Content-Type", "application/json")
                .addHeader("x-openclaw-session-key", _sessionKey)
                .addHeader("x-openclaw-message-channel", "glass")
                .build()

            val response = client.newCall(request).execute()
            val responseBody = response.body?.string() ?: ""
            val statusCode = response.code
            response.close()

            if (statusCode !in 200..299) {
                Log.d(TAG, "Chat failed: HTTP $statusCode - ${responseBody.take(200)}")
                _lastToolCallStatus.value = ToolCallStatus.Failed(toolName, "HTTP $statusCode")
                return@withContext ToolResult.Failure("Agent returned HTTP $statusCode")
            }

            val json = JSONObject(responseBody)
            val choices = json.optJSONArray("choices")
            val content = choices?.optJSONObject(0)
                ?.optJSONObject("message")
                ?.optString("content", "")

            if (!content.isNullOrEmpty()) {
                conversationHistory.add(JSONObject().apply {
                    put("role", "assistant")
                    put("content", content)
                })
                Log.d(TAG, "Agent result: ${content.take(200)}")
                _lastToolCallStatus.value = ToolCallStatus.Completed(toolName)
                return@withContext ToolResult.Success(content)
            }

            conversationHistory.add(JSONObject().apply {
                put("role", "assistant")
                put("content", responseBody)
            })
            Log.d(TAG, "Agent raw: ${responseBody.take(200)}")
            _lastToolCallStatus.value = ToolCallStatus.Completed(toolName)
            return@withContext ToolResult.Success(responseBody)
        } catch (e: Exception) {
            Log.e(TAG, "Agent error: ${e.message}")
            _lastToolCallStatus.value = ToolCallStatus.Failed(toolName, e.message ?: "Unknown")
            return@withContext ToolResult.Failure("Agent error: ${e.message}")
        }
    }
}
