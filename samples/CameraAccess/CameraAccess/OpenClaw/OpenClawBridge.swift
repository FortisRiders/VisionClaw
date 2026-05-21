import Foundation
import UIKit

enum OpenClawConnectionState: Equatable {
  case notConfigured
  case checking
  case connected
  case unreachable(String)
}

// Stable identifiers for this device, used for backend routing and session scoping.
private enum DeviceInfo {
  static let id: String = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
  static let name: String = UIDevice.current.name
}

@MainActor
class OpenClawBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle
  @Published var connectionState: OpenClawConnectionState = .notConfigured

  private let session: URLSession
  private let pingSession: URLSession
  private var conversationHistory: [[String: Any]] = []
  private let maxHistoryTurns = 10

  private struct ConversationStore {
    private let keyPrefix = "openclaw.history"
    private(set) var sessionKey: String

    var key: String { "\(keyPrefix).\(sessionKey)" }

    func save(_ history: [[String: Any]]) {
      guard let data = try? JSONSerialization.data(withJSONObject: history) else { return }
      UserDefaults.standard.set(data, forKey: key)
    }

    func load() -> [[String: Any]] {
      guard let data = UserDefaults.standard.data(forKey: key),
            let history = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
      else { return [] }
      return history
    }

    func clear() { UserDefaults.standard.removeObject(forKey: key) }

    mutating func switchSession(to newKey: String, saving history: [[String: Any]]) {
      save(history)
      sessionKey = newKey
    }
  }

  private var store: ConversationStore

  // Cached per-profile agent ID returned by the [REGISTER] handshake.
  // Key: "openclaw.agentId.<profileShortId>", value: "glass-name-xxxx"
  private var agentId: String?

  private static func agentIdKey(for profile: UserProfile?) -> String {
    "openclaw.agentId.\(profile?.shortId ?? "default")"
  }

  private static func makeSessionKey(agentId: String? = nil) -> String {
    if let id = agentId { return "agent:\(id):main" }
    let base = "agent:main:glass:\(DeviceInfo.id.prefix(8))"
    guard let user = ProfileManager.shared.activeProfile else { return base }
    return "\(base):\(user.shortId)"
  }

  init() {
    let profile = ProfileManager.shared.activeProfile
    let cachedAgentId = UserDefaults.standard.string(forKey: OpenClawBridge.agentIdKey(for: profile))
    let initialKey = OpenClawBridge.makeSessionKey(agentId: cachedAgentId)
    let initialStore = ConversationStore(sessionKey: initialKey)
    self.agentId = cachedAgentId
    self.store = initialStore
    self.conversationHistory = initialStore.load()

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 120
    self.session = URLSession(configuration: config)

    let pingConfig = URLSessionConfiguration.default
    pingConfig.timeoutIntervalForRequest = 5
    self.pingSession = URLSession(configuration: pingConfig)
  }

  func checkConnection() async {
    NSLog("[OpenClaw] checkConnection() called")
    NSLog("[OpenClaw] isOpenClawConfigured=%@", GeminiConfig.isOpenClawConfigured ? "true" : "false")
    NSLog("[OpenClaw] host=%@ port=%d tokenEmpty=%@",
          GeminiConfig.openClawHost, GeminiConfig.openClawPort,
          GeminiConfig.openClawGatewayToken.isEmpty ? "true" : "false")
    guard GeminiConfig.isOpenClawConfigured else {
      NSLog("[OpenClaw] Not configured — skipping ping")
      connectionState = .notConfigured
      return
    }
    connectionState = .checking
    let urlString = "\(GeminiConfig.openClawHost):\(GeminiConfig.openClawPort)/v1/chat/completions"
    NSLog("[OpenClaw] Pinging URL: %@", urlString)
    guard let url = URL(string: urlString) else {
      NSLog("[OpenClaw] Invalid URL: %@", urlString)
      connectionState = .unreachable("Invalid URL")
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    applyOpenClawHeaders(to: &request, includeUser: nil)
    do {
      NSLog("[OpenClaw] Sending ping...")
      let (_, response) = try await pingSession.data(for: request)
      if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
        NSLog("[OpenClaw] Gateway reachable (HTTP %d)", http.statusCode)
        connectionState = .connected
      } else {
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        NSLog("[OpenClaw] Unexpected response HTTP %d", code)
        connectionState = .unreachable("Unexpected response (HTTP \(code))")
      }
    } catch {
      NSLog("[OpenClaw] Ping failed: %@", error.localizedDescription)
      connectionState = .unreachable(error.localizedDescription)
    }
  }

  func switchProfile() {
    let newProfile = ProfileManager.shared.activeProfile
    let newAgentId = UserDefaults.standard.string(forKey: OpenClawBridge.agentIdKey(for: newProfile))
    agentId = newAgentId
    let newKey = OpenClawBridge.makeSessionKey(agentId: newAgentId)
    store.switchSession(to: newKey, saving: conversationHistory)
    conversationHistory = store.load()
    NSLog("[OpenClaw] Switched profile — session key: %@", store.sessionKey)
  }

  func resetSession() {
    store.clear()
    conversationHistory = []
    NSLog("[OpenClaw] Session reset (key: %@)", store.sessionKey)
  }

  private func applyOpenClawHeaders(to request: inout URLRequest, includeUser user: UserProfile?) {
    request.setValue("Bearer \(GeminiConfig.openClawGatewayToken)", forHTTPHeaderField: "Authorization")
    request.setValue("glass", forHTTPHeaderField: "x-openclaw-message-channel")
    request.setValue(DeviceInfo.id, forHTTPHeaderField: "x-openclaw-device-id")
    request.setValue(DeviceInfo.name, forHTTPHeaderField: "x-openclaw-device-name")
    if let user {
      request.setValue(user.id.uuidString, forHTTPHeaderField: "x-openclaw-user-id")
      request.setValue(user.fullName, forHTTPHeaderField: "x-openclaw-user-name")
    }
  }

  // MARK: - Agent Chat

  /// Sends a [REGISTER] handshake to OpenClaw and caches the returned agentId.
  /// Safe to call multiple times — skips the network call if an agentId is already cached.
  func registerAgent() async {
    let activeUser = ProfileManager.shared.activeProfile
    let key = OpenClawBridge.agentIdKey(for: activeUser)

    // Return cached value if available
    if let cached = agentId ?? UserDefaults.standard.string(forKey: key) {
      agentId = cached
      NSLog("[OpenClaw] Agent already registered: %@", cached)
      return
    }

    guard let url = URL(string: "\(GeminiConfig.openClawHost):\(GeminiConfig.openClawPort)/v1/chat/completions") else { return }

    let platform = "iOS \(UIDevice.current.systemVersion)"
    let userInfo = activeUser.map { "\($0.fullName) (\($0.id.uuidString))" } ?? "unknown"
    let regContent = "[REGISTER] Device: \(DeviceInfo.name) (\(DeviceInfo.id)) | User: \(userInfo) | Platform: \(platform)"

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    applyOpenClawHeaders(to: &request, includeUser: activeUser)

    let body: [String: Any] = [
      "model": "openclaw",
      "messages": [["role": "user", "content": regContent]],
      "user": activeUser?.id.uuidString ?? DeviceInfo.id
    ]

    NSLog("[OpenClaw] Sending [REGISTER]: %@", regContent)
    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, _) = try await session.data(for: request)
      let rawResponse = String(data: data, encoding: .utf8) ?? "no body"
      NSLog("[OpenClaw] Registration raw response: %@", String(rawResponse.prefix(500)))

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let choices = json["choices"] as? [[String: Any]],
         let message = choices.first?["message"] as? [String: Any],
         let text = message["content"] as? String {
        // Extract JSON object from within the content — Jarvis may wrap it in prose
        let extracted = extractJSON(from: text)
        if let id = extracted?["agentId"] as? String {
          agentId = id
          UserDefaults.standard.set(id, forKey: key)
          let newKey = OpenClawBridge.makeSessionKey(agentId: id)
          store.switchSession(to: newKey, saving: conversationHistory)
          conversationHistory = store.load()
          let status = extracted?["status"] as? String ?? "unknown"
          NSLog("[OpenClaw] Agent registered: %@ — session key: %@ (status: %@)", id, newKey, status)
        } else {
          NSLog("[OpenClaw] Registration: no agentId in content — content was: %@", String(text.prefix(300)))
        }
      } else {
        NSLog("[OpenClaw] Registration response unparseable — falling back to 'openclaw'")
      }
    } catch {
      NSLog("[OpenClaw] Registration failed: %@", error.localizedDescription)
    }
  }

  private func extractJSON(from text: String) -> [String: Any]? {
    guard let start = text.range(of: "{"), let end = text.range(of: "}", options: .backwards) else { return nil }
    let jsonString = String(text[start.lowerBound..<end.upperBound])
    return try? JSONSerialization.jsonObject(with: Data(jsonString.utf8)) as? [String: Any]
  }

  func delegateTask(
    task: String,
    images: [UIImage] = [],
    toolName: String = "execute"
  ) async -> ToolResult {
    lastToolCallStatus = .executing(toolName)

    // Ensure we have an agent ID before the first message, regardless of entry path.
    // Returns immediately on subsequent calls since the ID is cached.
    await registerAgent()

    let activeUser = ProfileManager.shared.activeProfile
    let urlString = "\(GeminiConfig.openClawHost):\(GeminiConfig.openClawPort)/v1/chat/completions"
    NSLog("[OpenClaw] POST → %@  sessionKey=%@  user=%@  token=%@…",
          urlString, store.sessionKey,
          activeUser.map { "\($0.fullName) (\($0.shortId))" } ?? "none",
          String(GeminiConfig.openClawGatewayToken.prefix(8)))
    guard let url = URL(string: urlString) else {
      lastToolCallStatus = .failed(toolName, "Invalid URL")
      return .failure("Invalid gateway URL")
    }
    var contextParts: [String] = ["Device: \(DeviceInfo.name)"]
    if let user = activeUser {
      contextParts.append("User: \(user.fullName) (\(user.shortId))")
    }
    if let location = LocationManager.shared.locationContext {
      contextParts.append("Location: \(location)")
    }
    let taskWithContext = "[\(contextParts.joined(separator: " | "))] " + task

    // Build user message — multimodal when frames are attached, plain text otherwise
    let userContent: Any
    if images.isEmpty {
      userContent = taskWithContext
    } else {
      var parts: [[String: Any]] = images.compactMap { image in
        guard let jpeg = image.downsampledJPEG(maxDimension: 768, quality: 0.65) else { return nil }
        return [
          "type": "image_url",
          "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]
        ]
      }
      parts.append(["type": "text", "text": taskWithContext])
      userContent = parts
      NSLog("[OpenClaw] Attaching %d frames to message", images.count)
    }

    // Store text-only in history so old turns don't carry image token cost
    conversationHistory.append(["role": "user", "content": taskWithContext])

    if conversationHistory.count > maxHistoryTurns * 2 {
      conversationHistory = Array(conversationHistory.suffix(maxHistoryTurns * 2))
    }

    // Build the actual request messages: history (text-only) + current turn (with images)
    var requestMessages = conversationHistory.dropLast()
    requestMessages.append(["role": "user", "content": userContent])

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(store.sessionKey, forHTTPHeaderField: "x-openclaw-session-key")
    applyOpenClawHeaders(to: &request, includeUser: activeUser)

    let model = agentId.map { "openclaw/\($0)" } ?? "openclaw"
    NSLog("[OpenClaw] Using model: %@ (agentId=%@)", model, agentId ?? "nil")
    let body: [String: Any] = [
      "model": model,
      "messages": Array(requestMessages),
      "stream": false
    ]

    NSLog("[OpenClaw] Sending %d messages in conversation", requestMessages.count)

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await session.data(for: request)
      let httpResponse = response as? HTTPURLResponse

      guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
        let code = httpResponse?.statusCode ?? 0
        let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
        NSLog("[OpenClaw] Chat failed: HTTP %d - %@", code, String(bodyStr.prefix(200)))
        lastToolCallStatus = .failed(toolName, "HTTP \(code)")
        return .failure("Agent returned HTTP \(code)")
      }

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let choices = json["choices"] as? [[String: Any]],
         let first = choices.first,
         let message = first["message"] as? [String: Any],
         let content = message["content"] as? String {
        conversationHistory.append(["role": "assistant", "content": content])
        store.save(conversationHistory)
        NSLog("[OpenClaw] Agent result: %@", String(content.prefix(200)))
        lastToolCallStatus = .completed(toolName)
        return .success(content)
      }

      let raw = String(data: data, encoding: .utf8) ?? "OK"
      conversationHistory.append(["role": "assistant", "content": raw])
      store.save(conversationHistory)
      NSLog("[OpenClaw] Agent raw: %@", String(raw.prefix(200)))
      lastToolCallStatus = .completed(toolName)
      return .success(raw)
    } catch {
      NSLog("[OpenClaw] Agent error: %@", error.localizedDescription)
      lastToolCallStatus = .failed(toolName, error.localizedDescription)
      return .failure("Agent error: \(error.localizedDescription)")
    }
  }
}

// MARK: - UIImage helpers

private extension UIImage {
  func downsampledJPEG(maxDimension: CGFloat, quality: CGFloat) -> Data? {
    let scale = min(maxDimension / max(size.width, size.height), 1.0)
    if scale < 1.0 {
      let newSize = CGSize(width: size.width * scale, height: size.height * scale)
      let renderer = UIGraphicsImageRenderer(size: newSize)
      let resized = renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
      return resized.jpegData(compressionQuality: quality)
    }
    return jpegData(compressionQuality: quality)
  }
}
