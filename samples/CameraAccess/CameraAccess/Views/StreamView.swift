import MWDATCore
import SwiftUI

struct StreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel
  @ObservedObject var webrtcVM: WebRTCSessionViewModel
  @ObservedObject var jarvisSession: JarvisVoiceSession

  @Binding var showJarvisPanel: Bool
  var onProfileTap: () -> Void = {}
  @State private var showExitConfirmation = false

  var body: some View {
    ZStack {
      Color.black.edgesIgnoringSafeArea(.all)

      // Video feed
      if webrtcVM.isActive && webrtcVM.connectionState == .connected {
        PiPVideoView(
          localFrame: viewModel.currentVideoFrame,
          remoteVideoTrack: webrtcVM.remoteVideoTrack,
          hasRemoteVideo: webrtcVM.hasRemoteVideo
        )
      } else if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
        GeometryReader { geometry in
          Image(uiImage: videoFrame)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .edgesIgnoringSafeArea(.all)
      } else {
        ProgressView().scaleEffect(1.5).foregroundColor(.white)
      }

      // WebRTC status overlay
      if webrtcVM.isActive {
        VStack {
          WebRTCStatusBar(webrtcVM: webrtcVM)
          Spacer()
        }
        .padding(.all, 24)
      }

      // Top toolbar: profile badge (left) + X button (right)
      VStack {
        HStack {
          ActiveProfileBadge(onTap: onProfileTap)
            .padding(.leading, 20)
            .padding(.top, 56)
          Spacer()
          Button { showExitConfirmation = true } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 28))
              .foregroundStyle(.white.opacity(0.85), .black.opacity(0.35))
              .shadow(color: .black.opacity(0.3), radius: 4)
          }
          .padding(.trailing, 20)
          .padding(.top, 56)
        }
        Spacer()
      }

      // Jarvis live status overlay — transcript / thinking indicator while active
      if jarvisSession.isLiveModeActive {
        VStack {
          Spacer()
          JarvisLiveOverlay(session: jarvisSession)
            .padding(.bottom, 140)
        }
      }

      // Bottom controls
      VStack {
        Spacer()
        StreamingControlsView(
          viewModel: viewModel,
          webrtcVM: webrtcVM,
          jarvisSession: jarvisSession
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
      }
    }
    .confirmationDialog("Stop Streaming?", isPresented: $showExitConfirmation) {
      Button("Stop Streaming", role: .destructive) {
        if jarvisSession.isLiveModeActive { jarvisSession.stopLiveMode() }
        Task { await viewModel.stopSession() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will end the current stream session.")
    }
    .onDisappear {
      Task {
        if viewModel.streamingStatus != .stopped { await viewModel.stopSession() }
        if geminiVM.isGeminiActive { geminiVM.stopSession() }
        if webrtcVM.isActive { webrtcVM.stopSession() }
        if jarvisSession.isLiveModeActive { jarvisSession.stopLiveMode() }
      }
    }
    .sheet(isPresented: $viewModel.showPhotoPreview) {
      if let photo = viewModel.capturedPhoto {
        PhotoPreviewView(photo: photo, onDismiss: { viewModel.dismissPhotoPreview() })
      }
    }
    .alert("AI Assistant", isPresented: Binding(
      get: { geminiVM.errorMessage != nil },
      set: { if !$0 { geminiVM.errorMessage = nil } }
    )) {
      Button("OK") { geminiVM.errorMessage = nil }
    } message: { Text(geminiVM.errorMessage ?? "") }
    .alert("Live Stream", isPresented: Binding(
      get: { webrtcVM.errorMessage != nil },
      set: { if !$0 { webrtcVM.errorMessage = nil } }
    )) {
      Button("OK") { webrtcVM.errorMessage = nil }
    } message: { Text(webrtcVM.errorMessage ?? "") }
  }
}

// MARK: - Jarvis live transcript overlay

struct JarvisLiveOverlay: View {
  @ObservedObject var session: JarvisVoiceSession

  var body: some View {
    Group {
      if session.state == .sending {
        HStack(spacing: 8) {
          ProgressView().tint(.white.opacity(0.7)).scaleEffect(0.75)
          Text("Thinking…")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
      } else if session.state == .speaking {
        HStack(spacing: 8) {
          Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.7))
          Text("Speaking…")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
      } else if !session.liveTranscript.isEmpty {
        Text(session.liveTranscript)
          .font(.system(size: 14))
          .foregroundColor(.white.opacity(0.8))
          .lineLimit(1)
          .padding(.horizontal, 16).padding(.vertical, 8)
          .background(.ultraThinMaterial)
          .clipShape(Capsule())
      }
    }
  }
}

// MARK: - Streaming controls

struct StreamingControlsView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var webrtcVM: WebRTCSessionViewModel
  @ObservedObject var jarvisSession: JarvisVoiceSession

  private var showLiveButton: Bool { SettingsManager.shared.showLiveButton }

  var body: some View {
    VStack(spacing: 12) {
      // Secondary row: camera button (glasses mode only)
      if viewModel.streamingMode == .glasses {
        HStack {
          Spacer()
          CircleButton(icon: "camera.fill", text: nil) { viewModel.capturePhoto() }
        }
      }

      // Primary row: slider (flexes) + optional Live button inline
      HStack(alignment: .center, spacing: 10) {
        if jarvisSession.isLiveModeActive {
          SlideToConfirm(
            label: "Slide to end session",
            icon: "stop.fill",
            color: Color(red: 0.9, green: 0.25, blue: 0.25)
          ) {
            jarvisSession.stopLiveMode()
            Task { await viewModel.stopSession() }
          }
        } else {
          SlideToConfirm(
            label: "Slide to activate Jarvis",
            icon: "ear.fill",
            color: Color(red: 0.0, green: 0.55, blue: 1.0)
          ) {
            jarvisSession.startLiveMode(sharedAudioManager: nil)
          }
        }

        if showLiveButton {
          CircleButton(
            icon: webrtcVM.isActive
              ? "antenna.radiowaves.left.and.right.circle.fill"
              : "antenna.radiowaves.left.and.right.circle",
            text: "Live"
          ) {
            Task {
              if webrtcVM.isActive { webrtcVM.stopSession() }
              else { await webrtcVM.startSession() }
            }
          }
        }
      }
    }
  }
}

// MARK: - Slide-to-confirm control

struct SlideToConfirm: View {
  let label: String
  let icon: String
  let color: Color
  let onConfirm: () -> Void

  @State private var dragOffset: CGFloat = 0

  private let height: CGFloat = 62
  private let inset: CGFloat = 4

  var body: some View {
    GeometryReader { geo in
      let knobSize = height - inset * 2
      let maxDrag = geo.size.width - knobSize - inset * 2
      let progress = maxDrag > 0 ? dragOffset / maxDrag : 0

      ZStack(alignment: .leading) {
        // Track background
        Capsule()
          .fill(color.opacity(0.15))
          .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))

        // Fill trail
        Capsule()
          .fill(color.opacity(0.25 * progress))
          .frame(width: knobSize + inset * 2 + dragOffset)
          .clipped()

        // Label fades as slider moves
        Text(label)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white.opacity(max(0, 0.75 - progress)))
          .frame(maxWidth: .infinity)
          .padding(.leading, knobSize + inset * 2 + 8)

        // Knob
        ZStack {
          Circle().fill(color)
          Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
        }
        .frame(width: knobSize, height: knobSize)
        .shadow(color: color.opacity(0.5), radius: 6)
        .offset(x: inset + dragOffset)
        .gesture(
          DragGesture(minimumDistance: 4)
            .onChanged { value in
              dragOffset = min(max(0, value.translation.width), maxDrag)
            }
            .onEnded { _ in
              if dragOffset > maxDrag * 0.8 {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onConfirm()
              }
              withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                dragOffset = 0
              }
            }
        )
      }
    }
    .frame(height: height)
  }
}
