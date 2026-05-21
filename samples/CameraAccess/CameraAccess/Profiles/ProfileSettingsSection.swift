import SwiftUI

// MARK: - Profile Settings Section (embedded in SettingsView Form)

enum ProfileSheet: Identifiable {
  case switchUser
  case addProfile
  case editProfile(UserProfile)
  case changePin(UserProfile)

  var id: String {
    switch self {
    case .switchUser:           return "switch"
    case .addProfile:           return "add"
    case .editProfile(let p):   return "edit-\(p.id)"
    case .changePin(let p):     return "pin-\(p.id)"
    }
  }
}

struct ProfileSettingsSection: View {
  @ObservedObject private var manager = ProfileManager.shared
  @Binding var activeSheet: ProfileSheet?
  @State private var showDeleteConfirm = false

  var body: some View {
    Section(header: Text("Profile")) {
      if let profile = manager.activeProfile {
        activeProfileRow(profile)

        Button("Edit Profile")  { activeSheet = .editProfile(profile) }
        Button("Switch User")   { activeSheet = .switchUser }
        Button("Change PIN")    { activeSheet = .changePin(profile) }
        Button("Add Profile")   { activeSheet = .addProfile }

        Button("Delete Profile", role: .destructive) { showDeleteConfirm = true }
          .confirmationDialog(
            "Delete \(profile.firstName)'s profile?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
          ) {
            Button("Delete", role: .destructive) { manager.deleteProfile(profile) }
            Button("Cancel", role: .cancel) {}
          } message: {
            Text("This cannot be undone. You will need to create a new profile to use the app.")
          }
      }
    }
  }

  private func activeProfileRow(_ profile: UserProfile) -> some View {
    HStack(spacing: 14) {
      ProfileAvatarCircle(profile: profile, size: 44)
      VStack(alignment: .leading, spacing: 3) {
        Text(profile.fullName)
          .fontWeight(.medium)
        Text(profile.email)
          .font(.caption)
          .foregroundColor(.secondary)
        Text("ID: \(profile.shortId)")
          .font(.system(.caption2, design: .monospaced))
          .foregroundColor(.secondary)
      }
      Spacer()
      Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.green)
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Switch Profile Sheet

struct SwitchProfileSheet: View {
  @ObservedObject private var manager = ProfileManager.shared
  @Environment(\.dismiss) private var dismiss
  @State private var selected: UserProfile? = nil
  @State private var pinError = false

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
        sheetHandle

        if let profile = selected {
          PINPadView(
            title: profile.firstName,
            subtitle: "Enter PIN to switch profiles.",
            digitCount: 6,
            hasError: $pinError,
            onComplete: { pin in
              if manager.unlock(profile: profile, pin: pin) {
                dismiss()
              } else {
                pinError = true
                resetPINError($pinError)
              }
            },
            lockoutUntil: manager.lockoutUntil
          )
          .padding(.top, 24)

          Button {
            withAnimation { selected = nil }
          } label: {
            Text("Back")
              .font(.subheadline)
              .foregroundColor(.white.opacity(0.4))
              .padding(.top, 20)
          }
        } else {
          profileList
        }

        Spacer()
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.hidden)
  }

  private var sheetHandle: some View {
    Capsule()
      .fill(Color.white.opacity(0.25))
      .frame(width: 36, height: 4)
      .padding(.top, 12)
      .padding(.bottom, 8)
  }

  private var profileList: some View {
    VStack(spacing: 24) {
      Text("Switch Profile")
        .font(.title3).fontWeight(.semibold)
        .foregroundColor(.white)
        .padding(.top, 16)

      VStack(spacing: 2) {
        ForEach(manager.profiles) { profile in
          Button {
            withAnimation { selected = profile }
          } label: {
            HStack(spacing: 14) {
              ProfileAvatarCircle(profile: profile, size: 40)
              VStack(alignment: .leading, spacing: 2) {
                Text(profile.fullName)
                  .fontWeight(.medium)
                  .foregroundColor(.white)
                Text(profile.email)
                  .font(.caption)
                  .foregroundColor(.white.opacity(0.5))
              }
              Spacer()
              if manager.activeProfile?.id == profile.id {
                Image(systemName: "checkmark")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundColor(.green)
              }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
          }
          Divider().background(Color.white.opacity(0.1))
            .padding(.leading, 78)
        }
      }
    }
  }
}

// MARK: - Change PIN Sheet

struct ChangePINSheet: View {
  let profile: UserProfile
  let onComplete: () -> Void

  @StateObject private var flow: PINFlowController

  init(profile: UserProfile, onComplete: @escaping () -> Void) {
    self.profile = profile
    self.onComplete = onComplete
    _flow = StateObject(wrappedValue: PINFlowController(mode: .change(profile: profile)))
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
        Capsule()
          .fill(Color.white.opacity(0.25))
          .frame(width: 36, height: 4)
          .padding(.top, 12)
          .padding(.bottom, 32)

        PINPadView(
          title: stepTitle,
          digitCount: 6,
          hasError: $flow.hasError,
          onComplete: { pin in withAnimation { flow.submit(pin) } }
        )
        .transition(.asymmetric(
          insertion: .move(edge: .trailing).combined(with: .opacity),
          removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .id(flow.step)

        Spacer()
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.hidden)
    .onChange(of: flow.isComplete) {
      if flow.isComplete { onComplete() }
    }
  }

  private var stepTitle: String {
    switch flow.step {
    case .verifyCurrent: return "Enter current PIN"
    case .enterNew:      return "Enter new PIN"
    case .confirmNew:    return "Confirm new PIN"
    }
  }
}

// MARK: - Active Profile Badge (shown in StreamSessionView)

struct ActiveProfileBadge: View {
  @ObservedObject private var manager = ProfileManager.shared
  var onTap: () -> Void

  var body: some View {
    if let profile = manager.activeProfile {
      Button(action: onTap) {
        HStack(spacing: 7) {
          ProfileAvatarCircle(profile: profile, size: 24)
          Text(profile.firstName)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
      }
    }
  }
}

// MARK: - Shared Avatar Component

struct ProfileAvatarCircle: View {
  let profile: UserProfile
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(color(for: profile.id))
        .frame(width: size, height: size)
      Text(profile.initials)
        .font(.system(size: size * 0.35, weight: .semibold))
        .foregroundColor(.white)
    }
  }

  private func color(for id: UUID) -> Color {
    let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint, .cyan]
    return palette[abs(id.hashValue) % palette.count]
  }
}
