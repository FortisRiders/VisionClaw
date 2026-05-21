import CryptoKit
import Foundation

@MainActor
final class ProfileManager: ObservableObject {
  static let shared = ProfileManager()

  private let store: UserDefaults

  @Published private(set) var profiles: [UserProfile] = []
  @Published private(set) var activeProfile: UserProfile?
  @Published private(set) var failedAttempts: Int = 0
  @Published private(set) var lockoutUntil: Date?

  private var pendingOTP: (code: String, email: String, expiry: Date)?

  private enum Keys {
    static let profiles = "co.fortis.visionclaw.profiles"
    static let keychainService = "co.fortis.visionclaw.profiles"
    static func pinEntry(_ id: UUID) -> String { "pin-\(id.uuidString)" }
  }

  private init() {
    self.store = .standard
    loadProfiles()
  }

  #if DEBUG
  static func makeIsolated() -> ProfileManager {
    let suiteName = "test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return ProfileManager(store: defaults)
  }

  private init(store: UserDefaults) {
    self.store = store
    loadProfiles()
  }
  #endif

  var isUnlocked: Bool { activeProfile != nil }
  var hasProfiles: Bool { !profiles.isEmpty }

  // MARK: - Profile CRUD

  @discardableResult
  func createProfile(firstName: String, lastName: String, email: String, pin: String) -> UserProfile {
    let profile = UserProfile(
      id: UUID(),
      firstName: firstName,
      lastName: lastName,
      email: email,
      createdAt: Date()
    )
    savePin(pin, for: profile.id)
    profiles.append(profile)
    persistProfiles()
    activeProfile = profile
    return profile
  }

  func updateProfile(_ updated: UserProfile) {
    guard let index = profiles.firstIndex(where: { $0.id == updated.id }) else { return }
    profiles[index] = updated
    persistProfiles()
    if activeProfile?.id == updated.id { activeProfile = updated }
  }

  func deleteProfile(_ profile: UserProfile) {
    deletePin(for: profile.id)
    profiles.removeAll { $0.id == profile.id }
    persistProfiles()
    if activeProfile?.id == profile.id {
      activeProfile = nil
    }
  }

  // MARK: - Authentication

  func unlock(profile: UserProfile, pin: String) -> Bool {
    guard !isLockedOut else { return false }
    guard verifyPin(pin, for: profile.id) else {
      failedAttempts += 1
      if failedAttempts >= 3 {
        lockoutUntil = Date().addingTimeInterval(30)
      }
      return false
    }
    failedAttempts = 0
    lockoutUntil = nil
    activeProfile = profile
    return true
  }

  func lock() {
    activeProfile = nil
  }

  var isLockedOut: Bool {
    guard let until = lockoutUntil else { return false }
    if Date() > until {
      lockoutUntil = nil
      failedAttempts = 0
      return false
    }
    return true
  }

  var lockoutRemaining: TimeInterval {
    guard let until = lockoutUntil else { return 0 }
    return max(0, until.timeIntervalSinceNow)
  }

  // MARK: - PIN Change

  func verifyPin(profile: UserProfile, pin: String) -> Bool {
    verifyPin(pin, for: profile.id)
  }

  // MARK: - OTP Reset

  func sendPINResetOTP(to email: String, for profile: UserProfile) async -> Bool {
    guard profile.email.lowercased() == email.lowercased() else { return false }
    let code = String(format: "%06d", Int.random(in: 0...999_999))
    pendingOTP = (code: code, email: email.lowercased(), expiry: Date().addingTimeInterval(300))
    return await deliverOTP(code: code, to: email, name: profile.firstName)
  }

  func verifyOTP(code: String, email: String) -> Bool {
    guard let otp = pendingOTP,
          otp.email == email.lowercased(),
          Date() < otp.expiry,
          otp.code == code
    else { return false }
    pendingOTP = nil
    return true
  }

  func resetPin(for profile: UserProfile, newPin: String) {
    savePin(newPin, for: profile.id)
  }

  @discardableResult
  func changePin(for profile: UserProfile, newPin: String) -> Bool {
    savePin(newPin, for: profile.id)
    return true
  }

  // MARK: - Keychain

  private func pinHash(_ pin: String, id: UUID) -> String {
    let data = Data((pin + id.uuidString).utf8)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func savePin(_ pin: String, for id: UUID) {
    let data = Data(pinHash(pin, id: id).utf8)
    KeychainService.save(data, account: Keys.pinEntry(id))
  }

  private func verifyPin(_ pin: String, for id: UUID) -> Bool {
    let expected = pinHash(pin, id: id)
    guard let data = KeychainService.load(account: Keys.pinEntry(id)),
          let stored = String(data: data, encoding: .utf8)
    else { return false }
    return stored == expected
  }

  private func deletePin(for id: UUID) {
    KeychainService.delete(account: Keys.pinEntry(id))
  }

  // MARK: - Persistence

  private func loadProfiles() {
    guard let data = store.data(forKey: Keys.profiles),
          let decoded = try? JSONDecoder().decode([UserProfile].self, from: data)
    else { return }
    profiles = decoded
  }

  private func persistProfiles() {
    guard let data = try? JSONEncoder().encode(profiles) else { return }
    store.set(data, forKey: Keys.profiles)
  }

  // MARK: - OTP Delivery

  private func deliverOTP(code: String, to email: String, name: String) async -> Bool {
    guard !Secrets.sendGridApiKey.isEmpty else {
      NSLog("[ProfileManager] SendGrid key not set — OTP for dev: %@", code)
      return true
    }
    guard let url = URL(string: "https://api.sendgrid.com/v3/mail/send") else { return false }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(Secrets.sendGridApiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: Any] = [
      "personalizations": [["to": [["email": email]]]],
      "from": ["email": "noreply@\(Secrets.sendGridFromDomain)", "name": "VisionClaw"],
      "subject": "Your VisionClaw PIN reset code",
      "content": [[
        "type": "text/html",
        "value": """
          <p>Hi \(name),</p>
          <p>Your PIN reset code is: <strong style="font-size:24px;letter-spacing:4px">\(code)</strong></p>
          <p>This code expires in 5 minutes. If you didn't request this, ignore this email.</p>
          """
      ]]
    ]
    guard let body = try? JSONSerialization.data(withJSONObject: body) else { return false }
    request.httpBody = body
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      return (200...299).contains(status)
    } catch {
      NSLog("[ProfileManager] OTP delivery error: %@", error.localizedDescription)
      return false
    }
  }

  #if DEBUG
  func resetLockoutForTesting() {
    failedAttempts = 0
    lockoutUntil = nil
  }
  #endif
}
