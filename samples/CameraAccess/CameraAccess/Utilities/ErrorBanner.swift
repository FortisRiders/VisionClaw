import SwiftUI

struct ErrorBanner: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.85), in: Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}
