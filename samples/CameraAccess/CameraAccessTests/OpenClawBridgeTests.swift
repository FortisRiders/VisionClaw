import Foundation
import UIKit
import XCTest
@testable import CameraAccess

@MainActor
final class OpenClawBridgeTests: XCTestCase {

    private var bridge: OpenClawBridge!
    private var createdProfileIds: [UUID] = []
    private let profilesDefaultsKey = "co.fortis.visionclaw.profiles"

    override func setUp() async throws {
        try await super.setUp()
        cleanUpProfiles()
        bridge = OpenClawBridge()
    }

    override func tearDown() async throws {
        clearAllHistoryKeys()
        for id in createdProfileIds {
            deleteKeychainPin(for: id)
        }
        createdProfileIds.removeAll()
        cleanUpProfiles()
        bridge = nil
        try await super.tearDown()
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

    private func clearAllHistoryKeys() {
        let defaults = UserDefaults.standard
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix("openclaw.history.") {
            defaults.removeObject(forKey: key)
        }
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

    private func currentSessionKey(from b: OpenClawBridge) -> String? {
        guard let storeValue = Mirror(reflecting: b).children
            .first(where: { $0.label == "store" })?.value
        else { return nil }
        return Mirror(reflecting: storeValue).children
            .first(where: { $0.label == "sessionKey" })?
            .value as? String
    }

    private func historyKey(from b: OpenClawBridge) -> String? {
        currentSessionKey(from: b).map { "openclaw.history.\($0)" }
    }

    private func conversationHistory(from b: OpenClawBridge) -> [[String: Any]]? {
        Mirror(reflecting: b).children
            .first(where: { $0.label == "conversationHistory" })?
            .value as? [[String: Any]]
    }

    private func storeHistory(_ history: [[String: Any]], forKey key: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: history) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - switchProfile

    func test_switchProfile_savesHistoryUnderOldKey() {
        let profileA = makeAndActivateProfile(firstName: "A", email: "a@example.com")
        let bridgeA = OpenClawBridge()
        guard let oldKey = historyKey(from: bridgeA) else {
            XCTFail("Could not resolve history key for profileA")
            return
        }

        storeHistory([["role": "user", "content": "A's message"]], forKey: oldKey)
        let bridgeWithHistory = OpenClawBridge()
        XCTAssertEqual(conversationHistory(from: bridgeWithHistory)?.count, 1,
                       "Pre-condition: history loaded from UserDefaults")

        let _ = makeAndActivateProfile(firstName: "B", email: "b@example.com")
        bridgeWithHistory.switchProfile()

        let saved = UserDefaults.standard.data(forKey: oldKey)
        XCTAssertNotNil(saved,
                        "switchProfile should persist history to UserDefaults under the old session key")

        _ = profileA
    }

    func test_switchProfile_clearsHistoryInMemory() {
        let _ = makeAndActivateProfile(firstName: "A", email: "a@example.com")
        let bridgeA = OpenClawBridge()
        guard let key = historyKey(from: bridgeA) else {
            XCTFail("Could not resolve history key")
            return
        }

        storeHistory([["role": "user", "content": "A's message"]], forKey: key)
        let loadedBridge = OpenClawBridge()
        XCTAssertEqual(conversationHistory(from: loadedBridge)?.count, 1,
                       "Pre-condition: history loaded")

        let _ = makeAndActivateProfile(firstName: "B", email: "b@example.com")
        loadedBridge.switchProfile()

        XCTAssertEqual(conversationHistory(from: loadedBridge)?.count ?? 0, 0,
                       "switchProfile should clear in-memory conversation history")
    }

    func test_switchProfile_updatesCurrentSessionKey() {
        let _ = makeAndActivateProfile(firstName: "A", email: "a@example.com")
        let b = OpenClawBridge()
        let keyBefore = currentSessionKey(from: b)

        let _ = makeAndActivateProfile(firstName: "B", email: "b@example.com")
        b.switchProfile()
        let keyAfter = currentSessionKey(from: b)

        XCTAssertNotNil(keyBefore)
        XCTAssertNotNil(keyAfter)
        XCTAssertNotEqual(keyBefore, keyAfter,
                          "currentSessionKey should change when switching to a different profile")
    }

    func test_switchProfile_loadsNewHistory() {
        let _ = makeAndActivateProfile(firstName: "A", email: "a@example.com")
        let b = OpenClawBridge()

        let profileB = makeAndActivateProfile(firstName: "B", email: "b@example.com")

        let tempBridge = OpenClawBridge()
        guard let bKey = historyKey(from: tempBridge) else {
            XCTFail("Could not compute historyKey for profileB")
            return
        }

        storeHistory([["role": "assistant", "content": "B's prior response"]], forKey: bKey)

        b.switchProfile()

        let loaded = conversationHistory(from: b)
        XCTAssertEqual(loaded?.count, 1,
                       "switchProfile should load the new profile's persisted history")
        XCTAssertEqual(loaded?.first?["content"] as? String, "B's prior response")

        _ = profileB
    }

    // MARK: - resetSession

    func test_resetSession_wipesHistoryAndUserDefaults() {
        let _ = makeAndActivateProfile()
        let b = OpenClawBridge()
        guard let key = historyKey(from: b) else {
            XCTFail("Could not resolve history key")
            return
        }

        storeHistory([["role": "user", "content": "Old history"]], forKey: key)
        let loadedBridge = OpenClawBridge()
        XCTAssertEqual(conversationHistory(from: loadedBridge)?.count, 1,
                       "Pre-condition: history loaded")

        loadedBridge.resetSession()

        XCTAssertEqual(conversationHistory(from: loadedBridge)?.count ?? 0, 0,
                       "resetSession should clear in-memory conversation history")
        XCTAssertNil(UserDefaults.standard.data(forKey: key),
                     "resetSession should remove the history from UserDefaults")
    }

    // MARK: - historyKey derivation

    func test_historyKey_includesCurrentSessionKey() {
        let _ = makeAndActivateProfile()
        let b = OpenClawBridge()

        guard let sessionKey = currentSessionKey(from: b),
              let key = historyKey(from: b) else {
            XCTFail("Could not read bridge internals via Mirror")
            return
        }

        XCTAssertTrue(key.hasPrefix("openclaw.history."),
                      "historyKey should be prefixed with 'openclaw.history.'")
        XCTAssertTrue(key.hasSuffix(sessionKey),
                      "historyKey '\(key)' should end with currentSessionKey '\(sessionKey)'")
    }

    func test_makeSessionKey_includesProfileShortId() {
        let profile = makeAndActivateProfile(firstName: "Scoped", email: "scoped@example.com")
        let b = OpenClawBridge()

        guard let sessionKey = currentSessionKey(from: b) else {
            XCTFail("Could not read currentSessionKey via Mirror")
            return
        }

        XCTAssertTrue(
            sessionKey.contains(profile.shortId),
            "Session key '\(sessionKey)' should contain profile shortId '\(profile.shortId)'"
        )
    }

    // MARK: - delegateTask

    func test_delegateTask_appendsUserAndAssistantToHistory() async {
        let _ = makeAndActivateProfile()
        let b = OpenClawBridge()

        let result = await b.delegateTask(task: "test task")

        let history = conversationHistory(from: b) ?? []
        switch result {
        case .success(let text):
            XCTAssertEqual(history.count, 2,
                           "A successful delegate task should append both user and assistant entries")
            XCTAssertEqual(history.first?["role"] as? String, "user")
            XCTAssertEqual(history.last?["role"] as? String, "assistant")
            XCTAssertFalse(text.isEmpty)
        case .failure(let reason):
            if reason == "Invalid gateway URL" {
                XCTAssertEqual(history.count, 0,
                               "URL validation fails before appending to history")
            } else {
                XCTAssertGreaterThanOrEqual(history.count, 1,
                                            "User message should be appended before a network-layer failure")
                XCTAssertEqual(history.first?["role"] as? String, "user")
            }
        }
    }
}
