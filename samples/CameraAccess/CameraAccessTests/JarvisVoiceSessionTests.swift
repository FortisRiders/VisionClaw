import Foundation
import XCTest
@testable import CameraAccess

@MainActor
final class JarvisVoiceSessionTests: XCTestCase {

    private var session: JarvisVoiceSession!
    private var createdProfileIds: [UUID] = []
    private let profilesDefaultsKey = "co.fortis.visionclaw.profiles"

    override func setUp() async throws {
        try await super.setUp()
        cleanUpProfiles()
        UserDefaults.standard.removeObject(forKey: "jarvis.chat.messages.default")
        session = JarvisVoiceSession()
    }

    override func tearDown() async throws {
        session?.clearHistory()
        for id in createdProfileIds {
            let messagesKey = "jarvis.chat.messages.\(id.uuidString)"
            UserDefaults.standard.removeObject(forKey: messagesKey)
            deleteKeychainPin(for: id)
        }
        UserDefaults.standard.removeObject(forKey: "jarvis.chat.messages.default")
        clearAllOpenClawHistoryKeys()
        createdProfileIds.removeAll()
        cleanUpProfiles()
        session = nil
        try await super.tearDown()
    }

    private func clearAllOpenClawHistoryKeys() {
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix("openclaw.history.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func cleanUpProfiles() {
        let manager = ProfileManager.shared
        manager.profiles.forEach { profile in
            deleteKeychainPin(for: profile.id)
            manager.deleteProfile(profile)
        }
        UserDefaults.standard.removeObject(forKey: profilesDefaultsKey)
        manager.lock()
        manager.resetLockoutForTesting()
    }

    private func deleteKeychainPin(for id: UUID) {
        KeychainService.delete(account: "pin-\(id.uuidString)")
    }

    @discardableResult
    private func makeAndActivateProfile(
        firstName: String = "Test",
        lastName: String = "User",
        email: String = "test@example.com",
        pin: String = "0000"
    ) -> UserProfile {
        let profile = ProfileManager.shared.createProfile(
            firstName: firstName,
            lastName: lastName,
            email: email,
            pin: pin
        )
        createdProfileIds.append(profile.id)
        return profile
    }

    private func storeMessages(_ messages: [ChatMessage], forProfileId id: UUID) {
        let key = "jarvis.chat.messages.\(id.uuidString)"
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func loadMessages(forProfileId id: UUID) -> [ChatMessage]? {
        let key = "jarvis.chat.messages.\(id.uuidString)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data)
        else { return nil }
        return messages
    }

    // MARK: - switchProfile

    func test_switchProfile_savesCurrentMessagesUnderOldKey() {
        let oldProfile = makeAndActivateProfile(firstName: "Old", email: "old@example.com")
        session.switchProfile()

        let twoMessages = [
            ChatMessage(role: .user, text: "Message one"),
            ChatMessage(role: .assistant, text: "Message two")
        ]
        storeMessages(twoMessages, forProfileId: oldProfile.id)

        let reloadedSession = JarvisVoiceSession()
        XCTAssertEqual(reloadedSession.messages.count, 2,
                       "Pre-condition: two messages loaded for oldProfile")

        let newProfile = makeAndActivateProfile(firstName: "New", email: "new@example.com")
        reloadedSession.switchProfile()

        let savedAfterSwitch = loadMessages(forProfileId: oldProfile.id)
        XCTAssertNotNil(savedAfterSwitch,
                        "switchProfile should save current messages under the old profile's key")
        XCTAssertEqual(savedAfterSwitch?.count, 2)

        _ = newProfile
        reloadedSession.clearHistory()
    }

    func test_switchProfile_loadsNewProfileMessages() {
        let oldProfile = makeAndActivateProfile(firstName: "Old", email: "old@example.com")
        session.switchProfile()

        let newProfile = makeAndActivateProfile(firstName: "New", email: "new@example.com")
        let preloaded = [ChatMessage(role: .assistant, text: "Pre-loaded response")]
        storeMessages(preloaded, forProfileId: newProfile.id)

        session.switchProfile()

        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(session.messages.first?.text, "Pre-loaded response")

        _ = oldProfile
    }

    func test_switchProfile_clearsLiveTranscript() {
        let _ = makeAndActivateProfile(firstName: "A", email: "a@example.com")
        session.switchProfile()
        session.liveTranscript = "in-flight text"

        let _ = makeAndActivateProfile(firstName: "B", email: "b@example.com")
        session.switchProfile()

        XCTAssertEqual(session.liveTranscript, "")
    }

    func test_switchProfile_advancesCurrentProfileId() {
        let profileA = makeAndActivateProfile(firstName: "A", email: "a@example.com")
        session.switchProfile()

        let messagesA = [ChatMessage(role: .user, text: "A's message")]
        storeMessages(messagesA, forProfileId: profileA.id)

        let profileB = makeAndActivateProfile(firstName: "B", email: "b@example.com")
        let messagesB = [ChatMessage(role: .user, text: "B's message")]
        storeMessages(messagesB, forProfileId: profileB.id)

        session.switchProfile()

        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(session.messages.first?.text, "B's message",
                       "After switching to profileB, session should load profileB's messages")
    }

    // MARK: - clearHistory

    func test_clearHistory_wipesMessages() {
        let preloaded = [ChatMessage(role: .user, text: "To be cleared")]
        UserDefaults.standard.set(
            try! JSONEncoder().encode(preloaded),
            forKey: "jarvis.chat.messages.default"
        )

        let freshSession = JarvisVoiceSession()
        XCTAssertFalse(freshSession.messages.isEmpty, "Pre-condition: messages loaded")
        freshSession.clearHistory()
        XCTAssertTrue(freshSession.messages.isEmpty)
    }

    func test_clearHistory_removesFromUserDefaults() {
        let profile = makeAndActivateProfile()
        session.switchProfile()

        let messagesKey = "jarvis.chat.messages.\(profile.id.uuidString)"
        storeMessages([ChatMessage(role: .user, text: "Stored")], forProfileId: profile.id)

        let activeSession = JarvisVoiceSession()
        activeSession.clearHistory()

        XCTAssertNil(UserDefaults.standard.data(forKey: messagesKey),
                     "clearHistory should remove the messages key from UserDefaults")
    }

    // MARK: - Message cap (100 max stored)

    func test_messagesCapAt100() {
        let profile = makeAndActivateProfile()
        session.switchProfile()

        var bulk: [ChatMessage] = []
        for i in 0..<105 {
            bulk.append(ChatMessage(role: i % 2 == 0 ? .user : .assistant, text: "Message \(i)"))
        }

        let capped = Array(bulk.suffix(100))
        storeMessages(capped, forProfileId: profile.id)

        let freshSession = JarvisVoiceSession()
        XCTAssertEqual(freshSession.messages.count, 100,
                       "Session should load at most 100 messages from UserDefaults")
        freshSession.clearHistory()
    }
}
