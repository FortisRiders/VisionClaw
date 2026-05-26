import Foundation

final class SettingsManager {
  static let shared = SettingsManager()

  private let defaults = UserDefaults.standard

  private enum Key: String {
    case openClawHost
    case openClawPort
    case openClawGatewayToken
    case webrtcSignalingURL
    case proactiveNotificationsEnabled
    case showLiveButton
    case useKokoroTTS
  }

  private init() {}

  // MARK: - OpenClaw

  var openClawHost: String {
    get { defaults.string(forKey: Key.openClawHost.rawValue) ?? Secrets.openClawHost }
    set { defaults.set(newValue, forKey: Key.openClawHost.rawValue) }
  }

  var openClawPort: Int {
    get {
      let stored = defaults.integer(forKey: Key.openClawPort.rawValue)
      return stored != 0 ? stored : Secrets.openClawPort
    }
    set { defaults.set(newValue, forKey: Key.openClawPort.rawValue) }
  }

  var openClawGatewayToken: String {
    get { defaults.string(forKey: Key.openClawGatewayToken.rawValue) ?? Secrets.openClawGatewayToken }
    set { defaults.set(newValue, forKey: Key.openClawGatewayToken.rawValue) }
  }

  // MARK: - WebRTC

  var webrtcSignalingURL: String {
    get { defaults.string(forKey: Key.webrtcSignalingURL.rawValue) ?? Secrets.webrtcSignalingURL }
    set { defaults.set(newValue, forKey: Key.webrtcSignalingURL.rawValue) }
  }

  // MARK: - Live Button

  var showLiveButton: Bool {
    get { defaults.bool(forKey: Key.showLiveButton.rawValue) }
    set { defaults.set(newValue, forKey: Key.showLiveButton.rawValue) }
  }

  // MARK: - Voice

  var useKokoroTTS: Bool {
    get { defaults.object(forKey: Key.useKokoroTTS.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.useKokoroTTS.rawValue) }
  }

  // MARK: - Notifications

  var proactiveNotificationsEnabled: Bool {
    get { defaults.object(forKey: Key.proactiveNotificationsEnabled.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.proactiveNotificationsEnabled.rawValue) }
  }

  // MARK: - Reset

  func resetAll() {
    for key in [Key.openClawHost, .openClawPort, .openClawGatewayToken,
                .webrtcSignalingURL, .showLiveButton, .proactiveNotificationsEnabled,
                .useKokoroTTS] {
      defaults.removeObject(forKey: key.rawValue)
    }
  }
}
