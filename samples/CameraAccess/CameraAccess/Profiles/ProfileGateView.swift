import SwiftUI

struct ProfileGateView: View {
  @ObservedObject private var manager = ProfileManager.shared
  @State private var gateState: GateState = .selectProfile
  @State private var pinError = false
  @State private var isLoading = false
  @State private var errorMessage: String? = nil
  @State private var showCreateProfile = false

  private enum GateState {
    case selectProfile
    case enterPIN(UserProfile)
    case forgotEmail(UserProfile)
    case enterOTP(UserProfile, email: String)
    case setNewPIN(UserProfile)
    case confirmNewPIN(UserProfile, pin: String)
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
        header
          .padding(.top, 64)
          .padding(.bottom, 48)

        content
          .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
          ))
          .id(stateId)

        Spacer()
      }
    }
    .fullScreenCover(isPresented: $showCreateProfile) {
      CreateProfileView {
        showCreateProfile = false
      }
    }
  }

  // MARK: - Header

  private var header: some View {
    VStack(spacing: 8) {
      Image(systemName: "person.crop.circle.badge.lock")
        .font(.system(size: 44))
        .foregroundColor(.white.opacity(0.8))
      Text(headerTitle)
        .font(.title2).fontWeight(.semibold)
        .foregroundColor(.white)
      if let subtitle = headerSubtitle {
        Text(subtitle)
          .font(.subheadline)
          .foregroundColor(.white.opacity(0.55))
          .multilineTextAlignment(.center)
          .padding(.horizontal, 40)
      }
    }
  }

  private var headerTitle: String {
    switch gateState {
    case .selectProfile:          return manager.hasProfiles ? "Who's there?" : "Welcome"
    case .enterPIN(let p):        return p.firstName
    case .forgotEmail:            return "Reset PIN"
    case .enterOTP:               return "Check your email"
    case .setNewPIN:              return "New PIN"
    case .confirmNewPIN:          return "Confirm PIN"
    }
  }

  private var headerSubtitle: String? {
    switch gateState {
    case .selectProfile:
      return manager.hasProfiles ? "Select your profile to continue." : "Create a profile to get started."
    case .enterOTP:
      return "If that email is on a profile, a reset code is on its way."
    case .setNewPIN:
      return "Choose a new 6-digit PIN."
    case .confirmNewPIN:
      return "Enter the same PIN again."
    default:
      return nil
    }
  }

  // MARK: - Content

  @ViewBuilder
  private var content: some View {
    switch gateState {
    case .selectProfile:
      profileGrid

    case .enterPIN(let profile):
      PINPadView(
        title: "",
        digitCount: 6,
        hasError: $pinError,
        onComplete: { pin in attemptUnlock(profile: profile, pin: pin) },
        onForgotPIN: { withAnimation { gateState = .forgotEmail(profile) } },
        lockoutUntil: manager.lockoutUntil
      )

    case .forgotEmail(let profile):
      emailResetForm(profile: profile)

    case .enterOTP(let profile, let email):
      PINPadView(
        title: "",
        digitCount: 6,
        hasError: $pinError,
        onComplete: { code in verifyOTP(code: code, email: email, profile: profile) }
      )

    case .setNewPIN(let profile):
      PINPadView(
        title: "",
        digitCount: 6,
        hasError: .constant(false),
        onComplete: { pin in withAnimation { gateState = .confirmNewPIN(profile, pin: pin) } }
      )

    case .confirmNewPIN(let profile, let pin):
      PINPadView(
        title: "",
        digitCount: 6,
        hasError: $pinError,
        onComplete: { confirmed in
          if confirmed == pin {
            manager.resetPin(for: profile, newPin: confirmed)
            let unlocked = manager.unlock(profile: profile, pin: confirmed)
            if !unlocked { pinError = true }
          } else {
            pinError = true
            resetPINError($pinError)
          }
        }
      )
    }
  }

  // MARK: - Profile Grid

  private var profileGrid: some View {
    VStack(spacing: 32) {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 24) {
        ForEach(manager.profiles) { profile in
          Button {
            withAnimation { gateState = .enterPIN(profile) }
          } label: {
            VStack(spacing: 10) {
              ProfileAvatarCircle(profile: profile, size: 64)
              Text(profile.firstName)
                .font(.caption).fontWeight(.medium)
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
            }
          }
        }
      }
      .padding(.horizontal, 40)

      Button {
        showCreateProfile = true
      } label: {
        Label("Add Profile", systemImage: "plus.circle")
          .font(.subheadline)
          .foregroundColor(.white.opacity(0.5))
      }
    }
  }

  // MARK: - Email Reset Form

  @State private var resetEmail = ""

  private func emailResetForm(profile: UserProfile) -> some View {
    VStack(spacing: 24) {
      ProfileTextField(
        placeholder: "Email address on your profile",
        text: $resetEmail,
        keyboardType: .emailAddress,
        autocapitalization: .never
      )
      .padding(.horizontal, 32)

      ErrorBanner(message: errorMessage)

      Button(action: { Task { await sendOTP(profile: profile) } }) {
        ZStack {
          RoundedRectangle(cornerRadius: 14)
            .fill(Color.white)
            .frame(height: 52)
          if isLoading {
            ProgressView().tint(.black)
          } else {
            Text("Send reset code")
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(.black)
          }
        }
        .padding(.horizontal, 32)
      }
      .disabled(isLoading)

      Button {
        withAnimation(.easeInOut(duration: 0.2)) { errorMessage = nil }
        withAnimation { gateState = .enterPIN(profile) }
      } label: {
        Text("Back")
          .font(.subheadline)
          .foregroundColor(.white.opacity(0.4))
      }
    }
  }

  // MARK: - Actions

  private func attemptUnlock(profile: UserProfile, pin: String) {
    if manager.unlock(profile: profile, pin: pin) {
      // ProfileManager sets activeProfile — gate dismisses via MainAppView's condition
    } else {
      pinError = true
      resetPINError($pinError)
    }
  }

  private func sendOTP(profile: UserProfile) async {
    let trimmed = resetEmail.trimmingCharacters(in: .whitespaces)
    guard EmailValidator.isValid(trimmed) else {
      withAnimation(.easeInOut(duration: 0.2)) { errorMessage = "Please enter a valid email address." }
      return
    }
    isLoading = true
    withAnimation(.easeInOut(duration: 0.2)) { errorMessage = nil }
    let email = trimmed.lowercased()
    _ = await manager.sendPINResetOTP(to: email, for: profile)
    isLoading = false
    withAnimation { gateState = .enterOTP(profile, email: email) }
  }

  private func verifyOTP(code: String, email: String, profile: UserProfile) {
    if manager.verifyOTP(code: code, email: email) {
      withAnimation { gateState = .setNewPIN(profile) }
    } else {
      pinError = true
      resetPINError($pinError)
    }
  }

  // Stable ID so SwiftUI remakes the content view when state changes
  private var stateId: String {
    switch gateState {
    case .selectProfile:           return "select"
    case .enterPIN(let p):         return "pin-\(p.id)"
    case .forgotEmail(let p):      return "email-\(p.id)"
    case .enterOTP(let p, _):      return "otp-\(p.id)"
    case .setNewPIN(let p):        return "newpin-\(p.id)"
    case .confirmNewPIN(let p, _): return "confirm-\(p.id)"
    }
  }
}

