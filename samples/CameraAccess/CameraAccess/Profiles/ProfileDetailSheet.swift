import SwiftUI

struct ProfileDetailSheet: View {
  @ObservedObject private var manager = ProfileManager.shared
  @Environment(\.dismiss) private var dismiss

  @State private var mode: Mode = .detail
  @State private var selectedForSwitch: UserProfile? = nil
  @State private var pinError = false

  private enum Mode { case detail, edit, switchUser }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
        handle

        content
          .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
          ))
          .id(modeId)

        Spacer()
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.hidden)
  }

  // MARK: - Mode routing

  @ViewBuilder
  private var content: some View {
    switch mode {
    case .detail:
      if let profile = manager.activeProfile { detailView(profile) }
    case .edit:
      if let profile = manager.activeProfile { EditProfileView(profile: profile) { withAnimation { mode = .detail } } }
    case .switchUser:
      switchView
    }
  }

  private var modeId: String {
    switch mode {
    case .detail:     return "detail"
    case .edit:       return "edit"
    case .switchUser: return selectedForSwitch.map { "pin-\($0.id)" } ?? "switch"
    }
  }

  // MARK: - Detail

  private func detailView(_ profile: UserProfile) -> some View {
    VStack(spacing: 28) {
      VStack(spacing: 12) {
        ProfileAvatarCircle(profile: profile, size: 80)
        VStack(spacing: 4) {
          Text(profile.fullName)
            .font(.title3).fontWeight(.semibold)
            .foregroundColor(.white)
          Text(profile.email)
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.55))
          Text("ID: \(profile.shortId)")
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.white.opacity(0.35))
            .padding(.top, 2)
        }
      }
      .padding(.top, 24)

      VStack(spacing: 12) {
        ProfileActionButton(icon: "pencil", label: "Edit Profile") {
          withAnimation { mode = .edit }
        }
        ProfileActionButton(icon: "person.2", label: "Switch User") {
          selectedForSwitch = nil
          withAnimation { mode = .switchUser }
        }
        ProfileActionButton(icon: "xmark.circle", label: "Close", destructive: false) {
          dismiss()
        }
      }
      .padding(.horizontal, 32)
    }
  }

  // MARK: - Switch User

  private var switchView: some View {
    VStack(spacing: 0) {
      if let profile = selectedForSwitch {
        PINPadView(
          title: profile.firstName,
          subtitle: "Enter PIN to switch profiles.",
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

        Button { withAnimation { selectedForSwitch = nil } } label: {
          Text("Back")
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.4))
            .padding(.top, 20)
        }
      } else {
        profileList
      }
    }
  }

  private var profileList: some View {
    VStack(spacing: 24) {
      Text("Switch Profile")
        .font(.title3).fontWeight(.semibold)
        .foregroundColor(.white)
        .padding(.top, 24)

      VStack(spacing: 2) {
        ForEach(manager.profiles) { profile in
          Button { withAnimation { selectedForSwitch = profile } } label: {
            HStack(spacing: 14) {
              ProfileAvatarCircle(profile: profile, size: 40)
              VStack(alignment: .leading, spacing: 2) {
                Text(profile.fullName)
                  .fontWeight(.medium).foregroundColor(.white)
                Text(profile.email)
                  .font(.caption).foregroundColor(.white.opacity(0.5))
              }
              Spacer()
              if manager.activeProfile?.id == profile.id {
                Image(systemName: "checkmark")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundColor(.green)
              }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
          }
          Divider().background(Color.white.opacity(0.1)).padding(.leading, 78)
        }
      }

      Button { withAnimation { mode = .detail } } label: {
        Text("Back")
          .font(.subheadline)
          .foregroundColor(.white.opacity(0.4))
      }
    }
  }

  // MARK: - Shared

  private var handle: some View {
    Capsule()
      .fill(Color.white.opacity(0.25))
      .frame(width: 36, height: 4)
      .padding(.top, 12).padding(.bottom, 8)
  }
}

// MARK: - Edit Profile

struct EditProfileView: View {
  let profile: UserProfile
  let onComplete: () -> Void

  @ObservedObject private var manager = ProfileManager.shared
  @State private var firstName: String
  @State private var lastName: String
  @State private var email: String
  @State private var errorMessage: String? = nil
  @FocusState private var focusedField: Field?

  private enum Field { case firstName, lastName, email }

  init(profile: UserProfile, onComplete: @escaping () -> Void) {
    self.profile = profile
    self.onComplete = onComplete
    _firstName = State(initialValue: profile.firstName)
    _lastName  = State(initialValue: profile.lastName)
    _email     = State(initialValue: profile.email)
  }

  var body: some View {
    VStack(spacing: 28) {
      VStack(spacing: 6) {
        Text("Edit Profile")
          .font(.title2).fontWeight(.semibold).foregroundColor(.white)
        Text("Changes take effect immediately.")
          .font(.subheadline).foregroundColor(.white.opacity(0.55))
      }
      .padding(.top, 8)

      VStack(spacing: 14) {
        ProfileTextField(placeholder: "First name", text: $firstName)
          .focused($focusedField, equals: .firstName)
          .submitLabel(.next).onSubmit { focusedField = .lastName }

        ProfileTextField(placeholder: "Last name", text: $lastName)
          .focused($focusedField, equals: .lastName)
          .submitLabel(.next).onSubmit { focusedField = .email }

        ProfileTextField(
          placeholder: "Email address",
          text: $email,
          keyboardType: .emailAddress,
          autocapitalization: .never
        )
        .focused($focusedField, equals: .email)
        .submitLabel(.done).onSubmit { focusedField = nil }
      }
      .padding(.horizontal, 32)

      ErrorBanner(message: errorMessage)

      Button(action: save) {
        Text("Save Changes")
          .font(.system(size: 17, weight: .semibold)).foregroundColor(.black)
          .frame(maxWidth: .infinity).frame(height: 52)
          .background(Color.white).cornerRadius(14)
          .padding(.horizontal, 32)
      }

      Button(action: onComplete) {
        Text("Cancel")
          .font(.subheadline).foregroundColor(.white.opacity(0.4))
      }
    }
  }

  private func save() {
    let f = firstName.trimmingCharacters(in: .whitespaces)
    let l = lastName.trimmingCharacters(in: .whitespaces)
    let e = email.trimmingCharacters(in: .whitespaces)
    guard !f.isEmpty, !l.isEmpty else { withAnimation(.easeInOut(duration: 0.2)) { errorMessage = "First and last name are required." }; return }
    guard EmailValidator.isValid(e) else { withAnimation(.easeInOut(duration: 0.2)) { errorMessage = "Please enter a valid email address." }; return }
    withAnimation(.easeInOut(duration: 0.2)) { errorMessage = nil }
    var updated = profile
    updated.firstName = f
    updated.lastName  = l
    updated.email     = e.lowercased()
    manager.updateProfile(updated)
    onComplete()
  }

}

// MARK: - Action Button

private struct ProfileActionButton: View {
  let icon: String
  let label: String
  var destructive: Bool = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 16))
          .frame(width: 24)
        Text(label)
          .font(.system(size: 16, weight: .medium))
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13))
          .foregroundColor(.white.opacity(0.3))
      }
      .foregroundColor(destructive ? .red : .white)
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .background(Color.white.opacity(0.08))
      .cornerRadius(14)
    }
  }
}
