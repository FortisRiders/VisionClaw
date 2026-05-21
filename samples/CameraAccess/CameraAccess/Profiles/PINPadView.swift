import SwiftUI

struct PINPadView: View {
  let title: String
  var subtitle: String? = nil
  var digitCount: Int = 6
  @Binding var hasError: Bool
  let onComplete: (String) -> Void
  var onForgotPIN: (() -> Void)? = nil
  var lockoutUntil: Date? = nil

  @State private var digits: String = ""
  @State private var shakeOffset: CGFloat = 0
  @State private var lockoutRemaining: Int = 0

  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    VStack(spacing: 36) {
      VStack(spacing: 8) {
        Text(title)
          .font(.title2).fontWeight(.semibold)
          .foregroundColor(.white)
        if let subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
      }

      dotRow

      statusLabel

      keypad
    }
    .onChange(of: hasError) {
      if hasError { triggerShake() }
    }
    .onChange(of: lockoutUntil) {
      refreshLockout()
      if lockoutUntil != nil { digits = "" }
    }
    .onReceive(timer) { _ in
      refreshLockout()
    }
    .onAppear {
      refreshLockout()
    }
  }

  // MARK: - Subviews

  private var dotRow: some View {
    HStack(spacing: 18) {
      ForEach(0..<digitCount, id: \.self) { i in
        Circle()
          .fill(i < digits.count ? Color.white : Color.clear)
          .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1.5))
          .frame(width: 14, height: 14)
          .animation(.easeInOut(duration: 0.1), value: digits.count)
      }
    }
    .offset(x: shakeOffset)
  }

  @ViewBuilder
  private var statusLabel: some View {
    if lockoutRemaining > 0 {
      Text("Too many attempts — try again in \(lockoutRemaining)s")
        .font(.caption)
        .foregroundColor(.red.opacity(0.85))
    } else if hasError {
      Text("Incorrect PIN. Try again.")
        .font(.caption)
        .foregroundColor(.red.opacity(0.85))
    } else {
      Text(" ").font(.caption)
    }
  }

  private var keypad: some View {
    let isDisabled = lockoutRemaining > 0
    return VStack(spacing: 14) {
      ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
        HStack(spacing: 20) {
          ForEach(row, id: \.self) { digit in
            KeypadDigitButton(label: "\(digit)") { appendDigit("\(digit)") }
              .disabled(isDisabled || digits.count >= digitCount)
          }
        }
      }
      HStack(spacing: 20) {
        if let onForgotPIN {
          Button(action: onForgotPIN) {
            Text("Forgot?")
              .font(.system(size: 15))
              .foregroundColor(.white.opacity(0.45))
              .frame(width: 76, height: 76)
          }
        } else {
          Spacer().frame(width: 76, height: 76)
        }
        KeypadDigitButton(label: "0") { appendDigit("0") }
          .disabled(isDisabled || digits.count >= digitCount)
        Button {
          guard !digits.isEmpty else { return }
          digits.removeLast()
          if hasError { hasError = false }
        } label: {
          Image(systemName: "delete.left")
            .font(.system(size: 22))
            .foregroundColor(.white.opacity(0.75))
            .frame(width: 76, height: 76)
        }
        .disabled(digits.isEmpty)
      }
    }
  }

  // MARK: - Logic

  private func appendDigit(_ d: String) {
    guard digits.count < digitCount, lockoutRemaining == 0 else { return }
    digits.append(d)
    if digits.count == digitCount {
      onComplete(digits)
    }
  }

  private func triggerShake() {
    let keyframes: [(CGFloat, Double)] = [(12, 0), (-12, 0.08), (8, 0.16), (-8, 0.24), (0, 0.32)]
    for (offset, delay) in keyframes {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        withAnimation(.interactiveSpring()) { shakeOffset = offset }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
      digits = ""
    }
  }

  private func refreshLockout() {
    guard let until = lockoutUntil else {
      lockoutRemaining = 0
      return
    }
    let remaining = until.timeIntervalSinceNow
    lockoutRemaining = remaining > 0 ? Int(ceil(remaining)) : 0
  }
}

func resetPINError(_ binding: Binding<Bool>, after delay: TimeInterval = 0.6) {
  DispatchQueue.main.asyncAfter(deadline: .now() + delay) { binding.wrappedValue = false }
}

// MARK: - Keypad Button

private struct KeypadDigitButton: View {
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(.system(size: 30, weight: .light))
        .foregroundColor(.white)
        .frame(width: 76, height: 76)
        .background(Color.white.opacity(0.1))
        .clipShape(Circle())
    }
  }
}
