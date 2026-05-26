import CryptoKit
import Foundation

class OpenClawEventClient {
  var onNotification: ((String) -> Void)?

  private var webSocketTask: URLSessionWebSocketTask?
  private var session: URLSession?
  private var isConnected = false
  private var shouldReconnect = false
  private var reconnectDelay: TimeInterval = 2
  private let maxReconnectDelay: TimeInterval = 30
  private var reconnectTask: Task<Void, Never>?

  private let clientId = "node-host"

  // MARK: - Device Identity (derived from public key, stable via Keychain)

  private lazy var signingKey: Curve25519.Signing.PrivateKey = {
    loadOrCreateSigningKey()
  }()

  // Device ID = SHA-256 hex of the raw 32-byte public key.
  // Gateway derives this independently and uses it to verify identity.
  private lazy var deviceId: String = {
    let raw = signingKey.publicKey.rawRepresentation
    return SHA256.hash(data: raw)
      .map { String(format: "%02x", $0) }
      .joined()
  }()

  func connect() {
    guard GeminiConfig.isOpenClawConfigured else {
      NSLog("[OpenClawWS] Not configured, skipping")
      return
    }

    shouldReconnect = true
    reconnectDelay = 2
    establishConnection()
  }

  func disconnect() {
    shouldReconnect = false
    reconnectTask?.cancel()
    reconnectTask = nil
    isConnected = false
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    webSocketTask = nil
    session?.invalidateAndCancel()
    session = nil
    NSLog("[OpenClawWS] Disconnected")
  }

  // MARK: - Private

  private func establishConnection() {
    let host = GeminiConfig.openClawHost
      .replacingOccurrences(of: "http://", with: "")
      .replacingOccurrences(of: "https://", with: "")
    let port = GeminiConfig.openClawPort
    guard let url = URL(string: "ws://\(host):\(port)") else {
      NSLog("[OpenClawWS] Invalid URL")
      return
    }

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    session = URLSession(configuration: config)
    webSocketTask = session?.webSocketTask(with: url)
    webSocketTask?.resume()

    NSLog("[OpenClawWS] Connecting to %@", url.absoluteString)
    startReceiving()
  }

  private func startReceiving() {
    webSocketTask?.receive { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let message):
        switch message {
        case .string(let text):
          self.handleMessage(text)
        case .data(let data):
          if let text = String(data: data, encoding: .utf8) {
            self.handleMessage(text)
          }
        @unknown default:
          break
        }
        self.startReceiving()
      case .failure(let error):
        NSLog("[OpenClawWS] Receive error: %@", error.localizedDescription)
        self.isConnected = false
        self.scheduleReconnect()
      }
    }
  }

  private func handleMessage(_ text: String) {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = json["type"] as? String else { return }

    if type == "event" {
      handleEvent(json)
    } else if type == "res" {
      let ok = json["ok"] as? Bool ?? false
      if ok {
        NSLog("[OpenClawWS] Connected and authenticated")
        isConnected = true
        reconnectDelay = 2
      } else {
        let error = json["error"] as? [String: Any]
        let msg = error?["message"] as? String ?? "unknown"
        NSLog("[OpenClawWS] Connect failed: %@", msg)
      }
    }
  }

  private func handleEvent(_ json: [String: Any]) {
    guard let event = json["event"] as? String else { return }
    let payload = json["payload"] as? [String: Any] ?? [:]

    switch event {
    case "connect.challenge":
      let nonce = payload["nonce"] as? String ?? ""
      NSLog("[OpenClawWS] Got challenge, nonce: %@", String(nonce.prefix(16)))
      sendConnectHandshake(nonce: nonce)

    case "heartbeat":
      handleHeartbeatEvent(payload)

    case "cron":
      handleCronEvent(payload)

    default:
      break
    }
  }

  private func sendConnectHandshake(nonce: String) {
    let rawPubKey = signingKey.publicKey.rawRepresentation
    let pubKeyBase64url = base64url(rawPubKey)
    let signedAtMs = Int(Date().timeIntervalSince1970 * 1000)
    let token = GeminiConfig.openClawGatewayToken
    let devId = deviceId

    // v3 pipe-separated payload — field order must match exactly
    let signaturePayload = [
      "v3",
      devId,          // SHA-256 hex of raw pubkey
      clientId,       // "node-host"
      "node",         // clientMode
      "node",         // role
      "",             // scopes (empty array joined by comma)
      String(signedAtMs),
      token,
      nonce,
      "ios",
      "mobile"
    ].joined(separator: "|")

    NSLog("[OpenClawWS] Sending handshake, deviceId: %@", devId)

    guard let payloadData = signaturePayload.data(using: .utf8) else {
      NSLog("[OpenClawWS] Failed to encode signature payload")
      return
    }

    let signatureBase64url: String
    do {
      let sig = try signingKey.signature(for: payloadData)
      let sigData = sig.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Data in
        Data(bytes: ptr.baseAddress!, count: ptr.count)
      }
      signatureBase64url = base64url(sigData)
    } catch {
      NSLog("[OpenClawWS] Signing failed: %@", error.localizedDescription)
      return
    }

    let connectMsg: [String: Any] = [
      "type": "req",
      "id": UUID().uuidString,
      "method": "connect",
      "params": [
        "minProtocol": 3,
        "maxProtocol": 3,
        "client": [
          "id": clientId,
          "displayName": "VisionClaw Glass",
          "version": "1.0",
          "platform": "ios",
          "deviceFamily": "mobile",
          "mode": "node"
        ],
        "device": [
          "id": devId,
          "publicKey": pubKeyBase64url,
          "signature": signatureBase64url,
          "signedAt": signedAtMs,
          "nonce": nonce
        ],
        "role": "node",
        "scopes": [] as [String],
        "caps": ["camera", "voice"],
        "commands": [] as [String],
        "permissions": [:] as [String: Any],
        "auth": [
          "token": token
        ]
      ] as [String: Any]
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: connectMsg),
          let string = String(data: data, encoding: .utf8) else { return }

    webSocketTask?.send(.string(string)) { error in
      if let error {
        NSLog("[OpenClawWS] Handshake send error: %@", error.localizedDescription)
      }
    }
  }

  private func handleHeartbeatEvent(_ payload: [String: Any]) {
    let status = payload["status"] as? String ?? ""
    guard status == "sent", let preview = payload["preview"] as? String, !preview.isEmpty else {
      return
    }

    let silent = payload["silent"] as? Bool ?? false
    guard !silent else { return }

    NSLog("[OpenClawWS] Heartbeat notification: %@", String(preview.prefix(100)))
    onNotification?("[Notification from your assistant] \(preview)")
  }

  private func handleCronEvent(_ payload: [String: Any]) {
    let action = payload["action"] as? String ?? ""
    guard action == "finished" else { return }

    let summary = payload["summary"] as? String
      ?? payload["result"] as? String
      ?? ""
    guard !summary.isEmpty else { return }

    NSLog("[OpenClawWS] Cron notification: %@", String(summary.prefix(100)))
    onNotification?("[Scheduled update] \(summary)")
  }

  private func scheduleReconnect() {
    guard shouldReconnect else { return }
    reconnectTask?.cancel()
    NSLog("[OpenClawWS] Reconnecting in %.0fs", reconnectDelay)
    let delay = reconnectDelay
    reconnectTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard !Task.isCancelled else { return }
      await MainActor.run { [weak self] in
        guard let self, self.shouldReconnect else { return }
        self.reconnectDelay = min(self.reconnectDelay * 2, self.maxReconnectDelay)
        self.reconnectTask = nil
        self.establishConnection()
      }
    }
  }

  // MARK: - Keychain key management

  private func loadOrCreateSigningKey() -> Curve25519.Signing.PrivateKey {
    let account = "openclaw-signing-key"

    if let keyData = KeychainService.load(account: account),
       let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) {
      NSLog("[OpenClawWS] Loaded existing signing key from Keychain")
      return key
    }

    let newKey = Curve25519.Signing.PrivateKey()
    KeychainService.save(newKey.rawRepresentation, account: account)
    NSLog("[OpenClawWS] Created new signing key and saved to Keychain")
    return newKey
  }

  private func base64url(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
