import Foundation
@testable import CameraAccess

final class MockUserDefaults {
    let suiteName: String
    let store: UserDefaults

    init() {
        suiteName = "test.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        store.removePersistentDomain(forName: suiteName)
    }
}

func makeProfile(
    firstName: String = "Test",
    lastName: String = "User",
    email: String = "test@example.com"
) -> UserProfile {
    UserProfile(
        id: UUID(),
        firstName: firstName,
        lastName: lastName,
        email: email,
        createdAt: Date()
    )
}

final class FrozenClock {
    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}
