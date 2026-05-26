import Foundation

struct ProfileScopedStore<T: Codable> {
    private let keyPrefix: String
    private(set) var currentProfileId: String

    init(keyPrefix: String, profileId: String) {
        self.keyPrefix = keyPrefix
        self.currentProfileId = profileId
    }

    var key: String { "\(keyPrefix).\(currentProfileId)" }

    func save(_ value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func load() -> T? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(T.self, from: data) else { return nil }
        return value
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
