import ActivityKit
import SwiftUI
import WidgetKit

private func stateColor(_ s: JarvisActivityAttributes.ContentState.JarvisState) -> Color {
    switch s {
    case .idle:      return Color(white: 0.5)
    case .listening: return .green
    case .sending:   return .yellow
    case .speaking:  return Color(red: 0.3, green: 0.7, blue: 1.0)
    }
}

private func stateLabel(_ s: JarvisActivityAttributes.ContentState.JarvisState) -> String {
    switch s {
    case .idle:      return "Ready"
    case .listening: return "Listening..."
    case .sending:   return "Thinking..."
    case .speaking:  return "Speaking..."
    }
}

// MARK: - Lock-screen expanded view

struct JarvisLockScreenView: View {
    let context: ActivityViewContext<JarvisActivityAttributes>

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(stateColor(context.state.jarvisState))
                    .frame(width: 9, height: 9)
                    .shadow(color: stateColor(context.state.jarvisState).opacity(0.8), radius: 4)
                Text("Jarvis")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(stateLabel(context.state.jarvisState))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                Button(intent: StopSessionIntent()) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.55), .white.opacity(0.15))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button(intent: StopJarvisIntent()) {
                    Label("Stop Jarvis", systemImage: "mic.slash.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.85, green: 0.2, blue: 0.2), in: Capsule())
                }
                .buttonStyle(.plain)

                if context.state.showLiveButton {
                    Button(intent: ToggleLiveIntent()) {
                        HStack(spacing: 5) {
                            if context.state.isLiveStreaming {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 6, height: 6)
                            }
                            Text(context.state.isLiveStreaming ? "Live" : "Go Live")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            context.state.isLiveStreaming
                                ? Color(red: 0.9, green: 0.45, blue: 0.1)
                                : Color(red: 0.2, green: 0.45, blue: 0.9),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(white: 0.1))
    }
}

// MARK: - Widget configuration

struct JarvisWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JarvisActivityAttributes.self) { context in
            JarvisLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(stateColor(context.state.jarvisState))
                            .frame(width: 8, height: 8)
                        Text("Jarvis")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: StopSessionIntent()) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(stateLabel(context.state.jarvisState))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Button(intent: StopJarvisIntent()) {
                            Label("Stop Jarvis", systemImage: "mic.slash.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color(red: 0.85, green: 0.2, blue: 0.2), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if context.state.showLiveButton {
                            Button(intent: ToggleLiveIntent()) {
                                Text(context.state.isLiveStreaming ? "● Live" : "Go Live")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        context.state.isLiveStreaming
                                            ? Color(red: 0.9, green: 0.45, blue: 0.1)
                                            : Color(red: 0.2, green: 0.45, blue: 0.9),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 6)
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(stateColor(context.state.jarvisState))
                    .font(.caption)
            } compactTrailing: {
                Button(intent: StopJarvisIntent()) {
                    Image(systemName: "mic.slash.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(stateColor(context.state.jarvisState))
            }
        }
    }
}
