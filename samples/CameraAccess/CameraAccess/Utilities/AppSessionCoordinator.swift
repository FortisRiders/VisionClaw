import Foundation

@MainActor
final class AppSessionCoordinator {
    static let shared = AppSessionCoordinator()
    private init() {}

    private weak var jarvis: JarvisVoiceSession?
    private weak var gemini: GeminiSessionViewModel?

    func register(jarvis: JarvisVoiceSession, gemini: GeminiSessionViewModel) {
        self.jarvis = jarvis
        self.gemini = gemini
    }

    func profileDidSwitch() {
        jarvis?.switchProfile()
    }
}
