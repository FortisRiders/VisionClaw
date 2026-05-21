import SwiftUI

struct CreateProfileView: View {
  var onComplete: (() -> Void)? = nil

  @State private var step: Step = .info
  @State private var firstName = ""
  @State private var lastName = ""
  @State private var email = ""
  @State private var infoError: String? = nil
  @FocusState private var focusedField: Field?
  @StateObject private var pinFlow = PINFlowController(mode: .create)

  private enum Step { case info, setPin, confirmPin }
  private enum Field { case firstName, lastName, email }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
        stepIndicator
          .padding(.top, 60)
          .padding(.bottom, 40)

        switch step {
        case .info:       infoForm
        case .setPin:     pinStep
        case .confirmPin: confirmStep
        }

        Spacer()
      }
    }
    .onChange(of: pinFlow.step) {
      if pinFlow.step == .confirmNew { withAnimation { step = .confirmPin } }
    }
    .onChange(of: pinFlow.isComplete) {
      if pinFlow.isComplete, let pin = pinFlow.confirmedPIN {
        ProfileManager.shared.createProfile(
          firstName: firstName.trimmingCharacters(in: .whitespaces),
          lastName: lastName.trimmingCharacters(in: .whitespaces),
          email: email.trimmingCharacters(in: .whitespaces).lowercased(),
          pin: pin
        )
        onComplete?()
      }
    }
  }

  // MARK: - Step Indicator

  private var stepIndicator: some View {
    HStack(spacing: 8) {
      ForEach(0..<3, id: \.self) { i in
        let active = stepIndex >= i
        Capsule()
          .fill(active ? Color.white : Color.white.opacity(0.2))
          .frame(width: active ? 24 : 8, height: 8)
          .animation(.spring(response: 0.4), value: stepIndex)
      }
    }
  }

  private var stepIndex: Int {
    switch step {
    case .info: return 0
    case .setPin: return 1
    case .confirmPin: return 2
    }
  }

  // MARK: - Step 1: Info

  private var infoForm: some View {
    VStack(spacing: 28) {
      VStack(spacing: 6) {
        Text("Create your profile")
          .font(.title2).fontWeight(.semibold)
          .foregroundColor(.white)
        Text("This identifies you when talking to Jarvis.")
          .font(.subheadline)
          .foregroundColor(.white.opacity(0.55))
      }

      VStack(spacing: 14) {
        ProfileTextField(placeholder: "First name", text: $firstName)
          .focused($focusedField, equals: .firstName)
          .submitLabel(.next)
          .onSubmit { focusedField = .lastName }

        ProfileTextField(placeholder: "Last name", text: $lastName)
          .focused($focusedField, equals: .lastName)
          .submitLabel(.next)
          .onSubmit { focusedField = .email }

        ProfileTextField(
          placeholder: "Email address",
          text: $email,
          keyboardType: .emailAddress,
          autocapitalization: .never
        )
        .focused($focusedField, equals: .email)
        .submitLabel(.done)
        .onSubmit { focusedField = nil }
      }
      .padding(.horizontal, 32)

      ErrorBanner(message: infoError)

      Button(action: advanceFromInfo) {
        Text("Continue")
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.black)
          .frame(maxWidth: .infinity)
          .frame(height: 52)
          .background(Color.white)
          .cornerRadius(14)
          .padding(.horizontal, 32)
      }
    }
  }

  // MARK: - Step 2: Set PIN

  private var pinStep: some View {
    PINPadView(
      title: "Create a PIN",
      subtitle: "You'll use this to unlock your profile.",
      digitCount: 6,
      hasError: .constant(false),
      onComplete: { pin in pinFlow.submit(pin) }
    )
  }

  // MARK: - Step 3: Confirm PIN

  private var confirmStep: some View {
    VStack(spacing: 0) {
      PINPadView(
        title: "Confirm your PIN",
        subtitle: "Enter the same PIN again to confirm.",
        digitCount: 6,
        hasError: $pinFlow.hasError,
        onComplete: { pin in pinFlow.submit(pin) }
      )

      Button {
        pinFlow.step = .enterNew
        withAnimation { step = .setPin }
      } label: {
        Text("Back")
          .font(.subheadline)
          .foregroundColor(.white.opacity(0.4))
          .padding(.top, 20)
      }
    }
  }

  // MARK: - Validation

  private func advanceFromInfo() {
    let f = firstName.trimmingCharacters(in: .whitespaces)
    let l = lastName.trimmingCharacters(in: .whitespaces)
    let e = email.trimmingCharacters(in: .whitespaces)

    guard !f.isEmpty, !l.isEmpty else {
      withAnimation(.easeInOut(duration: 0.2)) { infoError = "First and last name are required." }
      return
    }
    guard EmailValidator.isValid(e) else {
      withAnimation(.easeInOut(duration: 0.2)) { infoError = "Please enter a valid email address." }
      return
    }
    withAnimation(.easeInOut(duration: 0.2)) { infoError = nil }
    focusedField = nil
    withAnimation { step = .setPin }
  }

}

// MARK: - Shared text field style

struct ProfileTextField: View {
  let placeholder: String
  @Binding var text: String
  var keyboardType: UIKeyboardType = .default
  var autocapitalization: TextInputAutocapitalization = .words

  var body: some View {
    TextField(placeholder, text: $text)
      .foregroundColor(.white)
      .keyboardType(keyboardType)
      .textInputAutocapitalization(autocapitalization)
      .autocorrectionDisabled()
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(Color.white.opacity(0.1))
      .cornerRadius(12)
      .tint(.white)
  }
}
