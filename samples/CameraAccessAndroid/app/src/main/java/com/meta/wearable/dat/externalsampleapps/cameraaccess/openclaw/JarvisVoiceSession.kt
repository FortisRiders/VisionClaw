package com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw

import android.app.Application
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.meta.wearable.dat.externalsampleapps.cameraaccess.settings.SettingsManager
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

class JarvisVoiceSession(application: Application) : AndroidViewModel(application) {

    companion object {
        private const val TAG = "JarvisVoiceSession"
        private const val MAX_STORED_MESSAGES = 100
    }

    enum class State { IDLE, LISTENING, SENDING, SPEAKING }

    private val _state = MutableStateFlow(State.IDLE)
    val state: StateFlow<State> = _state.asStateFlow()

    private val _liveTranscript = MutableStateFlow("")
    val liveTranscript: StateFlow<String> = _liveTranscript.asStateFlow()

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _isLiveModeActive = MutableStateFlow(false)
    val isLiveModeActive: StateFlow<Boolean> = _isLiveModeActive.asStateFlow()

    private val _chatList = MutableStateFlow<List<JarvisChat>>(emptyList())
    val chatList: StateFlow<List<JarvisChat>> = _chatList.asStateFlow()

    private val _activeChatId = MutableStateFlow("main")
    val activeChatId: StateFlow<String> = _activeChatId.asStateFlow()

    val activeChatTitle: String
        get() {
            val id = _activeChatId.value
            if (id == "main") return "Jarvis"
            return _chatList.value.firstOrNull { it.id == id }?.title ?: "Jarvis"
        }

    private val bridge = OpenClawBridge()
    private val eventClient = OpenClawEventClient()
    private val ttsEngine: KokoraTTSEngine by lazy {
        KokoraTTSEngine.getInstance(getApplication())
    }

    private var speechRecognizer: SpeechRecognizer? = null
    private var sendJob: Job? = null
    private var messageSaveJob: Job? = null
    private var silenceJob: Job? = null

    private var partialTranscript = ""
    private var pttMode = false

    init {
        val savedChatId = SettingsManager.activeChatId
        _activeChatId.value = savedChatId
        _messages.value = loadMessages(savedChatId)
        val loaded = loadChatList()
        val withMain = if (loaded.none { it.id == "main" }) {
            listOf(JarvisChat(
                id = "main", title = "Jarvis", previewText = "",
                sessionKey = bridge.currentSessionKey,
            )) + loaded
        } else loaded
        _chatList.value = withMain
        if (withMain !== loaded) saveChatList(withMain)
    }

    // MARK: - Chat management

    suspend fun loadChatList() {
        val local = loadChatList()
        val withMain = if (local.none { it.id == "main" }) {
            listOf(JarvisChat(
                id = "main", title = "Jarvis", previewText = "",
                sessionKey = bridge.currentSessionKey,
            )) + local
        } else local
        _chatList.value = withMain

        val serverKeys = bridge.fetchSessionList()
        if (serverKeys.isEmpty()) return
        val current = withMain.toMutableList()
        var updated = false
        for (key in serverKeys) {
            if (current.any { it.sessionKey == key }) continue
            if (key.endsWith(":main")) continue
            val last = key.split(":").lastOrNull() ?: continue
            val chatId = if (last.startsWith("chat-")) last.removePrefix("chat-") else JarvisChat.makeId()
            current.add(JarvisChat(
                id = chatId,
                title = "Chat ${chatId.take(4)}",
                previewText = "",
                sessionKey = key,
            ))
            updated = true
        }
        if (updated) {
            sortChatList(current)
            _chatList.value = current
            saveChatList(current)
        }
    }

    suspend fun newChat() {
        val sessionKey = bridge.generateNewChatSessionKey()
        val last = sessionKey.split(":").lastOrNull() ?: ""
        val chatId = if (last.startsWith("chat-")) last.removePrefix("chat-") else JarvisChat.makeId()
        val chat = JarvisChat(
            id = chatId, title = "New Chat", previewText = "", sessionKey = sessionKey,
        )
        val current = _chatList.value.toMutableList()
        val insertAt = if (current.firstOrNull()?.id == "main") 1 else 0
        current.add(insertAt, chat)
        _chatList.value = current
        saveChatList(current)
        switchChat(chat)
    }

    suspend fun switchChat(chat: JarvisChat) {
        messageSaveJob?.cancel()
        messageSaveJob = null
        saveMessages(_activeChatId.value, _messages.value)
        _activeChatId.value = chat.id
        SettingsManager.activeChatId = chat.id
        _messages.value = loadMessages(chat.id)
        _liveTranscript.value = ""
        val serverHistory = bridge.fetchSessionHistory(chat.sessionKey, limit = 20)
        bridge.switchToSession(chat.sessionKey, serverHistory)
        Log.d(TAG, "Switched to chat: ${chat.title} (${chat.id})")
    }

    fun renameChat(id: String, title: String) {
        val current = _chatList.value.toMutableList()
        val idx = current.indexOfFirst { it.id == id }
        if (idx >= 0) {
            current[idx] = current[idx].copy(title = title)
            _chatList.value = current
            saveChatList(current)
        }
    }

    fun deleteChat(chat: JarvisChat) {
        if (chat.id == "main") return
        SettingsManager.deleteChatMessages(chat.id)
        val current = _chatList.value.toMutableList()
        current.removeAll { it.id == chat.id }
        _chatList.value = current
        saveChatList(current)
        if (_activeChatId.value == chat.id) {
            val main = current.firstOrNull { it.id == "main" } ?: return
            viewModelScope.launch { switchChat(main) }
        }
    }

    // MARK: - PTT (push-to-talk)

    fun startListening() {
        if (_state.value != State.IDLE) return
        ttsEngine.stop()
        _liveTranscript.value = ""
        partialTranscript = ""
        pttMode = true
        _state.value = State.LISTENING
        startSpeechRecognizer()
    }

    fun stopListeningAndSend() {
        if (_state.value != State.LISTENING) return
        _state.value = State.SENDING
        speechRecognizer?.stopListening()
        // onResults will deliver final transcript → dispatchSend(text)
    }

    fun sendText(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || _state.value != State.IDLE) return
        _state.value = State.SENDING
        appendMessage(ChatMessage(role = ChatMessage.Role.USER, text = trimmed))
        sendJob?.cancel()
        sendJob = viewModelScope.launch {
            when (val result = bridge.delegateTask(trimmed)) {
                is ToolResult.Success -> {
                    appendMessage(ChatMessage(role = ChatMessage.Role.ASSISTANT, text = result.result))
                    _state.value = State.IDLE
                }
                is ToolResult.Failure -> {
                    _errorMessage.value = result.error
                    _state.value = State.IDLE
                }
            }
        }
    }

    fun cancel() {
        sendJob?.cancel()
        sendJob = null
        silenceJob?.cancel()
        silenceJob = null
        ttsEngine.stop()
        destroySpeechRecognizer()
        _state.value = State.IDLE
        _liveTranscript.value = ""
        partialTranscript = ""
    }

    fun clearError() {
        _errorMessage.value = null
    }

    // MARK: - Live mode

    fun startLiveMode() {
        if (_isLiveModeActive.value) return
        _isLiveModeActive.value = true
        Log.d(TAG, "Live mode started")
        connectEventClientForLive()
        startNextLiveCycle()
    }

    fun stopLiveMode() {
        if (!_isLiveModeActive.value) return
        _isLiveModeActive.value = false
        Log.d(TAG, "Live mode stopped")
        silenceJob?.cancel()
        silenceJob = null
        sendJob?.cancel()
        sendJob = null
        eventClient.onNotification = null
        eventClient.disconnect()
        ttsEngine.stop()
        destroySpeechRecognizer()
        _state.value = State.IDLE
        _liveTranscript.value = ""
        partialTranscript = ""
    }

    private fun connectEventClientForLive() {
        if (!SettingsManager.proactiveNotificationsEnabled) return
        eventClient.onNotification = { text ->
            viewModelScope.launch {
                if (!_isLiveModeActive.value) return@launch
                Log.d(TAG, "Proactive notification: ${text.take(100)}")
                appendMessage(ChatMessage(role = ChatMessage.Role.ASSISTANT, text = text))
                if (_state.value == State.IDLE) speak(text)
            }
        }
        eventClient.connect()
    }

    private fun startNextLiveCycle() {
        if (!_isLiveModeActive.value || _state.value != State.IDLE) return
        _liveTranscript.value = ""
        partialTranscript = ""
        pttMode = false
        _state.value = State.LISTENING
        startSpeechRecognizer()
        Log.d(TAG, "Live: listening…")
    }

    private fun scheduleSilenceSend() {
        silenceJob?.cancel()
        if (partialTranscript.isBlank()) return
        silenceJob = viewModelScope.launch {
            delay(1_800)
            sendLiveUtterance()
        }
    }

    private fun sendLiveUtterance() {
        val trimmed = partialTranscript.trim()
        if (trimmed.isEmpty() || _state.value != State.LISTENING || !_isLiveModeActive.value) return
        silenceJob?.cancel()
        silenceJob = null
        destroySpeechRecognizer()
        _state.value = State.SENDING
        _liveTranscript.value = ""
        appendMessage(ChatMessage(role = ChatMessage.Role.USER, text = trimmed))
        val captured = partialTranscript
        partialTranscript = ""
        sendJob?.cancel()
        sendJob = viewModelScope.launch {
            Log.d(TAG, "Live: sending \"${captured.take(80)}\"")
            when (val result = bridge.delegateTask(captured)) {
                is ToolResult.Success -> {
                    if (_isLiveModeActive.value) {
                        appendMessage(ChatMessage(role = ChatMessage.Role.ASSISTANT, text = result.result))
                        speak(result.result)
                    } else {
                        _state.value = State.IDLE
                    }
                }
                is ToolResult.Failure -> {
                    Log.e(TAG, "Live error: ${result.error}")
                    _errorMessage.value = result.error
                    _state.value = State.IDLE
                    if (_isLiveModeActive.value) {
                        delay(600)
                        startNextLiveCycle()
                    }
                }
            }
        }
    }

    // MARK: - TTS

    private fun speak(text: String) {
        val clean = TextSanitizer.sanitize(text)
        Log.d(TAG, "Speaking: \"${clean.take(60)}\"")

        ttsEngine.onPlaybackStarted = {
            viewModelScope.launch { _state.value = State.SPEAKING }
        }
        ttsEngine.speak(clean, finishCallback = {
            viewModelScope.launch { handleTTSFinished() }
        })
    }

    private fun handleTTSFinished() {
        Log.d(TAG, "TTS finished")
        _state.value = State.IDLE
        if (_isLiveModeActive.value) {
            viewModelScope.launch {
                delay(300)
                startNextLiveCycle()
            }
        }
    }

    // MARK: - SpeechRecognizer

    private fun startSpeechRecognizer() {
        destroySpeechRecognizer()

        if (!SpeechRecognizer.isRecognitionAvailable(getApplication())) {
            Log.e(TAG, "SpeechRecognizer not available")
            _errorMessage.value = "Speech recognition not available on this device"
            _state.value = State.IDLE
            return
        }

        val isLive = !pttMode
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(getApplication()).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {
                    Log.d(TAG, "End of speech (ptt=$pttMode)")
                }

                override fun onError(error: Int) {
                    val msg = speechErrorString(error)
                    Log.e(TAG, "SpeechRecognizer error: $msg ($error)")
                    if (isLive) {
                        if (partialTranscript.isNotBlank()) {
                            sendLiveUtterance()
                        } else {
                            viewModelScope.launch {
                                _state.value = State.IDLE
                                if (_isLiveModeActive.value) {
                                    delay(600)
                                    startNextLiveCycle()
                                }
                            }
                        }
                    } else {
                        dispatchSend(partialTranscript)
                    }
                }

                override fun onResults(results: Bundle?) {
                    val text = results
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull() ?: partialTranscript
                    Log.d(TAG, "Final result: \"${text.take(80)}\"")
                    if (isLive) {
                        partialTranscript = text
                        sendLiveUtterance()
                    } else {
                        dispatchSend(text)
                    }
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    val partial = partialResults
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull() ?: return
                    partialTranscript = partial
                    _liveTranscript.value = partial
                    if (isLive) scheduleSilenceSend()
                }

                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            if (isLive) {
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
            }
        }
        speechRecognizer?.startListening(intent)
    }

    private fun dispatchSend(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) {
            _state.value = State.IDLE
            return
        }
        appendMessage(ChatMessage(role = ChatMessage.Role.USER, text = trimmed))
        sendJob?.cancel()
        sendJob = viewModelScope.launch {
            Log.d(TAG, "Sending to Jarvis: \"${trimmed.take(100)}\"")
            when (val result = bridge.delegateTask(trimmed)) {
                is ToolResult.Success -> {
                    appendMessage(ChatMessage(role = ChatMessage.Role.ASSISTANT, text = result.result))
                    speak(result.result)
                }
                is ToolResult.Failure -> {
                    Log.e(TAG, "Jarvis error: ${result.error}")
                    _errorMessage.value = result.error
                    _state.value = State.IDLE
                }
            }
        }
        destroySpeechRecognizer()
    }

    private fun destroySpeechRecognizer() {
        speechRecognizer?.destroy()
        speechRecognizer = null
    }

    private fun speechErrorString(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_AUDIO -> "audio"
        SpeechRecognizer.ERROR_CLIENT -> "client"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permissions"
        SpeechRecognizer.ERROR_NETWORK -> "network"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network timeout"
        SpeechRecognizer.ERROR_NO_MATCH -> "no match"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "recognizer busy"
        SpeechRecognizer.ERROR_SERVER -> "server"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "speech timeout"
        else -> "unknown ($error)"
    }

    // MARK: - Message persistence

    private fun appendMessage(message: ChatMessage) {
        val updated = (_messages.value + message).takeLast(MAX_STORED_MESSAGES)
        _messages.value = updated
        scheduleSave()
        updateActiveChatMeta(message)
    }

    private fun scheduleSave() {
        messageSaveJob?.cancel()
        messageSaveJob = viewModelScope.launch {
            delay(2_000)
            saveMessages(_activeChatId.value, _messages.value)
        }
    }

    private fun updateActiveChatMeta(message: ChatMessage) {
        val current = _chatList.value.toMutableList()
        val idx = current.indexOfFirst { it.id == _activeChatId.value }
        if (idx < 0) return
        var chat = current[idx].copy(updatedAt = System.currentTimeMillis())
        if (message.role == ChatMessage.Role.USER
            && chat.title == "New Chat"
            && _messages.value.count { it.role == ChatMessage.Role.USER } == 1
        ) {
            chat = chat.copy(title = JarvisChat.autoTitle(message.text))
        }
        if (message.role == ChatMessage.Role.ASSISTANT) {
            chat = chat.copy(previewText = message.text.take(80))
        }
        current[idx] = chat
        sortChatList(current)
        _chatList.value = current
        saveChatList(current)
    }

    fun clearHistory() {
        saveMessages(_activeChatId.value, emptyList())
        _messages.value = emptyList()
        _liveTranscript.value = ""
        bridge.resetSession()
        val current = _chatList.value.toMutableList()
        val idx = current.indexOfFirst { it.id == _activeChatId.value }
        if (idx >= 0) {
            current[idx] = current[idx].copy(previewText = "")
            _chatList.value = current
            saveChatList(current)
        }
    }

    // MARK: - Storage helpers

    private fun saveMessages(chatId: String, messages: List<ChatMessage>) {
        val array = JSONArray()
        for (msg in messages) {
            array.put(JSONObject().apply {
                put("id", msg.id)
                put("role", msg.role.name)
                put("text", msg.text)
                put("timestamp", msg.timestamp)
            })
        }
        SettingsManager.saveChatMessages(chatId, array.toString())
    }

    private fun loadMessages(chatId: String): List<ChatMessage> {
        val json = SettingsManager.loadChatMessages(chatId) ?: return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).mapNotNull { i ->
                val obj = array.optJSONObject(i) ?: return@mapNotNull null
                val role = try {
                    ChatMessage.Role.valueOf(obj.optString("role", "USER"))
                } catch (_: Exception) { ChatMessage.Role.USER }
                ChatMessage(
                    id = obj.optString("id", java.util.UUID.randomUUID().toString()),
                    role = role,
                    text = obj.optString("text", ""),
                    timestamp = obj.optLong("timestamp", System.currentTimeMillis()),
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "loadMessages error: ${e.message}")
            emptyList()
        }
    }

    private fun saveChatList(list: List<JarvisChat>) {
        val array = JSONArray()
        for (chat in list) {
            array.put(JSONObject().apply {
                put("id", chat.id)
                put("title", chat.title)
                put("previewText", chat.previewText)
                put("createdAt", chat.createdAt)
                put("updatedAt", chat.updatedAt)
                put("sessionKey", chat.sessionKey)
            })
        }
        SettingsManager.saveChatList(array.toString())
    }

    private fun loadChatList(): List<JarvisChat> {
        val json = SettingsManager.loadChatList() ?: return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).mapNotNull { i ->
                val obj = array.optJSONObject(i) ?: return@mapNotNull null
                JarvisChat(
                    id = obj.optString("id"),
                    title = obj.optString("title"),
                    previewText = obj.optString("previewText"),
                    createdAt = obj.optLong("createdAt", System.currentTimeMillis()),
                    updatedAt = obj.optLong("updatedAt", System.currentTimeMillis()),
                    sessionKey = obj.optString("sessionKey"),
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "loadChatList error: ${e.message}")
            emptyList()
        }
    }

    private fun sortChatList(list: MutableList<JarvisChat>) {
        list.sortWith { a, b ->
            when {
                a.id == "main" -> -1
                b.id == "main" -> 1
                else -> (b.updatedAt - a.updatedAt).toInt().coerceIn(-1, 1)
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        stopLiveMode()
        destroySpeechRecognizer()
        ttsEngine.stop()
    }
}
