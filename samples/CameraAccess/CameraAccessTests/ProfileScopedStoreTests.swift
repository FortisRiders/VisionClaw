import XCTest
@testable import CameraAccess

final class ProfileScopedStoreTests: XCTestCase {

    private var writtenKeys: [String] = []

    override func tearDown() async throws {
        for key in writtenKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        writtenKeys.removeAll()
        try await super.tearDown()
    }

    private func makeStore(profileId: String = "profile1") -> ProfileScopedStore<[String]> {
        let prefix = "test.store.\(UUID().uuidString)"
        let store = ProfileScopedStore<[String]>(keyPrefix: prefix, profileId: profileId)
        writtenKeys.append(store.key)
        return store
    }

    private func makeStore(keyPrefix: String, profileId: String) -> ProfileScopedStore<[String]> {
        let store = ProfileScopedStore<[String]>(keyPrefix: keyPrefix, profileId: profileId)
        writtenKeys.append(store.key)
        return store
    }

    // MARK: - key property

    func test_key_combinesPrefixAndProfileIdWithDot() {
        let prefix = "test.store.\(UUID().uuidString)"
        let profileId = "abc123"
        let store = ProfileScopedStore<[String]>(keyPrefix: prefix, profileId: profileId)
        writtenKeys.append(store.key)
        XCTAssertEqual(store.key, "\(prefix).\(profileId)")
    }

    // MARK: - save / load

    func test_saveAndLoad_roundTripsValue() {
        let store = makeStore()
        let value = ["alpha", "beta", "gamma"]
        store.save(value)
        XCTAssertEqual(store.load(), value)
    }

    func test_load_returnsNilWhenNothingSaved() {
        let store = makeStore()
        XCTAssertNil(store.load())
    }

    // MARK: - clear

    func test_clear_removesValueSoLoadReturnsNil() {
        let store = makeStore()
        store.save(["item"])
        store.clear()
        XCTAssertNil(store.load())
    }

    // MARK: - isolation between stores

    func test_differentProfileIds_dontShareData() {
        let prefix = "test.store.\(UUID().uuidString)"
        let storeA = ProfileScopedStore<[String]>(keyPrefix: prefix, profileId: "profileA")
        let storeB = ProfileScopedStore<[String]>(keyPrefix: prefix, profileId: "profileB")
        writtenKeys.append(storeA.key)
        writtenKeys.append(storeB.key)

        storeA.save(["only-A"])
        XCTAssertNil(storeB.load(), "Saving to storeA should not affect storeB")
    }

    func test_differentKeyPrefixes_dontShareData() {
        let prefixA = "test.store.\(UUID().uuidString)"
        let prefixB = "test.store.\(UUID().uuidString)"
        let storeA = ProfileScopedStore<[String]>(keyPrefix: prefixA, profileId: "sameProfile")
        let storeB = ProfileScopedStore<[String]>(keyPrefix: prefixB, profileId: "sameProfile")
        writtenKeys.append(storeA.key)
        writtenKeys.append(storeB.key)

        storeA.save(["only-A-prefix"])
        XCTAssertNil(storeB.load(), "Different prefixes should produce independent stores")
    }

    // MARK: - overwrite

    func test_save_overwritesPreviousValue() {
        let store = makeStore()
        store.save(["original"])
        store.save(["replacement"])
        XCTAssertEqual(store.load(), ["replacement"])
    }
}
