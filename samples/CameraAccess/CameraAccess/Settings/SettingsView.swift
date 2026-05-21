import CryptoKit
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared

  @State private var openClawDeviceId: String = ""
  @State private var deviceIdCopied = false
  @State private var webrtcSignalingURL: String = ""
  @State private var showLiveButton: Bool = false
  @State private var proactiveNotificationsEnabled: Bool = true
  @State private var showResetConfirmation = false
  @State private var profileSheet: ProfileSheet? = nil

  var body: some View {
    NavigationView {
      Form {
        ProfileSettingsSection(activeSheet: $profileSheet)

        Section(header: Text("OpenClaw"), footer: Text("Share your Device ID with the gateway admin to get this device approved for proactive notifications.")) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Device ID")
              .font(.caption)
              .foregroundColor(.secondary)
            HStack {
              Text(openClawDeviceId.isEmpty ? "Connect once to generate" : openClawDeviceId)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(openClawDeviceId.isEmpty ? .secondary : .primary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
              Spacer()
              Button {
                UIPasteboard.general.string = openClawDeviceId
                deviceIdCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                  deviceIdCopied = false
                }
              } label: {
                Image(systemName: deviceIdCopied ? "checkmark" : "doc.on.doc")
                  .foregroundColor(deviceIdCopied ? .green : .accentColor)
              }
              .disabled(openClawDeviceId.isEmpty)
            }
          }
          .padding(.vertical, 2)
        }

        Section(header: Text("WebRTC"), footer: Text("Enable to show the Live streaming button in streaming controls. Requires a signaling server URL.")) {
          Toggle("Show Live Button", isOn: $showLiveButton)
          if showLiveButton {
            VStack(alignment: .leading, spacing: 4) {
              Text("Signaling URL")
                .font(.caption)
                .foregroundColor(.secondary)
              TextField("wss://your-server.example.com", text: $webrtcSignalingURL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.URL)
                .font(.system(.body, design: .monospaced))
            }
          }
        }

        Section(header: Text("Notifications"), footer: Text("Receive proactive updates from OpenClaw (heartbeat, scheduled tasks) spoken through the glasses.")) {
          Toggle("Proactive Notifications", isOn: $proactiveNotificationsEnabled)
        }

        Section {
          Button("Reset to Defaults") {
            showResetConfirmation = true
          }
          .foregroundColor(.red)
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Save") {
            save()
            dismiss()
          }
          .fontWeight(.semibold)
        }
      }
      .alert("Reset Settings", isPresented: $showResetConfirmation) {
        Button("Reset", role: .destructive) {
          settings.resetAll()
          loadCurrentValues()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This will reset all settings to the values built into the app.")
      }
      .onAppear {
        loadCurrentValues()
      }
      .sheet(item: $profileSheet) { sheet in
        switch sheet {
        case .switchUser:
          SwitchProfileSheet()
        case .addProfile:
          CreateProfileView { profileSheet = nil }
        case .editProfile(let profile):
          EditProfileView(profile: profile) { profileSheet = nil }
        case .changePin(let profile):
          ChangePINSheet(profile: profile) { profileSheet = nil }
        }
      }
    }
  }

  private func loadCurrentValues() {
    openClawDeviceId = resolveOpenClawDeviceId()
    webrtcSignalingURL = settings.webrtcSignalingURL
    showLiveButton = settings.showLiveButton
    proactiveNotificationsEnabled = settings.proactiveNotificationsEnabled
  }

  private func resolveOpenClawDeviceId() -> String {
    guard let keyData = KeychainService.load(account: "openclaw-signing-key"),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
      return ""
    }
    return SHA256.hash(data: key.publicKey.rawRepresentation)
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private func save() {
    settings.webrtcSignalingURL = webrtcSignalingURL.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.showLiveButton = showLiveButton
    settings.proactiveNotificationsEnabled = proactiveNotificationsEnabled
  }
}
