import Foundation

@MainActor
final class PINFlowController: ObservableObject {
    enum Mode {
        case create
        case change(profile: UserProfile)
    }

    enum Step: Equatable {
        case enterNew
        case confirmNew
        case verifyCurrent
    }

    @Published var step: Step
    @Published var hasError: Bool = false
    @Published private(set) var isComplete = false
    private(set) var confirmedPIN: String?

    private let mode: Mode
    private var firstPIN: String?
    private let manager: ProfileManager

    init(mode: Mode, manager: ProfileManager = .shared) {
        self.mode = mode
        self.manager = manager
        switch mode {
        case .create:  self.step = .enterNew
        case .change:  self.step = .verifyCurrent
        }
    }

    func submit(_ pin: String) {
        switch step {
        case .verifyCurrent:
            guard case .change(let profile) = mode else { return }
            if manager.verifyPin(profile: profile, pin: pin) {
                step = .enterNew
            } else {
                triggerError()
            }

        case .enterNew:
            firstPIN = pin
            step = .confirmNew

        case .confirmNew:
            guard pin == firstPIN else { triggerError(); return }
            commitPIN(pin)
        }
    }

    private func commitPIN(_ pin: String) {
        switch mode {
        case .create:
            confirmedPIN = pin
            isComplete = true
        case .change(let profile):
            if manager.changePin(for: profile, newPin: pin) {
                isComplete = true
            } else {
                triggerError()
            }
        }
    }

    private func triggerError() {
        hasError = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.hasError = false }
        firstPIN = nil
        if step == .confirmNew { step = .enterNew }
    }
}
