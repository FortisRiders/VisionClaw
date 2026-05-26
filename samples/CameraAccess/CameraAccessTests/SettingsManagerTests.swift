import XCTest
@testable import CameraAccess

final class SettingsManagerTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        SettingsManager.shared.resetAll()
    }

    override func tearDown() async throws {
        SettingsManager.shared.resetAll()
        try await super.tearDown()
    }

    // MARK: - openClawPort

    func test_openClawPort_defaultsToSecretsValue() {
        XCTAssertEqual(SettingsManager.shared.openClawPort, Secrets.openClawPort)
    }

    func test_openClawPort_canBeSetAndReadBack() {
        SettingsManager.shared.openClawPort = 9999
        XCTAssertEqual(SettingsManager.shared.openClawPort, 9999)
    }

    // MARK: - openClawHost

    func test_openClawHost_defaultsToSecretsValue() {
        XCTAssertEqual(SettingsManager.shared.openClawHost, Secrets.openClawHost)
    }

    func test_openClawHost_canBeSetAndReadBack() {
        SettingsManager.shared.openClawHost = "http://192.168.1.100"
        XCTAssertEqual(SettingsManager.shared.openClawHost, "http://192.168.1.100")
    }

    // MARK: - useKokoroTTS

    func test_useKokoroTTS_defaultsToTrue() {
        XCTAssertTrue(SettingsManager.shared.useKokoroTTS)
    }

    func test_useKokoroTTS_canBeSetToFalse() {
        SettingsManager.shared.useKokoroTTS = false
        XCTAssertFalse(SettingsManager.shared.useKokoroTTS)
    }

    // MARK: - proactiveNotificationsEnabled

    func test_proactiveNotificationsEnabled_defaultsToTrue() {
        XCTAssertTrue(SettingsManager.shared.proactiveNotificationsEnabled)
    }

    func test_proactiveNotificationsEnabled_canBeSetToFalse() {
        SettingsManager.shared.proactiveNotificationsEnabled = false
        XCTAssertFalse(SettingsManager.shared.proactiveNotificationsEnabled)
    }

    // MARK: - showLiveButton

    func test_showLiveButton_defaultsToFalse() {
        XCTAssertFalse(SettingsManager.shared.showLiveButton)
    }

    func test_showLiveButton_canBeSetToTrue() {
        SettingsManager.shared.showLiveButton = true
        XCTAssertTrue(SettingsManager.shared.showLiveButton)
    }

    // MARK: - resetAll

    func test_resetAll_clearsPreviouslySetValues() {
        SettingsManager.shared.openClawPort = 12345
        SettingsManager.shared.openClawHost = "http://changed.host"
        SettingsManager.shared.useKokoroTTS = false
        SettingsManager.shared.proactiveNotificationsEnabled = false
        SettingsManager.shared.showLiveButton = true

        SettingsManager.shared.resetAll()

        XCTAssertEqual(SettingsManager.shared.openClawPort, Secrets.openClawPort)
        XCTAssertEqual(SettingsManager.shared.openClawHost, Secrets.openClawHost)
        XCTAssertTrue(SettingsManager.shared.useKokoroTTS)
        XCTAssertTrue(SettingsManager.shared.proactiveNotificationsEnabled)
        XCTAssertFalse(SettingsManager.shared.showLiveButton)
    }
}
