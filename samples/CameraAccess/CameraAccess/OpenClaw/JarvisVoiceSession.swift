import ActivityKit
import AVFoundation
import Foundation
import Speech
import UIKit

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date

    enum Role: String, Codable { case user, assistant }

    init(role: Role, text: String) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = Date()
    }
}

@MainActor
class JarvisVoiceSession: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case listening
        case sending
        case speaking
    }

    @Published var state: State = .idle {
        didSet {
            if isLiveModeActive {
                updateLiveActivity()
            }
        }
    }
    @Published var liveTranscript: String = ""
    @Published var messages: [ChatMessage] = []
    @Published var errorMessage: String?
    @Published var isLiveModeActive = false
    @Published var chatList: [JarvisChat] = []
    @Published var activeChatId: String = "main"

    var activeChatTitle: String {
        if activeChatId == "main" { return "Jarvis" }
        return chatList.first { $0.id == activeChatId }?.title ?? "Jarvis"
    }

    var frameProvider: (() -> [UIImage])?
    var isLiveStreamingActive: Bool = false
    var onStopSessionRequested: (() -> Void)?

    private var liveActivity: Activity<JarvisActivityAttributes>?

    private let bridge = OpenClawBridge()
    private let eventClient = OpenClawEventClient()
    private let synthesizer = AVSpeechSynthesizer()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var standaloneEngine: AVAudioEngine?
    private var finalTranscriptContinuation: CheckedContinuation<String, Never>?

    private weak var liveModeAudioManager: AudioManager?
    private var liveStandaloneEngine: AVAudioEngine?
    private var silenceTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var messageSaveTask: Task<Void, Never>?
    private var ttsBgTask: UIBackgroundTaskIdentifier = .invalid
    private var audioInterruptionObserver: NSObjectProtocol?

    private static let maxStoredMessages = 100
    private var store: ProfileScopedStore<[ChatMessage]>

    override init() {
        let profileId = ProfileManager.shared.activeProfile?.id.uuidString ?? "default"
        let savedChatId = UserDefaults.standard.string(forKey: "jarvis.activeChatId.\(profileId)") ?? "main"
        let prefix = savedChatId == "main" ? "jarvis.chat.messages" : "jarvis.chat.messages.\(savedChatId)"
        self.store = ProfileScopedStore<[ChatMessage]>(keyPrefix: prefix, profileId: profileId)
        super.init()
        self.activeChatId = savedChatId
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        messages = store.load() ?? []
        chatList = Self.loadLocalChatList(profileId: profileId)
        ensureMainChat(profileId: profileId)
        registerWidgetNotificationObservers()
        observeAudioInterruptions()
        _ = KokoraTTSEngine.shared
    }

    // MARK: - Chat storage helpers

    private static func loadLocalChatList(profileId: String) -> [JarvisChat] {
        guard let data = UserDefaults.standard.data(forKey: "jarvis.chats.\(profileId)"),
              let list = try? JSONDecoder().decode([JarvisChat].self, from: data)
        else { return [] }
        return list
    }

    private func saveLocalChatList(_ list: [JarvisChat], profileId: String) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: "jarvis.chats.\(profileId)")
    }

    private func makeStore(chatId: String, profileId: String) -> ProfileScopedStore<[ChatMessage]> {
        let prefix = chatId == "main" ? "jarvis.chat.messages" : "jarvis.chat.messages.\(chatId)"
        return ProfileScopedStore<[ChatMessage]>(keyPrefix: prefix, profileId: profileId)
    }

    private var profileId: String {
        ProfileManager.shared.activeProfile?.id.uuidString ?? "default"
    }

    private func ensureMainChat(profileId: String) {
        guard !chatList.contains(where: { $0.id == "main" }) else { return }
        let main = JarvisChat(
            id: "main",
            title: "Jarvis",
            previewText: "",
            createdAt: Date(),
            updatedAt: Date(),
            sessionKey: bridge.currentSessionKey
        )
        chatList.insert(main, at: 0)
        saveLocalChatList(chatList, profileId: profileId)
    }

    // MARK: - Chat management

    func loadChatList() async {
        let pid = profileId
        chatList = Self.loadLocalChatList(profileId: pid)
        ensureMainChat(profileId: pid)

        let serverKeys = await bridge.fetchSessionList()
        var updated = false
        for key in serverKeys {
            if chatList.contains(where: { $0.sessionKey == key }) { continue }
            if key.hasSuffix(":main") { continue }
            let parts = key.split(separator: ":")
            let chatId: String
            if let last = parts.last, last.hasPrefix("chat-") {
                chatId = String(last.dropFirst(5))
            } else {
                chatId = JarvisChat.makeId()
            }
            let chat = JarvisChat(
                id: chatId,
                title: "Chat \(chatId.prefix(4))",
                previewText: "",
                createdAt: Date(),
                updatedAt: Date(),
                sessionKey: key
            )
            chatList.append(chat)
            updated = true
        }
        if updated {
            sortChatList()
            saveLocalChatList(chatList, profileId: pid)
        }
    }

    func newChat() async {
        let pid = profileId
        let sessionKey = await bridge.generateNewChatSessionKey()
        let parts = sessionKey.split(separator: ":")
        let chatId: String
        if let last = parts.last, last.hasPrefix("chat-") {
            chatId = String(last.dropFirst(5))
        } else {
            chatId = JarvisChat.makeId()
        }
        let chat = JarvisChat(
            id: chatId,
            title: "New Chat",
            previewText: "",
            createdAt: Date(),
            updatedAt: Date(),
            sessionKey: sessionKey
        )
        chatList.insert(chat, at: chatList.first?.id == "main" ? 1 : 0)
        saveLocalChatList(chatList, profileId: pid)
        await switchChat(to: chat)
    }

    func switchChat(to chat: JarvisChat) async {
        messageSaveTask?.cancel()
        messageSaveTask = nil
        let pid = profileId
        store.save(messages)
        activeChatId = chat.id
        UserDefaults.standard.set(chat.id, forKey: "jarvis.activeChatId.\(pid)")
        store = makeStore(chatId: chat.id, profileId: pid)
        messages = store.load() ?? []
        liveTranscript = ""
        let serverHistory = await bridge.fetchSessionHistory(sessionKey: chat.sessionKey, limit: 20)
        let bridgeHistory: [[String: Any]] = serverHistory.compactMap { msg in
            guard let role = msg["role"], let content = msg["content"] else { return nil }
            return ["role": role, "content": content]
        }
        bridge.switchToSession(chat.sessionKey, withHistory: bridgeHistory)
        NSLog("[JarvisPTT] Switched to chat: %@ (%@)", chat.title, chat.id)
    }

    func renameChat(id: String, title: String) {
        let pid = profileId
        if let idx = chatList.firstIndex(where: { $0.id == id }) {
            chatList[idx].title = title
            saveLocalChatList(chatList, profileId: pid)
        }
    }

    func deleteChat(_ chat: JarvisChat) {
        guard chat.id != "main" else { return }
        let pid = profileId
        let key = "jarvis.chat.messages.\(chat.id).\(pid)"
        UserDefaults.standard.removeObject(forKey: key)
        chatList.removeAll { $0.id == chat.id }
        saveLocalChatList(chatList, profileId: pid)
        if activeChatId == chat.id {
            if let main = chatList.first(where: { $0.id == "main" }) {
                Task { await switchChat(to: main) }
            }
        }
    }

    private func sortChatList() {
        chatList.sort {
            if $0.id == "main" { return true }
            if $1.id == "main" { return false }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func updateActiveChatMeta(with message: ChatMessage) {
        let pid = profileId
        guard let idx = chatList.firstIndex(where: { $0.id == activeChatId }) else { return }
        if message.role == .user
            && chatList[idx].title == "New Chat"
            && messages.filter({ $0.role == .user }).count == 1 {
            chatList[idx].title = JarvisChat.autoTitle(from: message.text)
        }
        if message.role == .assistant {
            chatList[idx].previewText = String(message.text.prefix(80))
        }
        chatList[idx].updatedAt = Date()
        sortChatList()
        saveLocalChatList(chatList, profileId: pid)
    }

    func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }
        if #available(iOS 17, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    func startListening(sharedAudioManager: AudioManager?) {
        guard state == .idle else { return }
        synthesizer.stopSpeaking(at: .immediate)
        KokoraTTSEngine.shared.stop()
        liveTranscript = ""
        finalTranscriptContinuation = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.liveTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.resumeTranscript(result.bestTranscription.formattedString)
                    }
                }
                if error != nil {
                    self.resumeTranscript(self.liveTranscript)
                }
            }
        }

        if let sharedManager = sharedAudioManager {
            sharedManager.pttAudioConsumer = { [weak self] buffer in
                self?.recognitionRequest?.append(buffer)
            }
            state = .listening
        } else {
            startStandaloneEngine(request: request)
        }
    }

    private func startStandaloneEngine(request: SFSpeechAudioBufferRecognitionRequest) {
        let engine = AVAudioEngine()
        standaloneEngine = engine
        do {
            // Activate session BEFORE querying inputNode format — after TTS switches
            // the session to .playback, inputNode.outputFormat returns 0 Hz and
            // installTap crashes with IsFormatSampleRateAndChannelCountValid.
            try AudioSessionController.shared.activate(.voiceChat)
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }
            engine.prepare()
            try engine.start()
            state = .listening
        } catch {
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            stopEngine()
            errorMessage = "Mic error: \(error.localizedDescription)"
        }
    }

    func stopListeningAndSend(sharedAudioManager: AudioManager?) {
        guard state == .listening else { return }
        state = .sending

        sharedAudioManager?.pttAudioConsumer = nil
        stopEngine()
        recognitionRequest?.endAudio()

        sendTask = Task {
            let transcript = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
                self.finalTranscriptContinuation = cont
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    self.resumeTranscript(self.liveTranscript)
                }
            }

            self.recognitionTask?.cancel()
            self.recognitionTask = nil
            self.recognitionRequest = nil

            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                NSLog("[JarvisPTT] No speech detected")
                self.state = .idle
                return
            }

            self.appendMessage(ChatMessage(role: .user, text: trimmed))

            let frames = self.frameProvider?() ?? []
            NSLog("[JarvisPTT] Sending to Jarvis: \"%@\" with %d frame(s)", trimmed, frames.count)
            let result = await self.bridge.delegateTask(task: trimmed, images: frames)
            switch result {
            case .success(let text):
                NSLog("[JarvisPTT] Jarvis response: %@", String(text.prefix(200)))
                self.appendMessage(ChatMessage(role: .assistant, text: text))
                self.speak(text)
            case .failure(let err):
                NSLog("[JarvisPTT] Jarvis error: %@", err)
                self.errorMessage = err
                self.state = .idle
            }
        }
    }

    // MARK: - Live Mode (always-on voice)

    func startLiveMode(sharedAudioManager: AudioManager?) {
        guard !isLiveModeActive else { return }
        isLiveModeActive = true
        liveModeAudioManager = sharedAudioManager
        NSLog("[JarvisLive] Starting live mode")
        // Claim and hold the audio session before the screen can lock.
        // iOS respects an already-active session on lock; a new activation from
        // background fails with 'cannot interrupt others' (error 560557684).
        // isHeld prevents any deactivate() call from releasing it between turns.
        AudioSessionController.shared.isHeld = true
        try? AudioSessionController.shared.activate(.voiceChatEchoCancelled)
        connectEventClient()
        // Start and hold the mic engine for the entire live session.
        // Never stopping/restarting it means no AUIOClient_StartIO call from locked state.
        if sharedAudioManager == nil {
            startLiveStandaloneEngine()
        }
        startLiveActivity()
        startNextLiveListeningCycle()
    }

    func stopLiveMode() {
        guard isLiveModeActive else { return }
        NSLog("[JarvisLive] Stopping live mode")
        isLiveModeActive = false
        AudioSessionController.shared.isHeld = false
        silenceTask?.cancel()
        silenceTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        eventClient.disconnect()
        eventClient.onNotification = nil
        liveModeAudioManager?.pttAudioConsumer = nil
        stopEngine()
        if let engine = liveStandaloneEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            liveStandaloneEngine = nil
            NSLog("[JarvisLive] Persistent standalone engine stopped")
        }
        synthesizer.stopSpeaking(at: .immediate)
        KokoraTTSEngine.shared.stop()
        liveTranscript = ""
        state = .idle
        liveModeAudioManager = nil
        endLiveActivity()
    }

    private func connectEventClient() {
        guard SettingsManager.shared.proactiveNotificationsEnabled else { return }
        eventClient.onNotification = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self, self.isLiveModeActive else { return }
                NSLog("[JarvisLive] Proactive notification: %@", String(text.prefix(120)))
                let message = ChatMessage(role: .assistant, text: text)
                self.appendMessage(message)
                // Speak only when idle — don't interrupt an ongoing turn
                if self.state == .idle {
                    self.speak(text)
                }
            }
        }
        eventClient.connect()
        NSLog("[JarvisLive] OpenClaw event client connected")
    }

    private func startLiveStandaloneEngine() {
        let engine = AVAudioEngine()
        do {
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }
            engine.prepare()
            try engine.start()
            liveStandaloneEngine = engine
            NSLog("[JarvisLive] Persistent standalone engine started")
        } catch {
            NSLog("[JarvisLive] Persistent standalone engine failed to start: %@", error.localizedDescription)
        }
    }

    // MARK: - Live Activity (lock-screen widget)

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            NSLog("[JarvisActivity] Activities not enabled on this device")
            return
        }
        let state = JarvisActivityAttributes.ContentState(
            jarvisState: .idle,
            showLiveButton: SettingsManager.shared.showLiveButton,
            isLiveStreaming: isLiveStreamingActive
        )
        do {
            liveActivity = try Activity<JarvisActivityAttributes>.request(
                attributes: JarvisActivityAttributes(),
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            NSLog("[JarvisActivity] Started id=%@", liveActivity?.id ?? "nil")
        } catch {
            NSLog("[JarvisActivity] Failed to start: %@", error.localizedDescription)
        }
    }

    private func updateLiveActivity() {
        guard let liveActivity else { return }
        let jarvisState: JarvisActivityAttributes.ContentState.JarvisState
        switch state {
        case .idle:      jarvisState = .idle
        case .listening: jarvisState = .listening
        case .sending:   jarvisState = .sending
        case .speaking:  jarvisState = .speaking
        }
        let newState = JarvisActivityAttributes.ContentState(
            jarvisState: jarvisState,
            showLiveButton: SettingsManager.shared.showLiveButton,
            isLiveStreaming: isLiveStreamingActive
        )
        Task {
            await liveActivity.update(.init(state: newState, staleDate: nil))
        }
    }

    func updateLiveActivityForStreamingChange() {
        updateLiveActivity()
    }

    private func endLiveActivity() {
        guard let liveActivity else { return }
        let finalState = JarvisActivityAttributes.ContentState(
            jarvisState: .idle,
            showLiveButton: false,
            isLiveStreaming: false
        )
        Task {
            await liveActivity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            NSLog("[JarvisActivity] Ended")
        }
        self.liveActivity = nil
    }

    // MARK: - Widget Darwin notification bridge

    private func registerWidgetNotificationObservers() {
        bridgeDarwinToLocal("com.xiaoanliu.VisionClaw.widget.stopJarvis")
        bridgeDarwinToLocal("com.xiaoanliu.VisionClaw.widget.stopSession")

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("com.xiaoanliu.VisionClaw.widget.stopJarvis"),
            object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                NSLog("[JarvisWidget] Received stopJarvis from widget")
                self?.stopLiveMode()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("com.xiaoanliu.VisionClaw.widget.stopSession"),
            object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                NSLog("[JarvisWidget] Received stopSession from widget")
                self?.stopLiveMode()
                self?.onStopSessionRequested?()
            }
        }
    }

    private func bridgeDarwinToLocal(_ name: String) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, cfName, _, _ in
                guard let cfName else { return }
                let localName = cfName.rawValue as String
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name(localName), object: nil)
                }
            },
            name as CFString, nil, .deliverImmediately
        )
    }

    private func startNextLiveListeningCycle() {
        guard isLiveModeActive, state == .idle else { return }
        liveTranscript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                guard self.isLiveModeActive, self.state == .listening else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    guard !text.isEmpty else { return }
                    self.liveTranscript = text
                    if result.isFinal {
                        self.silenceTask?.cancel()
                        await self.sendLiveUtterance()
                    } else {
                        self.scheduleSilenceSend()
                    }
                } else if error != nil {
                    self.silenceTask?.cancel()
                    if !self.liveTranscript.trimmingCharacters(in: .whitespaces).isEmpty {
                        await self.sendLiveUtterance()
                    } else {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        self.startNextLiveListeningCycle()
                    }
                }
            }
        }

        if let sharedManager = liveModeAudioManager {
            sharedManager.pttAudioConsumer = { [weak self] buffer in
                self?.recognitionRequest?.append(buffer)
            }
        } else if liveStandaloneEngine != nil {
            // Persistent engine is already running — recognitionRequest update above is sufficient.
            NSLog("[JarvisLive] Reusing persistent engine for new recognition cycle")
        } else {
            startStandaloneEngine(request: request)
        }
        state = .listening
        NSLog("[JarvisLive] Listening…")
    }

    private func scheduleSilenceSend() {
        silenceTask?.cancel()
        guard !liveTranscript.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            // Launch independent task so cancelling the silence timer doesn't
            // kill the in-flight network request via cooperative cancellation.
            Task { @MainActor [weak self] in
                guard let self, self.isLiveModeActive else { return }
                await self.sendLiveUtterance()
            }
        }
    }

    private func sendLiveUtterance() async {
        let trimmed = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state == .listening, isLiveModeActive else { return }

        silenceTask?.cancel()
        silenceTask = nil
        liveModeAudioManager?.pttAudioConsumer = nil
        // Keep session active (deactivateSession: false) so iOS doesn't suspend
        // the app while the network call is in flight when screen is locked.
        stopEngine(deactivateSession: false)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        state = .sending
        liveTranscript = ""
        appendMessage(ChatMessage(role: .user, text: trimmed))

        let frames = frameProvider?() ?? []
        NSLog("[JarvisLive] Sending: \"%@\" with %d frames", trimmed, frames.count)

        // Background task gives iOS an explicit signal that we need time to finish
        // this network request even if the screen is locked.
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "jarvis-openclaw") {
            UIApplication.shared.endBackgroundTask(bgTask)
        }

        let result = await bridge.delegateTask(task: trimmed, images: frames)

        UIApplication.shared.endBackgroundTask(bgTask)

        guard isLiveModeActive else {
            NSLog("[JarvisLive] Live mode stopped during API call, discarding response")
            state = .idle
            return
        }

        switch result {
        case .success(let text):
            appendMessage(ChatMessage(role: .assistant, text: text))
            speak(text)
        case .failure(let err):
            NSLog("[JarvisLive] Error: %@", err)
            errorMessage = err
            state = .idle
            if isLiveModeActive {
                try? await Task.sleep(nanoseconds: 600_000_000)
                startNextLiveListeningCycle()
            }
        }
    }

    func sendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state == .idle else { return }
        state = .sending
        appendMessage(ChatMessage(role: .user, text: trimmed))
        sendTask = Task {
            let frames = self.frameProvider?() ?? []
            let result = await self.bridge.delegateTask(task: trimmed, images: frames)
            switch result {
            case .success(let response):
                self.appendMessage(ChatMessage(role: .assistant, text: response))
                self.state = .idle
            case .failure(let err):
                self.errorMessage = err
                self.state = .idle
            }
        }
    }

    func cancel(sharedAudioManager: AudioManager?) {
        sendTask?.cancel()
        sendTask = nil
        sharedAudioManager?.pttAudioConsumer = nil
        resumeTranscript(liveTranscript)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        stopEngine()
        synthesizer.stopSpeaking(at: .immediate)
        KokoraTTSEngine.shared.stop()
        state = .idle
        liveTranscript = ""
    }

    func switchProfile() {
        sendTask?.cancel()
        sendTask = nil
        messageSaveTask?.cancel()
        messageSaveTask = nil
        let newPid = ProfileManager.shared.activeProfile?.id.uuidString ?? "default"
        store.save(messages)
        let savedChatId = UserDefaults.standard.string(forKey: "jarvis.activeChatId.\(newPid)") ?? "main"
        activeChatId = savedChatId
        store = makeStore(chatId: savedChatId, profileId: newPid)
        messages = store.load() ?? []
        chatList = Self.loadLocalChatList(profileId: newPid)
        ensureMainChat(profileId: newPid)
        liveTranscript = ""
        bridge.switchProfile()
    }

    func clearHistory() {
        store.clear()
        messages = []
        liveTranscript = ""
        bridge.resetSession()
        let pid = profileId
        if let idx = chatList.firstIndex(where: { $0.id == activeChatId }) {
            chatList[idx].previewText = ""
            saveLocalChatList(chatList, profileId: pid)
        }
    }

    private func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        if messages.count > Self.maxStoredMessages {
            messages = Array(messages.suffix(Self.maxStoredMessages))
        }
        scheduleSave()
        updateActiveChatMeta(with: message)
    }

    private func scheduleSave() {
        messageSaveTask?.cancel()
        messageSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.store.save(self.messages)
        }
    }

    private func resumeTranscript(_ text: String) {
        guard let cont = finalTranscriptContinuation else { return }
        finalTranscriptContinuation = nil
        cont.resume(returning: text)
    }

    private func stopEngine(deactivateSession: Bool = true) {
        if let engine = standaloneEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            standaloneEngine = nil
            // Release the audio session so AVSpeechSynthesizer can acquire it cleanly.
            // In live mode, skip deactivation so iOS keeps the app alive in background
            // during the network call between stopping recording and starting TTS.
            if deactivateSession {
                AudioSessionController.shared.deactivate()
            }
        }
    }

    private func speak(_ text: String) {
        let clean = TextSanitizer.sanitize(text)

        // Keep app alive while speaking so audio continues when screen is locked.
        if ttsBgTask != .invalid { UIApplication.shared.endBackgroundTask(ttsBgTask) }
        ttsBgTask = UIApplication.shared.beginBackgroundTask(withName: "jarvis-tts") { [weak self] in
            guard let self else { return }
            NSLog("[JarvisTTS] Background task expired before didFinish")
            UIApplication.shared.endBackgroundTask(self.ttsBgTask)
            self.ttsBgTask = .invalid
        }
        let isBackground = UIApplication.shared.applicationState != .active
        NSLog("[JarvisTTS] speak() called — bgTask=%lu screen=%@",
              ttsBgTask.rawValue, isBackground ? "background/locked" : "active")

        var sessionReady = false
        if AudioSessionController.shared.isHeld {
            AudioSessionController.shared.reactivate()
            sessionReady = true
            NSLog("[JarvisTTS] Audio session resumed via reactivate() (held)")
        } else {
            do {
                try AudioSessionController.shared.activate(.voiceChatEchoCancelled)
                NSLog("[JarvisTTS] Audio session activated OK (voiceChatEchoCancelled)")
                sessionReady = true
            } catch {
                NSLog("[JarvisTTS] voiceChatEchoCancelled failed (%@), trying playback fallback",
                      error.localizedDescription)
                do {
                    try AudioSessionController.shared.activate(.playback)
                    NSLog("[JarvisTTS] Audio session activated OK (playback fallback)")
                    sessionReady = true
                } catch {
                    NSLog("[JarvisTTS] All audio session activation failed: %@", error.localizedDescription)
                }
            }
        }

        guard sessionReady else {
            NSLog("[JarvisTTS] Skipping TTS — no audio session available")
            if ttsBgTask != .invalid {
                UIApplication.shared.endBackgroundTask(ttsBgTask)
                ttsBgTask = .invalid
            }
            state = .idle
            if isLiveModeActive {
                Task { try? await Task.sleep(nanoseconds: 300_000_000); self.startNextLiveListeningCycle() }
            }
            return
        }

        let kokoroEnabled = SettingsManager.shared.useKokoroTTS
        let kokoroReady = KokoraTTSEngine.shared.isReady
        NSLog("[JarvisTTS] TTS decision — kokoroEnabled=%@ kokoroReady=%@",
              kokoroEnabled ? "true" : "false", kokoroReady ? "true" : "false")

        if kokoroEnabled && kokoroReady {
            NSLog("[JarvisTTS] Kokoro generating — text=\"%@\"", String(clean.prefix(60)))
            KokoraTTSEngine.shared.speak(clean) { [weak self] in
                Task { @MainActor [weak self] in self?.handleTTSDidFinish() }
            }
            KokoraTTSEngine.shared.onPlaybackStarted = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    NSLog("[JarvisTTS] Kokoro playback started — switching to speaking")
                    self.state = .speaking
                }
            }
        } else {
            state = .speaking
            let utterance = AVSpeechUtterance(string: clean)
            utterance.rate = 0.52
            utterance.voice = bestEnglishVoice()
            NSLog("[JarvisTTS] Apple TTS — text=\"%@\"", String(clean.prefix(60)))
            synthesizer.speak(utterance)
        }
    }

    private func handleTTSDidFinish() {
        NSLog("[JarvisTTS] handleTTSDidFinish — ending bgTask, state=%@", "\(state)")
        if ttsBgTask != .invalid {
            UIApplication.shared.endBackgroundTask(ttsBgTask)
            ttsBgTask = .invalid
        }
        guard isLiveModeActive else {
            state = .idle
            return
        }
        state = .idle
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.startNextLiveListeningCycle()
        }
    }

    private func observeAudioInterruptions() {
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }

            if type == .began {
                NSLog("[JarvisTTS] Audio session interrupted (screen lock / call) — state=%@",
                      "\(self.state)")
                AudioSessionController.shared.markInterrupted()
                if self.state == .speaking {
                    self.synthesizer.stopSpeaking(at: .immediate)
                    KokoraTTSEngine.shared.stop()
                }
            } else if type == .ended {
                let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                NSLog("[JarvisTTS] Audio session interruption ended — shouldResume=%@",
                      options.contains(.shouldResume) ? "true" : "false")
                if self.isLiveModeActive {
                    // Use reactivate() (setActive only) to resume the held session without
                    // reconfiguring category, which fails from background with '!int'.
                    AudioSessionController.shared.reactivate()
                }
            }
        }
    }

    private func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en-US") }
        let quality: [AVSpeechSynthesisVoiceQuality] = [.premium, .enhanced, .default]
        for q in quality {
            if let voice = voices.first(where: { $0.quality == q }) {
                NSLog("[Jarvis] Using voice: %@ (quality %d)", voice.name, q.rawValue)
                return voice
            }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension JarvisVoiceSession: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        NSLog("[JarvisTTS] AVSpeechSynthesizer didFinish")
        Task { @MainActor in self.handleTTSDidFinish() }
    }
}
