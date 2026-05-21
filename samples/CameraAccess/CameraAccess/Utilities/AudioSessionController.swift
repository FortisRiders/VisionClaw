#if os(iOS)
import AVFoundation

final class AudioSessionController {
    static let shared = AudioSessionController()
    private init() {}

    enum Mode: Equatable {
        case voiceChat              // .playAndRecord, .default — standalone mic + speaker (Jarvis PTT)
        case voiceChatEchoCancelled // .playAndRecord, .voiceChat — hardware AEC during TTS barge-in
        case voiceChatPhone         // .playAndRecord, .voiceChat — iPhone mic+speaker co-located
        case voiceChatGlasses       // .playAndRecord, .videoChat — mic on glasses, mild AEC
        case playback               // .playback, .default
        case inactive
    }

    private(set) var currentMode: Mode = .inactive

    /// When true, deactivate() is a no-op — used during live sessions to keep
    /// the session alive across turn boundaries so iOS doesn't reclaim it on lock.
    var isHeld: Bool = false

    func activate(_ mode: Mode) throws {
        guard mode != currentMode else { return }
        let session = AVAudioSession.sharedInstance()
        switch mode {
        case .voiceChat:
            try session.setCategory(.playAndRecord, mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        case .voiceChatEchoCancelled:
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        case .voiceChatPhone:
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true)
        case .voiceChatGlasses:
            try session.setCategory(.playAndRecord, mode: .videoChat,
                options: [.allowBluetooth, .mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
        case .playback:
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        case .inactive:
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        }
        currentMode = mode
    }

    func deactivate() {
        guard !isHeld else {
            NSLog("[AudioSession] deactivate() suppressed — session is held for live mode")
            return
        }
        try? activate(.inactive)
    }

    /// Call when AVAudioSession sends an interruption-began notification so the
    /// next activate() call properly re-calls setActive(true) instead of bailing early.
    /// No-op when isHeld — held sessions don't need currentMode reset.
    func markInterrupted() {
        guard !isHeld else { return }
        currentMode = .inactive
    }

    /// Resumes a held session after interruption by calling setActive(true) only —
    /// skips setCategory() which fails from background/locked state ('!int' error).
    func reactivate() {
        guard isHeld, currentMode != .inactive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            NSLog("[AudioSession] reactivate() — session resumed (mode=%@)", "\(currentMode)")
        } catch {
            NSLog("[AudioSession] reactivate() failed: %@", error.localizedDescription)
        }
    }
}
#endif
