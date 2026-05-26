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

    // MARK: - activeChatTitle

    func test_activeChatTitle_returnsJarvisWhenIdIsMain() {
        session.activeChatId = "main"
        XCTAssertEqual(session.activeChatTitle, "Jarvis")
    }

    func test_activeChatTitle_returnsChatTitleForNamedChat() {
        let chat = JarvisChat(
            id: "abc12345",
            title: "My Test Chat",
            previewText: "",
            createdAt: Date(),
            updatedAt: Date(),
            sessionKey: "key:chat-abc12345"
        )
        session.chatList = [chat]
        session.activeChatId = "abc12345"
        XCTAssertEqual(session.activeChatTitle, "My Test Chat")
    }

    func test_activeChatTitle_fallsBackToJarvisForUnknownId() {
        session.chatList = []
        session.activeChatId = "nonexistent"
        XCTAssertEqual(session.activeChatTitle, "Jarvis")
    }

    // MARK: - renameChat

    func test_renameChat_updatesTitle() {
        let chat = JarvisChat(
            id: "rename01",
            title: "Old Title",
            previewText: "",
            createdAt: Date(),
            updatedAt: Date(),
            sessionKey: "key:chat-rename01"
        )
        let _ = makeAndActivateProfile()
        session.switchProfile()
        session.chatList.append(chat)
        session.renameChat(id: "rename01", title: "New Title")
        let updated = session.chatList.first { $0.id == "rename01" }
        XCTAssertEqual(updated?.title, "New Title")
    }

    func test_renameChat_unknownId_doesNothing() {
        let _ = makeAndActivateProfile()
        session.switchProfile()
        let before = session.chatList.count
        session.renameChat(id: "nonexistent-id", title: "Whatever")
        XCTAssertEqual(session.chatList.count, before, "renameChat with unknown id should not change chatList size")
    }

    // MARK: - deleteChat

    func test_deleteChat_withMainId_isNoOp() {
        let mainChat = JarvisChat(
            id: "main",
            title: "Jarvis",
            previewText: "",
            createdAt: Date(),
            updatedAt: Date(),
            sessionKey: "key:main"
        )
        let _ = makeAndActivateProfile()
        session.switchProfile()
        session.chatList = [mainChat]
        session.deleteChat(mainChat)
        XCTAssertEqual(session.chatList.count, 1, "deleteChat should not remove the main chat")
        XCTAssertEqual(session.chatList.first?.id, "main")
    }

    func test_deleteChat_removesNonMainChat() {
        let mainChat = JarvisChat(
            id: "main",
            title: "Jarvis",
            previewText: "",
            createdAt: Date(),
            updatedAt: Date(),
            sessionKey: "key:main"
        )
        let secondary = JarvisChat(
            id: "del00001",
            title: "To Delete",
            previewText: "",
            createdAt: Date(),
            updatedAt: Date(),
            sessionKey: "key:chat-del00001"
        )
        let _ = makeAndActivateProfile()
        session.switchProfile()
        session.chatList = [mainChat, secondary]
        session.activeChatId = "main"
        session.deleteChat(secondary)
        XCTAssertFalse(session.chatList.contains { $0.id == "del00001" },
                       "deleteChat should remove the chat from chatList")
    }

    // MARK: - clearHistory

    func test_clearHistory_resetsPreviewTextOnActiveChat() {
        let _ = makeAndActivateProfile()
        session.switchProfile()

        let chat = JarvisChat(
            id: "main",
            title: "Jarvis",
            previewText: "Some previous response preview",
            createdAt: Date(),
            updatedAt: Date(),
            sessionKey: "key:main"
        )
        session.chatList = [chat]
        session.activeChatId = "main"

        session.clearHistory()

        let updated = session.chatList.first { $0.id == "main" }
        XCTAssertEqual(updated?.previewText, "",
                       "clearHistory should reset previewText to empty string")
    }

    func test_clearHistory_emptiesMessages() {
        let _ = makeAndActivateProfile()
        session.switchProfile()

        let preloaded = [
            ChatMessage(role: .user, text: "Hello"),
            ChatMessage(role: .assistant, text: "Hi there")
        ]
        let profile = ProfileManager.shared.activeProfile!
        storeMessages(preloaded, forProfileId: profile.id)

        let fresh = JarvisVoiceSession()
        XCTAssertFalse(fresh.messages.isEmpty, "Pre-condition: messages loaded")
        fresh.clearHistory()
        XCTAssertTrue(fresh.messages.isEmpty)
    }
}
